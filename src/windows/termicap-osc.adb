-------------------------------------------------------------------------------
--  Termicap.OSC - OSC Probe Session and Terminal I/O (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows implementation of the OSC probe session package.
--
--  @description
--  This body implements the probe session lifecycle on Windows by acquiring
--  STD_INPUT_HANDLE / STD_OUTPUT_HANDLE (with CONIN$/CONOUT$ as a fallback
--  when the standard handles are redirected), saving and restoring the two
--  console modes via GetConsoleMode/SetConsoleMode, and using
--  WaitForSingleObject + ReadFile / WriteFile for the timed-read and write
--  primitives.  The Termios_State buffer is repurposed to hold:
--
--    bytes 1..4 : Input  console mode (DWORD, little-endian)
--    bytes 5..8 : Output console mode (DWORD, little-endian)
--    byte 9     : Input_Saved  flag (1 = present, 0 = absent)
--    byte 10    : Output_Saved flag (1 = present, 0 = absent)
--    State.Size : 10 (bytes consumed)
--
--  The synthetic File_Descriptor returned to the caller is a slot index in
--  the body-private Slots array (1 .. MAX_SLOTS).  MAX_SLOTS = 1 enforces
--  the FUNC-OSC-012 single-session invariant; the Active_Session_Guard
--  protected object further serialises Open / Close.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-001): Open_Terminal / Close_Terminal via console handles
--    - @relation(FUNC-OSC-002): Save_Termios / Restore_Termios via GetConsoleMode/SetConsoleMode
--    - @relation(FUNC-OSC-003): Set_Raw_Mode via SetConsoleMode (raw input + VT output)
--    - @relation(FUNC-OSC-004): Timed_Read via WaitForSingleObject + ReadFile
--    - @relation(FUNC-OSC-005): Write_Query via WriteFile
--    - @relation(FUNC-OSC-006): Sentinel_Query loop with DA1 detection
--    - @relation(FUNC-OSC-007): Is_Foreground_Process degenerate on Windows
--    - @relation(FUNC-OSC-008): Open / Close / Finalize lifecycle
--    - @relation(FUNC-OSC-009): MAX_RESPONSE_SIZE overflow protection
--    - @relation(FUNC-OSC-011): Drain_Input bounded non-blocking loop
--    - @relation(FUNC-OSC-012): Active_Session_Guard single-session guard
--    - @relation(FUNC-OSC-013): Optional retry in Sentinel_Query
--    - @relation(FUNC-OSC-015): SPARK_Mode Off; FFI boundary
--    - @relation(FUNC-OSC-017): ENABLE_VIRTUAL_TERMINAL_INPUT / DISABLE_NEWLINE_AUTO_RETURN

pragma SPARK_Mode (Off);

with Ada.Calendar;
with Termicap.OSC.Parsing;
with Termicap.Win32_VT;
with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Termicap.OSC is

   use type Interfaces.C.unsigned_char;
   use type Win32.BOOL;
   use type Win32.DWORD;
   use type Win32.WORD;

   ---------------------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------------------

   --  Maximum non-blocking drain iterations (FUNC-OSC-011).
   MAX_DRAIN_ITERATIONS : constant := 16;

   --  DA1 sentinel bytes: ESC [ c  (3 bytes: 0x1B 0x5B 0x63) (FUNC-OSC-006).
   DA1_SENTINEL : constant Byte_Array (1 .. 3) := [16#1B#, 16#5B#, 16#63#];

   --  FUNC-OSC-012: single concurrent session enforced by Active_Session_Guard;
   --  one slot is sufficient.
   MAX_SLOTS : constant := 1;

   ---------------------------------------------------------------------------
   --  Slot Table
   ---------------------------------------------------------------------------

   type Console_Handle_Origin is
     (Not_Acquired, Borrowed_From_Std, Owned_From_CreateFile);

   type Console_Slot is record
      In_Use     : Boolean := False;
      In_Handle  : Win32.Winnt.HANDLE := Win32.Winbase.INVALID_HANDLE_VALUE;
      In_Origin  : Console_Handle_Origin := Not_Acquired;
      Out_Handle : Win32.Winnt.HANDLE := Win32.Winbase.INVALID_HANDLE_VALUE;
      Out_Origin : Console_Handle_Origin := Not_Acquired;
   end record;

   type Slot_Array is array (1 .. MAX_SLOTS) of Console_Slot;

   --  Body-private slot table; serialised access via Active_Session_Guard.
   Slots : Slot_Array;

   ---------------------------------------------------------------------------
   --  Single-Session Guard (FUNC-OSC-012)
   ---------------------------------------------------------------------------

   protected Active_Session_Guard is
      procedure Acquire (Acquired : out Boolean);
      procedure Release;
   private
      Active : Boolean := False;
   end Active_Session_Guard;

   protected body Active_Session_Guard is

      procedure Acquire (Acquired : out Boolean) is
      begin
         if Active then
            Acquired := False;
         else
            Active := True;
            Acquired := True;
         end if;
      end Acquire;

      procedure Release is
      begin
         Active := False;
      end Release;

   end Active_Session_Guard;

   ---------------------------------------------------------------------------
   --  Slot Helpers
   ---------------------------------------------------------------------------

   --  Find a free slot index, or 0 if none.
   function Allocate_Slot return Natural is
   begin
      for I in Slots'Range loop
         if not Slots (I).In_Use then
            return I;
         end if;
      end loop;
      return 0;
   end Allocate_Slot;

   procedure Free_Slot (Index : Positive) is
   begin
      Slots (Index) :=
        (In_Use     => False,
         In_Handle  => Win32.Winbase.INVALID_HANDLE_VALUE,
         In_Origin  => Not_Acquired,
         Out_Handle => Win32.Winbase.INVALID_HANDLE_VALUE,
         Out_Origin => Not_Acquired);
   end Free_Slot;

   ---------------------------------------------------------------------------
   --  Termios_State byte-packing helpers
   ---------------------------------------------------------------------------

   --  Pack a 32-bit DWORD into Data starting at byte index Offset (1-based)
   --  in little-endian order.
   procedure Pack_DWORD
     (Data   : in out Byte_Array;
      Offset : Positive;
      Value  : Win32.DWORD)
   is
      V : Win32.DWORD := Value;
   begin
      for I in 0 .. 3 loop
         Data (Offset + I) := Byte (V and 16#FF#);
         V := V / 256;
      end loop;
   end Pack_DWORD;

   --  Unpack a 32-bit DWORD from Data starting at byte index Offset (1-based)
   --  in little-endian order.
   function Unpack_DWORD
     (Data   : Byte_Array;
      Offset : Positive)
      return Win32.DWORD
   is
      Result : Win32.DWORD := 0;
   begin
      for I in reverse 0 .. 3 loop
         Result := Result * 256 + Win32.DWORD (Data (Offset + I));
      end loop;
      return Result;
   end Unpack_DWORD;

   ---------------------------------------------------------------------------
   --  Internal Terminal Operations (FUNC-OSC-001..003, FUNC-OSC-011)
   ---------------------------------------------------------------------------

   ---------- Open_Terminal ----------

   function Open_Terminal return File_Descriptor is
      Slot_Idx : Natural;
      H        : Win32.Winnt.HANDLE;
      Mode     : aliased Win32.DWORD := 0;
      OK       : Win32.BOOL;
   begin
      Slot_Idx := Allocate_Slot;
      if Slot_Idx = 0 then
         return INVALID_FD;
      end if;

      declare
         Slot : Console_Slot renames Slots (Slot_Idx);
      begin
         --  Stage 1: try the standard handles and verify they are consoles.
         H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_INPUT_HANDLE);
         if Termicap.Win32_VT.Is_Valid_Handle (H) then
            OK := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
            if OK /= Win32.FALSE then
               Slot.In_Handle := H;
               Slot.In_Origin := Borrowed_From_Std;
            end if;
         end if;

         H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE);
         if Termicap.Win32_VT.Is_Valid_Handle (H) then
            OK := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
            if OK /= Win32.FALSE then
               Slot.Out_Handle := H;
               Slot.Out_Origin := Borrowed_From_Std;
            end if;
         end if;

         --  Stage 2: fall back to CONIN$ / CONOUT$ for each side that the
         --  standard-handle path failed to acquire.
         if Slot.In_Origin = Not_Acquired then
            H := Termicap.Win32_VT.Open_Console_Input;
            if Termicap.Win32_VT.Is_Valid_Handle (H) then
               Slot.In_Handle := H;
               Slot.In_Origin := Owned_From_CreateFile;
            end if;
         end if;

         if Slot.Out_Origin = Not_Acquired then
            H := Termicap.Win32_VT.Open_Console_Output;
            if Termicap.Win32_VT.Is_Valid_Handle (H) then
               Slot.Out_Handle := H;
               Slot.Out_Origin := Owned_From_CreateFile;
            end if;
         end if;

         --  If neither side was acquired, free the slot and report failure.
         if Slot.In_Origin = Not_Acquired
           and then Slot.Out_Origin = Not_Acquired
         then
            Free_Slot (Slot_Idx);
            return INVALID_FD;
         end if;

         Slot.In_Use := True;
      end;

      return File_Descriptor (Slot_Idx);
   end Open_Terminal;

   ---------- Close_Terminal ----------

   procedure Close_Terminal (FD : in out File_Descriptor) is
   begin
      if FD = INVALID_FD then
         return;
      end if;

      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         FD := INVALID_FD;
         return;
      end if;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         if Slot.In_Origin = Owned_From_CreateFile then
            Termicap.Win32_VT.Close_Handle (Slot.In_Handle);
         end if;
         if Slot.Out_Origin = Owned_From_CreateFile then
            Termicap.Win32_VT.Close_Handle (Slot.Out_Handle);
         end if;
         Free_Slot (Positive (FD));
      end;

      FD := INVALID_FD;
   end Close_Terminal;

   ---------- Save_Termios ----------

   procedure Save_Termios
     (FD : File_Descriptor; State : out Termios_State; OK : out Boolean)
   is
      In_Mode  : aliased Win32.DWORD := 0;
      Out_Mode : aliased Win32.DWORD := 0;
      In_OK    : Boolean := False;
      Out_OK   : Boolean := False;
      Status   : Win32.BOOL;
   begin
      State.Data := [others => 0];
      State.Size := 0;
      OK := False;

      if FD = INVALID_FD then
         return;
      end if;
      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         return;
      end if;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         if Slot.In_Origin /= Not_Acquired then
            Status := Win32.Wincon.GetConsoleMode (Slot.In_Handle, In_Mode'Unchecked_Access);
            if Status /= Win32.FALSE then
               Pack_DWORD (State.Data, 1, In_Mode);
               State.Data (9) := 1;
               In_OK := True;
            end if;
         end if;

         if Slot.Out_Origin /= Not_Acquired then
            Status := Win32.Wincon.GetConsoleMode (Slot.Out_Handle, Out_Mode'Unchecked_Access);
            if Status /= Win32.FALSE then
               Pack_DWORD (State.Data, 5, Out_Mode);
               State.Data (10) := 1;
               Out_OK := True;
            end if;
         end if;
      end;

      State.Size := 10;
      OK := In_OK or Out_OK;  --  FUNC-OSC-017: partial save permitted
   end Save_Termios;

   ---------- Restore_Termios ----------

   procedure Restore_Termios
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      Input_Saved   : Boolean;
      Output_Saved  : Boolean;
      In_Mode       : Win32.DWORD;
      Out_Mode      : Win32.DWORD;
      In_OK         : Boolean := True;
      Out_OK        : Boolean := True;
      Status        : Win32.BOOL;
   begin
      OK := False;

      if FD = INVALID_FD then
         return;
      end if;
      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         return;
      end if;
      if State.Size = 0 then
         return;
      end if;

      Input_Saved  := State.Data (9) = 1;
      Output_Saved := State.Data (10) = 1;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         if Input_Saved and then Slot.In_Origin /= Not_Acquired then
            In_Mode := Unpack_DWORD (State.Data, 1);
            Status := Win32.Wincon.SetConsoleMode (Slot.In_Handle, In_Mode);
            In_OK := Status /= Win32.FALSE;
         end if;

         if Output_Saved and then Slot.Out_Origin /= Not_Acquired then
            Out_Mode := Unpack_DWORD (State.Data, 5);
            Status := Win32.Wincon.SetConsoleMode (Slot.Out_Handle, Out_Mode);
            Out_OK := Status /= Win32.FALSE;
         end if;
      end;

      OK := In_OK and Out_OK;
   end Restore_Termios;

   ---------- Set_Raw_Mode ----------

   procedure Set_Raw_Mode
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      Input_Saved   : Boolean;
      Output_Saved  : Boolean;
      In_Mode       : Win32.DWORD;
      Out_Mode      : Win32.DWORD;
      New_In        : Win32.DWORD;
      New_Out       : Win32.DWORD;
      In_Set_OK     : Boolean := True;
      Out_Set_OK    : Boolean := True;
      Status        : Win32.BOOL;

      Cooked_Bits : constant Win32.DWORD :=
        Win32.Wincon.ENABLE_LINE_INPUT
        or Win32.Wincon.ENABLE_ECHO_INPUT
        or Win32.Wincon.ENABLE_PROCESSED_INPUT;
   begin
      OK := False;

      if FD = INVALID_FD then
         return;
      end if;
      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         return;
      end if;
      if State.Size = 0 then
         return;
      end if;

      Input_Saved  := State.Data (9) = 1;
      Output_Saved := State.Data (10) = 1;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         if Input_Saved and then Slot.In_Origin /= Not_Acquired then
            In_Mode := Unpack_DWORD (State.Data, 1);
            New_In :=
              (In_Mode and not Cooked_Bits)
              or Termicap.Win32_VT.ENABLE_VIRTUAL_TERMINAL_INPUT;
            Status := Win32.Wincon.SetConsoleMode (Slot.In_Handle, New_In);
            In_Set_OK := Status /= Win32.FALSE;
         end if;

         if Output_Saved and then Slot.Out_Origin /= Not_Acquired then
            Out_Mode := Unpack_DWORD (State.Data, 5);
            New_Out :=
              Out_Mode
              or Termicap.Win32_VT.ENABLE_VIRTUAL_TERMINAL_PROCESSING
              or Termicap.Win32_VT.DISABLE_NEWLINE_AUTO_RETURN;
            Status := Win32.Wincon.SetConsoleMode (Slot.Out_Handle, New_Out);
            Out_Set_OK := Status /= Win32.FALSE;
         end if;
      end;

      OK := (not Input_Saved or else In_Set_OK)
        and then (not Output_Saved or else Out_Set_OK);
   end Set_Raw_Mode;

   ---------------------------------------------------------------------------
   --  Low-Level I/O (FUNC-OSC-004, FUNC-OSC-005, FUNC-OSC-007)
   ---------------------------------------------------------------------------

   ---------- Timed_Read ----------

   --  We use ReadConsoleInputW (not ReadFile) on the input handle.  Why:
   --
   --    With ENABLE_VIRTUAL_TERMINAL_INPUT set, ReadFile is documented to
   --    block until at least one byte is available.  WaitForSingleObject on
   --    the input handle is signalled whenever ANY console event is queued
   --    (KEY_EVENT, MOUSE_EVENT, FOCUS_EVENT, MENU_EVENT,
   --    WINDOW_BUFFER_SIZE_EVENT).  Most of those produce zero bytes for
   --    ReadFile in VT mode -- so a Wait+ReadFile sequence can hang
   --    indefinitely when the wait was triggered by a non-byte event (e.g.,
   --    the cmd.exe-in-Windows-Terminal focus chatter that fires the moment
   --    a new shim subprocess starts).
   --
   --    ReadConsoleInputW returns one INPUT_RECORD per call without ever
   --    blocking past the wait: if the queue is empty after WaitForSingleObject
   --    signals, ReadConsoleInputW returns Got=0 immediately.  We filter for
   --    KEY_EVENT records that carry a printable byte (key press,
   --    UnicodeChar in 1..255) and discard everything else.  Terminal-emulator
   --    escape-sequence responses (DA1, XTVERSION, OSC 11, ...) are delivered
   --    as a stream of synthetic KEY_EVENT records with the response bytes
   --    in UnicodeChar -- exactly what we want.
   procedure Timed_Read
     (FD         : File_Descriptor;
      Buffer     : out Byte_Array;
      Bytes_Read : out Natural;
      Timeout_Ms : Natural;
      Timed_Out  : out Boolean)
   is
      use type Ada.Calendar.Time;
      Start_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed_Ms : Natural;
      Remaining  : Natural;
      Wait       : Win32.DWORD;
      Status     : Win32.BOOL;
      Got        : aliased Win32.DWORD := 0;
      Pending    : aliased Win32.DWORD := 0;
      Rec        : aliased Win32.Wincon.INPUT_RECORD;
   begin
      Buffer := [others => 0];
      Bytes_Read := 0;
      Timed_Out := False;

      if Buffer'Length = 0 then
         return;
      end if;
      if FD = INVALID_FD then
         return;
      end if;
      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         return;
      end if;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         if Slot.In_Origin = Not_Acquired then
            return;
         end if;

         Wait_Loop :
         loop
            Elapsed_Ms := Natural
              ((Ada.Calendar.Clock - Start_Time) * 1_000.0);
            if Elapsed_Ms >= Timeout_Ms then
               Timed_Out := (Bytes_Read = 0);
               return;
            end if;
            Remaining := Timeout_Ms - Elapsed_Ms;

            Wait := Win32.Winbase.WaitForSingleObject
                      (Slot.In_Handle, Win32.DWORD (Remaining));
            if Wait = Win32.Winbase.WAIT_TIMEOUT then
               Timed_Out := (Bytes_Read = 0);
               return;
            end if;
            if Wait /= Win32.Winbase.WAIT_OBJECT_0 then
               --  I/O error or abandoned wait: treat as 0 bytes, not timed out.
               return;
            end if;

            --  Drain the queue, collecting useful bytes from KEY_EVENT records
            --  and discarding mouse/focus/menu/window-resize events that
            --  signalled the wait but produce no readable bytes.
            Drain_Loop :
            loop
               exit Drain_Loop when Bytes_Read >= Buffer'Length;
               Got := 0;
               Status := Win32.Wincon.ReadConsoleInputW
                           (hConsoleInput        => Slot.In_Handle,
                            lpBuffer             => Rec'Unchecked_Access,
                            nLength              => 1,
                            lpNumberOfEventsRead => Got'Unchecked_Access);
               exit Drain_Loop when Status = Win32.FALSE or else Got = 0;

               if Rec.EventType = Win32.WORD (Win32.Wincon.KEY_EVENT)
                 and then Rec.Event.KeyEvent.bKeyDown /= Win32.FALSE
               then
                  declare
                     Code : constant Natural :=
                       Win32.WCHAR'Pos (Rec.Event.KeyEvent.uChar.UnicodeChar);
                  begin
                     if Code in 1 .. 255 then
                        Bytes_Read := Bytes_Read + 1;
                        Buffer (Buffer'First + Bytes_Read - 1) :=
                          Byte (Code);
                     end if;
                  end;
               end if;

               --  Stop draining if the queue is empty; otherwise the next
               --  ReadConsoleInputW call would block waiting for fresh events.
               Pending := 0;
               Status := Win32.Wincon.GetNumberOfConsoleInputEvents
                           (hConsoleInput        => Slot.In_Handle,
                            lpNumberOfEvents     => Pending'Unchecked_Access);
               exit Drain_Loop when Status = Win32.FALSE or else Pending = 0;
            end loop Drain_Loop;

            if Bytes_Read > 0 then
               return;  --  Got useful data; let the caller process it.
            end if;
            --  Otherwise we drained only non-byte events; loop back to wait
            --  for actual byte-producing input within the remaining budget.
         end loop Wait_Loop;
      end;
   end Timed_Read;

   ---------- Is_Foreground_Process ----------

   function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
   begin
      if FD = INVALID_FD then
         return False;
      end if;
      if Integer (FD) < Slots'First or else Integer (FD) > Slots'Last then
         return False;
      end if;

      declare
         Slot : Console_Slot renames Slots (Positive (FD));
      begin
         return Slot.In_Use
           and then (Slot.In_Origin /= Not_Acquired
                     or else Slot.Out_Origin /= Not_Acquired);
      end;
   end Is_Foreground_Process;

   ---------- Drain_Input ----------

   procedure Drain_Input (FD : File_Descriptor) is
      Drain_Buf  : Byte_Array (1 .. 256);
      Bytes_Read : Natural;
      Timed_Out  : Boolean;
   begin
      for Iter in 1 .. MAX_DRAIN_ITERATIONS loop
         Timed_Read (FD, Drain_Buf, Bytes_Read, 0, Timed_Out);
         exit when Bytes_Read = 0;
      end loop;
   end Drain_Input;

   ---------------------------------------------------------------------------
   --  Query Operations (FUNC-OSC-005, FUNC-OSC-006, FUNC-OSC-013)
   ---------------------------------------------------------------------------

   ---------- Write_Query ----------

   procedure Write_Query
     (Session : Probe_Session; Query : Byte_Array; Written : out Natural; Success : out Boolean)
   is
      Got    : aliased Win32.DWORD := 0;
      Status : Win32.BOOL;
   begin
      Written := 0;
      Success := False;

      if Query'Length = 0 then
         Success := True;
         return;
      end if;
      if Session.FD = INVALID_FD then
         return;
      end if;
      if Integer (Session.FD) < Slots'First
        or else Integer (Session.FD) > Slots'Last
      then
         return;
      end if;

      declare
         Slot   : Console_Slot renames Slots (Positive (Session.FD));
         Handle : Win32.Winnt.HANDLE;
      begin
         if Slot.Out_Origin /= Not_Acquired then
            Handle := Slot.Out_Handle;
         elsif Slot.In_Origin /= Not_Acquired then
            Handle := Slot.In_Handle;
         else
            return;
         end if;

         Status := Win32.Winbase.WriteFile
                     (hFile                  => Handle,
                      lpBuffer               => Query (Query'First)'Address,
                      nNumberOfBytesToWrite  => Win32.DWORD (Query'Length),
                      lpNumberOfBytesWritten => Got'Unchecked_Access,
                      lpOverlapped           => null);

         Written := Natural (Got);
         Success := (Status /= Win32.FALSE) and then Written = Query'Length;
      end;
   end Write_Query;

   ---------- Sentinel_Query ----------

   procedure Sentinel_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean;
      Retry       : Boolean := False)
   is

      procedure Do_Query (Effective_Timeout : Natural; Did_Time_Out : out Boolean; Out_Length : out Natural) is
         Buffer       : Response_Buffer := [others => 0];
         Length       : Natural := 0;
         Chunk        : Byte_Array (1 .. 512);
         Chunk_Len    : Natural;
         Chunk_Tout   : Boolean;
         Written      : Natural;
         Write_OK     : Boolean;
         Start_Time   : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Elapsed_Ms   : Natural;
         Remaining_Ms : Natural;
         Boundary     : Natural;
      begin
         Did_Time_Out := True;
         Out_Length := 0;

         --  Step 1: write the user query
         Write_Query (Session, Query, Written, Write_OK);
         if not Write_OK then
            return;
         end if;

         --  Step 1 (cont): write the DA1 sentinel
         Write_Query (Session, DA1_SENTINEL, Written, Write_OK);
         if not Write_OK then
            return;
         end if;

         --  Step 2: accumulate response until DA1 detected or timeout
         loop
            Elapsed_Ms := Natural (Ada.Calendar."-" (Ada.Calendar.Clock, Start_Time) * 1_000.0);

            if Elapsed_Ms >= Effective_Timeout then
               return;  --  total timeout expired
            end if;

            Remaining_Ms := Effective_Timeout - Elapsed_Ms;

            Timed_Read (Session.FD, Chunk, Chunk_Len, Remaining_Ms, Chunk_Tout);

            if Chunk_Tout or else Chunk_Len = 0 then
               return;  --  timeout or no data
            end if;

            --  Append chunk bytes to buffer (overflow protection FUNC-OSC-009)
            if Length + Chunk_Len > MAX_RESPONSE_SIZE then
               return;
            end if;

            for J in 1 .. Chunk_Len loop
               Buffer (Length + J) := Chunk (J);
            end loop;
            Length := Length + Chunk_Len;

            --  Check for DA1 sentinel in accumulated bytes
            if Termicap.OSC.Parsing.Contains_DA1_Response (Buffer, Length) then
               Boundary := Termicap.OSC.Parsing.DA1_Response_Start (Buffer, Length);

               if Boundary > 0 then
                  Out_Length := Boundary - 1;
               else
                  Out_Length := 0;
               end if;

               Response (1 .. Out_Length) := Buffer (1 .. Out_Length);
               Did_Time_Out := False;
               return;
            end if;
         end loop;
      end Do_Query;

      Did_Time_Out : Boolean;
      Out_Length   : Natural;

   begin
      Response := [others => 0];
      Resp_Length := 0;
      Timed_Out := True;

      Do_Query (Timeout_Ms, Did_Time_Out, Out_Length);

      if Did_Time_Out and then Retry then
         --  Step 3: retry with doubled timeout (FUNC-OSC-013)
         Do_Query (Timeout_Ms * 2, Did_Time_Out, Out_Length);
      end if;

      Timed_Out := Did_Time_Out;
      Resp_Length := Out_Length;
   end Sentinel_Query;

   ---------- Timeout_Query ----------

   procedure Timeout_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean)
   is
      Buffer       : Response_Buffer := [others => 0];
      Length       : Natural := 0;
      Chunk        : Byte_Array (1 .. 512);
      Chunk_Len    : Natural;
      Chunk_Tout   : Boolean;
      Written      : Natural;
      Write_OK     : Boolean;
      Start_Time   : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Elapsed_Ms   : Natural;
      Remaining_Ms : Natural;
   begin
      Response := [others => 0];
      Resp_Length := 0;
      Timed_Out := True;

      --  Write the query (e.g., DA1_QUERY).
      Write_Query (Session, Query, Written, Write_OK);
      if not Write_OK then
         return;
      end if;

      --  Accumulate bytes until Contains_DA1_Response or timeout.
      loop
         Elapsed_Ms := Natural (Ada.Calendar."-" (Ada.Calendar.Clock, Start_Time) * 1_000.0);

         exit when Elapsed_Ms >= Timeout_Ms;

         Remaining_Ms := Timeout_Ms - Elapsed_Ms;

         Timed_Read (Session.FD, Chunk, Chunk_Len, Remaining_Ms, Chunk_Tout);

         exit when Chunk_Tout or else Chunk_Len = 0;

         --  Overflow protection: treat overflow as timeout.
         exit when Length + Chunk_Len > MAX_RESPONSE_SIZE;

         for J in 1 .. Chunk_Len loop
            Buffer (Length + J) := Chunk (J);
         end loop;
         Length := Length + Chunk_Len;

         if Termicap.OSC.Parsing.Contains_DA1_Response (Buffer, Length) then
            Response (1 .. Length) := Buffer (1 .. Length);
            Resp_Length := Length;
            Timed_Out := False;
            return;
         end if;
      end loop;
   end Timeout_Query;

   ---------------------------------------------------------------------------
   --  Session Lifecycle (FUNC-OSC-008)
   ---------------------------------------------------------------------------

   ---------- Open ----------

   procedure Open (Session : in out Probe_Session; Status : out Session_Status) is
      FD       : File_Descriptor;
      Save_OK  : Boolean;
      Raw_OK   : Boolean;
      Acquired : Boolean;
   begin
      --  Step 1: acquire a usable console (Open_Terminal performs the
      --  STD_*_HANDLE -> CONIN$/CONOUT$ cascade and validates the handles).
      FD := Open_Terminal;
      if FD = INVALID_FD then
         Status := Session_No_Terminal;
         return;
      end if;

      --  Step 2: acquire the single-session guard (FUNC-OSC-012).
      Active_Session_Guard.Acquire (Acquired);
      if not Acquired then
         Close_Terminal (FD);
         Status := Session_Already_Active;
         return;
      end if;

      --  Step 3: defensive foreground check (Open_Terminal already enforces
      --  the contract, but symmetry with the POSIX body is intentional).
      if not Is_Foreground_Process (FD) then
         Close_Terminal (FD);
         Active_Session_Guard.Release;
         Status := Session_Not_Foreground;
         return;
      end if;

      Session.FD := FD;

      --  Step 4: save the current console modes (FUNC-OSC-002, FUNC-OSC-017).
      Save_Termios (Session.FD, Session.Saved_State, Save_OK);
      if not Save_OK then
         Close_Terminal (Session.FD);
         Active_Session_Guard.Release;
         Status := Session_Save_Failed;
         return;
      end if;

      --  Step 5: switch to raw + VT mode (FUNC-OSC-003, FUNC-OSC-017).
      Set_Raw_Mode (Session.FD, Session.Saved_State, Raw_OK);
      if not Raw_OK then
         declare
            Restore_OK : Boolean;
         begin
            Restore_Termios (Session.FD, Session.Saved_State, Restore_OK);
            pragma Unreferenced (Restore_OK);
         end;
         Close_Terminal (Session.FD);
         Active_Session_Guard.Release;
         Status := Session_Raw_Failed;
         return;
      end if;

      Session.Is_Raw := True;

      --  Step 6: drain stale input (FUNC-OSC-011).  Non-fatal.
      Drain_Input (Session.FD);

      Status := Session_OK;
   end Open;

   ---------- Is_Open ----------

   function Is_Open (Session : Probe_Session) return Boolean is
   begin
      return Session.FD /= INVALID_FD and then Session.Is_Raw;
   end Is_Open;

   ---------- Close ----------

   procedure Close (Session : in out Probe_Session) is
      Restore_OK : Boolean;
   begin
      if not Is_Open (Session) and then Session.FD = INVALID_FD then
         return;
      end if;

      --  Restore console mode; ignore failure (FUNC-OSC-008).
      if Session.Is_Raw then
         Restore_Termios (Session.FD, Session.Saved_State, Restore_OK);
         pragma Unreferenced (Restore_OK);
         Session.Is_Raw := False;
      end if;

      --  Close the underlying console handles.
      if Session.FD /= INVALID_FD then
         Close_Terminal (Session.FD);
      end if;

      --  Release the single-session guard (FUNC-OSC-012).
      Active_Session_Guard.Release;
   end Close;

   ---------- Finalize ----------

   overriding
   procedure Finalize (Session : in out Probe_Session) is
   begin
      Close (Session);
   end Finalize;

end Termicap.OSC;
