-------------------------------------------------------------------------------
--  Termicap.Graphics.IO - Sixel / Kitty Graphics Detection I/O (POSIX Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  POSIX implementation of the graphics detection cascade.
--  Starts at guard 1 (TTY check); no Win32 dependencies.
--
--  @description
--  Implements the full detection cascade for POSIX platforms (Linux/macOS/BSD):
--
--  Step 1: Passive Kitty env-var harvest (FUNC-SXL-009) — always runs.
--    KITTY_WINDOW_ID present => Kitty_Graphics_Supported := True.
--    TERM = "xterm-kitty" => Kitty_Graphics_Supported := True.
--    TERM_PROGRAM = "WezTerm" => Kitty_Graphics_Supported := True.
--
--  Step 2: Passive Sixel env-var harvest (FUNC-SXL-008) — always runs.
--    TERM_PROGRAM = "WezTerm" => Sixel_Supported := True.
--    TERM in exact-match set (xterm-kitty, foot, foot-extra, mlterm, yaft).
--    TERM starts with "xterm" => Sixel_Supported := True (imprecise fallback).
--
--  Guard 1 (FUNC-SXL-012): Is_TTY (Stdout) = False => return passive only.
--  Guards 2+3: Foreground guard + /dev/tty open, composed inside DA1/probe sessions.
--
--  Step 3: DA1 active probe for Sixel Ps=4 (FUNC-SXL-005, FUNC-SXL-006).
--    Call Termicap.DA1.IO.Detect_DA1; test Sixel_Graphics flag.
--
--  Step 4: XTVERSION name-substring fallback (FUNC-SXL-007).
--    Only when Sixel_Via_DA1 = False; case-insensitive "kitty" / "WezTerm".
--
--  Step 5: Optional Kitty APC active probe (FUNC-SXL-010).
--    Only when Kitty_Graphics_Supported is still False after passive harvest.
--    Send KITTY_APC_QUERY + DA1 sentinel; parse with Parse_Kitty_APC_Response.
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-005): Sixel via DA1 Has_Capability
--    - @relation(FUNC-SXL-006): DA1 probe session via Detect_DA1
--    - @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
--    - @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
--    - @relation(FUNC-SXL-009): Passive Kitty env-var heuristics
--    - @relation(FUNC-SXL-010): Optional Kitty APC active probe
--    - @relation(FUNC-SXL-012): TTY guard (Guard 1) before active probes
--    - @relation(FUNC-SXL-013): No-TTY passive fallback
--    - @relation(FUNC-SXL-014): Termios restore via Probe_Session RAII
--    - @relation(FUNC-SXL-015): 1000 ms per-session timeout
--    - @relation(FUNC-SXL-016): No-exception guarantee
--    - @relation(FUNC-SXL-017): One-probe-per-process cache

pragma SPARK_Mode (Off);

with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Termicap.DA1;
with Termicap.DA1.IO;
with Termicap.Environment.Capture;
with Termicap.OSC;
with Termicap.TTY;
with Termicap.Version;
with Termicap.XTVERSION.IO;

package body Termicap.Graphics.IO is

   use type Termicap.OSC.Session_Status;
   use type Termicap.XTVERSION.XTVERSION_Status;

   ---------------------------------------------------------------------------
   --  Protected cache (FUNC-SXL-017)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean := False;
      Value       : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
   end record;

   protected Cache is
      function Get_Cached return Cache_Slot;
      procedure Set_Cached (Caps : Graphics_Capabilities);
   private
      Slot : Cache_Slot := (Initialized => False, Value => NO_GRAPHICS_CAPABILITIES);
   end Cache;

   protected body Cache is
      function Get_Cached return Cache_Slot is
      begin
         return Slot;
      end Get_Cached;

      procedure Set_Cached (Caps : Graphics_Capabilities) is
      begin
         Slot := (Initialized => True, Value => Caps);
      end Set_Cached;
   end Cache;

   ---------------------------------------------------------------------------
   --  Passive env-var harvest helpers
   ---------------------------------------------------------------------------

   --  @summary Return True when env-var heuristics indicate Kitty graphics support.
   --  @description Checks KITTY_WINDOW_ID (presence/non-empty), TERM=xterm-kitty,
   --  TERM_PROGRAM=WezTerm (case-insensitive).
   --  @relation(FUNC-SXL-009): Passive Kitty env-var heuristics
   function Has_Kitty_Graphics_From_Env (Env : Termicap.Environment.Environment) return Boolean is
      KW : constant String := Termicap.Environment.Value (Env, ENV_KITTY_WINDOW_ID);
      T  : constant String := Termicap.Environment.Value (Env, "TERM");
      TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
   begin
      --  Step 1: KITTY_WINDOW_ID present and non-empty (highest confidence).
      if KW'Length > 0 then
         return True;
      end if;

      --  Step 2: TERM = xterm-kitty (exact, case-insensitive).
      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
         return True;
      end if;

      --  Step 3: TERM_PROGRAM = WezTerm (case-insensitive).
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         return True;
      end if;

      return False;
   end Has_Kitty_Graphics_From_Env;

   --  @summary Return True when env-var heuristics indicate Sixel support.
   --  @description Checks TERM_PROGRAM=WezTerm and TERM exact matches for the
   --  set of terminals whose stable identity is reliably Sixel-capable
   --  (foot, foot-extra, mlterm, mlterm-256color, yaft).  The legacy
   --  "TERM prefix xterm" fallback was removed in B2a because every modern
   --  terminal advertises TERM=xterm-256color and the prefix has no positive
   --  predictive value; xterm-kitty was also removed because kitty
   --  intentionally rejects sixel.  DA1 (FUNC-SXL-005) remains the
   --  authoritative answer for everything else.
   --  @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
   function Has_Sixel_From_Env (Env : Termicap.Environment.Environment) return Boolean is
      MLTERM_256COLOR : constant String := "mlterm-256color";

      T  : constant String := Termicap.Environment.Value (Env, "TERM");
      TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
   begin
      --  Step 1: TERM_PROGRAM = WezTerm (case-insensitive).
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         return True;
      end if;

      --  Step 2: TERM exact matches for known Sixel-capable terminals.
      --  Note: TERM_XTERM_KITTY is intentionally NOT in this list — kitty
      --  has its own graphics protocol and does not implement sixel.
      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT)
        or else Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT_EXTRA)
        or else Termicap.Environment.Equal_Case_Insensitive (T, TERM_MLTERM)
        or else Termicap.Environment.Equal_Case_Insensitive (T, MLTERM_256COLOR)
        or else Termicap.Environment.Equal_Case_Insensitive (T, TERM_YAFT)
      then
         return True;
      end if;

      return False;
   end Has_Sixel_From_Env;

   --  @summary Return True when the XTVERSION terminal name indicates Sixel support.
   --  @description Case-insensitive substring match for "kitty" and "WezTerm"
   --  in the XTVERSION-reported terminal name.
   --  @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
   function Has_Sixel_From_XTVERSION_Name (Name : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
      use Ada.Strings.Unbounded;
      Lower : constant String := Ada.Characters.Handling.To_Lower (To_String (Name));
   begin
      return
        Ada.Strings.Fixed.Index (Lower, Ada.Characters.Handling.To_Lower (XTVERSION_NAME_KITTY)) > 0
        or else Ada.Strings.Fixed.Index (Lower, Ada.Characters.Handling.To_Lower (XTVERSION_NAME_WEZTERM)) > 0;
   end Has_Sixel_From_XTVERSION_Name;

   --  @summary Run the optional Kitty APC active probe.
   --  @description Opens a Probe_Session, sends KITTY_APC_QUERY + DA1 sentinel,
   --  reads response with timeout, parses with Parse_Kitty_APC_Response.
   --  Returns Not_Present on session failure or empty response.
   --  RAII Probe_Session guarantees termios restore (FUNC-SXL-014).
   --  @relation(FUNC-SXL-010): Optional Kitty APC active probe
   function Run_APC_Probe return APC_Parse_Result is
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

      --  Sentinel_Query writes KITTY_APC_QUERY then a DA1 sentinel (ESC [ c),
      --  then reads until the DA1 response terminates the session.
      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => KITTY_APC_QUERY,
         Response    => Resp_Buffer,
         Resp_Length => Resp_Length,
         Timeout_Ms  => GRAPHICS_PROBE_TIMEOUT_MS,
         Timed_Out   => Timed_Out,
         Retry       => False);

      --  Probe_Session goes out of scope when Run_APC_Probe returns; RAII
      --  Finalize unconditionally restores termios and closes /dev/tty
      --  (FUNC-SXL-014).
      if Resp_Length = 0 then
         return Not_Present;
      end if;

      declare
         Slice : constant Byte_Array :=
           Byte_Array (Resp_Buffer (Resp_Buffer'First .. Resp_Buffer'First + Resp_Length - 1));
      begin
         return Parse_Kitty_APC_Response (Slice, Resp_Length);
      end;
   end Run_APC_Probe;

   ---------------------------------------------------------------------------
   --  Internal worker: run the full detection cascade without caching
   ---------------------------------------------------------------------------

   --  @relation(FUNC-SXL-005): Sixel detection via DA1 Has_Capability
   --  @relation(FUNC-SXL-006): DA1 probe session via Detect_DA1
   --  @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
   --  @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
   --  @relation(FUNC-SXL-009): Passive Kitty env-var heuristics
   --  @relation(FUNC-SXL-010): Optional Kitty APC active probe
   --  @relation(FUNC-SXL-012): TTY guard (Guard 1)
   --  @relation(FUNC-SXL-013): No-TTY passive fallback
   --  @relation(FUNC-SXL-016): No-exception guarantee
   function Run_Cascade return Graphics_Capabilities is
      Caps : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
      Env  : Termicap.Environment.Environment;
   begin
      --  Step 0: Capture environment once for all subsequent passive checks.
      Termicap.Environment.Capture.Capture_Current (Env);

      --  Step 1: Passive Kitty env-var harvest (FUNC-SXL-009).
      --  Independent of TTY status: KITTY_WINDOW_ID may be set even on piped
      --  output (FUNC-SXL-013).
      if Has_Kitty_Graphics_From_Env (Env) then
         Caps.Kitty_Graphics_Supported := True;
      end if;

      --  Step 2: Passive Sixel env-var harvest (FUNC-SXL-008).
      --  Same TTY-independence as step 1.
      if Has_Sixel_From_Env (Env) then
         Caps.Sixel_Supported := True;
      end if;

      --  Guard 1: TTY check (FUNC-SXL-012).
      --  Skip all active probes when stdout is not a terminal; passive results
      --  preserved.  Probed stays False (FUNC-SXL-013).
      if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdout) then
         return Caps;
      end if;

      --  Step 3: DA1 active probe for Sixel Ps=4 (FUNC-SXL-005, FUNC-SXL-006).
      --  Detect_DA1 reuses the cached DA1 result from Termicap.DA1.IO if
      --  available (ADR-0027). Guards 2+3 (foreground + /dev/tty) are composed
      --  inside Detect_DA1's own Probe_Session.Open call.
      declare
         DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
           Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
      begin
         if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Sixel_Graphics) then
            Caps.Sixel_Supported := True;
            Caps.Sixel_Via_DA1 := True;
            Caps.Probed := True;
         elsif DA1_Caps.Supported then
            --  DA1 returned a valid response without Ps=4: authoritative
            --  negative.  Override any over-eager passive heuristic so the
            --  terminal's own answer wins (B2b, FUNC-SXL-005/006).
            Caps.Sixel_Supported := False;
            Caps.Sixel_Via_DA1 := False;
            Caps.Probed := True;
         else
            --  DA1 timed out / session failed: keep whatever passive set.
            null;
         end if;
      end;

      --  Step 4: XTVERSION name-substring fallback (FUNC-SXL-007).
      --  Skip when DA1 already confirmed Sixel (authoritative).
      --  Also skip when DA1 authoritatively negated Sixel (B2c): the
      --  terminal's own DA1 reply trumps an XTVERSION-name substring match,
      --  preventing iTerm2-named knock-offs from re-promoting after a clear
      --  DA1 "no" answer.
      if not Caps.Sixel_Via_DA1 and then not (Caps.Probed and then not Caps.Sixel_Supported) then
         declare
            XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
              Termicap.XTVERSION.IO.Query_And_Identify (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
         begin
            if XTV.Status = Termicap.XTVERSION.Success and then Has_Sixel_From_XTVERSION_Name (XTV.Terminal_Name) then
               Caps.Sixel_Supported := True;
               --  Sixel_Via_DA1 stays False (provenance is XTVERSION, not DA1).
               Caps.Probed := True;
            end if;
         end;
      end if;

      --  Step 5: Optional Kitty APC active probe (FUNC-SXL-010).
      --  Skip when env-var harvest already established Kitty support.
      --  Skip for Apple Terminal: it does not implement APC (ESC _) and prints
      --  the query content as literal text, corrupting the terminal output.
      if not Caps.Kitty_Graphics_Supported
        and then not Termicap.Environment.Equal_Case_Insensitive
                       (Termicap.Environment.Value (Env, "TERM_PROGRAM"), TERM_PROGRAM_APPLE_TERMINAL)
      then
         declare
            APC_Result : constant APC_Parse_Result := Run_APC_Probe;
         begin
            if APC_Result = OK then
               Caps.Kitty_Graphics_Supported := True;
               Caps.Kitty_Via_Active_Probe := True;
               Caps.Probed := True;
            end if;
         end;
      end if;

      --  Step 6: XTVERSION-driven Kitty graphics refinement (B3a, FUNC-SXL-010).
      --  When the APC probe did not establish Kitty support (timeout, Apple
      --  Terminal skip, or terminal answered Error), query XTVERSION and
      --  consult the curated known-good name+version table for terminals that
      --  are documented to support the kitty graphics protocol but did not
      --  answer the APC probe in time (notably iTerm2 >= 3.6).
      if not Caps.Kitty_Graphics_Supported then
         declare
            XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
              Termicap.XTVERSION.IO.Query_And_Identify (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
         begin
            Caps := Refine_Kitty_With_XTVERSION (Caps, XTV);
         end;
      end if;

      return Caps;
   exception
      when others =>
         --  FUNC-SXL-016: no-exception guarantee — any failure degrades safely.
         return NO_GRAPHICS_CAPABILITIES;
   end Run_Cascade;

   ---------------------------------------------------------------------------
   --  Detect_Graphics (FUNC-SXL-016, FUNC-SXL-017)
   ---------------------------------------------------------------------------

   function Detect_Graphics return Graphics_Capabilities is
      Cached : Cache_Slot;
   begin
      Cached := Cache.Get_Cached;
      if Cached.Initialized then
         return Cached.Value;
      end if;

      declare
         Result : constant Graphics_Capabilities := Run_Cascade;
      begin
         Cache.Set_Cached (Result);
         return Result;
      end;
   exception
      when others =>
         return NO_GRAPHICS_CAPABILITIES;
   end Detect_Graphics;

   ---------------------------------------------------------------------------
   --  Detect_Graphics_Uncached (FUNC-SXL-017 Should Clause)
   ---------------------------------------------------------------------------

   function Detect_Graphics_Uncached return Graphics_Capabilities is
   begin
      return Run_Cascade;
   exception
      when others =>
         return NO_GRAPHICS_CAPABILITIES;
   end Detect_Graphics_Uncached;

   ---------------------------------------------------------------------------
   --  Known-good Kitty graphics XTVERSION table (B3a, FUNC-SXL-010)
   ---------------------------------------------------------------------------

   type Known_Good_Kitty_Entry is record
      Name        : access constant String;
      Min_Version : Termicap.Version.Version;
      Treat_Any   : Boolean;
   end record;

   --  Name literals stored in lowercase for case-insensitive lookup.
   ITERM2_KITTY_NAME  : aliased constant String := "iterm2";
   KITTY_KITTY_NAME   : aliased constant String := "kitty";
   WEZTERM_KITTY_NAME : aliased constant String := "wezterm";
   GHOSTTY_KITTY_NAME : aliased constant String := "ghostty";
   KONSOLE_KITTY_NAME : aliased constant String := "konsole";

   KNOWN_GOOD_KITTY : constant array (1 .. 5) of Known_Good_Kitty_Entry :=
     [1 => (Name => ITERM2_KITTY_NAME'Access, Min_Version => Termicap.Version.Make (3, 6, 0), Treat_Any => False),
      2 => (Name => KITTY_KITTY_NAME'Access, Min_Version => Termicap.Version.Make (0, 20, 0), Treat_Any => False),
      3 => (Name => WEZTERM_KITTY_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True),
      4 => (Name => GHOSTTY_KITTY_NAME'Access, Min_Version => Termicap.Version.ZERO_VERSION, Treat_Any => True),
      5 => (Name => KONSOLE_KITTY_NAME'Access, Min_Version => Termicap.Version.Make (22, 4, 0), Treat_Any => False)];

   ---------------------------------------------------------------------------
   --  Refine_Kitty_With_XTVERSION (B3a, FUNC-SXL-010)
   ---------------------------------------------------------------------------

   function Refine_Kitty_With_XTVERSION
     (Passive : Graphics_Capabilities; XTV : Termicap.XTVERSION.XTVERSION_Result) return Graphics_Capabilities
   is
      Promoted : Graphics_Capabilities := Passive;
   begin
      Promoted.Kitty_Graphics_Supported := True;
      --  Provenance: XTVERSION-driven, not the active APC probe.
      Promoted.Kitty_Via_Active_Probe := False;

      --  No active refinement when XTVERSION did not succeed.
      if XTV.Status /= Termicap.XTVERSION.Success then
         return Passive;
      end if;

      declare
         use Ada.Strings.Unbounded;
         Name_Lower  : constant String := Ada.Characters.Handling.To_Lower (To_String (XTV.Terminal_Name));
         Entry_Found : Boolean := False;
         Entry_Idx   : Positive := 1;
      begin
         for I in KNOWN_GOOD_KITTY'Range loop
            if Name_Lower = KNOWN_GOOD_KITTY (I).Name.all then
               Entry_Found := True;
               Entry_Idx := I;
               exit;
            end if;
         end loop;

         if not Entry_Found then
            return Passive;
         end if;

         --  "Any version" entries: name match alone is sufficient.
         if KNOWN_GOOD_KITTY (Entry_Idx).Treat_Any then
            return Promoted;
         end if;

         --  Strict-version entries: parse the reported version and compare.
         declare
            Reported : Termicap.Version.Version;
            Ok       : Boolean;
         begin
            Termicap.Version.Parse (To_String (XTV.Terminal_Version), Reported, Ok);
            if not Ok then
               return Passive;
            end if;

            case Termicap.Version.Compare (Reported, KNOWN_GOOD_KITTY (Entry_Idx).Min_Version) is
               when Termicap.Version.Less_Than =>
                  return Passive;

               when Termicap.Version.Equal | Termicap.Version.Greater_Than =>
                  return Promoted;
            end case;
         end;
      end;
   exception
      when others =>
         return Passive;
   end Refine_Kitty_With_XTVERSION;

end Termicap.Graphics.IO;
