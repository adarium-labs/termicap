-------------------------------------------------------------------------------
--  Test_Hyperlinks - Unit Tests for Termicap.Hyperlinks
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Termicap.Hyperlinks:
--    - Hyperlinks_Support / Hyperlinks_Provenance enumeration integrity
--    - DEFAULT_HYPERLINKS_RESULT canonical default value
--    - Classify_Hyperlinks_Support table-driven tests (FUNC-HYP-004, -005, -005b)
--    - Refine_With_XTVERSION state-transition table (FUNC-HYP-012)
--
--  All tests use synthetic Environment and Terminal_Identity inputs.
--  No live terminal is required.
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-001): Hyperlinks_Support enumeration
--    - @relation(FUNC-HYP-002): Hyperlinks_Result / DEFAULT_HYPERLINKS_RESULT
--    - @relation(FUNC-HYP-003): Hyperlinks_Provenance enumeration
--    - @relation(FUNC-HYP-004): TERM legacy-prefix exclusion
--    - @relation(FUNC-HYP-005): Known-good Terminal_Kind list
--    - @relation(FUNC-HYP-005b): Terminal_Kind hard exclusion
--    - @relation(FUNC-HYP-007): Classify_Hyperlinks_Support signature
--    - @relation(FUNC-HYP-009): XTVERSION promotion
--    - @relation(FUNC-HYP-010): XTVERSION demotion
--    - @relation(FUNC-HYP-011): Refine_With_XTVERSION signature
--    - @relation(FUNC-HYP-012): Complete state-transition table
--    - @relation(FUNC-HYP-018): SPARK Silver provability (no-exception contract)

with AUnit.Test_Cases;

package Test_Hyperlinks is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Group 1: Enumeration integrity (FUNC-HYP-001, FUNC-HYP-003)
   ---------------------------------------------------------------------------

   --  FUNC-HYP-001: four distinct Hyperlinks_Support values
   procedure Test_Support_Enum_Distinct (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-HYP-003: seven distinct Hyperlinks_Provenance values
   procedure Test_Provenance_Enum_Distinct (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 2: DEFAULT_HYPERLINKS_RESULT (FUNC-HYP-002)
   ---------------------------------------------------------------------------

   --  DEFAULT_HYPERLINKS_RESULT.Support = Unknown
   procedure Test_Default_Result_Support_Unknown (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  DEFAULT_HYPERLINKS_RESULT.Provenance = Default
   procedure Test_Default_Result_Provenance_Default (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  DEFAULT_HYPERLINKS_RESULT.Terminal_Version_Known = False
   procedure Test_Default_Result_Version_Known_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Zero-initialised Hyperlinks_Result equals DEFAULT_HYPERLINKS_RESULT
   procedure Test_Default_Equals_Uninitialised (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 3: Classify_Hyperlinks_Support — TERM exclusion (FUNC-HYP-004)
   ---------------------------------------------------------------------------

   --  TERM="vt100" -> Unsupported, Env_Excluded (vt prefix)
   procedure Test_Classify_TERM_vt100 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="vt220" -> Unsupported, Env_Excluded (vt prefix, longer match)
   procedure Test_Classify_TERM_vt220 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="ansi" -> Unsupported, Env_Excluded (ansi prefix)
   procedure Test_Classify_TERM_ansi (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="ansi-bbs" -> Unsupported, Env_Excluded (ansi prefix, variant)
   procedure Test_Classify_TERM_ansi_bbs (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="linux" -> Unsupported, Env_Excluded (exact match)
   procedure Test_Classify_TERM_linux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="sun-color" -> Unsupported, Env_Excluded (sun prefix)
   procedure Test_Classify_TERM_sun_color (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM="dumb" -> Unsupported, Env_Excluded (exact match)
   procedure Test_Classify_TERM_dumb (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  TERM exclusion fires before Terminal_Kind check:
   --  WezTerm with TERM="dumb" -> Unsupported, Env_Excluded (not Likely_Supported)
   procedure Test_Classify_TERM_Exclusion_Before_Kind (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 4: Classify_Hyperlinks_Support — Terminal_Kind exclusion (FUNC-HYP-005b)
   ---------------------------------------------------------------------------

   --  Apple_Terminal, TERM="xterm-256color" -> Unsupported, Env_Excluded
   procedure Test_Classify_Apple_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Dumb kind, TERM="xterm-256color" -> Unsupported, Env_Excluded
   procedure Test_Classify_Kind_Dumb (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Linux_Console kind, TERM="xterm-256color" -> Unsupported, Env_Excluded
   procedure Test_Classify_Kind_Linux_Console (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 5: Classify_Hyperlinks_Support — known-good list (FUNC-HYP-005)
   ---------------------------------------------------------------------------

   --  Each known-good Terminal_Kind -> Likely_Supported, Env_Known_Good

   procedure Test_Classify_Alacritty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Foot (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Ghostty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_ITerm2 (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_JediTerm (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Kitty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Konsole (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Mintty (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_VSCode (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_VTE (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_WarpTerminal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_WezTerm (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Windows_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Classify_Xterm (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 6: Classify_Hyperlinks_Support — Unknown fallback (FUNC-HYP-005)
   ---------------------------------------------------------------------------

   --  Rxvt -> Unknown, Env_Unknown
   procedure Test_Classify_Rxvt (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Screen -> Unknown, Env_Unknown
   procedure Test_Classify_Screen (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Tmux -> Unknown, Env_Unknown
   procedure Test_Classify_Tmux (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Unknown kind -> Unknown, Env_Unknown
   procedure Test_Classify_Unknown_Kind (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 7: Refine_With_XTVERSION state-transition table (FUNC-HYP-012)
   ---------------------------------------------------------------------------

   --  Passive Unsupported (Env_Excluded) + any XTV -> unchanged (terminal state)
   procedure Test_Refine_Passive_Unsupported_Unchanged (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + XTV.Status = Failure -> Likely_Supported, XTVERSION_Unresolved
   procedure Test_Refine_Likely_XTV_Timeout (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + iTerm2 v3.1.0 -> Supported, XTVERSION_Confirmed, True
   procedure Test_Refine_Likely_iTerm2_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + iTerm2 v3.2.0 -> Supported, XTVERSION_Confirmed (above min)
   procedure Test_Refine_Likely_iTerm2_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + iTerm2 v3.0.0 -> Unsupported, XTVERSION_Rejected, True
   procedure Test_Refine_Likely_iTerm2_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + iTerm2 version "garbage" -> Likely_Supported, Env_Known_Good, True
   procedure Test_Refine_Likely_iTerm2_Unparseable (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Likely_Supported + unrecognised emulator -> Likely_Supported, XTVERSION_Unresolved, False
   procedure Test_Refine_Likely_Unrecognised_Name (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Unknown + iTerm2 v3.1.0 -> Supported, XTVERSION_Confirmed, True
   procedure Test_Refine_Unknown_iTerm2_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Unknown + iTerm2 v3.0.0 -> Unsupported, XTVERSION_Rejected, True
   procedure Test_Refine_Unknown_iTerm2_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Unknown + unrecognised emulator -> Unknown, XTVERSION_Unresolved, False
   procedure Test_Refine_Unknown_Unrecognised (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Passive Unknown + XTV.Status = Timeout -> Unknown, XTVERSION_Unresolved
   procedure Test_Refine_Unknown_XTV_Timeout (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 8: "Any version" emulators (FUNC-HYP-009, tech-spec §7)
   ---------------------------------------------------------------------------

   --  WezTerm any version -> Supported
   procedure Test_Refine_WezTerm_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  foot any version -> Supported
   procedure Test_Refine_Foot_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Ghostty any version -> Supported
   procedure Test_Refine_Ghostty_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Konsole any version -> Supported
   procedure Test_Refine_Konsole_Any_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Group 9: Minimum-version boundary tests for each versioned emulator
   ---------------------------------------------------------------------------

   --  kitty: 0.19.0 = min -> Supported
   procedure Test_Refine_Kitty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  kitty: 0.18.0 < min -> Unsupported
   procedure Test_Refine_Kitty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  kitty: 0.20.0 > min -> Supported
   procedure Test_Refine_Kitty_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  VTE: 0.50.0 = min -> Supported
   procedure Test_Refine_VTE_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  VTE: 0.49.99 < min -> Unsupported
   procedure Test_Refine_VTE_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Alacritty: 0.11.0 = min -> Supported
   procedure Test_Refine_Alacritty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Alacritty: 0.10.0 < min -> Unsupported
   procedure Test_Refine_Alacritty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  mintty: 3.4.0 = min -> Supported
   procedure Test_Refine_Mintty_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  mintty: 3.3.0 < min -> Unsupported
   procedure Test_Refine_Mintty_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  xterm: 357 = min (single-component) -> Supported
   procedure Test_Refine_Xterm_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  xterm: 356 < min -> Unsupported
   procedure Test_Refine_Xterm_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  xterm: 388 > min -> Supported
   procedure Test_Refine_Xterm_Above_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Windows_Terminal: 1.4.0 = min -> Supported
   procedure Test_Refine_Windows_Terminal_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Windows_Terminal: 1.3.0 < min -> Unsupported
   procedure Test_Refine_Windows_Terminal_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  VSCode: 1.72.0 = min -> Supported
   procedure Test_Refine_VSCode_At_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  VSCode: 1.71.0 < min -> Unsupported
   procedure Test_Refine_VSCode_Below_Min (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Hyperlinks;
