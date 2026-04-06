-------------------------------------------------------------------------------
--  Termicap.OSC - OSC Probe Session and Terminal I/O (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Full Unix implementation of the OSC probe session package.
--
--  @description
--  This body implements the probe session lifecycle via C helper functions
--  for termios, select(), ioctl, read, write, and open/close of /dev/tty.
--  A protected object (Active_Session_Guard) enforces single-session
--  semantics.  The Finalize override guarantees terminal state restoration
--  even when an exception propagates through the query phase.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-001): Open_Terminal / Close_Terminal via C helper
--    - @relation(FUNC-OSC-002): Save_Termios / Restore_Termios via C helper
--    - @relation(FUNC-OSC-003): Set_Raw_Mode via C helper
--    - @relation(FUNC-OSC-004): Timed_Read via select() C helper
--    - @relation(FUNC-OSC-005): Write_Query via write() C helper
--    - @relation(FUNC-OSC-006): Sentinel_Query loop with DA1 detection
--    - @relation(FUNC-OSC-007): Is_Foreground_Process via ioctl C helper
--    - @relation(FUNC-OSC-008): Open / Close / Finalize lifecycle
--    - @relation(FUNC-OSC-009): MAX_RESPONSE_SIZE overflow protection
--    - @relation(FUNC-OSC-011): Drain_Input bounded non-blocking loop
--    - @relation(FUNC-OSC-012): Active_Session_Guard single-session guard
--    - @relation(FUNC-OSC-013): Optional retry in Sentinel_Query
--    - @relation(FUNC-OSC-015): SPARK_Mode Off; FFI boundary

pragma SPARK_Mode (Off);

with Ada.Calendar;
with System;
with Termicap.OSC.Parsing;

package body Termicap.OSC is

   use type Interfaces.C.int;

   ---------------------------------------------------------------------------
   --  C FFI Bindings
   ---------------------------------------------------------------------------

   --  open("/dev/tty", O_RDWR) via C helper (FUNC-OSC-001).
   function C_Open_TTY return Interfaces.C.int;
   pragma Import (C, C_Open_TTY, "termicap_osc_open_tty");

   --  close(fd) via C helper (FUNC-OSC-001).
   function C_Close_FD (FD : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Close_FD, "termicap_osc_close_fd");

   --  tcgetattr wrapper: copies struct termios into Ada buffer (FUNC-OSC-002).
   function C_Save_Termios
     (FD          : Interfaces.C.int;
      Buf         : System.Address;
      Buf_Size    : Interfaces.C.int;
      Actual_Size : access Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Save_Termios, "termicap_osc_save_termios");

   --  tcsetattr(TCSANOW) wrapper: restores struct termios from Ada buffer (FUNC-OSC-002).
   function C_Restore_Termios
     (FD : Interfaces.C.int; Buf : System.Address; Size : Interfaces.C.int)
      return Interfaces.C.int;
   pragma Import (C, C_Restore_Termios, "termicap_osc_restore_termios");

   --  Raw-mode derivation and application via tcsetattr (FUNC-OSC-003).
   function C_Set_Raw
     (FD        : Interfaces.C.int;
      Saved_Buf : System.Address;
      Size      : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Set_Raw, "termicap_osc_set_raw");

   --  select() + read() with millisecond timeout (FUNC-OSC-004).
   function C_Timed_Read
     (FD         : Interfaces.C.int;
      Buf        : System.Address;
      Buf_Size   : Interfaces.C.int;
      Timeout_Ms : Interfaces.C.int;
      Bytes_Read : access Interfaces.C.int;
      Timed_Out  : access Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Timed_Read, "termicap_osc_timed_read");

   --  write() wrapper (FUNC-OSC-005).
   function C_Write
     (FD      : Interfaces.C.int;
      Buf     : System.Address;
      Len     : Interfaces.C.int;
      Written : access Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Write, "termicap_osc_write");

   --  ioctl(TIOCGPGRP) + getpgrp() comparison (FUNC-OSC-007).
   function C_Is_Foreground (FD : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Is_Foreground, "termicap_osc_is_foreground");

   ---------------------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------------------

   --  Maximum non-blocking drain iterations (FUNC-OSC-011).
   MAX_DRAIN_ITERATIONS : constant := 16;

   --  DA1 sentinel bytes: ESC [ c  (3 bytes: 0x1B 0x5B 0x63) (FUNC-OSC-006).
   DA1_SENTINEL : constant Byte_Array (1 .. 3) := [16#1B#, 16#5B#, 16#63#];

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
   --  Internal Terminal Operations (FUNC-OSC-001..003, FUNC-OSC-011)
   ---------------------------------------------------------------------------

   function Open_Terminal return File_Descriptor is
      Result : constant Interfaces.C.int := C_Open_TTY;
   begin
      if Result < 0 then
         return INVALID_FD;
      end if;
      return File_Descriptor (Result);
   end Open_Terminal;

   procedure Close_Terminal (FD : in out File_Descriptor) is
      Status : Interfaces.C.int;
      pragma Unreferenced (Status);
   begin
      if FD /= INVALID_FD then
         Status := C_Close_FD (Interfaces.C.int (FD));
         FD := INVALID_FD;
      end if;
   end Close_Terminal;

   procedure Save_Termios
     (FD : File_Descriptor; State : out Termios_State; OK : out Boolean)
   is
      Actual_Size : aliased Interfaces.C.int := 0;
      Status      : Interfaces.C.int;
   begin
      State.Data := [others => 0];
      State.Size := 0;

      Status :=
        C_Save_Termios
          (Interfaces.C.int (FD),
           State.Data (State.Data'First)'Address,
           Interfaces.C.int (MAX_TERMIOS_SIZE),
           Actual_Size'Access);

      if Status = 0 then
         State.Size := Natural (Actual_Size);
         OK := True;
      else
         OK := False;
      end if;
   end Save_Termios;

   procedure Restore_Termios
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      Status : Interfaces.C.int;
   begin
      if State.Size = 0 then
         OK := False;
         return;
      end if;

      Status :=
        C_Restore_Termios
          (Interfaces.C.int (FD),
           State.Data (State.Data'First)'Address,
           Interfaces.C.int (State.Size));

      OK := (Status = 0);
   end Restore_Termios;

   procedure Set_Raw_Mode
     (FD : File_Descriptor; State : Termios_State; OK : out Boolean)
   is
      Status : Interfaces.C.int;
   begin
      if State.Size = 0 then
         OK := False;
         return;
      end if;

      Status :=
        C_Set_Raw
          (Interfaces.C.int (FD),
           State.Data (State.Data'First)'Address,
           Interfaces.C.int (State.Size));

      OK := (Status = 0);
   end Set_Raw_Mode;

   ---------------------------------------------------------------------------
   --  Low-Level I/O (FUNC-OSC-004, FUNC-OSC-005, FUNC-OSC-007)
   ---------------------------------------------------------------------------

   procedure Timed_Read
     (FD         : File_Descriptor;
      Buffer     : out Byte_Array;
      Bytes_Read : out Natural;
      Timeout_Ms : Natural;
      Timed_Out  : out Boolean)
   is
      C_Bytes_Read : aliased Interfaces.C.int := 0;
      C_Timed_Out  : aliased Interfaces.C.int := 0;
      Status       : Interfaces.C.int;
   begin
      Buffer := [others => 0];
      Bytes_Read := 0;
      Timed_Out := False;

      if Buffer'Length = 0 then
         return;
      end if;

      Status :=
        C_Timed_Read
          (Interfaces.C.int (FD),
           Buffer (Buffer'First)'Address,
           Interfaces.C.int (Buffer'Length),
           Interfaces.C.int (Timeout_Ms),
           C_Bytes_Read'Access,
           C_Timed_Out'Access);

      if Status /= 0 then
         --  select() or read() error Ã¢ÂÂ treat as 0 bytes, not timed out
         return;
      end if;

      Bytes_Read := Natural (C_Bytes_Read);
      Timed_Out := (C_Timed_Out /= 0);
   end Timed_Read;

   function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
      Result : constant Interfaces.C.int :=
        C_Is_Foreground (Interfaces.C.int (FD));
   begin
      return Result = 1;
   end Is_Foreground_Process;

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

   procedure Write_Query
     (Session : Probe_Session;
      Query   : Byte_Array;
      Written : out Natural;
      Success : out Boolean)
   is
      C_Written : aliased Interfaces.C.int := 0;
      Status    : Interfaces.C.int;
   begin
      Written := 0;
      Success := False;

      if Query'Length = 0 then
         Success := True;
         return;
      end if;

      Status :=
        C_Write
          (Interfaces.C.int (Session.FD),
           Query (Query'First)'Address,
           Interfaces.C.int (Query'Length),
           C_Written'Access);

      Written := Natural (C_Written);
      Success := (Status = 0) and then Written = Query'Length;
   end Write_Query;

   procedure Sentinel_Query
     (Session     : Probe_Session;
      Query       : Byte_Array;
      Response    : out Response_Buffer;
      Resp_Length : out Natural;
      Timeout_Ms  : Natural;
      Timed_Out   : out Boolean;
      Retry       : Boolean := False)
   is

      procedure Do_Query
        (Effective_Timeout : Natural;
         Did_Time_Out      : out Boolean;
         Out_Length        : out Natural)
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
            --  Compute elapsed time and remaining budget
            Elapsed_Ms :=
              Natural
                (Ada.Calendar."-" (Ada.Calendar.Clock, Start_Time) * 1_000.0);

            if Elapsed_Ms >= Effective_Timeout then
               return;  --  total timeout expired

            end if;

            Remaining_Ms := Effective_Timeout - Elapsed_Ms;

            Timed_Read
              (Session.FD, Chunk, Chunk_Len, Remaining_Ms, Chunk_Tout);

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
               Boundary :=
                 Termicap.OSC.Parsing.DA1_Response_Start (Buffer, Length);

               --  Boundary is the 1-based index of the ESC that starts DA1;
               --  pre-sentinel bytes are 1 .. Boundary-1.
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
      Response    := [others => 0];
      Resp_Length := 0;
      Timed_Out   := True;

      --  Write the query (e.g., DA1_QUERY).
      Write_Query (Session, Query, Written, Write_OK);
      if not Write_OK then
         return;
      end if;

      --  Accumulate bytes until Contains_DA1_Response or timeout.
      loop
         Elapsed_Ms :=
           Natural
             (Ada.Calendar."-" (Ada.Calendar.Clock, Start_Time) * 1_000.0);

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

   procedure Open (Session : in out Probe_Session; Status : out Session_Status)
   is
      Save_OK  : Boolean;
      Raw_OK   : Boolean;
      Acquired : Boolean;
   begin
      --  Step 1: foreground process group check (FUNC-OSC-007).
      --  We need a temporary FD to check; open /dev/tty first for the check,
      --  but actually the spec says to check before opening. Use stdout (fd 1)
      --  as a temporary handle for the foreground check.
      declare
         Temp_FD : constant File_Descriptor := Open_Terminal;
      begin
         if Temp_FD = INVALID_FD then
            Status := Session_No_Terminal;
            return;
         end if;

         if not Is_Foreground_Process (Temp_FD) then
            declare
               Dummy_FD : File_Descriptor := Temp_FD;
            begin
               Close_Terminal (Dummy_FD);
            end;
            Status := Session_Not_Foreground;
            return;
         end if;

         --  Step 2: acquire single-session guard (FUNC-OSC-012).
         Active_Session_Guard.Acquire (Acquired);
         if not Acquired then
            declare
               Dummy_FD : File_Descriptor := Temp_FD;
            begin
               Close_Terminal (Dummy_FD);
            end;
            Status := Session_Already_Active;
            return;
         end if;

         --  FD is already open from step 1; store it in the session.
         Session.FD := Temp_FD;
      end;

      --  Step 3: save termios state (FUNC-OSC-002).
      Save_Termios (Session.FD, Session.Saved_State, Save_OK);
      if not Save_OK then
         Close_Terminal (Session.FD);
         Active_Session_Guard.Release;
         Status := Session_Save_Failed;
         return;
      end if;

      --  Step 4: activate raw mode (FUNC-OSC-003).
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

      --  Step 5: drain stale input (FUNC-OSC-011).  Non-fatal.
      Drain_Input (Session.FD);

      Status := Session_OK;
   end Open;

   function Is_Open (Session : Probe_Session) return Boolean is
   begin
      return Session.FD /= INVALID_FD and then Session.Is_Raw;
   end Is_Open;

   procedure Close (Session : in out Probe_Session) is
      Restore_OK : Boolean;
   begin
      if not Is_Open (Session) and then Session.FD = INVALID_FD then
         return;
      end if;

      --  Restore termios; ignore failure (FUNC-OSC-008).
      if Session.Is_Raw then
         Restore_Termios (Session.FD, Session.Saved_State, Restore_OK);
         pragma Unreferenced (Restore_OK);
         Session.Is_Raw := False;
      end if;

      --  Close the file descriptor.
      if Session.FD /= INVALID_FD then
         Close_Terminal (Session.FD);
      end if;

      --  Release the single-session guard (FUNC-OSC-012).
      Active_Session_Guard.Release;
   end Close;

   overriding
   procedure Finalize (Session : in out Probe_Session) is
   begin
      Close (Session);
   end Finalize;

end Termicap.OSC;
