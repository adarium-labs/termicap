-------------------------------------------------------------------------------
--  Termicap.Clipboard.IO - OSC 52 Clipboard Detection I/O (POSIX Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX implementation of the clipboard detection cascade.
--  Starts at Guard 1 (TTY check); no Win32 dependencies.
--
--  @description
--  Implements the full three-phase detection cascade for POSIX platforms:
--
--  Guard 1 (FUNC-C52-012): Is_TTY (Stdout) = False => skip active probes;
--    run env-var heuristics only (Probed = False, FUNC-C52-013).
--  Guards 2+3: Foreground guard + /dev/tty openability, composed inside
--    Probe_Session.Open inside Run_OSC52_Probe and Detect_DA1.
--
--  Phase 1: DA1 passive detection (FUNC-C52-006).
--    Call Termicap.DA1.IO.Detect_DA1 (cached); if Has_Capability (DA1_Caps,
--    Clipboard_Access) then Support := Write_Only, Via_DA1 := True,
--    Probed := True.
--
--  Phase 2: Active OSC 52 read-back probe (FUNC-C52-007, FUNC-C52-011).
--    Opens a Probe_Session, sends OSC52_QUERY (wrapped for tmux/screen),
--    reads with Sentinel_Query, parses with Parse_OSC52_Response.  If
--    Valid_Response, Support := Read_Write, Via_Active_Probe := True,
--    Probed := True.  Skipped when Support is already Read_Write.
--
--  Phase 3: Env-var heuristics (FUNC-C52-009).
--    Applied only when Support = None after Phases 1 and 2.
--    TERM_PROGRAM=WezTerm|iTerm.app -> Read_Write.
--    TERM_PROGRAM=vscode -> Write_Only.
--    WT_SESSION present -> Write_Only.
--    TERM=xterm-kitty -> Read_Write.
--    TERM prefix "xterm" -> Write_Only.
--
--  Requirements Coverage:
--    - @relation(FUNC-C52-006): Clipboard inference from DA1 Ps=52
--    - @relation(FUNC-C52-007): Active OSC 52 read-back probe
--    - @relation(FUNC-C52-009): Passive env-var heuristics
--    - @relation(FUNC-C52-010): Combined detection cascade
--    - @relation(FUNC-C52-011): tmux and screen OSC 52 query passthrough
--    - @relation(FUNC-C52-012): Pre-condition guards and TTY guards
--    - @relation(FUNC-C52-013): No-TTY passive fallback
--    - @relation(FUNC-C52-014): Termios restore via Probe_Session RAII
--    - @relation(FUNC-C52-015): 1000 ms per-session timeout
--    - @relation(FUNC-C52-016): No-exception guarantee
--    - @relation(FUNC-C52-017): One-probe-per-process cache; uncached bypass

pragma SPARK_Mode (Off);

with Ada.Characters.Handling;
with Termicap.DA1;
with Termicap.DA1.IO;
with Termicap.Environment;
with Termicap.Environment.Capture;
with Termicap.OSC;
with Termicap.OSC.Parsing;
with Termicap.TTY;

package body Termicap.Clipboard.IO is

   use type Termicap.OSC.Session_Status;

   ---------------------------------------------------------------------------
   --  Protected cache (FUNC-C52-017)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
   end record;

   protected Cache is
      function Get_Cached return Cache_Slot;
      procedure Set_Cached (Caps : Clipboard_Capabilities);
   private
      Slot : Cache_Slot := (Initialized => False, Value => NO_CLIPBOARD_CAPABILITIES);
   end Cache;

   protected body Cache is
      function Get_Cached return Cache_Slot is
      begin
         return Slot;
      end Get_Cached;

      procedure Set_Cached (Caps : Clipboard_Capabilities) is
      begin
         Slot := (Initialized => True, Value => Caps);
      end Set_Cached;
   end Cache;

   ---------------------------------------------------------------------------
   --  Phase 3: Env-var heuristics helper (FUNC-C52-009)
   ---------------------------------------------------------------------------

   --  @summary Infer clipboard support level from environment variable heuristics.
   --  @description Checks TERM_PROGRAM (WezTerm, iTerm.app -> Read_Write;
   --  vscode -> Write_Only), WT_SESSION presence (Write_Only), TERM=xterm-kitty
   --  (Read_Write), and TERM prefix "xterm" (Write_Only).  Sets Via_Env_Heuristic
   --  on the first match.  Support remains None when no heuristic matches.
   --  @param Env  The captured environment snapshot.
   --  @param Caps The clipboard capabilities record to update in place.
   --  @relation(FUNC-C52-009): Passive env-var heuristics

   procedure Infer_Clipboard_From_Env
     (Env  :        Termicap.Environment.Environment;
      Caps : in out Clipboard_Capabilities)
   is
      TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
      T  : constant String := Termicap.Environment.Value (Env, "TERM");
      WT : constant String := Termicap.Environment.Value (Env, ENV_WT_SESSION);
   begin
      --  Step 1: TERM_PROGRAM = WezTerm (case-insensitive) -> Read_Write.
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  Step 1 continued: TERM_PROGRAM = iTerm.app (case-insensitive) -> Read_Write.
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_ITERM2) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  Step 2: TERM_PROGRAM = vscode (case-insensitive) -> Write_Only.
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_VSCODE) then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  Step 3: WT_SESSION present and non-empty -> Write_Only (Windows Terminal).
      if WT'Length > 0 then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  Step 4: TERM = xterm-kitty (exact, case-insensitive) -> Read_Write.
      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  Step 4 continued: TERM starts with "xterm" (prefix, lower-cased) -> Write_Only.
      --  Conservative: allowWindowOps (gates read-back) is disabled by default.
      if T'Length >= TERM_XTERM'Length
        and then Ada.Characters.Handling.To_Lower
                   (T (T'First .. T'First + TERM_XTERM'Length - 1)) = TERM_XTERM
      then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      --  No heuristic matched.  Support remains as supplied by the caller.
   end Infer_Clipboard_From_Env;

   ---------------------------------------------------------------------------
   --  Phase 2: Active OSC 52 read-back probe helper (FUNC-C52-007, FUNC-C52-011)
   ---------------------------------------------------------------------------

   --  @summary Send OSC52_QUERY + DA1 sentinel and parse the response.
   --  @description Opens a Probe_Session, derives the multiplexer passthrough mode
   --  from TMUX / STY environment variables, wraps OSC52_QUERY if required, calls
   --  Sentinel_Query, then parses the result with Parse_OSC52_Response.
   --  Returns Not_Present on session failure or empty response.
   --  RAII Probe_Session guarantees termios restore (FUNC-C52-014).
   --  @param Env  The captured environment snapshot (for TMUX / STY detection).
   --  @return OSC52_Parse_Result indicating whether a valid read-back was received.
   --  @relation(FUNC-C52-007): Active OSC 52 probe with DA1 sentinel boundary
   --  @relation(FUNC-C52-011): tmux and screen passthrough wrapping

   function Run_OSC52_Probe
     (Env : Termicap.Environment.Environment) return OSC52_Parse_Result
   is
      Session     : Termicap.OSC.Probe_Session;
      Status      : Termicap.OSC.Session_Status;
      Resp_Buffer : Termicap.OSC.Response_Buffer;
      Resp_Length : Natural := 0;
      Timed_Out   : Boolean := False;
   begin
      Termicap.OSC.Open (Session, Status);
      if Status /= Termicap.OSC.Session_OK then
         return Not_Present;
      end if;

      --  Determine multiplexer passthrough mode from environment variables.
      --  TMUX set -> Tmux_Passthrough; STY set -> Screen_Passthrough; else No_Passthrough.
      declare
         Tmux_Val    : constant String :=
           Termicap.Environment.Value (Env, ENV_TMUX);
         STY_Val     : constant String :=
           Termicap.Environment.Value (Env, ENV_STY);
         Passthrough : Termicap.OSC.Parsing.Passthrough_Mode :=
           Termicap.OSC.Parsing.No_Passthrough;
      begin
         if Tmux_Val'Length > 0 then
            Passthrough := Termicap.OSC.Parsing.Tmux_Passthrough;
         elsif STY_Val'Length > 0 then
            Passthrough := Termicap.OSC.Parsing.Screen_Passthrough;
         end if;

         --  Wrap OSC52_QUERY in the appropriate DCS envelope (or leave unwrapped).
         declare
            Wrapped_Query : constant Termicap.OSC.Byte_Array :=
              Termicap.OSC.Parsing.Wrap_For_Passthrough
                (Termicap.OSC.Byte_Array (OSC52_QUERY), Passthrough);
         begin
            --  Sentinel_Query writes the (possibly wrapped) OSC52_QUERY, appends the
            --  DA1 sentinel (ESC [ c), then reads until the DA1 response terminates.
            --  The DA1 sentinel is placed outside the DCS passthrough envelope by
            --  Sentinel_Query, so the multiplexer forwards it directly (FUNC-C52-011).
            Termicap.OSC.Sentinel_Query
              (Session     => Session,
               Query       => Wrapped_Query,
               Response    => Resp_Buffer,
               Resp_Length => Resp_Length,
               Timeout_Ms  => CLIPBOARD_PROBE_TIMEOUT_MS,
               Timed_Out   => Timed_Out,
               Retry       => False);
         end;
      end;

      --  Probe_Session goes out of scope when Run_OSC52_Probe returns; RAII
      --  Finalize unconditionally restores termios and closes /dev/tty (FUNC-C52-014).
      if Resp_Length = 0 then
         return Not_Present;
      end if;

      declare
         Slice : constant Termicap.Clipboard.Byte_Array :=
           Termicap.Clipboard.Byte_Array
             (Resp_Buffer (Resp_Buffer'First .. Resp_Buffer'First + Resp_Length - 1));
      begin
         return Parse_OSC52_Response (Slice, Resp_Length);
      end;
   end Run_OSC52_Probe;

   ---------------------------------------------------------------------------
   --  Internal worker: full detection cascade without caching
   ---------------------------------------------------------------------------

   --  @relation(FUNC-C52-006): Clipboard inference from DA1 Ps=52
   --  @relation(FUNC-C52-007): Active OSC 52 read-back probe
   --  @relation(FUNC-C52-009): Passive env-var heuristics
   --  @relation(FUNC-C52-010): Combined detection cascade
   --  @relation(FUNC-C52-011): tmux and screen OSC 52 query passthrough
   --  @relation(FUNC-C52-012): TTY guard (Guard 1)
   --  @relation(FUNC-C52-013): No-TTY passive fallback
   --  @relation(FUNC-C52-016): No-exception guarantee

   function Run_Cascade return Clipboard_Capabilities is
      Caps : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
      Env  : Termicap.Environment.Environment;
   begin
      --  Step 0: Capture environment once for all subsequent passive checks.
      Termicap.Environment.Capture.Capture_Current (Env);

      --  Guard 1: TTY check (FUNC-C52-012).
      --  Skip all active probes when stdout is not a terminal; preserve passive
      --  heuristic results.  Probed stays False (FUNC-C52-013).
      if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdout) then
         Infer_Clipboard_From_Env (Env, Caps);
         return Caps;
      end if;

      --  Phase 1: DA1 passive detection (FUNC-C52-006).
      --  Reuses the cached DA1 result from Termicap.DA1.IO when available
      --  (ADR-0027).  Guards 2 + 3 (foreground + /dev/tty open) are composed
      --  inside Detect_DA1's own Probe_Session.Open call.
      declare
         DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
           Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => CLIPBOARD_PROBE_TIMEOUT_MS);
      begin
         if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Clipboard_Access) then
            --  DA1 Ps=52 present: terminal advertises OSC 52 support.
            --  DA1 alone establishes Write_Only (not Read_Write): Ps=52 means
            --  the terminal understands OSC 52, but does not confirm read-back
            --  (e.g., xterm advertises Ps=52 even when allowWindowOps is false).
            Caps.Support := Write_Only;
            Caps.Via_DA1 := True;
            Caps.Probed  := True;
         elsif DA1_Caps.Supported then
            --  DA1 returned a valid response but Ps=52 absent: terminal
            --  explicitly reports no clipboard support.  Probed = True.
            Caps.Probed := True;
         else
            --  DA1 timed out or session failed.  Probed stays False.
            null;
         end if;
      end;

      --  Phase 2: Active OSC 52 read-back probe (FUNC-C52-007).
      --  Runs regardless of Phase 1 outcome: can upgrade Write_Only -> Read_Write,
      --  or detect Read_Write even when DA1 lacked Ps=52.
      --  Skipped only when Phase 1 already established Read_Write (impossible here
      --  because DA1 alone yields at most Write_Only, but the guard future-proofs).
      if Caps.Support /= Read_Write then
         declare
            OSC52_Result : constant OSC52_Parse_Result := Run_OSC52_Probe (Env);
         begin
            if OSC52_Result = Valid_Response then
               Caps.Support          := Read_Write;
               Caps.Via_Active_Probe := True;
               Caps.Probed           := True;
            end if;
         end;
      end if;

      --  Phase 3: Env-var heuristics (FUNC-C52-009).
      --  Applied only when Support is still None after Phases 1 and 2.
      --  DA1 / active-probe results are more authoritative than env-var inference;
      --  this phase is skipped when either Phase 1 or Phase 2 yielded a result.
      if Caps.Support = None then
         Infer_Clipboard_From_Env (Env, Caps);
      end if;

      return Caps;
   exception
      when others =>
         --  FUNC-C52-016: no-exception guarantee — any failure degrades safely.
         return NO_CLIPBOARD_CAPABILITIES;
   end Run_Cascade;

   ---------------------------------------------------------------------------
   --  Detect_Clipboard (FUNC-C52-016, FUNC-C52-017)
   ---------------------------------------------------------------------------

   function Detect_Clipboard return Clipboard_Capabilities is
      Cached : constant Cache_Slot := Cache.Get_Cached;
   begin
      if Cached.Initialized then
         return Cached.Value;
      end if;
      declare
         Result : constant Clipboard_Capabilities := Run_Cascade;
      begin
         Cache.Set_Cached (Result);
         return Result;
      end;
   exception
      when others =>
         return NO_CLIPBOARD_CAPABILITIES;  --  FUNC-C52-016
   end Detect_Clipboard;

   ---------------------------------------------------------------------------
   --  Detect_Clipboard_Uncached (FUNC-C52-017 Should Clause)
   ---------------------------------------------------------------------------

   function Detect_Clipboard_Uncached return Clipboard_Capabilities is
   begin
      return Run_Cascade;
   exception
      when others =>
         return NO_CLIPBOARD_CAPABILITIES;  --  FUNC-C52-016
   end Detect_Clipboard_Uncached;

end Termicap.Clipboard.IO;
