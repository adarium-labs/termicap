-------------------------------------------------------------------------------
--  Termicap.Mouse.IO - Mouse Protocol Detection I/O (POSIX Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX implementation of the mouse protocol detection cascade.
--  Starts at guard 2 (Linux/GPM heuristic); no Win32 dependencies.
--
--  @description
--  Implements the five-guard detection cascade (FUNC-MSE-009) and the batched
--  DECRPM probe session (FUNC-MSE-005, ADR-0022) on POSIX platforms.
--
--  Guard 2: Linux/GPM heuristic (FUNC-MSE-011, ADR-0024) — if TERM=linux
--    and /dev/gpmctl exists, return GPM_Available = True immediately.
--  Guard 3: Non-TTY guard (FUNC-MSE-009) — if Is_TTY (Stdin) = False,
--    return NO_MOUSE_CAPABILITIES.
--  Guards 4+5: Foreground + /dev/tty open, composed inside Probe_Session.Open.
--  Probe: batched six-mode DECRPM session with one DA1 sentinel (ADR-0022).
--    Write six DECRPM queries via Write_Query, then a single empty Sentinel_Query.
--    Parse all DECRPM frames from the accumulated response buffer.
--    Call Resolve_Best_Encoding to compute Best_Encoding.
--    Set Probed := True.
--
--  Requirements Coverage:
--    - @relation(FUNC-MSE-005): Single batched DECRPM probe session (ADR-0022)
--    - @relation(FUNC-MSE-009): Five-guard cascade (guards 2-5 on POSIX)
--    - @relation(FUNC-MSE-011): Linux/GPM heuristic (ADR-0024)
--    - @relation(FUNC-MSE-014): No-exception guarantee
--    - @relation(FUNC-MSE-015): Termios restore via Probe_Session RAII
--    - @relation(FUNC-MSE-016): Process-lifetime cache

pragma SPARK_Mode (Off);

with Ada.Directories;
with Interfaces.C;
with Termicap.DECRPM;
with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.OSC;
with Termicap.TTY;

package body Termicap.Mouse.IO is

   use type Interfaces.C.unsigned_char;
   use type Termicap.DECRPM.Mode_Status;
   use type Termicap.OSC.Session_Status;

   ---------------------------------------------------------------------------
   --  Protected cache (FUNC-MSE-016)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
   end record;

   protected Cache is
      function Get_Cached return Cache_Slot;
      procedure Set_Cached (Caps : Mouse_Capabilities);
   private
      Slot : Cache_Slot := (Initialized => False, Value => NO_MOUSE_CAPABILITIES);
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

   --  @summary Construct the canonical GPM-available result.
   --  @relation(FUNC-MSE-011): GPM heuristic fired; GPM_Available = True
   function Make_GPM_Result return Mouse_Capabilities
   is ((Best_Encoding         => Unknown,
        Supports_X10          => False,
        Supports_Button_Event => False,
        Supports_Any_Event    => False,
        Supports_URXVT        => False,
        Supports_SGR          => False,
        Supports_SGR_Pixels   => False,
        Win32_Console_Mouse   => False,
        GPM_Available         => True,
        Probed                => False));

   --  @summary Finalise a probed Mouse_Capabilities: set Probed=True and
   --  derive Best_Encoding via the cascade.
   --  @relation(FUNC-MSE-008): Resolve_Best_Encoding applied to Caps
   function Make_Probed_Result (Caps : Mouse_Capabilities) return Mouse_Capabilities is
      Result : Mouse_Capabilities := Caps;
   begin
      Result.Probed := True;
      Result.Best_Encoding := Resolve_Best_Encoding (Result);
      return Result;
   end Make_Probed_Result;

   ---------------------------------------------------------------------------
   --  Guard 2 helper: Linux/GPM heuristic (FUNC-MSE-011, ADR-0024)
   ---------------------------------------------------------------------------

   --  @summary Return True when TERM=linux and /dev/gpmctl exists.
   --  @description Two exception layers ensure FUNC-MSE-014 is satisfied:
   --  the inner layer covers Ada.Directories.Exists (may raise on symlink loops
   --  or unusual /dev configurations); the outer layer covers
   --  Capture_Current or any unforeseen OS failure.
   --  @relation(FUNC-MSE-011): TERM=linux + /dev/gpmctl existence check
   function Is_Linux_Console_With_GPM return Boolean is
      Env : Termicap.Environment.Environment;
   begin
      Termicap.Environment.Capture.Capture_Current (Env);
      if not Termicap.Environment.Equal_Case_Insensitive (Termicap.Environment.Value (Env, "TERM"), "linux") then
         return False;
      end if;

      declare
         Exists : Boolean := False;
      begin
         Exists := Ada.Directories.Exists ("/dev/gpmctl");
         return Exists;
      exception
         when others =>
            --  FUNC-MSE-014: symlink loops or unusual /dev: treat as absent.
            return False;
      end;
   exception
      when others =>
         --  Belt-and-braces: environment-capture failure or any other OS error.
         return False;
   end Is_Linux_Console_With_GPM;

   ---------------------------------------------------------------------------
   --  Probe helpers: Apply_Mode_Status and Parse_All_Responses
   ---------------------------------------------------------------------------

   --  @summary Apply a single DECRPM mode/status result to Mouse_Capabilities.
   --  @description Status /= Not_Recognized means the terminal supports the mode.
   --  @relation(FUNC-MSE-006): Pm /= 0 => Supports_* = True
   procedure Apply_Mode_Status
     (Caps : in out Mouse_Capabilities; Mode : Termicap.DECRPM.Mode_Id; Status : Termicap.DECRPM.Mode_Status)
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
   function Parse_All_Responses (Buf : Termicap.OSC.Response_Buffer; Len : Natural) return Mouse_Capabilities is
      Caps  : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
      I     : Positive := Buf'First;
      Slice : constant Byte_Array := Byte_Array (Buf (Buf'First .. Buf'Last));
   begin
      while I <= Buf'First + Len - 1 loop
         --  Skip non-ESC bytes.
         while I <= Buf'First + Len - 1 and then Slice (I) /= 16#1B# loop
            I := I + 1;
         end loop;

         --  Need at least 8 bytes (ESC [ ? d ; d $ y) for a valid DECRPM frame.
         exit when I + 7 > Buf'First + Len - 1;

         --  Try to parse a DECRPM frame starting at I.
         declare
            Tail_Len : constant Natural := Buf'First + Len - I;
            Tail     : constant Byte_Array := Slice (I .. I + Tail_Len - 1);
            Result   : constant DECRPM_Parse_Result := Parse_Mouse_DECRPM_Response (Tail, Tail_Len);
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
   --  1006, 1016.  Phase 2: Sentinel_Query with empty query bytes (empty Query
   --  causes only the DA1 sentinel to be sent).  Phase 3: Parse all DECRPM
   --  frames from the accumulated response buffer.
   --  @relation(FUNC-MSE-005): Single batched probe session (ADR-0022)
   function Run_Batched_DECRPM_Probe (Session : Termicap.OSC.Probe_Session) return Mouse_Capabilities is
      --  Six mouse modes in fixed issue order (FUNC-MSE-004).
      --  Responses are matched by Ps, not by position.
      Modes : constant array (1 .. 6) of Termicap.DECRPM.Mode_Id :=
        [MODE_MOUSE_X10,
         MODE_MOUSE_BUTTON_EVENT,
         MODE_MOUSE_ANY_EVENT,
         MODE_MOUSE_URXVT,
         MODE_MOUSE_SGR,
         MODE_MOUSE_SGR_PIXELS];

      --  Zero-length query: Sentinel_Query will write only the DA1 sentinel.
      Empty_Query : constant Byte_Array (1 .. 0) := [];

      Resp_Buffer : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural := 0;
      Timed_Out   : Boolean := False;
      Written     : Natural := 0;
      Write_OK    : Boolean := False;
   begin
      --  Phase 1: Write all six DECRPM queries without reading.
      for I in Modes'Range loop
         declare
            Q : constant Byte_Array := Termicap.DECRPM.DECRPM_Query (Modes (I));
         begin
            Termicap.OSC.Write_Query
              (Session => Session, Query => Q, Written => Written, Success => Write_OK);
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
      --  Partial-response case: Resp_Length > 0 but Timed_Out = True means
      --  we have some frames; preserve them (FUNC-MSE-013 partial results).
      if Resp_Length = 0 then
         return NO_MOUSE_CAPABILITIES;
      end if;

      return Parse_All_Responses (Resp_Buffer, Resp_Length);
   end Run_Batched_DECRPM_Probe;

   ---------------------------------------------------------------------------
   --  Internal worker: run the full detection cascade without caching
   ---------------------------------------------------------------------------

   --  @relation(FUNC-MSE-009): Full five-guard cascade (POSIX: guards 2-5)
   --  @relation(FUNC-MSE-014): No-exception guarantee
   function Run_Cascade return Mouse_Capabilities is
      use Termicap.OSC;
      Session : Termicap.OSC.Probe_Session;
      Status  : Termicap.OSC.Session_Status;
      Caps    : Mouse_Capabilities;
   begin
      --  Guard 2: Linux/GPM heuristic (FUNC-MSE-011, ADR-0024).
      --  POSIX-only; Windows body omits this guard.
      if Is_Linux_Console_With_GPM then
         return Make_GPM_Result;
      end if;

      --  Guard 3: Non-TTY guard (FUNC-MSE-009 step 3).
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
