-------------------------------------------------------------------------------
--  Termicap.Clipboard.IO - OSC 52 Clipboard Detection I/O (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows implementation of the clipboard detection cascade.
--  Prepends a Win32 Console gate (Guard 4) before the POSIX-like cascade.
--
--  @description
--  Guard 4: GetConsoleMode (STD_OUTPUT_HANDLE).  If it succeeds, stdout is a
--  native Windows Console (not a Cygwin/MSYS PTY); run env-var heuristics only
--  (Probed = False) and return without active probing (FUNC-C52-012).  If it
--  fails, fall through to the POSIX-like cascade starting at the TTY guard
--  (Guard 1), which lets Cygwin/MSYS PTY sessions reach the DA1 / OSC 52 probes.
--
--  All other phases are identical to the POSIX body.  A single protected
--  object caches the result for the process lifetime (FUNC-C52-017);
--  Detect_Clipboard_Uncached bypasses the cache.
--
--  The outer exception handler satisfies the no-exception contract for
--  Detect_Clipboard (FUNC-C52-016).
--
--  Requirements Coverage:
--    - @relation(FUNC-C52-006): Clipboard inference from DA1 Ps=52
--    - @relation(FUNC-C52-007): Active OSC 52 read-back probe
--    - @relation(FUNC-C52-009): Passive env-var heuristics
--    - @relation(FUNC-C52-010): Combined detection cascade
--    - @relation(FUNC-C52-011): tmux and screen OSC 52 query passthrough
--    - @relation(FUNC-C52-012): Pre-condition guards including Win32 gate
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
with Termicap.Win32_VT;
with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Termicap.Clipboard.IO is

   use type Termicap.OSC.Session_Status;
   use type Win32.BOOL;

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
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_ITERM2) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_VSCODE) then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      if WT'Length > 0 then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
         Caps.Support           := Read_Write;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;

      if T'Length >= TERM_XTERM'Length
        and then Ada.Characters.Handling.To_Lower
                   (T (T'First .. T'First + TERM_XTERM'Length - 1)) = TERM_XTERM
      then
         Caps.Support           := Write_Only;
         Caps.Via_Env_Heuristic := True;
         return;
      end if;
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

         declare
            Wrapped_Query : constant Byte_Array :=
              Termicap.OSC.Parsing.Wrap_For_Passthrough (OSC52_QUERY, Passthrough);
         begin
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

      if Resp_Length = 0 then
         return Not_Present;
      end if;

      declare
         Slice : constant Byte_Array :=
           Byte_Array (Resp_Buffer (Resp_Buffer'First .. Resp_Buffer'First + Resp_Length - 1));
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
   --  @relation(FUNC-C52-012): Win32 + TTY guards
   --  @relation(FUNC-C52-013): No-TTY passive fallback
   --  @relation(FUNC-C52-016): No-exception guarantee

   function Run_Cascade return Clipboard_Capabilities is
      Caps : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
      Env  : Termicap.Environment.Environment;

      --  Win32 Console gate (FUNC-C52-012, Guard 4)
      H    : Win32.Winnt.HANDLE;
      Mode : aliased Win32.DWORD := 0;
      Res  : Win32.BOOL;
   begin
      --  Step 0: Capture environment once for all subsequent passive checks.
      Termicap.Environment.Capture.Capture_Current (Env);

      --  Guard 4 (Windows): Win32 Console gate (FUNC-C52-012).
      --  GetConsoleMode succeeding on STD_OUTPUT_HANDLE means stdout is a
      --  native Windows Console.  No OSC 52 probe is meaningful there; run
      --  env-var heuristics only with Probed = False.
      H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE);
      if Termicap.Win32_VT.Is_Valid_Handle (H) then
         Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
         if Res /= Win32.FALSE then
            Infer_Clipboard_From_Env (Env, Caps);
            return Caps;
         end if;
         --  GetConsoleMode returned FALSE: Cygwin/MSYS PTY, pipe, or file.
         --  Fall through to the POSIX-like cascade below.
      end if;

      --  Guard 1: TTY check (FUNC-C52-012).
      if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdout) then
         Infer_Clipboard_From_Env (Env, Caps);
         return Caps;
      end if;

      --  Phase 1: DA1 passive detection (FUNC-C52-006).
      declare
         DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
           Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => CLIPBOARD_PROBE_TIMEOUT_MS);
      begin
         if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Clipboard_Access) then
            Caps.Support := Write_Only;
            Caps.Via_DA1 := True;
            Caps.Probed  := True;
         elsif DA1_Caps.Supported then
            Caps.Probed := True;
         else
            null;
         end if;
      end;

      --  Phase 2: Active OSC 52 read-back probe (FUNC-C52-007).
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
      if Caps.Support = None then
         Infer_Clipboard_From_Env (Env, Caps);
      end if;

      return Caps;
   exception
      when others =>
         --  FUNC-C52-016: no-exception guarantee.
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
