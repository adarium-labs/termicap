-------------------------------------------------------------------------------
--  Test_Override - Unit Tests for Termicap.Override
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the Override_Mode type, Set/Get round-trip,
--  Reset_Override, Parse_Color_Flag, Scoped_Override RAII, and interaction
--  with color and TTY detection.
--
--  Requirements Coverage:
--    - @relation(FUNC-OVR-001): Override_Mode enumeration type
--    - @relation(FUNC-OVR-002): Set_Override procedure
--    - @relation(FUNC-OVR-003): Get_Override function
--    - @relation(FUNC-OVR-004): Override interaction with color detection
--    - @relation(FUNC-OVR-005): Override interaction with TTY detection
--    - @relation(FUNC-OVR-007): Scoped_Override controlled type
--    - @relation(FUNC-OVR-008): Scoped_Override exception safety
--    - @relation(FUNC-OVR-011): Reset_Override convenience procedure
--    - @relation(FUNC-OVR-012): Unit testability without a live terminal
--    - @relation(FUNC-OVR-013): Parse_Color_Flag pure function

with AUnit.Test_Cases;

package Test_Override is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-001: Override_Mode Enumeration Properties
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-001): Five literals, correct ordering
   procedure Test_Override_Mode_Literals (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-001): Auto is the first (default) literal
   procedure Test_Override_Mode_Auto_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-002 / FUNC-OVR-003: Set/Get Round-Trip
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-002): Initial state is Auto (before any Set_Override)
   procedure Test_Initial_State_Is_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-002): Set_Override (Force_None) -> Get_Override = Force_None
   procedure Test_Set_Get_Force_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-002): Set_Override (Force_Basic) -> Get_Override = Force_Basic
   procedure Test_Set_Get_Force_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-002): Set_Override (Force_256) -> Get_Override = Force_256
   procedure Test_Set_Get_Force_256 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-002): Set_Override (Force_True_Color) -> Get_Override = Force_True_Color
   procedure Test_Set_Get_Force_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-002): Set_Override (Auto) -> Get_Override = Auto
   procedure Test_Set_Get_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-011: Reset_Override
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-011): Reset_Override restores Auto after Force_True_Color
   procedure Test_Reset_Override_Restores_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-011): Reset_Override is idempotent when already Auto
   procedure Test_Reset_Override_Idempotent (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-013: Parse_Color_Flag
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-013): "never" -> Force_None
   procedure Test_Parse_Never (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "false" -> Force_None
   procedure Test_Parse_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "off" -> Force_None
   procedure Test_Parse_Off (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "0" -> Force_None
   procedure Test_Parse_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "true" -> Force_Basic
   procedure Test_Parse_True (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "1" -> Force_Basic
   procedure Test_Parse_One (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "16" -> Force_Basic
   procedure Test_Parse_Sixteen (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "2" -> Force_256
   procedure Test_Parse_Two (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "256" -> Force_256
   procedure Test_Parse_256 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "always" -> Force_True_Color
   procedure Test_Parse_Always (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "truecolor" -> Force_True_Color
   procedure Test_Parse_Truecolor (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "16m" -> Force_True_Color
   procedure Test_Parse_16m (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "3" -> Force_True_Color
   procedure Test_Parse_Three (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "auto" -> Auto
   procedure Test_Parse_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): unknown "foo" -> Auto (no exception)
   procedure Test_Parse_Unknown_Returns_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): empty string -> Auto
   procedure Test_Parse_Empty_Returns_Auto (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "NEVER" (uppercase) -> Force_None (case-insensitive)
   procedure Test_Parse_Never_Uppercase (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "Always" (mixed case) -> Force_True_Color (case-insensitive)
   procedure Test_Parse_Always_Mixed_Case (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-013): "TRUE" (uppercase) -> Force_Basic (case-insensitive)
   procedure Test_Parse_True_Uppercase (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-007 / FUNC-OVR-008: Scoped_Override
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-007): Scoped_Override installs mode and restores on exit
   procedure Test_Scoped_Override_Restores (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-008): Scoped_Override restores even when exception raised
   procedure Test_Scoped_Override_Exception_Safety (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-007): Scoped_Override inner mode is visible while in scope
   procedure Test_Scoped_Override_Inner_Mode_Visible (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-007): Nested Scoped_Override objects unwind correctly
   procedure Test_Scoped_Override_Nested (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-004: Override Interaction with Color Detection
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-004): Force_None -> Detect_Color_Level returns None
   procedure Test_Color_Interaction_Force_None (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-004): Force_Basic -> Detect_Color_Level returns Basic_16
   procedure Test_Color_Interaction_Force_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-004): Force_256 -> Detect_Color_Level returns Extended_256
   procedure Test_Color_Interaction_Force_256 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-004): Force_True_Color -> Detect_Color_Level returns True_Color
   procedure Test_Color_Interaction_Force_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-OVR-005: Override Interaction with TTY Detection
   ---------------------------------------------------------------------------

   --  @relation(FUNC-OVR-005): Force_Basic -> Is_TTY returns True
   procedure Test_Tty_Interaction_Force_Basic (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-005): Force_256 -> Is_TTY returns True
   procedure Test_Tty_Interaction_Force_256 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-005): Force_True_Color -> Is_TTY returns True
   procedure Test_Tty_Interaction_Force_True_Color (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  @relation(FUNC-OVR-005): Force_None -> Is_TTY returns False
   procedure Test_Tty_Interaction_Force_None (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Override;
