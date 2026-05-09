-------------------------------------------------------------------------------
--  Termicap.Graphics.IO - Sixel / Kitty Graphics Detection I/O (Windows Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Windows implementation of the graphics detection cascade.
--  Starts at Guard 4 (Win32 Console gate), then falls through to the
--  POSIX-like TTY/foreground/probe cascade for Cygwin/MSYS2 PTY sessions.
--
--  @description
--  Guard 4 (FUNC-SXL-012, evaluated FIRST on Windows per spec):
--    GetConsoleMode (STD_OUTPUT_HANDLE) succeeds => stdout is a Win32 Console;
--    return passive env-var heuristics only (Probed = False).  Escape
--    sequences for Sixel/Kitty graphics must not be sent to a Win32 Console.
--  Cygwin/MSYS2 fall-through:
--    GetConsoleMode returns FALSE (Cygwin/MSYS PTY or pipe/file) => proceed
--    to POSIX-like Guards 1-3 and active probes.
--
--  Step 1: Passive Kitty env-var harvest (FUNC-SXL-009) — always runs.
--  Step 2: Passive Sixel env-var harvest (FUNC-SXL-008) — always runs.
--  Guard 1: Is_TTY (Stdout) = False => return passive only.
--  Step 3: DA1 active probe for Sixel (FUNC-SXL-005, FUNC-SXL-006).
--  Step 4: XTVERSION name-substring fallback (FUNC-SXL-007).
--  Step 5: Optional Kitty APC active probe (FUNC-SXL-010).
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-005): Sixel via DA1 Has_Capability
--    - @relation(FUNC-SXL-006): DA1 probe session via Detect_DA1
--    - @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
--    - @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
--    - @relation(FUNC-SXL-009): Passive Kitty env-var heuristics
--    - @relation(FUNC-SXL-010): Optional Kitty APC active probe
--    - @relation(FUNC-SXL-012): Win32 Console gate (Guard 4, evaluated first)
--    - @relation(FUNC-SXL-013): No-TTY passive fallback
--    - @relation(FUNC-SXL-014): Termios restore via Probe_Session RAII
--    - @relation(FUNC-SXL-015): 1000 ms per-session timeout
--    - @relation(FUNC-SXL-016): No-exception guarantee
--    - @relation(FUNC-SXL-017): One-probe-per-process cache

pragma SPARK_Mode (Off);

with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces.C;
with Termicap.DA1;
with Termicap.DA1.IO;
with Termicap.Environment.Capture;
with Termicap.OSC;
with Termicap.TTY;
with Termicap.Version;
with Termicap.Win32_VT;
with Termicap.XTVERSION.IO;

package body Termicap.Graphics.IO is

   use type Interfaces.C.unsigned_char;
   use type Termicap.OSC.Session_Status;
   use type Termicap.XTVERSION.XTVERSION_Status;

   ---------------------------------------------------------------------------
   --  Protected cache (FUNC-SXL-017)
   ---------------------------------------------------------------------------

   type Cache_Slot is record
      Initialized : Boolean             := False;
      Value       : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
   end record;

   protected Cache is
      function  Get_Cached return Cache_Slot;
      procedure Set_Cached (Caps : Graphics_Capabilities);
   private
      Slot : Cache_Slot :=
        (Initialized => False, Value => NO_GRAPHICS_CAPABILITIES);
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
   --  @relation(FUNC-SXL-009): Passive Kitty env-var heuristics
   function Has_Kitty_Graphics_From_Env
     (Env : Termicap.Environment.Environment) return Boolean
   is
      KW : constant String := Termicap.Environment.Value (Env, ENV_KITTY_WINDOW_ID);
      T  : constant String := Termicap.Environment.Value (Env, "TERM");
      TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
   begin
      if KW'Length > 0 then
         return True;
      end if;

      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
         return True;
      end if;

      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         return True;
      end if;

      return False;
   end Has_Kitty_Graphics_From_Env;

   --  @summary Return True when env-var heuristics indicate Sixel support.
   --  @relation(FUNC-SXL-008): Passive Sixel env-var heuristics
   function Has_Sixel_From_Env
     (Env : Termicap.Environment.Environment) return Boolean
   is
      MLTERM_256COLOR : constant String := "mlterm-256color";

      T  : constant String := Termicap.Environment.Value (Env, "TERM");
      TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
   begin
      --  Step 1: TERM_PROGRAM = WezTerm (case-insensitive).
      if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
         return True;
      end if;

      --  Step 2: TERM exact matches for known Sixel-capable terminals.
      --  TERM_XTERM_KITTY removed in B2a (kitty has its own graphics protocol,
      --  no sixel) and the legacy "TERM prefix xterm" rule was removed because
      --  every modern terminal advertises TERM=xterm-256color.
      if Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT)         or else
         Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT_EXTRA)   or else
         Termicap.Environment.Equal_Case_Insensitive (T, TERM_MLTERM)       or else
         Termicap.Environment.Equal_Case_Insensitive (T, MLTERM_256COLOR)   or else
         Termicap.Environment.Equal_Case_Insensitive (T, TERM_YAFT)
      then
         return True;
      end if;

      return False;
   end Has_Sixel_From_Env;

   --  @summary Return True when the XTVERSION terminal name indicates Sixel support.
   --  @relation(FUNC-SXL-007): XTVERSION name-substring Sixel fallback
   function Has_Sixel_From_XTVERSION_Name
     (Name : Ada.Strings.Unbounded.Unbounded_String) return Boolean
   is
      use Ada.Strings.Unbounded;
      Lower : constant String :=
        Ada.Characters.Handling.To_Lower (To_String (Name));
   begin
      return
        Ada.Strings.Fixed.Index
          (Lower,
           Ada.Characters.Handling.To_Lower (XTVERSION_NAME_KITTY)) > 0
        or else
        Ada.Strings.Fixed.Index
          (Lower,
           Ada.Characters.Handling.To_Lower (XTVERSION_NAME_WEZTERM)) > 0;
   end Has_Sixel_From_XTVERSION_Name;

   --  @summary Run the optional Kitty APC active probe.
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

      Termicap.OSC.Sentinel_Query
        (Session     => Session,
         Query       => KITTY_APC_QUERY,
         Response    => Resp_Buffer,
         Resp_Length => Resp_Length,
         Timeout_Ms  => GRAPHICS_PROBE_TIMEOUT_MS,
         Timed_Out   => Timed_Out,
         Retry       => False);

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

   --  @relation(FUNC-SXL-012): Win32 Console gate (Guard 4) evaluated first
   --  @relation(FUNC-SXL-016): No-exception guarantee
   function Run_Cascade return Graphics_Capabilities is
      Caps : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
      Env  : Termicap.Environment.Environment;
   begin
      --  Step 0: Capture environment once for all subsequent passive checks.
      Termicap.Environment.Capture.Capture_Current (Env);

      --  Step 1: Passive Kitty env-var harvest (FUNC-SXL-009).
      if Has_Kitty_Graphics_From_Env (Env) then
         Caps.Kitty_Graphics_Supported := True;
      end if;

      --  Step 2: Passive Sixel env-var harvest (FUNC-SXL-008).
      if Has_Sixel_From_Env (Env) then
         Caps.Sixel_Supported := True;
      end if;

      --  Guard 4 (Windows only): Win32 Console gate (FUNC-SXL-012, FUNC-WIN-014).
      --  Three-way classifier on STD_OUTPUT_HANDLE:
      --    Legacy_Conhost     => bail; cannot render VT escapes.
      --    ConPTY_VT_Enabled  => proceed; ConPTY host honours active probes.
      --    Not_A_Console      => proceed; the OSC layer will try CONIN$/CONOUT$
      --                          (FUNC-OSC-016) and self-bail with
      --                          Session_No_Terminal if no console is reachable.
      --
      --  The redundant Is_TTY(Stdout) guard previously here was wrong for the
      --  redirected-stdout case (e.g., conformance harness, prog.exe > out.log):
      --  it bailed before OSC's CONIN$/CONOUT$ fallback could acquire a usable
      --  console.  Trust the classifier + OSC.Open's own gating instead.
      case Termicap.Win32_VT.Classify_Console_VT is
         when Termicap.Win32_VT.Legacy_Conhost =>
            return Caps;  --  Probed = False; passive results preserved.
         when Termicap.Win32_VT.Not_A_Console =>
            null;  --  Proceed; OSC.Open will try CONIN$/CONOUT$.
         when Termicap.Win32_VT.ConPTY_VT_Enabled =>
            null;  --  Proceed; ConPTY host honours active probes.
      end case;

      --  Step 3: DA1 active probe for Sixel Ps=4 (FUNC-SXL-005, FUNC-SXL-006).
      declare
         DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
           Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
      begin
         if Termicap.DA1.Has_Capability
              (DA1_Caps, Termicap.DA1.Sixel_Graphics)
         then
            Caps.Sixel_Supported := True;
            Caps.Sixel_Via_DA1   := True;
            Caps.Probed          := True;
         elsif DA1_Caps.Supported then
            --  DA1 returned a valid response without Ps=4: authoritative
            --  negative.  Override any over-eager passive heuristic so the
            --  terminal's own answer wins (B2b, FUNC-SXL-005/006).
            Caps.Sixel_Supported := False;
            Caps.Sixel_Via_DA1   := False;
            Caps.Probed          := True;
         else
            null;
         end if;
      end;

      --  Step 4: XTVERSION name-substring fallback (FUNC-SXL-007).
      --  Skip when DA1 already confirmed Sixel (authoritative); also skip
      --  when DA1 authoritatively negated Sixel (B2c).
      if not Caps.Sixel_Via_DA1 and then not (Caps.Probed and then not Caps.Sixel_Supported) then
         declare
            XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
              Termicap.XTVERSION.IO.Query_And_Identify
                (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
         begin
            if XTV.Status = Termicap.XTVERSION.Success
               and then Has_Sixel_From_XTVERSION_Name (XTV.Terminal_Name)
            then
               Caps.Sixel_Supported := True;
               Caps.Probed := True;
            end if;
         end;
      end if;

      --  Step 5: Optional Kitty APC active probe (FUNC-SXL-010).
      if not Caps.Kitty_Graphics_Supported then
         declare
            APC_Result : constant APC_Parse_Result := Run_APC_Probe;
         begin
            if APC_Result = OK then
               Caps.Kitty_Graphics_Supported := True;
               Caps.Kitty_Via_Active_Probe   := True;
               Caps.Probed                   := True;
            end if;
         end;
      end if;

      --  Step 6: XTVERSION-driven Kitty graphics refinement (B3a).
      --  When the APC probe did not establish Kitty support, query XTVERSION
      --  and check the curated known-good name+version table.
      if not Caps.Kitty_Graphics_Supported then
         declare
            XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
              Termicap.XTVERSION.IO.Query_And_Identify
                (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
         begin
            Caps := Refine_Kitty_With_XTVERSION (Caps, XTV);
         end;
      end if;

      return Caps;
   exception
      when others =>
         --  FUNC-SXL-016: no-exception guarantee.
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
      Promoted.Kitty_Via_Active_Probe   := False;

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

         if KNOWN_GOOD_KITTY (Entry_Idx).Treat_Any then
            return Promoted;
         end if;

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
