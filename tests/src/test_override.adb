-------------------------------------------------------------------------------
--  Test_Override - Unit Tests for Termicap.Override
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;  use AUnit.Assertions;
with AUnit.Test_Cases;  use AUnit.Test_Cases.Registration;

with Termicap.Color;       use Termicap.Color;
with Termicap.Environment; use Termicap.Environment;
with Termicap.Override;    use Termicap.Override;
with Termicap.TTY;         use Termicap.TTY;

package body Test_Override is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Override");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-OVR-001
      Register_Routine (T, Test_Override_Mode_Literals'Access,
         "FUNC-OVR-001: Override_Mode has exactly five literals");
      Register_Routine (T, Test_Override_Mode_Auto_Is_First'Access,
         "FUNC-OVR-001: Auto is the first (default) literal");

      --  FUNC-OVR-002 / FUNC-OVR-003
      Register_Routine (T, Test_Initial_State_Is_Auto'Access,
         "FUNC-OVR-002/003: Initial state after Reset_Override is Auto");
      Register_Routine (T, Test_Set_Get_Force_None'Access,
         "FUNC-OVR-002/003: Set_Override (Force_None) -> Get_Override = Force_None");
      Register_Routine (T, Test_Set_Get_Force_Basic'Access,
         "FUNC-OVR-002/003: Set_Override (Force_Basic) -> Get_Override = Force_Basic");
      Register_Routine (T, Test_Set_Get_Force_256'Access,
         "FUNC-OVR-002/003: Set_Override (Force_256) -> Get_Override = Force_256");
      Register_Routine (T, Test_Set_Get_Force_True_Color'Access,
         "FUNC-OVR-002/003: Set_Override (Force_True_Color) -> Get_Override = Force_True_Color");
      Register_Routine (T, Test_Set_Get_Auto'Access,
         "FUNC-OVR-002/003: Set_Override (Auto) -> Get_Override = Auto");

      --  FUNC-OVR-011
      Register_Routine (T, Test_Reset_Override_Restores_Auto'Access,
         "FUNC-OVR-011: Reset_Override restores Auto after Force_True_Color");
      Register_Routine (T, Test_Reset_Override_Idempotent'Access,
         "FUNC-OVR-011: Reset_Override is idempotent when already Auto");

      --  FUNC-OVR-013
      Register_Routine (T, Test_Parse_Never'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""never"") -> Force_None");
      Register_Routine (T, Test_Parse_False'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""false"") -> Force_None");
      Register_Routine (T, Test_Parse_Off'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""off"") -> Force_None");
      Register_Routine (T, Test_Parse_Zero'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""0"") -> Force_None");
      Register_Routine (T, Test_Parse_True'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""true"") -> Force_Basic");
      Register_Routine (T, Test_Parse_One'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""1"") -> Force_Basic");
      Register_Routine (T, Test_Parse_Sixteen'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""16"") -> Force_Basic");
      Register_Routine (T, Test_Parse_Two'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""2"") -> Force_256");
      Register_Routine (T, Test_Parse_256'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""256"") -> Force_256");
      Register_Routine (T, Test_Parse_Always'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""always"") -> Force_True_Color");
      Register_Routine (T, Test_Parse_Truecolor'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""truecolor"") -> Force_True_Color");
      Register_Routine (T, Test_Parse_16m'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""16m"") -> Force_True_Color");
      Register_Routine (T, Test_Parse_Three'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""3"") -> Force_True_Color");
      Register_Routine (T, Test_Parse_Auto'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""auto"") -> Auto");
      Register_Routine (T, Test_Parse_Unknown_Returns_Auto'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""foo"") -> Auto (no exception)");
      Register_Routine (T, Test_Parse_Empty_Returns_Auto'Access,
         "FUNC-OVR-013: Parse_Color_Flag ("""") -> Auto");
      Register_Routine (T, Test_Parse_Never_Uppercase'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""NEVER"") -> Force_None (case-insensitive)");
      Register_Routine (T, Test_Parse_Always_Mixed_Case'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""Always"") -> Force_True_Color (case-insensitive)");
      Register_Routine (T, Test_Parse_True_Uppercase'Access,
         "FUNC-OVR-013: Parse_Color_Flag (""TRUE"") -> Force_Basic (case-insensitive)");

      --  FUNC-OVR-007 / FUNC-OVR-008
      Register_Routine (T, Test_Scoped_Override_Restores'Access,
         "FUNC-OVR-007: Scoped_Override installs mode and restores previous on exit");
      Register_Routine (T, Test_Scoped_Override_Exception_Safety'Access,
         "FUNC-OVR-008: Scoped_Override restores previous mode even when exception raised");
      Register_Routine (T, Test_Scoped_Override_Inner_Mode_Visible'Access,
         "FUNC-OVR-007: Scoped_Override inner mode is visible while in scope");
      Register_Routine (T, Test_Scoped_Override_Nested'Access,
         "FUNC-OVR-007: Nested Scoped_Override objects unwind in LIFO order");

      --  FUNC-OVR-004
      Register_Routine (T, Test_Color_Interaction_Force_None'Access,
         "FUNC-OVR-004: Override Force_None -> Detect_Color_Level returns None");
      Register_Routine (T, Test_Color_Interaction_Force_Basic'Access,
         "FUNC-OVR-004: Override Force_Basic -> Detect_Color_Level returns Basic_16");
      Register_Routine (T, Test_Color_Interaction_Force_256'Access,
         "FUNC-OVR-004: Override Force_256 -> Detect_Color_Level returns Extended_256");
      Register_Routine (T, Test_Color_Interaction_Force_True_Color'Access,
         "FUNC-OVR-004: Override Force_True_Color -> Detect_Color_Level returns True_Color");

      --  FUNC-OVR-005
      Register_Routine (T, Test_Tty_Interaction_Force_Basic'Access,
         "FUNC-OVR-005: Override Force_Basic -> Is_TTY returns True");
      Register_Routine (T, Test_Tty_Interaction_Force_256'Access,
         "FUNC-OVR-005: Override Force_256 -> Is_TTY returns True");
      Register_Routine (T, Test_Tty_Interaction_Force_True_Color'Access,
         "FUNC-OVR-005: Override Force_True_Color -> Is_TTY returns True");
      Register_Routine (T, Test_Tty_Interaction_Force_None'Access,
         "FUNC-OVR-005: Override Force_None -> Is_TTY returns False");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------------

   --  Ensure a clean Auto state before tests that check initial conditions.
   procedure Clean_State is
   begin
      Reset_Override;
   end Clean_State;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-001: Override_Mode Enumeration Properties
   ---------------------------------------------------------------------------


   procedure Test_Override_Mode_Literals
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange / Act: inspect enumeration bounds and count
      --  Assert: five literals means Pos range 0..4
      Assert
         (Override_Mode'Pos (Override_Mode'First) = 0,
          "Override_Mode'First position should be 0");
      Assert
         (Override_Mode'Pos (Override_Mode'Last) = 4,
          "Override_Mode should have exactly five literals (0..4)");
      --  Verify each literal is representable
      Assert
         (Override_Mode'Pos (Auto)             = 0, "Auto position should be 0");
      Assert
         (Override_Mode'Pos (Force_None)        = 1, "Force_None position should be 1");
      Assert
         (Override_Mode'Pos (Force_Basic)       = 2, "Force_Basic position should be 2");
      Assert
         (Override_Mode'Pos (Force_256)         = 3, "Force_256 position should be 3");
      Assert
         (Override_Mode'Pos (Force_True_Color)  = 4, "Force_True_Color position should be 4");
   end Test_Override_Mode_Literals;


   procedure Test_Override_Mode_Auto_Is_First
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Assert: Auto is the zero-position default
      Assert
         (Override_Mode'First = Auto,
          "Override_Mode'First should be Auto");
   end Test_Override_Mode_Auto_Is_First;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-002 / FUNC-OVR-003: Set/Get Round-Trip
   ---------------------------------------------------------------------------


   procedure Test_Initial_State_Is_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange: reset to known clean state
      Reset_Override;
      --  Act / Assert: initial value must be Auto
      Assert
         (Get_Override = Auto,
          "After Reset_Override, Get_Override should return Auto");
   end Test_Initial_State_Is_Auto;


   procedure Test_Set_Get_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Clean_State;
      --  Act
      Set_Override (Force_None);
      --  Assert
      Assert
         (Get_Override = Force_None,
          "After Set_Override (Force_None), Get_Override should return Force_None");
      --  Teardown
      Reset_Override;
   end Test_Set_Get_Force_None;


   procedure Test_Set_Get_Force_Basic
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Clean_State;
      --  Act
      Set_Override (Force_Basic);
      --  Assert
      Assert
         (Get_Override = Force_Basic,
          "After Set_Override (Force_Basic), Get_Override should return Force_Basic");
      --  Teardown
      Reset_Override;
   end Test_Set_Get_Force_Basic;


   procedure Test_Set_Get_Force_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Clean_State;
      --  Act
      Set_Override (Force_256);
      --  Assert
      Assert
         (Get_Override = Force_256,
          "After Set_Override (Force_256), Get_Override should return Force_256");
      --  Teardown
      Reset_Override;
   end Test_Set_Get_Force_256;


   procedure Test_Set_Get_Force_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Clean_State;
      --  Act
      Set_Override (Force_True_Color);
      --  Assert
      Assert
         (Get_Override = Force_True_Color,
          "After Set_Override (Force_True_Color), Get_Override should return Force_True_Color");
      --  Teardown
      Reset_Override;
   end Test_Set_Get_Force_True_Color;


   procedure Test_Set_Get_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange: put the state into a non-Auto value first
      Set_Override (Force_None);
      --  Act
      Set_Override (Auto);
      --  Assert
      Assert
         (Get_Override = Auto,
          "After Set_Override (Auto), Get_Override should return Auto");
   end Test_Set_Get_Auto;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-011: Reset_Override
   ---------------------------------------------------------------------------


   procedure Test_Reset_Override_Restores_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Set_Override (Force_True_Color);
      Assert (Get_Override = Force_True_Color, "Pre-condition: Force_True_Color must be set");
      --  Act
      Reset_Override;
      --  Assert
      Assert
         (Get_Override = Auto,
          "Reset_Override should set the override to Auto");
   end Test_Reset_Override_Restores_Auto;


   procedure Test_Reset_Override_Idempotent
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Reset_Override;
      --  Act: call again when already Auto
      Reset_Override;
      --  Assert
      Assert
         (Get_Override = Auto,
          "Reset_Override when already Auto should still return Auto");
   end Test_Reset_Override_Idempotent;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-013: Parse_Color_Flag
   ---------------------------------------------------------------------------


   procedure Test_Parse_Never
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("never") = Force_None,
          "Parse_Color_Flag (""never"") should return Force_None");
   end Test_Parse_Never;


   procedure Test_Parse_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("false") = Force_None,
          "Parse_Color_Flag (""false"") should return Force_None");
   end Test_Parse_False;


   procedure Test_Parse_Off
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("off") = Force_None,
          "Parse_Color_Flag (""off"") should return Force_None");
   end Test_Parse_Off;


   procedure Test_Parse_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("0") = Force_None,
          "Parse_Color_Flag (""0"") should return Force_None");
   end Test_Parse_Zero;


   procedure Test_Parse_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("true") = Force_Basic,
          "Parse_Color_Flag (""true"") should return Force_Basic");
   end Test_Parse_True;


   procedure Test_Parse_One
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("1") = Force_Basic,
          "Parse_Color_Flag (""1"") should return Force_Basic");
   end Test_Parse_One;


   procedure Test_Parse_Sixteen
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("16") = Force_Basic,
          "Parse_Color_Flag (""16"") should return Force_Basic");
   end Test_Parse_Sixteen;


   procedure Test_Parse_Two
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("2") = Force_256,
          "Parse_Color_Flag (""2"") should return Force_256");
   end Test_Parse_Two;


   procedure Test_Parse_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("256") = Force_256,
          "Parse_Color_Flag (""256"") should return Force_256");
   end Test_Parse_256;


   procedure Test_Parse_Always
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("always") = Force_True_Color,
          "Parse_Color_Flag (""always"") should return Force_True_Color");
   end Test_Parse_Always;


   procedure Test_Parse_Truecolor
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("truecolor") = Force_True_Color,
          "Parse_Color_Flag (""truecolor"") should return Force_True_Color");
   end Test_Parse_Truecolor;


   procedure Test_Parse_16m
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("16m") = Force_True_Color,
          "Parse_Color_Flag (""16m"") should return Force_True_Color");
   end Test_Parse_16m;


   procedure Test_Parse_Three
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("3") = Force_True_Color,
          "Parse_Color_Flag (""3"") should return Force_True_Color");
   end Test_Parse_Three;


   procedure Test_Parse_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("auto") = Auto,
          "Parse_Color_Flag (""auto"") should return Auto");
   end Test_Parse_Auto;


   procedure Test_Parse_Unknown_Returns_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Override_Mode;
   begin
      --  Act: no exception must be raised for an unrecognised value
      Result := Parse_Color_Flag ("foo");
      --  Assert
      Assert
         (Result = Auto,
          "Parse_Color_Flag with unknown value should return Auto");
   end Test_Parse_Unknown_Returns_Auto;


   procedure Test_Parse_Empty_Returns_Auto
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("") = Auto,
          "Parse_Color_Flag with empty string should return Auto");
   end Test_Parse_Empty_Returns_Auto;


   procedure Test_Parse_Never_Uppercase
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("NEVER") = Force_None,
          "Parse_Color_Flag (""NEVER"") should return Force_None (case-insensitive)");
   end Test_Parse_Never_Uppercase;


   procedure Test_Parse_Always_Mixed_Case
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("Always") = Force_True_Color,
          "Parse_Color_Flag (""Always"") should return Force_True_Color (case-insensitive)");
   end Test_Parse_Always_Mixed_Case;


   procedure Test_Parse_True_Uppercase
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Parse_Color_Flag ("TRUE") = Force_Basic,
          "Parse_Color_Flag (""TRUE"") should return Force_Basic (case-insensitive)");
   end Test_Parse_True_Uppercase;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-007 / FUNC-OVR-008: Scoped_Override
   ---------------------------------------------------------------------------


   procedure Test_Scoped_Override_Restores
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange: install an outer override
      Set_Override (Force_True_Color);
      Assert (Get_Override = Force_True_Color, "Pre-condition: Force_True_Color must be active");

      --  Act: enter scoped block with a different mode
      declare
         Guard : Scoped_Override (Mode => Force_None);
         pragma Unreferenced (Guard);
      begin
         null;  --  Finalize restores Force_True_Color when Guard goes out of scope
      end;

      --  Assert: outer mode is restored after scope exits
      Assert
         (Get_Override = Force_True_Color,
          "After Scoped_Override (Force_None) block exits, Get_Override should return " &
          "Force_True_Color (the previously active mode)");

      --  Teardown
      Reset_Override;
   end Test_Scoped_Override_Restores;


   procedure Test_Scoped_Override_Exception_Safety
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange: install a known outer mode
      Set_Override (Force_True_Color);

      --  Act: enter scoped block that raises an exception
      begin
         declare
            Guard : Scoped_Override (Mode => Force_None);
            pragma Unreferenced (Guard);
         begin
            --  Assert: inner mode is active while in scope
            Assert
               (Get_Override = Force_None,
                "Inside Scoped_Override block, Get_Override should return Force_None");
            --  Raise to trigger finalization path
            raise Program_Error with "deliberate test exception";
         end;
      exception
         when Program_Error => null;  --  Expected; swallow the exception
      end;

      --  Assert: outer mode restored despite exception propagation
      Assert
         (Get_Override = Force_True_Color,
          "After exception inside Scoped_Override block, Get_Override should return " &
          "Force_True_Color (restored by Finalize)");

      --  Teardown
      Reset_Override;
   end Test_Scoped_Override_Exception_Safety;


   procedure Test_Scoped_Override_Inner_Mode_Visible
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Inner_Mode_Seen : Override_Mode;
   begin
      --  Arrange
      Set_Override (Force_Basic);

      --  Act: capture the override value while inside the scoped block
      declare
         Guard : Scoped_Override (Mode => Force_256);
         pragma Unreferenced (Guard);
      begin
         Inner_Mode_Seen := Get_Override;
      end;

      --  Assert: the inner mode was Force_256 during the block
      Assert
         (Inner_Mode_Seen = Force_256,
          "Inside Scoped_Override (Force_256) block, Get_Override should return Force_256");

      --  Assert: outer mode is restored after block
      Assert
         (Get_Override = Force_Basic,
          "After Scoped_Override (Force_256) block, Get_Override should return Force_Basic");

      --  Teardown
      Reset_Override;
   end Test_Scoped_Override_Inner_Mode_Visible;


   procedure Test_Scoped_Override_Nested
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Outer_Mode   : Override_Mode;
      Inner_Mode   : Override_Mode;
      Deepest_Mode : Override_Mode;
   begin
      --  Arrange: start with Force_None as the outer state
      Set_Override (Force_None);

      declare
         Guard_Outer : Scoped_Override (Mode => Force_Basic);
         pragma Unreferenced (Guard_Outer);
      begin
         Outer_Mode := Get_Override;
         declare
            Guard_Inner : Scoped_Override (Mode => Force_True_Color);
            pragma Unreferenced (Guard_Inner);
         begin
            Deepest_Mode := Get_Override;
         end;
         Inner_Mode := Get_Override;
      end;

      --  Assert: each level saw the correct mode
      Assert
         (Outer_Mode = Force_Basic,
          "Inside outer Scoped_Override (Force_Basic), Get_Override should return Force_Basic");
      Assert
         (Deepest_Mode = Force_True_Color,
          "Inside inner Scoped_Override (Force_True_Color), Get_Override should return " &
          "Force_True_Color");
      Assert
         (Inner_Mode = Force_Basic,
          "After inner guard exits, Get_Override should return Force_Basic");
      Assert
         (Get_Override = Force_None,
          "After both guards exit, Get_Override should return Force_None");

      --  Teardown
      Reset_Override;
   end Test_Scoped_Override_Nested;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-004: Override Interaction with Color Detection
   ---------------------------------------------------------------------------


   procedure Test_Color_Interaction_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Use an env snapshot that would normally yield a high color level,
      --  to prove the override is applied first regardless of env.
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      --  Arrange
      Insert (Env, "COLORTERM", "truecolor");
      Set_Override (Force_None);
      --  Act / Assert
      Assert
         (Detect_Color_Level (Env, Is_TTY => True) = None,
          "With Override=Force_None, Detect_Color_Level should return None regardless of env");
      --  Teardown
      Reset_Override;
   end Test_Color_Interaction_Force_None;


   procedure Test_Color_Interaction_Force_Basic
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      --  Arrange
      Set_Override (Force_Basic);
      --  Act / Assert
      Assert
         (Detect_Color_Level (Env, Is_TTY => False) = Basic_16,
          "With Override=Force_Basic, Detect_Color_Level should return Basic_16 regardless of TTY");
      --  Teardown
      Reset_Override;
   end Test_Color_Interaction_Force_Basic;


   procedure Test_Color_Interaction_Force_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      --  Arrange
      Set_Override (Force_256);
      --  Act / Assert
      Assert
         (Detect_Color_Level (Env, Is_TTY => False) = Extended_256,
          "With Override=Force_256, Detect_Color_Level should return Extended_256");
      --  Teardown
      Reset_Override;
   end Test_Color_Interaction_Force_256;


   procedure Test_Color_Interaction_Force_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      --  Arrange
      Set_Override (Force_True_Color);
      --  Act / Assert
      Assert
         (Detect_Color_Level (Env, Is_TTY => False) = True_Color,
          "With Override=Force_True_Color, Detect_Color_Level should return True_Color");
      --  Teardown
      Reset_Override;
   end Test_Color_Interaction_Force_True_Color;


   ---------------------------------------------------------------------------
   --  FUNC-OVR-005: Override Interaction with TTY Detection
   ---------------------------------------------------------------------------


   procedure Test_Tty_Interaction_Force_Basic
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Set_Override (Force_Basic);
      --  Act / Assert: TTY detection must return True for any stream
      Assert
         (Is_TTY (Stdout),
          "With Override=Force_Basic, Is_TTY (Stdout) should return True");
      Assert
         (Is_TTY (Stdin),
          "With Override=Force_Basic, Is_TTY (Stdin) should return True");
      Assert
         (Is_TTY (Stderr),
          "With Override=Force_Basic, Is_TTY (Stderr) should return True");
      --  Teardown
      Reset_Override;
   end Test_Tty_Interaction_Force_Basic;


   procedure Test_Tty_Interaction_Force_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Set_Override (Force_256);
      --  Act / Assert
      Assert
         (Is_TTY (Stdout),
          "With Override=Force_256, Is_TTY (Stdout) should return True");
      Assert
         (Is_TTY (Stdin),
          "With Override=Force_256, Is_TTY (Stdin) should return True");
      Assert
         (Is_TTY (Stderr),
          "With Override=Force_256, Is_TTY (Stderr) should return True");
      --  Teardown
      Reset_Override;
   end Test_Tty_Interaction_Force_256;


   procedure Test_Tty_Interaction_Force_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Set_Override (Force_True_Color);
      --  Act / Assert
      Assert
         (Is_TTY (Stdout),
          "With Override=Force_True_Color, Is_TTY (Stdout) should return True");
      Assert
         (Is_TTY (Stdin),
          "With Override=Force_True_Color, Is_TTY (Stdin) should return True");
      Assert
         (Is_TTY (Stderr),
          "With Override=Force_True_Color, Is_TTY (Stderr) should return True");
      --  Teardown
      Reset_Override;
   end Test_Tty_Interaction_Force_True_Color;


   procedure Test_Tty_Interaction_Force_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      --  Arrange
      Set_Override (Force_None);
      --  Act / Assert: TTY detection must return False for every stream
      Assert
         (not Is_TTY (Stdout),
          "With Override=Force_None, Is_TTY (Stdout) should return False");
      Assert
         (not Is_TTY (Stdin),
          "With Override=Force_None, Is_TTY (Stdin) should return False");
      Assert
         (not Is_TTY (Stderr),
          "With Override=Force_None, Is_TTY (Stderr) should return False");
      --  Teardown
      Reset_Override;
   end Test_Tty_Interaction_Force_None;

end Test_Override;
