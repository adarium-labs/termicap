-------------------------------------------------------------------------------
--  Termicap.Mouse.IO - Mouse Protocol Detection I/O (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows implementation of the mouse protocol detection cascade.
--  Starts at guard 1 (Win32 Console gate), then falls through to the
--  POSIX-like DECRPM path for Cygwin/MSYS2 PTY sessions.
--
--  @description
--  Guard 1: Win32 Console gate (FUNC-MSE-010) — GetConsoleMode (STD_INPUT_HANDLE)
--    succeeds => return Win32_Console_Mouse = True immediately.
--  Guard 3: Non-TTY guard — Is_TTY (Stdin) = False => return NO_MOUSE_CAPABILITIES.
--  Guards 4+5: Foreground + /dev/tty open, composed inside Probe_Session.Open.
--  Probe: batched six-mode DECRPM session with one DA1 sentinel (ADR-0022).
--    Write six DECRPM queries via Write_Query, then single empty Sentinel_Query.
--    Parse all DECRPM frames from the accumulated response buffer.
--    Call Resolve_Best_Encoding to compute Best_Encoding.
--    Set Probed := True.
--
--  Requirements Coverage:
--    - @relation(FUNC-MSE-005): Single batched DECRPM probe session (ADR-0022)
--    - @relation(FUNC-MSE-009): Five-guard cascade
--    - @relation(FUNC-MSE-010): Win32 Console platform gate
--    - @relation(FUNC-MSE-014): No-exception guarantee
--    - @relation(FUNC-MSE-015): Termios restore via Probe_Session RAII
--    - @relation(FUNC-MSE-016): Process-lifetime cache

pragma SPARK_Mode (Off);

with Interfaces.C;
with Termicap.DECRPM;
with Termicap.OSC;
with Termicap.TTY;
with Termicap.Win32_VT;
with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Termicap.Mouse.IO is

   use type Win32.BOOL;
   use type Interfaces.C.unsigned_char;
   use type Termicap.DECRPM.Mode_Status;
   use type Termicap.OSC.Session_Status;

   ---------------------------------------------------------------------------
   --  Protected cache (FUNC-MSE-016)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean            := False;
      Value       : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
   end record;

   protected Cache is
      function  Get_Cached return Cache_Slot;
      procedure Set_Cached (Caps : Mouse_Capabilities);
   private
      Slot : Cache_Slot :=
        (Initialized => False, Value => NO_MOUSE_CAPABILITIES);
   end Cache;

   protected body Cache is
      function Get_Cached return Cache_Slot is
      begin
         return Slot;
      end Get_Cached;

      procedure Set_Cached (Caps : Mouse_Capabilities) is
      begin
         Slot := (Initialized => True, Value => Caps);
      end Set_Cached;
   end Cache;

   ---------------------------------------------------------------------------
   --  Body-private constructor helpers (FUNC-MSE-002, tech spec §F.3)
   ---------------------------------------------------------------------------

   --  @summary Construct the canonical Win32-Console-detected result.
   --  @relation(FUNC-MSE-010): Win32 gate fired; Win32_Console_Mouse = True
   function Make_Win32_Result return Mouse_Capabilities is
     ((Best_Encoding         => Unknown,
       Supports_X10          => False,
       Supports_Button_Event => False,
       Supports_Any_Event    => False,
       Supports_URXVT        => False,
       Supports_SGR          => False,
       Supports_SGR_Pixels   => False,
       Win32_Console_Mouse   => True,
       GPM_Available         => False,
       Probed                => False));

   --  @summary Finalise a probed Mouse_Capabilities: set Probed=True and
   --  derive Best_Encoding via the cascade.
   --  @relation(FUNC-MSE-008): Resolve_Best_Encoding applied to Caps
   function Make_Probed_Result
     (Caps : Mouse_Capabilities) return Mouse_Capabilities
   is
      Result : Mouse_Capabilities := Caps;
   begin
      Result.Probed        := True;
      Result.Best_Encoding := Resolve_Best_Encoding (Result);
      return Result;
   end Make_Probed_Result;

   ---------------------------------------------------------------------------
   --  Probe helpers: Apply_Mode_Status and Parse_All_Responses
   ---------------------------------------------------------------------------

   --  @summary Apply a single DECRPM mode/status result to Mouse_Capabilities.
   --  @description Status /= Not_Recognized means the terminal supports the mode.
   --  @relation(FUNC-MSE-006): Pm /= 0 => Supports_* = True
   procedure Apply_Mode_Status
     (Caps   : in out Mouse_Capabilities;
      Mode   : Termicap.DECRPM.Mode_Id;
      Status : Termicap.DECRPM.Mode_Status)
   is
      Supported : constant Boolean := Status /= Termicap.DECRPM.Not_Recognized;
   begin
      if Mode = MODE_MOUSE_X10 then
         Caps.Supports_X10 := Supported;
      elsif Mode = MODE_MOUSE_BUTTON_EVENT then
         Caps.Supports_Button_Event := Supported;
      elsif Mode = MODE_MOUSE_ANY_EVENT then
         Caps.Supports_Any_Event := Supported;
      elsif Mode = MODE_MOUSE_URXVT then
         Caps.Supports_URXVT := Supported;
      elsif Mode = MODE_MOUSE_SGR then
         Caps.Supports_SGR := Supported;
      elsif Mode = MODE_MOUSE_SGR_PIXELS then
         Caps.Supports_SGR_Pixels := Supported;
      else
         null;  --  Unrecognised mode in the response; ignore.
      end if;
   end Apply_Mode_Status;

   --  @summary Scan a raw response buffer for all DECRPM frames and populate
   --  Mouse_Capabilities per-mode flags.
   --  @description Linear scan O(Len). Advances by at least one byte per
   --  iteration. All buffers are stack-resident; no allocation occurs.
   --  @relation(FUNC-MSE-006): Multi-frame scanning per ADR-0022
   function Parse_All_Responses
     (Buf : Termicap.OSC.Response_Buffer;
      Len : Natural) return Mouse_Capabilities
   is
      Caps  : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
      I     : Positive := Buf'First;
      Slice : constant Termicap.Mouse.Byte_Array :=
        Termicap.Mouse.Byte_Array (Buf (Buf'First .. Buf'Last));
   begin
      while I <= Buf'First + Len - 1 loop
         --  Skip non-ESC bytes.
         while I <= Buf'First + Len - 1
           and then Slice (I) /= 16#1B#
         loop
            I := I + 1;
         end loop;

         --  Need at least 8 bytes (ESC [ ? d ; d $ y) for a valid DECRPM frame.
         exit when I + 7 > Buf'First + Len - 1;

         --  Try to parse a DECRPM frame starting at I.
         declare
            Tail_Len : constant Natural := Buf'First + Len - I;
            Tail     : constant Termicap.Mouse.Byte_Array :=
              Slice (I .. I + Tail_Len - 1);
            Result   : constant DECRPM_Parse_Result :=
              Parse_Mouse_DECRPM_Response (Tail, Tail_Len);
         begin
            if Result.Valid then
               Apply_Mode_Status (Caps, Result.Mode, Result.Status);
            end if;
         end;
         --  Always advance by at least one byte to guarantee termination.
         I := I + 1;
      end loop;

      return Caps;
   end Parse_All_Responses;

   ---------------------------------------------------------------------------
   --  The batched DECRPM probe (FUNC-MSE-004, FUNC-MSE-005, ADR-0022)
   ---------------------------------------------------------------------------

   --  @summary Write six DECRPM queries and one DA1 sentinel; parse responses.
   --  @description Phase 1: Write_Query x 6 for modes 1000, 1002, 1003, 1015,
   --  1006, 1016.  Phase 2: Sentinel_Query with empty query bytes (only DA1
   --  sentinel is written).  Phase 3: Parse all DECRPM frames.
   --  @relation(FUNC-MSE-005): Single batched probe session (ADR-0022)
   function Run_Batched_DECRPM_Probe
     (Session : Termicap.OSC.Probe_Session) return Mouse_Capabilities
   is
      --  Six mouse modes in fixed issue order (FUNC-MSE-004).
      Modes : constant array (1 .. 6) of Termicap.DECRPM.Mode_Id :=
        [MODE_MOUSE_X10,
         MODE_MOUSE_BUTTON_EVENT,
         MODE_MOUSE_ANY_EVENT,
         MODE_MOUSE_URXVT,
         MODE_MOUSE_SGR,
         MODE_MOUSE_SGR_PIXELS];

      --  Zero-length query: Sentinel_Query will write only the DA1 sentinel.
      Empty_Query : constant Termicap.OSC.Byte_Array (1 .. 0) := [];

      Resp_Buffer : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural  := 0;
      Timed_Out   : Boolean  := False;
      Written     : Natural  := 0;
      Write_OK    : Boolean  := False;
   begin
      --  Phase 1: Write all six DECRPM queries without reading.
      for I in Modes'Range loop
         declare
            Q : constant Termicap.DECRPM.Byte_Array :=
              Termicap.DECRPM.DECRPM_Query (Modes (I));
         begin
            Termicap.OSC.Write_Query
              (Session => Session,
               Query   => Termicap.OSC.Byte_Array (Q),
               Written => Written,
               Success => Write_OK);
            if not Write_OK then
               --  Partial/failed write: bail; Probed stays False.
               return NO_MOUSE_CAPABILITIES;
            end if;
         end;
      end loop;

      --  Phase 2: Send DA1 sentinel and read until DA1 response terminates
      --  the batch (FUNC-MSE-013: 1000 ms total timeout).
      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => Empty_Query,
         Response    => Resp_Buffer,
         Resp_Length => Resp_Length,
         Timeout_Ms  => MOUSE_PROBE_TIMEOUT_MS,
         Timed_Out   => Timed_Out,
         Retry       => False);

      if Timed_Out and then Resp_Length = 0 then
         --  FUNC-MSE-013: total timeout, no usable data => Unknown.
         return NO_MOUSE_CAPABILITIES;
      end if;

      --  Phase 3: Scan the accumulated buffer for all DECRPM frames.
      if Resp_Length = 0 then
         return NO_MOUSE_CAPABILITIES;
      end if;

      return Parse_All_Responses (Resp_Buffer, Resp_Length);
   end Run_Batched_DECRPM_Probe;

   ---------------------------------------------------------------------------
   --  Internal worker: run the full detection cascade without caching
   ---------------------------------------------------------------------------

   --  @relation(FUNC-MSE-009): Full five-guard cascade
   --  @relation(FUNC-MSE-010): Win32 Console gate (guard 1)
   --  @relation(FUNC-MSE-014): No-exception guarantee
   function Run_Cascade return Mouse_Capabilities is
      use Termicap.OSC;

      Session : Termicap.OSC.Probe_Session;
      Status  : Termicap.OSC.Session_Status;
      Caps    : Mouse_Capabilities;

      --  Win32 gate variables (FUNC-MSE-010)
      H    : Win32.Winnt.HANDLE;
      Mode : aliased Win32.DWORD := 0;
      Res  : Win32.BOOL;
   begin
      --  Guard 1: Win32 Console gate (FUNC-MSE-010).
      --  If GetConsoleMode succeeds on STD_INPUT_HANDLE, stdin is a native
      --  Windows Console; return Win32_Console_Mouse = True immediately.
      H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_INPUT_HANDLE);
      if Termicap.Win32_VT.Is_Valid_Handle (H) then
         Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
         if Res /= Win32.FALSE then
            --  Native Windows Console confirmed; DECRPM probe is not applicable.
            return Make_Win32_Result;
         end if;
         --  GetConsoleMode returned FALSE: Cygwin/MSYS2 PTY or file.
         --  Fall through to the POSIX-like cascade.
      end if;

      --  Guard 3: Non-TTY guard (FUNC-MSE-009 step 3).
      --  (Guard 2 / GPM heuristic is POSIX-only; Windows body skips it.)
      if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdin) then
         return NO_MOUSE_CAPABILITIES;
      end if;

      --  Guards 4+5: Foreground guard + /dev/tty openability (FUNC-MSE-009
      --  steps 4-5), composed inside Probe_Session.Open (FUNC-OSC-007/008).
      Termicap.OSC.Open (Session, Status);
      if Status /= Termicap.OSC.Session_OK then
         return NO_MOUSE_CAPABILITIES;
      end if;

      --  Batched DECRPM probe (FUNC-MSE-005, ADR-0022).
      --  Probe_Session goes out of scope when Run_Cascade returns; RAII
      --  Finalize unconditionally restores termios (FUNC-MSE-015).
      Caps := Run_Batched_DECRPM_Probe (Session);

      --  Finalise: set Probed=True and derive Best_Encoding.
      return Make_Probed_Result (Caps);
   exception
      when others =>
         --  FUNC-MSE-014: no-exception guarantee — any failure degrades safely.
         return NO_MOUSE_CAPABILITIES;
   end Run_Cascade;

   ---------------------------------------------------------------------------
   --  Detect_Mouse_Protocols (FUNC-MSE-009, FUNC-MSE-016)
   ---------------------------------------------------------------------------

   function Detect_Mouse_Protocols return Mouse_Capabilities is
      Cached : Cache_Slot;
   begin
      Cached := Cache.Get_Cached;
      if Cached.Initialized then
         return Cached.Value;
      end if;

      declare
         Result : constant Mouse_Capabilities := Run_Cascade;
      begin
         Cache.Set_Cached (Result);
         return Result;
      end;
   exception
      when others =>
         return NO_MOUSE_CAPABILITIES;
   end Detect_Mouse_Protocols;

   ---------------------------------------------------------------------------
   --  Probe_Mouse_Protocols (FUNC-MSE-016 Should Clause)
   ---------------------------------------------------------------------------

   function Probe_Mouse_Protocols return Mouse_Capabilities is
   begin
      return Run_Cascade;
   exception
      when others =>
         return NO_MOUSE_CAPABILITIES;
   end Probe_Mouse_Protocols;

end Termicap.Mouse.IO;
