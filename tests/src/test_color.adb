-------------------------------------------------------------------------------
--  Test_Color - Unit Tests for Termicap.Color
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Color;       use Termicap.Color;
with Termicap.Environment; use Termicap.Environment;

package body Test_Color is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Color");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-CLR-001
      Register_Routine
        (T,
         Test_Color_Level_Ordering'Access,
         "FUNC-CLR-001: Color_Level ordering: None < Basic_16 < Extended_256 < True_Color");
      Register_Routine (T, Test_Color_Level_Max'Access, "FUNC-CLR-001: Color_Level'Max returns higher of two levels");

      --  FUNC-CLR-003
      Register_Routine
        (T, Test_No_Color_Empty_Disables'Access, "FUNC-CLR-003: NO_COLOR='' (empty) present, no force -> None");
      Register_Routine (T, Test_No_Color_One_Disables'Access, "FUNC-CLR-003: NO_COLOR='1' present, no force -> None");
      Register_Routine
        (T, Test_No_Color_Absent_Proceeds'Access, "FUNC-CLR-003: NO_COLOR absent -> detection proceeds normally");
      Register_Routine
        (T,
         Test_No_Color_Overridden_By_Force'Access,
         "FUNC-CLR-003: NO_COLOR + FORCE_COLOR='1' -> Basic_16 (force overrides)");

      --  FUNC-CLR-004
      Register_Routine
        (T, Test_Force_Color_Three_True_Color'Access, "FUNC-CLR-004: FORCE_COLOR='3' -> True_Color regardless");
      Register_Routine
        (T, Test_Force_Color_Two_Extended_256'Access, "FUNC-CLR-004: FORCE_COLOR='2' -> Extended_256 regardless");
      Register_Routine (T, Test_Force_Color_One_Basic_16'Access, "FUNC-CLR-004: FORCE_COLOR='1' -> Basic_16");
      Register_Routine
        (T, Test_Force_Color_Zero_None'Access, "FUNC-CLR-004: FORCE_COLOR='0' -> None even with COLORTERM=truecolor");
      Register_Routine (T, Test_Force_Color_False_None'Access, "FUNC-CLR-004: FORCE_COLOR='false' -> None");
      Register_Routine (T, Test_Force_Color_True_Basic_16'Access, "FUNC-CLR-004: FORCE_COLOR='true' -> Basic_16");
      Register_Routine (T, Test_Force_Color_Empty_Basic_16'Access, "FUNC-CLR-004: FORCE_COLOR='' (empty) -> Basic_16");
      Register_Routine
        (T, Test_Force_Color_Unknown_Basic_16'Access, "FUNC-CLR-004: FORCE_COLOR='xyz' (unknown) -> Basic_16");
      Register_Routine
        (T, Test_Force_Color_Three_Overrides_Dumb'Access, "FUNC-CLR-004: FORCE_COLOR='3' + TERM=dumb -> True_Color");
      Register_Routine
        (T,
         Test_Force_Color_Two_Overrides_Tty_Gate'Access,
         "FUNC-CLR-004: FORCE_COLOR='2' + Is_TTY=False -> Extended_256");

      --  FUNC-CLR-005
      Register_Routine
        (T, Test_Clicolor_Force_One_No_Tty'Access, "FUNC-CLR-005: CLICOLOR_FORCE='1' + Is_TTY=False -> Basic_16");
      Register_Routine (T, Test_Clicolor_Force_Zero_No_Effect'Access, "FUNC-CLR-005: CLICOLOR_FORCE='0' -> no effect");
      Register_Routine
        (T,
         Test_Clicolor_Force_Superseded_By_Force_Color'Access,
         "FUNC-CLR-005: CLICOLOR_FORCE='1' + FORCE_COLOR='3' -> True_Color");
      Register_Routine
        (T, Test_Clicolor_Force_Overrides_No_Color'Access, "FUNC-CLR-005: CLICOLOR_FORCE='1' + NO_COLOR -> Basic_16");

      --  FUNC-CLR-006
      Register_Routine (T, Test_Term_Dumb_No_Force_None'Access, "FUNC-CLR-006: TERM='dumb', no force -> None");
      Register_Routine
        (T, Test_Term_Dumb_With_Force_Color'Access, "FUNC-CLR-006: TERM='dumb' + FORCE_COLOR='1' -> Basic_16");
      Register_Routine (T, Test_Term_Dumb_Uppercase'Access, "FUNC-CLR-006: TERM='DUMB' (uppercase) -> None");

      --  FUNC-CLR-007
      Register_Routine (T, Test_Tty_Gate_No_Tty_None'Access, "FUNC-CLR-007: Is_TTY=False, no force, no CI -> None");
      Register_Routine (T, Test_Tty_Gate_Tty_No_Signal_None'Access, "FUNC-CLR-007: Is_TTY=True, no env vars -> None");
      Register_Routine
        (T, Test_Tty_Gate_Force_Color_Bypasses'Access, "FUNC-CLR-007: Is_TTY=False + FORCE_COLOR='1' -> Basic_16");

      --  FUNC-CLR-008
      Register_Routine (T, Test_Colorterm_Truecolor'Access, "FUNC-CLR-008: COLORTERM='truecolor' -> True_Color");
      Register_Routine (T, Test_Colorterm_24bit'Access, "FUNC-CLR-008: COLORTERM='24bit' -> True_Color");
      Register_Routine
        (T, Test_Colorterm_Mixed_Case'Access, "FUNC-CLR-008: COLORTERM='TrueColor' (mixed case) -> True_Color");
      Register_Routine (T, Test_Colorterm_Yes_Basic_16'Access, "FUNC-CLR-008: COLORTERM='yes' -> Basic_16");

      --  FUNC-CLR-009
      Register_Routine (T, Test_Term_Xterm_256color'Access, "FUNC-CLR-009: TERM='xterm-256color' -> Extended_256");
      Register_Routine (T, Test_Term_Screen_256color'Access, "FUNC-CLR-009: TERM='screen-256color' -> Extended_256");
      Register_Routine (T, Test_Term_Xterm_Basic_16'Access, "FUNC-CLR-009: TERM='xterm' -> Basic_16");
      Register_Routine (T, Test_Term_Linux_Basic_16'Access, "FUNC-CLR-009: TERM='linux' -> Basic_16");
      Register_Routine (T, Test_Term_Rxvt_Unicode_Basic_16'Access, "FUNC-CLR-009: TERM='rxvt-unicode' -> Basic_16");
      Register_Routine (T, Test_Term_Unknown_None'Access, "FUNC-CLR-009: TERM='unknown-terminal' -> None");

      --  FUNC-CLR-010
      Register_Routine
        (T,
         Test_Term_Program_Iterm_V3_True_Color'Access,
         "FUNC-CLR-010: TERM_PROGRAM='iTerm.app' version '3.4.0' -> True_Color");
      Register_Routine
        (T,
         Test_Term_Program_Iterm_V2_Extended_256'Access,
         "FUNC-CLR-010: TERM_PROGRAM='iTerm.app' version '2.1.0' -> Extended_256");
      Register_Routine
        (T,
         Test_Term_Program_Iterm_No_Version'Access,
         "FUNC-CLR-010: TERM_PROGRAM='iTerm.app' no version -> Extended_256");
      Register_Routine
        (T, Test_Term_Program_Apple_Terminal'Access, "FUNC-CLR-010: TERM_PROGRAM='Apple_Terminal' -> Extended_256");
      Register_Routine (T, Test_Term_Program_Vscode'Access, "FUNC-CLR-010: TERM_PROGRAM='vscode' -> Extended_256");

      --  FUNC-CLR-011
      Register_Routine
        (T, Test_Ci_Github_Actions_True_Color'Access, "FUNC-CLR-011: GITHUB_ACTIONS='true' -> True_Color");
      Register_Routine (T, Test_Ci_Travis_Basic_16'Access, "FUNC-CLR-011: TRAVIS present -> Basic_16");
      Register_Routine (T, Test_Ci_Generic_Basic_16'Access, "FUNC-CLR-011: CI='true' generic -> Basic_16");
      Register_Routine
        (T, Test_Ci_Before_Tty_Gate'Access, "FUNC-CLR-011: CI detection with Is_TTY=False -> still returns color");

      --  FUNC-CLR-012
      Register_Routine (T, Test_Clicolor_One_With_Tty'Access, "FUNC-CLR-012: CLICOLOR='1' + Is_TTY=True -> Basic_16");
      Register_Routine (T, Test_Clicolor_Zero_No_Effect'Access, "FUNC-CLR-012: CLICOLOR='0' -> no effect");
      Register_Routine
        (T, Test_Clicolor_One_No_Tty_None'Access, "FUNC-CLR-012: CLICOLOR='1' + Is_TTY=False -> None (post-TTY-gate)");

      --  FUNC-CLR-013
      Register_Routine
        (T,
         Test_Multiplexer_Screen_Cap'Access,
         "FUNC-CLR-013: TERM='screen' + COLORTERM='truecolor' -> Extended_256 (capped)");
      Register_Routine
        (T,
         Test_Multiplexer_Tmux_Exception'Access,
         "FUNC-CLR-013: screen-256color + COLORTERM=truecolor + TERM_PROGRAM=tmux -> True_Color");
      Register_Routine
        (T,
         Test_Multiplexer_Force_Not_Capped'Access,
         "FUNC-CLR-013: FORCE_COLOR='3' + TERM='screen' -> True_Color (force not capped)");

      --  FUNC-CLR-015
      Register_Routine
        (T,
         Test_Priority_Floor_Plus_Heuristic'Access,
         "FUNC-CLR-015: FORCE_COLOR='2' + NO_COLOR + COLORTERM='truecolor' -> True_Color");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   procedure Test_Color_Level_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Color_Level'First = None, "Color_Level'First should be None");
      Assert (Color_Level'Last = True_Color, "Color_Level'Last should be True_Color");
      Assert (None < Basic_16, "None should be less than Basic_16");
      Assert (Basic_16 < Extended_256, "Basic_16 should be less than Extended_256");
      Assert (Extended_256 < True_Color, "Extended_256 should be less than True_Color");
      Assert (None < True_Color, "None should be less than True_Color");
   end Test_Color_Level_Ordering;

   procedure Test_Color_Level_Max (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Color_Level'Max (None, None) = None, "Max(None, None) should be None");
      Assert (Color_Level'Max (None, Basic_16) = Basic_16, "Max(None, Basic_16) should be Basic_16");
      Assert
        (Color_Level'Max (Basic_16, Extended_256) = Extended_256, "Max(Basic_16, Extended_256) should be Extended_256");
      Assert
        (Color_Level'Max (Extended_256, True_Color) = True_Color, "Max(Extended_256, True_Color) should be True_Color");
      Assert (Color_Level'Max (True_Color, None) = True_Color, "Max(True_Color, None) should be True_Color");
      Assert
        (Color_Level'Max (Extended_256, Basic_16) = Extended_256, "Max(Extended_256, Basic_16) should be Extended_256");
   end Test_Color_Level_Max;

   procedure Test_No_Color_Empty_Disables (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "NO_COLOR='' (empty, present) with no force should return None");
   end Test_No_Color_Empty_Disables;

   procedure Test_No_Color_One_Disables (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = None, "NO_COLOR='1' with no force should return None");
   end Test_No_Color_One_Disables;

   procedure Test_No_Color_Absent_Proceeds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  NO_COLOR absent; with COLORTERM=truecolor detection should proceed
      Insert (Env, "COLORTERM", "truecolor");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = True_Color,
         "NO_COLOR absent: detection should proceed; COLORTERM=truecolor gives True_Color");
   end Test_No_Color_Absent_Proceeds;

   procedure Test_No_Color_Overridden_By_Force (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Insert (Env, "FORCE_COLOR", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "NO_COLOR present but FORCE_COLOR='1' should return Basic_16");
   end Test_No_Color_Overridden_By_Force;

   procedure Test_Force_Color_Three_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "3");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = True_Color, "FORCE_COLOR='3' should return True_Color");
   end Test_Force_Color_Three_True_Color;

   procedure Test_Force_Color_Two_Extended_256 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "2");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = Extended_256, "FORCE_COLOR='2' should return Extended_256");
   end Test_Force_Color_Two_Extended_256;

   procedure Test_Force_Color_One_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "1");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = Basic_16, "FORCE_COLOR='1' should return Basic_16");
   end Test_Force_Color_One_Basic_16;

   procedure Test_Force_Color_Zero_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "0");
      Insert (Env, "COLORTERM", "truecolor");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "FORCE_COLOR='0' should return None even with COLORTERM=truecolor");
   end Test_Force_Color_Zero_None;

   procedure Test_Force_Color_False_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "false");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = None, "FORCE_COLOR='false' should return None");
   end Test_Force_Color_False_None;

   procedure Test_Force_Color_True_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "true");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = Basic_16, "FORCE_COLOR='true' should return Basic_16");
   end Test_Force_Color_True_Basic_16;

   procedure Test_Force_Color_Empty_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "FORCE_COLOR='' (empty, present) should return Basic_16");
   end Test_Force_Color_Empty_Basic_16;

   procedure Test_Force_Color_Unknown_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "xyz");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "FORCE_COLOR='xyz' (unknown value) should return Basic_16");
   end Test_Force_Color_Unknown_Basic_16;

   procedure Test_Force_Color_Three_Overrides_Dumb (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "3");
      Insert (Env, "TERM", "dumb");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = True_Color,
         "FORCE_COLOR='3' + TERM='dumb' should return True_Color (force overrides dumb)");
   end Test_Force_Color_Three_Overrides_Dumb;

   procedure Test_Force_Color_Two_Overrides_Tty_Gate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "2");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Extended_256,
         "FORCE_COLOR='2' + Is_TTY=False should return Extended_256 (overrides TTY gate)");
   end Test_Force_Color_Two_Overrides_Tty_Gate;

   procedure Test_Clicolor_Force_One_No_Tty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR_FORCE", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "CLICOLOR_FORCE='1' + Is_TTY=False should return Basic_16");
   end Test_Clicolor_Force_One_No_Tty;

   procedure Test_Clicolor_Force_Zero_No_Effect (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR_FORCE", "0");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = None,
         "CLICOLOR_FORCE='0' should have no effect; Is_TTY=False with no signals gives None");
   end Test_Clicolor_Force_Zero_No_Effect;

   procedure Test_Clicolor_Force_Superseded_By_Force_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "3");
      Insert (Env, "CLICOLOR_FORCE", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = True_Color,
         "FORCE_COLOR='3' supersedes CLICOLOR_FORCE='1': should return True_Color");
   end Test_Clicolor_Force_Superseded_By_Force_Color;

   procedure Test_Clicolor_Force_Overrides_No_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR_FORCE", "1");
      Insert (Env, "NO_COLOR", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "CLICOLOR_FORCE='1' + NO_COLOR: CLICOLOR_FORCE overrides NO_COLOR -> Basic_16");
   end Test_Clicolor_Force_Overrides_No_Color;

   procedure Test_Term_Dumb_No_Force_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "dumb");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = None, "TERM='dumb' with no force override should return None");
   end Test_Term_Dumb_No_Force_None;

   procedure Test_Term_Dumb_With_Force_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "dumb");
      Insert (Env, "FORCE_COLOR", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Basic_16, "TERM='dumb' + FORCE_COLOR='1' should return Basic_16");
   end Test_Term_Dumb_With_Force_Color;

   procedure Test_Term_Dumb_Uppercase (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "DUMB");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "TERM='DUMB' (uppercase) should return None (case-insensitive dumb check)");
   end Test_Term_Dumb_Uppercase;

   procedure Test_Tty_Gate_No_Tty_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = None, "Is_TTY=False with no force and no CI should return None");
   end Test_Tty_Gate_No_Tty_None;

   procedure Test_Tty_Gate_Tty_No_Signal_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "Is_TTY=True with no env vars should return None (no positive signal)");
   end Test_Tty_Gate_Tty_No_Signal_None;

   procedure Test_Tty_Gate_Force_Color_Bypasses (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
         "FORCE_COLOR='1' + Is_TTY=False should return Basic_16 (force bypasses TTY gate)");
   end Test_Tty_Gate_Force_Color_Bypasses;

   procedure Test_Colorterm_Truecolor (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "COLORTERM", "truecolor");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = True_Color, "COLORTERM='truecolor' should return True_Color");
   end Test_Colorterm_Truecolor;

   procedure Test_Colorterm_24bit (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "COLORTERM", "24bit");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = True_Color, "COLORTERM='24bit' should return True_Color");
   end Test_Colorterm_24bit;

   procedure Test_Colorterm_Mixed_Case (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "COLORTERM", "TrueColor");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = True_Color,
         "COLORTERM='TrueColor' (mixed case) should return True_Color");
   end Test_Colorterm_Mixed_Case;

   procedure Test_Colorterm_Yes_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "COLORTERM", "yes");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Basic_16,
         "COLORTERM='yes' (non-truecolor value) should return Basic_16");
   end Test_Colorterm_Yes_Basic_16;

   procedure Test_Term_Xterm_256color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm-256color");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256, "TERM='xterm-256color' should return Extended_256");
   end Test_Term_Xterm_256color;

   procedure Test_Term_Screen_256color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "screen-256color");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256, "TERM='screen-256color' should return Extended_256");
   end Test_Term_Screen_256color;

   procedure Test_Term_Xterm_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = Basic_16, "TERM='xterm' should return Basic_16");
   end Test_Term_Xterm_Basic_16;

   procedure Test_Term_Linux_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "linux");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = Basic_16, "TERM='linux' should return Basic_16");
   end Test_Term_Linux_Basic_16;

   procedure Test_Term_Rxvt_Unicode_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "rxvt-unicode");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Basic_16,
         "TERM='rxvt-unicode' (contains 'rxvt') should return Basic_16");
   end Test_Term_Rxvt_Unicode_Basic_16;

   procedure Test_Term_Unknown_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "unknown-terminal");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "TERM='unknown-terminal' (no known pattern) should return None");
   end Test_Term_Unknown_None;

   procedure Test_Term_Program_Iterm_V3_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM_PROGRAM", "iTerm.app");
      Insert (Env, "TERM_PROGRAM_VERSION", "3.4.0");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = True_Color,
         "TERM_PROGRAM='iTerm.app' with version '3.4.0' should return True_Color");
   end Test_Term_Program_Iterm_V3_True_Color;

   procedure Test_Term_Program_Iterm_V2_Extended_256 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM_PROGRAM", "iTerm.app");
      Insert (Env, "TERM_PROGRAM_VERSION", "2.1.0");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256,
         "TERM_PROGRAM='iTerm.app' with version '2.1.0' should return Extended_256");
   end Test_Term_Program_Iterm_V2_Extended_256;

   procedure Test_Term_Program_Iterm_No_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM_PROGRAM", "iTerm.app");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256,
         "TERM_PROGRAM='iTerm.app' with no version should return Extended_256");
   end Test_Term_Program_Iterm_No_Version;

   procedure Test_Term_Program_Apple_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM_PROGRAM", "Apple_Terminal");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256,
         "TERM_PROGRAM='Apple_Terminal' should return Extended_256");
   end Test_Term_Program_Apple_Terminal;

   procedure Test_Term_Program_Vscode (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM_PROGRAM", "vscode");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256, "TERM_PROGRAM='vscode' should return Extended_256");
   end Test_Term_Program_Vscode;

   procedure Test_Ci_Github_Actions_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "GITHUB_ACTIONS", "true");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = True_Color, "GITHUB_ACTIONS='true' should return True_Color");
   end Test_Ci_Github_Actions_True_Color;

   procedure Test_Ci_Travis_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TRAVIS", "1");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = Basic_16, "TRAVIS present should return Basic_16");
   end Test_Ci_Travis_Basic_16;

   procedure Test_Ci_Generic_Basic_16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CI", "true");
      Assert (Detect_Color_Level (Env, Is_TTY => False) = Basic_16, "CI='true' (generic CI) should return Basic_16");
   end Test_Ci_Generic_Basic_16;

   procedure Test_Ci_Before_Tty_Gate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  CI detection is positioned before the TTY gate (step 5 vs step 6).
      --  With Is_TTY=False and GITHUB_ACTIONS=true, the CI level (True_Color)
      --  is established before the TTY gate, so the gate is bypassed.
      Insert (Env, "GITHUB_ACTIONS", "true");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = True_Color,
         "CI with Is_TTY=False: CI detection precedes TTY gate, should return True_Color");
   end Test_Ci_Before_Tty_Gate;

   procedure Test_Clicolor_One_With_Tty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR", "1");
      Assert (Detect_Color_Level (Env, Is_TTY => True) = Basic_16, "CLICOLOR='1' + Is_TTY=True should return Basic_16");
   end Test_Clicolor_One_With_Tty;

   procedure Test_Clicolor_Zero_No_Effect (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR", "0");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = None,
         "CLICOLOR='0' should have no effect; no other signals -> None");
   end Test_Clicolor_Zero_No_Effect;

   procedure Test_Clicolor_One_No_Tty_None (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "CLICOLOR", "1");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = None,
         "CLICOLOR='1' + Is_TTY=False should return None " & "(CLICOLOR is post-TTY-gate, so TTY gate blocks it)");
   end Test_Clicolor_One_No_Tty_None;

   procedure Test_Multiplexer_Screen_Cap (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "screen");
      Insert (Env, "COLORTERM", "truecolor");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = Extended_256,
         "TERM='screen' + COLORTERM='truecolor' should be capped at Extended_256");
   end Test_Multiplexer_Screen_Cap;

   procedure Test_Multiplexer_Tmux_Exception (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "screen-256color");
      Insert (Env, "COLORTERM", "truecolor");
      Insert (Env, "TERM_PROGRAM", "tmux");
      Assert
        (Detect_Color_Level (Env, Is_TTY => True) = True_Color,
         "screen + COLORTERM=truecolor + TERM_PROGRAM=tmux: tmux exception -> True_Color");
   end Test_Multiplexer_Tmux_Exception;

   procedure Test_Multiplexer_Force_Not_Capped (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "FORCE_COLOR", "3");
      Insert (Env, "TERM", "screen");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = True_Color,
         "FORCE_COLOR='3' + TERM='screen': force override is not subject to multiplexer cap");
   end Test_Multiplexer_Force_Not_Capped;

   procedure Test_Priority_Floor_Plus_Heuristic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  FORCE_COLOR="2" sets Floor=Extended_256, Force_Set=True.
      --  NO_COLOR is present but ignored because Force_Set=True.
      --  COLORTERM="truecolor" sets Heuristic=True_Color.
      --  Final result = max(Floor=Extended_256, Heuristic=True_Color) = True_Color.
      Insert (Env, "FORCE_COLOR", "2");
      Insert (Env, "NO_COLOR", "1");
      Insert (Env, "COLORTERM", "truecolor");
      Assert
        (Detect_Color_Level (Env, Is_TTY => False) = True_Color,
         "FORCE_COLOR='2' + NO_COLOR + COLORTERM='truecolor': "
         & "floor=256, NO_COLOR ignored, heuristic=TrueColor -> max=True_Color");
   end Test_Priority_Floor_Plus_Heuristic;

end Test_Color;
