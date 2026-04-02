-------------------------------------------------------------------------------
--  Test_Color - Unit Tests for Termicap.Color
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Color_Level type properties and the full
--  Detect_Color_Level priority cascade.
--
--  Requirements Coverage:
--    - @relation(FUNC-CLR-001): Color_Level enumeration type
--    - @relation(FUNC-CLR-003): NO_COLOR compliance
--    - @relation(FUNC-CLR-004): FORCE_COLOR override
--    - @relation(FUNC-CLR-005): CLICOLOR_FORCE support
--    - @relation(FUNC-CLR-006): TERM=dumb handling
--    - @relation(FUNC-CLR-007): TTY gate
--    - @relation(FUNC-CLR-008): COLORTERM detection
--    - @relation(FUNC-CLR-009): TERM-based color detection
--    - @relation(FUNC-CLR-010): TERM_PROGRAM detection
--    - @relation(FUNC-CLR-011): CI environment detection
--    - @relation(FUNC-CLR-012): CLICOLOR support
--    - @relation(FUNC-CLR-013): Multiplexer awareness
--    - @relation(FUNC-CLR-015): Detection priority order

with AUnit.Test_Cases;

package Test_Color is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-001: Color_Level Enumeration Properties
   ---------------------------------------------------------------------------

   --  FUNC-CLR-001: Ordering None < Basic_16 < Extended_256 < True_Color
   procedure Test_Color_Level_Ordering
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-001: Color_Level'Max works correctly
   procedure Test_Color_Level_Max
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-003: NO_COLOR Compliance
   ---------------------------------------------------------------------------

   --  FUNC-CLR-003: NO_COLOR="" present, no force -> None
   procedure Test_No_Color_Empty_Disables
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-003: NO_COLOR="1" present, no force -> None
   procedure Test_No_Color_One_Disables
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-003: NO_COLOR absent -> detection proceeds normally
   procedure Test_No_Color_Absent_Proceeds
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-003: NO_COLOR + FORCE_COLOR="1" -> Basic_16 (force overrides)
   procedure Test_No_Color_Overridden_By_Force
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-004: FORCE_COLOR Override
   ---------------------------------------------------------------------------

   --  FUNC-CLR-004: FORCE_COLOR="3" -> True_Color regardless
   procedure Test_Force_Color_Three_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="2" -> Extended_256 regardless
   procedure Test_Force_Color_Two_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="1" -> Basic_16
   procedure Test_Force_Color_One_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="0" -> None even with COLORTERM=truecolor
   procedure Test_Force_Color_Zero_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="false" -> None
   procedure Test_Force_Color_False_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="true" -> Basic_16
   procedure Test_Force_Color_True_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="" (empty) -> Basic_16
   procedure Test_Force_Color_Empty_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="xyz" (unknown) -> Basic_16
   procedure Test_Force_Color_Unknown_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="3" + TERM=dumb -> True_Color (overrides dumb)
   procedure Test_Force_Color_Three_Overrides_Dumb
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-004: FORCE_COLOR="2" + Is_TTY=False -> Extended_256 (overrides gate)
   procedure Test_Force_Color_Two_Overrides_Tty_Gate
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-005: CLICOLOR_FORCE
   ---------------------------------------------------------------------------

   --  FUNC-CLR-005: CLICOLOR_FORCE="1" + Is_TTY=False -> Basic_16
   procedure Test_Clicolor_Force_One_No_Tty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-005: CLICOLOR_FORCE="0" -> no effect
   procedure Test_Clicolor_Force_Zero_No_Effect
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-005: CLICOLOR_FORCE="1" + FORCE_COLOR="3" -> True_Color
   procedure Test_Clicolor_Force_Superseded_By_Force_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-005: CLICOLOR_FORCE="1" + NO_COLOR -> Basic_16 (overrides NO_COLOR)
   procedure Test_Clicolor_Force_Overrides_No_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-006: TERM=dumb
   ---------------------------------------------------------------------------

   --  FUNC-CLR-006: TERM="dumb", no force -> None
   procedure Test_Term_Dumb_No_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-006: TERM="dumb" + FORCE_COLOR="1" -> Basic_16
   procedure Test_Term_Dumb_With_Force_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-006: TERM="DUMB" (uppercase) -> None (case-insensitive)
   procedure Test_Term_Dumb_Uppercase
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-007: TTY Gate
   ---------------------------------------------------------------------------

   --  FUNC-CLR-007: Is_TTY=False, no force, no CI -> None
   procedure Test_Tty_Gate_No_Tty_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-007: Is_TTY=True, no env vars -> None (no positive signal)
   procedure Test_Tty_Gate_Tty_No_Signal_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-007: Is_TTY=False + FORCE_COLOR="1" -> Basic_16
   procedure Test_Tty_Gate_Force_Color_Bypasses
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-008: COLORTERM Detection
   ---------------------------------------------------------------------------

   --  FUNC-CLR-008: COLORTERM="truecolor" -> True_Color
   procedure Test_Colorterm_Truecolor
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-008: COLORTERM="24bit" -> True_Color
   procedure Test_Colorterm_24bit
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-008: COLORTERM="TrueColor" (mixed case) -> True_Color
   procedure Test_Colorterm_Mixed_Case
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-008: COLORTERM="yes" -> Basic_16
   procedure Test_Colorterm_Yes_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-009: TERM-Based Detection
   ---------------------------------------------------------------------------

   --  FUNC-CLR-009: TERM="xterm-256color" -> Extended_256
   procedure Test_Term_Xterm_256color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-009: TERM="screen-256color" -> Extended_256
   procedure Test_Term_Screen_256color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-009: TERM="xterm" -> Basic_16
   procedure Test_Term_Xterm_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-009: TERM="linux" -> Basic_16
   procedure Test_Term_Linux_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-009: TERM="rxvt-unicode" -> Basic_16 (contains rxvt)
   procedure Test_Term_Rxvt_Unicode_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-009: TERM="unknown-terminal" -> None
   procedure Test_Term_Unknown_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-010: TERM_PROGRAM Detection
   ---------------------------------------------------------------------------

   --  FUNC-CLR-010: TERM_PROGRAM="iTerm.app" + version "3.4.0" -> True_Color
   procedure Test_Term_Program_Iterm_V3_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-010: TERM_PROGRAM="iTerm.app" + version "2.1.0" -> Extended_256
   procedure Test_Term_Program_Iterm_V2_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-010: TERM_PROGRAM="iTerm.app" no version -> Extended_256
   procedure Test_Term_Program_Iterm_No_Version
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-010: TERM_PROGRAM="Apple_Terminal" -> Extended_256
   procedure Test_Term_Program_Apple_Terminal
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-010: TERM_PROGRAM="vscode" -> Extended_256
   procedure Test_Term_Program_Vscode
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-011: CI Environment Detection
   ---------------------------------------------------------------------------

   --  FUNC-CLR-011: GITHUB_ACTIONS="true" -> True_Color
   procedure Test_Ci_Github_Actions_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-011: TRAVIS present -> Basic_16
   procedure Test_Ci_Travis_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-011: CI="true" generic -> Basic_16
   procedure Test_Ci_Generic_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-011: CI detection with Is_TTY=False -> still returns color
   procedure Test_Ci_Before_Tty_Gate
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-012: CLICOLOR
   ---------------------------------------------------------------------------

   --  FUNC-CLR-012: CLICOLOR="1" + Is_TTY=True -> Basic_16
   procedure Test_Clicolor_One_With_Tty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-012: CLICOLOR="0" -> no effect
   procedure Test_Clicolor_Zero_No_Effect
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-012: CLICOLOR="1" + Is_TTY=False -> None (post-TTY-gate)
   procedure Test_Clicolor_One_No_Tty_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-013: Multiplexer Awareness
   ---------------------------------------------------------------------------

   --  FUNC-CLR-013: TERM="screen" + COLORTERM="truecolor" -> Extended_256 (capped)
   procedure Test_Multiplexer_Screen_Cap
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-013: TERM="screen-256color" + COLORTERM="truecolor" + TERM_PROGRAM="tmux" -> True_Color
   procedure Test_Multiplexer_Tmux_Exception
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CLR-013: FORCE_COLOR="3" + TERM="screen" -> True_Color (force not capped)
   procedure Test_Multiplexer_Force_Not_Capped
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CLR-015: Priority Order
   ---------------------------------------------------------------------------

   --  FUNC-CLR-015: FORCE_COLOR="2" + NO_COLOR + COLORTERM="truecolor" -> True_Color
   procedure Test_Priority_Floor_Plus_Heuristic
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Color;
