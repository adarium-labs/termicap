-------------------------------------------------------------------------------
--  Test_Hyperlinks - Unit Tests for Termicap.Hyperlinks
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Environment;  use Termicap.Environment;
with Termicap.Hyperlinks;   use Termicap.Hyperlinks;
with Termicap.Terminal_Id;  use Termicap.Terminal_Id;
with Termicap.XTVERSION;    use Termicap.XTVERSION;

package body Test_Hyperlinks is

   ---------------------------------------------------------------------------
   --  Private helpers
   ---------------------------------------------------------------------------

   --  Build a minimal Environment with TERM set to the given value.
   function Env_With_Term (Term_Value : String) return Termicap.Environment.Environment is
      E : Termicap.Environment.Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (E, "TERM", Term_Value);
      return E;
   end Env_With_Term;

   --  Build a Terminal_Identity for a given Kind with a benign TERM.
   function Identity_Of
     (Kind : Terminal_Kind) return Terminal_Identity
   is
   begin
      return (Kind            => Kind,
              Program_Name    => Null_Unbounded_String,
              Program_Version => Null_Unbounded_String,
              Term_Value      => To_Unbounded_String ("xterm-256color"),
              Is_Multiplexer  => Kind = Screen or else Kind = Tmux);
   end Identity_Of;

   --  Build an XTVERSION_Result with Status = Success.
   function XTV_Success
     (Name    : String;
      Version : String) return XTVERSION_Result
   is
   begin
      return (Status           => Success,
              Terminal_Name    => To_Unbounded_String (Name),
              Terminal_Version => To_Unbounded_String (Version));
   end XTV_Success;

   --  Build an XTVERSION_Result with Status = Timeout.
   function XTV_Timeout return XTVERSION_Result is
   begin
      return (Status => Timeout);
   end XTV_Timeout;

   --  Build an XTVERSION_Result with Status = Parse_Error.
   function XTV_Parse_Error return XTVERSION_Result is
   begin
      return (Status => Parse_Error);
   end XTV_Parse_Error;

   ---------------------------------------------------------------------------
   --  Register_Tests
   ---------------------------------------------------------------------------

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Hyperlinks");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Group 1: enum integrity
      Register_Routine (T, Test_Support_Enum_Distinct'Access,
                        "FUNC-HYP-001: Hyperlinks_Support has 4 distinct values");
      Register_Routine (T, Test_Provenance_Enum_Distinct'Access,
                        "FUNC-HYP-003: Hyperlinks_Provenance has 7 distinct values");

      --  Group 2: DEFAULT_HYPERLINKS_RESULT
      Register_Routine (T, Test_Default_Result_Support_Unknown'Access,
                        "FUNC-HYP-002: DEFAULT_HYPERLINKS_RESULT.Support = Unknown");
      Register_Routine (T, Test_Default_Result_Provenance_Default'Access,
                        "FUNC-HYP-002: DEFAULT_HYPERLINKS_RESULT.Provenance = Default");
      Register_Routine (T, Test_Default_Result_Version_Known_False'Access,
                        "FUNC-HYP-002: DEFAULT_HYPERLINKS_RESULT.Terminal_Version_Known = False");
      Register_Routine (T, Test_Default_Equals_Uninitialised'Access,
                        "FUNC-HYP-002: default-init Hyperlinks_Result equals DEFAULT_HYPERLINKS_RESULT");

      --  Group 3: TERM exclusion (FUNC-HYP-004)
      Register_Routine (T, Test_Classify_TERM_vt100'Access,
                        "FUNC-HYP-004: TERM=vt100 -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_vt220'Access,
                        "FUNC-HYP-004: TERM=vt220 -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_ansi'Access,
                        "FUNC-HYP-004: TERM=ansi -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_ansi_bbs'Access,
                        "FUNC-HYP-004: TERM=ansi-bbs -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_linux'Access,
                        "FUNC-HYP-004: TERM=linux -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_sun_color'Access,
                        "FUNC-HYP-004: TERM=sun-color -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_dumb'Access,
                        "FUNC-HYP-004: TERM=dumb -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_TERM_Exclusion_Before_Kind'Access,
                        "FUNC-HYP-004: TERM=dumb + Kind=WezTerm -> Unsupported (TERM fires first)");

      --  Group 4: Terminal_Kind exclusion (FUNC-HYP-005b)
      Register_Routine (T, Test_Classify_Apple_Terminal'Access,
                        "FUNC-HYP-005b: Apple_Terminal -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_Kind_Dumb'Access,
                        "FUNC-HYP-005b: Kind=Dumb -> Unsupported, Env_Excluded");
      Register_Routine (T, Test_Classify_Kind_Linux_Console'Access,
                        "FUNC-HYP-005b: Kind=Linux_Console -> Unsupported, Env_Excluded");

      --  Group 5: known-good list (FUNC-HYP-005)
      Register_Routine (T, Test_Classify_Alacritty'Access,
                        "FUNC-HYP-005: Alacritty -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Foot'Access,
                        "FUNC-HYP-005: Foot -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Ghostty'Access,
                        "FUNC-HYP-005: Ghostty -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_ITerm2'Access,
                        "FUNC-HYP-005: ITerm2 -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_JediTerm'Access,
                        "FUNC-HYP-005: JediTerm -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Kitty'Access,
                        "FUNC-HYP-005: Kitty -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Konsole'Access,
                        "FUNC-HYP-005: Konsole -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Mintty'Access,
                        "FUNC-HYP-005: Mintty -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_VSCode'Access,
                        "FUNC-HYP-005: VSCode -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_VTE'Access,
                        "FUNC-HYP-005: VTE -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_WarpTerminal'Access,
                        "FUNC-HYP-005: WarpTerminal -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_WezTerm'Access,
                        "FUNC-HYP-005: WezTerm -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Windows_Terminal'Access,
                        "FUNC-HYP-005: Windows_Terminal -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Classify_Xterm'Access,
                        "FUNC-HYP-005: Xterm -> Likely_Supported, Env_Known_Good");

      --  Group 6: unknown fallback
      Register_Routine (T, Test_Classify_Rxvt'Access,
                        "FUNC-HYP-005: Rxvt -> Unknown, Env_Unknown");
      Register_Routine (T, Test_Classify_Screen'Access,
                        "FUNC-HYP-005: Screen -> Unknown, Env_Unknown");
      Register_Routine (T, Test_Classify_Tmux'Access,
                        "FUNC-HYP-005: Tmux -> Unknown, Env_Unknown");
      Register_Routine (T, Test_Classify_Unknown_Kind'Access,
                        "FUNC-HYP-005: Unknown kind -> Unknown, Env_Unknown");

      --  Group 7: Refine_With_XTVERSION state-transition table (FUNC-HYP-012)
      Register_Routine (T, Test_Refine_Passive_Unsupported_Unchanged'Access,
                        "FUNC-HYP-012: Unsupported (Env_Excluded) + any XTV -> unchanged");
      Register_Routine (T, Test_Refine_Likely_XTV_Timeout'Access,
                        "FUNC-HYP-012: Likely_Supported + Timeout -> Likely_Supported, XTVERSION_Unresolved");
      Register_Routine (T, Test_Refine_Likely_iTerm2_At_Min'Access,
                        "FUNC-HYP-009: Likely_Supported + iTerm2 3.1.0 -> Supported, XTVERSION_Confirmed");
      Register_Routine (T, Test_Refine_Likely_iTerm2_Above_Min'Access,
                        "FUNC-HYP-009: Likely_Supported + iTerm2 3.2.0 -> Supported, XTVERSION_Confirmed");
      Register_Routine (T, Test_Refine_Likely_iTerm2_Below_Min'Access,
                        "FUNC-HYP-010: Likely_Supported + iTerm2 3.0.0 -> Unsupported, XTVERSION_Rejected");
      Register_Routine (T, Test_Refine_Likely_iTerm2_Unparseable'Access,
                        "FUNC-HYP-012: Likely_Supported + iTerm2 garbage version -> Likely_Supported, Env_Known_Good");
      Register_Routine (T, Test_Refine_Likely_Unrecognised_Name'Access,
                        "FUNC-HYP-012: Likely_Supported + unrecognised name -> Likely_Supported, XTVERSION_Unresolved");
      Register_Routine (T, Test_Refine_Unknown_iTerm2_At_Min'Access,
                        "FUNC-HYP-009: Unknown + iTerm2 3.1.0 -> Supported, XTVERSION_Confirmed");
      Register_Routine (T, Test_Refine_Unknown_iTerm2_Below_Min'Access,
                        "FUNC-HYP-010: Unknown + iTerm2 3.0.0 -> Unsupported, XTVERSION_Rejected");
      Register_Routine (T, Test_Refine_Unknown_Unrecognised'Access,
                        "FUNC-HYP-012: Unknown + unrecognised name -> Unknown, XTVERSION_Unresolved");
      Register_Routine (T, Test_Refine_Unknown_XTV_Timeout'Access,
                        "FUNC-HYP-012: Unknown + Timeout -> Unknown, XTVERSION_Unresolved");

      --  Group 8: "any version" emulators
      Register_Routine (T, Test_Refine_WezTerm_Any_Version'Access,
                        "FUNC-HYP-009: WezTerm (any) v0.0.0 -> Supported");
      Register_Routine (T, Test_Refine_Foot_Any_Version'Access,
                        "FUNC-HYP-009: foot (any) v0.0 -> Supported");
      Register_Routine (T, Test_Refine_Ghostty_Any_Version'Access,
                        "FUNC-HYP-009: Ghostty (any) v0 -> Supported");
      Register_Routine (T, Test_Refine_Konsole_Any_Version'Access,
                        "FUNC-HYP-009: Konsole (any) v0.0 -> Supported");

      --  Group 9: minimum-version boundaries
      Register_Routine (T, Test_Refine_Kitty_At_Min'Access,
                        "FUNC-HYP-009: kitty 0.19.0 = min -> Supported");
      Register_Routine (T, Test_Refine_Kitty_Below_Min'Access,
                        "FUNC-HYP-010: kitty 0.18.0 < min -> Unsupported");
      Register_Routine (T, Test_Refine_Kitty_Above_Min'Access,
                        "FUNC-HYP-009: kitty 0.20.0 > min -> Supported");
      Register_Routine (T, Test_Refine_VTE_At_Min'Access,
                        "FUNC-HYP-009: VTE 0.50.0 = min -> Supported");
      Register_Routine (T, Test_Refine_VTE_Below_Min'Access,
                        "FUNC-HYP-010: VTE 0.49.99 < min -> Unsupported");
      Register_Routine (T, Test_Refine_Alacritty_At_Min'Access,
                        "FUNC-HYP-009: Alacritty 0.11.0 = min -> Supported");
      Register_Routine (T, Test_Refine_Alacritty_Below_Min'Access,
                        "FUNC-HYP-010: Alacritty 0.10.0 < min -> Unsupported");
      Register_Routine (T, Test_Refine_Mintty_At_Min'Access,
                        "FUNC-HYP-009: mintty 3.4.0 = min -> Supported");
      Register_Routine (T, Test_Refine_Mintty_Below_Min'Access,
                        "FUNC-HYP-010: mintty 3.3.0 < min -> Unsupported");
      Register_Routine (T, Test_Refine_Xterm_At_Min'Access,
                        "FUNC-HYP-009: xterm 357 = min -> Supported");
      Register_Routine (T, Test_Refine_Xterm_Below_Min'Access,
                        "FUNC-HYP-010: xterm 356 < min -> Unsupported");
      Register_Routine (T, Test_Refine_Xterm_Above_Min'Access,
                        "FUNC-HYP-009: xterm 388 > min -> Supported");
      Register_Routine (T, Test_Refine_Windows_Terminal_At_Min'Access,
                        "FUNC-HYP-009: Windows_Terminal 1.4.0 = min -> Supported");
      Register_Routine (T, Test_Refine_Windows_Terminal_Below_Min'Access,
                        "FUNC-HYP-010: Windows_Terminal 1.3.0 < min -> Unsupported");
      Register_Routine (T, Test_Refine_VSCode_At_Min'Access,
                        "FUNC-HYP-009: VSCode 1.72.0 = min -> Supported");
      Register_Routine (T, Test_Refine_VSCode_Below_Min'Access,
                        "FUNC-HYP-010: VSCode 1.71.0 < min -> Unsupported");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Group 1: Enumeration integrity
   ---------------------------------------------------------------------------

   procedure Test_Support_Enum_Distinct (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Unsupported /= Likely_Supported, "Unsupported /= Likely_Supported");
      Assert (Unsupported /= Supported,        "Unsupported /= Supported");
      Assert (Unsupported /= Unknown,          "Unsupported /= Unknown");
      Assert (Likely_Supported /= Supported,   "Likely_Supported /= Supported");
      Assert (Likely_Supported /= Unknown,     "Likely_Supported /= Unknown");
      Assert (Supported /= Unknown,            "Supported /= Unknown");
   end Test_Support_Enum_Distinct;

   procedure Test_Provenance_Enum_Distinct (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Default /= Env_Excluded,          "Default /= Env_Excluded");
      Assert (Default /= Env_Known_Good,         "Default /= Env_Known_Good");
      Assert (Default /= Env_Unknown,            "Default /= Env_Unknown");
      Assert (Default /= XTVERSION_Confirmed,    "Default /= XTVERSION_Confirmed");
      Assert (Default /= XTVERSION_Rejected,     "Default /= XTVERSION_Rejected");
      Assert (Default /= XTVERSION_Unresolved,   "Default /= XTVERSION_Unresolved");
      Assert (Env_Excluded /= Env_Known_Good,    "Env_Excluded /= Env_Known_Good");
      Assert (XTVERSION_Confirmed /= XTVERSION_Rejected, "XTVERSION_Confirmed /= XTVERSION_Rejected");
   end Test_Provenance_Enum_Distinct;

   ---------------------------------------------------------------------------
   --  Group 2: DEFAULT_HYPERLINKS_RESULT
   ---------------------------------------------------------------------------

   procedure Test_Default_Result_Support_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (DEFAULT_HYPERLINKS_RESULT.Support = Unknown,
              "DEFAULT_HYPERLINKS_RESULT.Support should be Unknown");
   end Test_Default_Result_Support_Unknown;

   procedure Test_Default_Result_Provenance_Default (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (DEFAULT_HYPERLINKS_RESULT.Provenance = Default,
              "DEFAULT_HYPERLINKS_RESULT.Provenance should be Default");
   end Test_Default_Result_Provenance_Default;

   procedure Test_Default_Result_Version_Known_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (not DEFAULT_HYPERLINKS_RESULT.Terminal_Version_Known,
              "DEFAULT_HYPERLINKS_RESULT.Terminal_Version_Known should be False");
   end Test_Default_Result_Version_Known_False;

   procedure Test_Default_Equals_Uninitialised (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result := (Support => Unknown, Provenance => Default, Terminal_Version_Known => False);
   begin
      Assert (R.Support = DEFAULT_HYPERLINKS_RESULT.Support,
              "Support fields should match DEFAULT_HYPERLINKS_RESULT");
      Assert (R.Provenance = DEFAULT_HYPERLINKS_RESULT.Provenance,
              "Provenance fields should match DEFAULT_HYPERLINKS_RESULT");
      Assert (R.Terminal_Version_Known = DEFAULT_HYPERLINKS_RESULT.Terminal_Version_Known,
              "Terminal_Version_Known fields should match DEFAULT_HYPERLINKS_RESULT");
   end Test_Default_Equals_Uninitialised;

   ---------------------------------------------------------------------------
   --  Group 3: TERM exclusion (FUNC-HYP-004)
   ---------------------------------------------------------------------------

   procedure Test_Classify_TERM_vt100 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("vt100"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=vt100 should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=vt100 should yield Env_Excluded");
      Assert (not R.Terminal_Version_Known, "TERM=vt100: Terminal_Version_Known should be False");
   end Test_Classify_TERM_vt100;

   procedure Test_Classify_TERM_vt220 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("vt220"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=vt220 should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=vt220 should yield Env_Excluded");
   end Test_Classify_TERM_vt220;

   procedure Test_Classify_TERM_ansi (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("ansi"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=ansi should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=ansi should yield Env_Excluded");
   end Test_Classify_TERM_ansi;

   procedure Test_Classify_TERM_ansi_bbs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("ansi-bbs"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=ansi-bbs should yield Unsupported (ansi prefix)");
      Assert (R.Provenance = Env_Excluded, "TERM=ansi-bbs should yield Env_Excluded");
   end Test_Classify_TERM_ansi_bbs;

   procedure Test_Classify_TERM_linux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("linux"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=linux should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=linux should yield Env_Excluded");
   end Test_Classify_TERM_linux;

   procedure Test_Classify_TERM_sun_color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("sun-color"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=sun-color should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=sun-color should yield Env_Excluded");
   end Test_Classify_TERM_sun_color;

   procedure Test_Classify_TERM_dumb (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("dumb"), Identity_Of (Termicap.Terminal_Id.Unknown));
   begin
      Assert (R.Support = Unsupported, "TERM=dumb should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "TERM=dumb should yield Env_Excluded");
   end Test_Classify_TERM_dumb;

   procedure Test_Classify_TERM_Exclusion_Before_Kind (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Even a known-good emulator (WezTerm) must return Unsupported when TERM=dumb.
      --  The TERM exclusion fires in Step 1 before the Terminal_Kind check (Step 3).
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("dumb"), Identity_Of (WezTerm));
   begin
      Assert (R.Support = Unsupported,
              "TERM=dumb + WezTerm kind: TERM exclusion must fire first => Unsupported");
      Assert (R.Provenance = Env_Excluded,
              "TERM=dumb + WezTerm kind: Provenance must be Env_Excluded");
   end Test_Classify_TERM_Exclusion_Before_Kind;

   ---------------------------------------------------------------------------
   --  Group 4: Terminal_Kind exclusion (FUNC-HYP-005b)
   ---------------------------------------------------------------------------

   procedure Test_Classify_Apple_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("xterm-256color"), Identity_Of (Apple_Terminal));
   begin
      Assert (R.Support = Unsupported, "Apple_Terminal should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "Apple_Terminal should yield Env_Excluded");
   end Test_Classify_Apple_Terminal;

   procedure Test_Classify_Kind_Dumb (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("xterm-256color"), Identity_Of (Termicap.Terminal_Id.Dumb));
   begin
      Assert (R.Support = Unsupported, "Kind=Dumb should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "Kind=Dumb should yield Env_Excluded");
   end Test_Classify_Kind_Dumb;

   procedure Test_Classify_Kind_Linux_Console (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      R : constant Hyperlinks_Result :=
        Classify_Hyperlinks_Support (Env_With_Term ("xterm-256color"), Identity_Of (Linux_Console));
   begin
      Assert (R.Support = Unsupported, "Kind=Linux_Console should yield Unsupported");
      Assert (R.Provenance = Env_Excluded, "Kind=Linux_Console should yield Env_Excluded");
   end Test_Classify_Kind_Linux_Console;

   ---------------------------------------------------------------------------
   --  Group 5: known-good list (FUNC-HYP-005) — helper macro
   ---------------------------------------------------------------------------

   procedure Assert_Likely_Known_Good (Kind : Terminal_Kind; Label : String) is
      E : constant Termicap.Environment.Environment := Env_With_Term ("xterm-256color");
      R : constant Hyperlinks_Result := Classify_Hyperlinks_Support (E, Identity_Of (Kind));
   begin
      Assert (R.Support = Likely_Supported,
              Label & ": Support should be Likely_Supported");
      Assert (R.Provenance = Env_Known_Good,
              Label & ": Provenance should be Env_Known_Good");
      Assert (not R.Terminal_Version_Known,
              Label & ": Terminal_Version_Known should be False");
   end Assert_Likely_Known_Good;

   procedure Test_Classify_Alacritty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Alacritty, "Alacritty");
   end Test_Classify_Alacritty;

   procedure Test_Classify_Foot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Foot, "Foot");
   end Test_Classify_Foot;

   procedure Test_Classify_Ghostty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Ghostty, "Ghostty");
   end Test_Classify_Ghostty;

   procedure Test_Classify_ITerm2 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (ITerm2, "ITerm2");
   end Test_Classify_ITerm2;

   procedure Test_Classify_JediTerm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (JediTerm, "JediTerm");
   end Test_Classify_JediTerm;

   procedure Test_Classify_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Kitty, "Kitty");
   end Test_Classify_Kitty;

   procedure Test_Classify_Konsole (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Konsole, "Konsole");
   end Test_Classify_Konsole;

   procedure Test_Classify_Mintty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Mintty, "Mintty");
   end Test_Classify_Mintty;

   procedure Test_Classify_VSCode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (VSCode, "VSCode");
   end Test_Classify_VSCode;

   procedure Test_Classify_VTE (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (VTE, "VTE");
   end Test_Classify_VTE;

   procedure Test_Classify_WarpTerminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (WarpTerminal, "WarpTerminal");
   end Test_Classify_WarpTerminal;

   procedure Test_Classify_WezTerm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (WezTerm, "WezTerm");
   end Test_Classify_WezTerm;

   procedure Test_Classify_Windows_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Windows_Terminal, "Windows_Terminal");
   end Test_Classify_Windows_Terminal;

   procedure Test_Classify_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Likely_Known_Good (Xterm, "Xterm");
   end Test_Classify_Xterm;

   ---------------------------------------------------------------------------
   --  Group 6: Unknown fallback
   ---------------------------------------------------------------------------

   procedure Assert_Unknown_Env (Kind : Terminal_Kind; Label : String) is
      E : constant Termicap.Environment.Environment := Env_With_Term ("xterm-256color");
      R : constant Hyperlinks_Result := Classify_Hyperlinks_Support (E, Identity_Of (Kind));
   begin
      Assert (R.Support = Unknown,
              Label & ": Support should be Unknown");
      Assert (R.Provenance = Env_Unknown,
              Label & ": Provenance should be Env_Unknown");
   end Assert_Unknown_Env;

   procedure Test_Classify_Rxvt (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Unknown_Env (Rxvt, "Rxvt");
   end Test_Classify_Rxvt;

   procedure Test_Classify_Screen (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Unknown_Env (Screen, "Screen");
   end Test_Classify_Screen;

   procedure Test_Classify_Tmux (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Unknown_Env (Tmux, "Tmux");
   end Test_Classify_Tmux;

   procedure Test_Classify_Unknown_Kind (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Unknown_Env (Termicap.Terminal_Id.Unknown, "Unknown kind");
   end Test_Classify_Unknown_Kind;

   ---------------------------------------------------------------------------
   --  Group 7: Refine_With_XTVERSION state-transition table
   ---------------------------------------------------------------------------

   procedure Test_Refine_Passive_Unsupported_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Unsupported, Provenance => Env_Excluded, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.1.0"));
   begin
      Assert (Refined.Support = Unsupported, "Passive Unsupported: Support must remain Unsupported");
      Assert (Refined.Provenance = Env_Excluded, "Passive Unsupported: Provenance must remain Env_Excluded");
   end Test_Refine_Passive_Unsupported_Unchanged;

   procedure Test_Refine_Likely_XTV_Timeout (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Timeout);
   begin
      Assert (Refined.Support = Likely_Supported,
              "Likely_Supported + Timeout: Support should remain Likely_Supported");
      Assert (Refined.Provenance = XTVERSION_Unresolved,
              "Likely_Supported + Timeout: Provenance should be XTVERSION_Unresolved");
   end Test_Refine_Likely_XTV_Timeout;

   procedure Test_Refine_Likely_iTerm2_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.1.0"));
   begin
      Assert (Refined.Support = Supported,
              "Likely_Supported + iTerm2 3.1.0: Support should be Supported");
      Assert (Refined.Provenance = XTVERSION_Confirmed,
              "Likely_Supported + iTerm2 3.1.0: Provenance should be XTVERSION_Confirmed");
      Assert (Refined.Terminal_Version_Known,
              "Likely_Supported + iTerm2 3.1.0: Terminal_Version_Known should be True");
   end Test_Refine_Likely_iTerm2_At_Min;

   procedure Test_Refine_Likely_iTerm2_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.2.0"));
   begin
      Assert (Refined.Support = Supported,
              "Likely_Supported + iTerm2 3.2.0: Support should be Supported");
      Assert (Refined.Provenance = XTVERSION_Confirmed,
              "Likely_Supported + iTerm2 3.2.0: Provenance should be XTVERSION_Confirmed");
   end Test_Refine_Likely_iTerm2_Above_Min;

   procedure Test_Refine_Likely_iTerm2_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.0.0"));
   begin
      Assert (Refined.Support = Unsupported,
              "Likely_Supported + iTerm2 3.0.0: Support should be Unsupported");
      Assert (Refined.Provenance = XTVERSION_Rejected,
              "Likely_Supported + iTerm2 3.0.0: Provenance should be XTVERSION_Rejected");
      Assert (Refined.Terminal_Version_Known,
              "Likely_Supported + iTerm2 3.0.0: Terminal_Version_Known should be True");
   end Test_Refine_Likely_iTerm2_Below_Min;

   procedure Test_Refine_Likely_iTerm2_Unparseable (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "garbage"));
   begin
      Assert (Refined.Support = Likely_Supported,
              "Likely_Supported + iTerm2 garbage: Support should remain Likely_Supported");
      Assert (Refined.Provenance = Env_Known_Good,
              "Likely_Supported + iTerm2 garbage: Provenance should be Env_Known_Good (unchanged)");
      Assert (Refined.Terminal_Version_Known,
              "Likely_Supported + iTerm2 garbage: Terminal_Version_Known should be True (name matched)");
   end Test_Refine_Likely_iTerm2_Unparseable;

   procedure Test_Refine_Likely_Unrecognised_Name (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result :=
        Refine_With_XTVERSION (Passive, XTV_Success ("SomeUnknownTerminal", "1.0.0"));
   begin
      Assert (Refined.Support = Likely_Supported,
              "Likely_Supported + unrecognised: Support should remain Likely_Supported");
      Assert (Refined.Provenance = XTVERSION_Unresolved,
              "Likely_Supported + unrecognised: Provenance should be XTVERSION_Unresolved");
      Assert (not Refined.Terminal_Version_Known,
              "Likely_Supported + unrecognised: Terminal_Version_Known should be False");
   end Test_Refine_Likely_Unrecognised_Name;

   procedure Test_Refine_Unknown_iTerm2_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Unknown, Provenance => Env_Unknown, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.1.0"));
   begin
      Assert (Refined.Support = Supported,
              "Unknown + iTerm2 3.1.0: Support should be Supported");
      Assert (Refined.Provenance = XTVERSION_Confirmed,
              "Unknown + iTerm2 3.1.0: Provenance should be XTVERSION_Confirmed");
      Assert (Refined.Terminal_Version_Known,
              "Unknown + iTerm2 3.1.0: Terminal_Version_Known should be True");
   end Test_Refine_Unknown_iTerm2_At_Min;

   procedure Test_Refine_Unknown_iTerm2_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Unknown, Provenance => Env_Unknown, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success ("iTerm2", "3.0.0"));
   begin
      Assert (Refined.Support = Unsupported,
              "Unknown + iTerm2 3.0.0: Support should be Unsupported");
      Assert (Refined.Provenance = XTVERSION_Rejected,
              "Unknown + iTerm2 3.0.0: Provenance should be XTVERSION_Rejected");
   end Test_Refine_Unknown_iTerm2_Below_Min;

   procedure Test_Refine_Unknown_Unrecognised (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Unknown, Provenance => Env_Unknown, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result :=
        Refine_With_XTVERSION (Passive, XTV_Success ("MyUnknownTerminal", "2.0"));
   begin
      Assert (Refined.Support = Unknown,
              "Unknown + unrecognised name: Support should remain Unknown");
      Assert (Refined.Provenance = XTVERSION_Unresolved,
              "Unknown + unrecognised name: Provenance should be XTVERSION_Unresolved");
      Assert (not Refined.Terminal_Version_Known,
              "Unknown + unrecognised name: Terminal_Version_Known should be False");
   end Test_Refine_Unknown_Unrecognised;

   procedure Test_Refine_Unknown_XTV_Timeout (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Passive : constant Hyperlinks_Result :=
        (Support => Unknown, Provenance => Env_Unknown, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Timeout);
   begin
      Assert (Refined.Support = Unknown,
              "Unknown + Timeout: Support should remain Unknown");
      Assert (Refined.Provenance = XTVERSION_Unresolved,
              "Unknown + Timeout: Provenance should be XTVERSION_Unresolved");
   end Test_Refine_Unknown_XTV_Timeout;

   ---------------------------------------------------------------------------
   --  Group 8: "Any version" emulators
   ---------------------------------------------------------------------------

   procedure Assert_Any_Version_Supported (Name : String; Version_Str : String; Label : String) is
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result :=
        Refine_With_XTVERSION (Passive, XTV_Success (Name, Version_Str));
   begin
      Assert (Refined.Support = Supported,
              Label & " (any version, v=" & Version_Str & "): Support should be Supported");
      Assert (Refined.Provenance = XTVERSION_Confirmed,
              Label & " (any version, v=" & Version_Str & "): Provenance should be XTVERSION_Confirmed");
      Assert (Refined.Terminal_Version_Known,
              Label & " (any version, v=" & Version_Str & "): Terminal_Version_Known should be True");
   end Assert_Any_Version_Supported;

   procedure Test_Refine_WezTerm_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Any_Version_Supported ("WezTerm", "0.0.0", "WezTerm");
   end Test_Refine_WezTerm_Any_Version;

   procedure Test_Refine_Foot_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Any_Version_Supported ("foot", "0.0", "foot");
   end Test_Refine_Foot_Any_Version;

   procedure Test_Refine_Ghostty_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Any_Version_Supported ("Ghostty", "0", "Ghostty");
   end Test_Refine_Ghostty_Any_Version;

   procedure Test_Refine_Konsole_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Any_Version_Supported ("Konsole", "0.0", "Konsole");
   end Test_Refine_Konsole_Any_Version;

   ---------------------------------------------------------------------------
   --  Group 9: Minimum-version boundary helpers
   ---------------------------------------------------------------------------

   procedure Assert_At_Min (Name : String; Ver : String; Label : String) is
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success (Name, Ver));
   begin
      Assert (Refined.Support = Supported,
              Label & " v" & Ver & " (at min): Support should be Supported");
   end Assert_At_Min;

   procedure Assert_Below_Min (Name : String; Ver : String; Label : String) is
      Passive : constant Hyperlinks_Result :=
        (Support => Likely_Supported, Provenance => Env_Known_Good, Terminal_Version_Known => False);
      Refined : constant Hyperlinks_Result := Refine_With_XTVERSION (Passive, XTV_Success (Name, Ver));
   begin
      Assert (Refined.Support = Unsupported,
              Label & " v" & Ver & " (below min): Support should be Unsupported");
      Assert (Refined.Provenance = XTVERSION_Rejected,
              Label & " v" & Ver & " (below min): Provenance should be XTVERSION_Rejected");
   end Assert_Below_Min;

   procedure Test_Refine_Kitty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("kitty", "0.19.0", "kitty");
   end Test_Refine_Kitty_At_Min;

   procedure Test_Refine_Kitty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("kitty", "0.18.0", "kitty");
   end Test_Refine_Kitty_Below_Min;

   procedure Test_Refine_Kitty_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("kitty", "0.20.0", "kitty (above min)");
   end Test_Refine_Kitty_Above_Min;

   procedure Test_Refine_VTE_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("VTE", "0.50.0", "VTE");
   end Test_Refine_VTE_At_Min;

   procedure Test_Refine_VTE_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("VTE", "0.49.99", "VTE");
   end Test_Refine_VTE_Below_Min;

   procedure Test_Refine_Alacritty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("Alacritty", "0.11.0", "Alacritty");
   end Test_Refine_Alacritty_At_Min;

   procedure Test_Refine_Alacritty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("Alacritty", "0.10.0", "Alacritty");
   end Test_Refine_Alacritty_Below_Min;

   procedure Test_Refine_Mintty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("mintty", "3.4.0", "mintty");
   end Test_Refine_Mintty_At_Min;

   procedure Test_Refine_Mintty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("mintty", "3.3.0", "mintty");
   end Test_Refine_Mintty_Below_Min;

   procedure Test_Refine_Xterm_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("xterm", "357", "xterm");
   end Test_Refine_Xterm_At_Min;

   procedure Test_Refine_Xterm_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("xterm", "356", "xterm");
   end Test_Refine_Xterm_Below_Min;

   procedure Test_Refine_Xterm_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("xterm", "388", "xterm (above min)");
   end Test_Refine_Xterm_Above_Min;

   procedure Test_Refine_Windows_Terminal_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("Windows_Terminal", "1.4.0", "Windows_Terminal");
   end Test_Refine_Windows_Terminal_At_Min;

   procedure Test_Refine_Windows_Terminal_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("Windows_Terminal", "1.3.0", "Windows_Terminal");
   end Test_Refine_Windows_Terminal_Below_Min;

   procedure Test_Refine_VSCode_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_At_Min ("VSCode", "1.72.0", "VSCode");
   end Test_Refine_VSCode_At_Min;

   procedure Test_Refine_VSCode_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert_Below_Min ("VSCode", "1.71.0", "VSCode");
   end Test_Refine_VSCode_Below_Min;

end Test_Hyperlinks;
