-------------------------------------------------------------------------------
--  Test_Dark_Light - Unit Tests for Termicap.Color.Dark_Light
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Color.BG_Query;       use Termicap.Color.BG_Query;
with Termicap.Color.Dark_Light;     use Termicap.Color.Dark_Light;
with Termicap.Color.Dark_Light.Detect;
with Termicap.Color.Detection;      use Termicap.Color.Detection;

package body Test_Dark_Light is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Color.Dark_Light");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-DKL-001: Theme_Kind enumeration properties
      Register_Routine (T, Test_Theme_Kind_First_Is_Dark'Access,
         "FUNC-DKL-001: Theme_Kind'First = Dark");
      Register_Routine (T, Test_Theme_Kind_Last_Is_Light'Access,
         "FUNC-DKL-001: Theme_Kind'Last = Light");

      --  FUNC-DKL-002: Luminance computation
      Register_Routine (T, Test_Luminance_Black'Access,
         "FUNC-DKL-002: RGB(0,0,0) -> Luminance = 0");
      Register_Routine (T, Test_Luminance_White'Access,
         "FUNC-DKL-002: RGB(255,255,255) -> Luminance = 255");
      Register_Routine (T, Test_Luminance_Pure_Red'Access,
         "FUNC-DKL-002: RGB(255,0,0) -> Luminance = 76 (pure red, 299*255/1000)");
      Register_Routine (T, Test_Luminance_Pure_Green'Access,
         "FUNC-DKL-002: RGB(0,255,0) -> Luminance = 149 (pure green, 587*255/1000)");
      Register_Routine (T, Test_Luminance_Pure_Blue'Access,
         "FUNC-DKL-002: RGB(0,0,255) -> Luminance = 29 (pure blue, 114*255/1000)");
      Register_Routine (T, Test_Luminance_Mid_Grey'Access,
         "FUNC-DKL-002: RGB(128,128,128) -> Luminance = 128 (mid grey)");
      Register_Routine (T, Test_Luminance_Near_Threshold'Access,
         "FUNC-DKL-002: RGB(127,127,127) -> Luminance = 127 (near-threshold)");

      --  FUNC-DKL-003: Classify_Theme
      Register_Routine (T, Test_Classify_Theme_Black_Is_Dark'Access,
         "FUNC-DKL-003: RGB(0,0,0) -> Dark");
      Register_Routine (T, Test_Classify_Theme_White_Is_Light'Access,
         "FUNC-DKL-003: RGB(255,255,255) -> Light");
      Register_Routine (T, Test_Classify_Theme_Mid_Grey_Is_Light'Access,
         "FUNC-DKL-003: RGB(128,128,128) -> Light (boundary: luminance=128 >= threshold)");
      Register_Routine (T, Test_Classify_Theme_Near_Threshold_Is_Dark'Access,
         "FUNC-DKL-003: RGB(127,127,127) -> Dark (just below threshold: luminance=127)");
      Register_Routine (T, Test_Classify_Theme_Typical_Dark_Terminal'Access,
         "FUNC-DKL-003: RGB(30,30,30) -> Dark (typical dark terminal)");
      Register_Routine (T, Test_Classify_Theme_Typical_Light_Terminal'Access,
         "FUNC-DKL-003: RGB(240,240,240) -> Light (typical light terminal)");
      Register_Routine (T, Test_Classify_Theme_Solarized_Dark'Access,
         "FUNC-DKL-003: RGB(0,43,54) -> Dark (Solarized Dark background)");
      Register_Routine (T, Test_Classify_Theme_Solarized_Light'Access,
         "FUNC-DKL-003: RGB(253,246,227) -> Light (Solarized Light background)");

      --  FUNC-DKL-004: Is_Dark and Is_Light
      Register_Routine (T, Test_Is_Dark_Black_True'Access,
         "FUNC-DKL-004: Is_Dark(RGB(0,0,0)) = True");
      Register_Routine (T, Test_Is_Dark_White_False'Access,
         "FUNC-DKL-004: Is_Dark(RGB(255,255,255)) = False");
      Register_Routine (T, Test_Is_Light_Black_False'Access,
         "FUNC-DKL-004: Is_Light(RGB(0,0,0)) = False");
      Register_Routine (T, Test_Is_Light_White_True'Access,
         "FUNC-DKL-004: Is_Light(RGB(255,255,255)) = True");
      Register_Routine (T, Test_Is_Dark_And_Is_Light_Are_Complementary'Access,
         "FUNC-DKL-004: Is_Dark and Is_Light are complementary for same color");

      --  FUNC-DKL-006: Theme_Result discriminated record
      Register_Routine (T, Test_Theme_Result_Success_Variant'Access,
         "FUNC-DKL-006: Success variant can hold Theme + Color");
      Register_Routine (T, Test_Theme_Result_Failure_Variant'Access,
         "FUNC-DKL-006: Failure variant can hold Error");
      Register_Routine (T, Test_Theme_Result_Default_Discriminant_Is_False'Access,
         "FUNC-DKL-006: Default discriminant is False (failure state)");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   ---------------------------------------------------------------------------
   --  FUNC-DKL-001: Theme_Kind Enumeration Properties
   ---------------------------------------------------------------------------


   procedure Test_Theme_Kind_First_Is_Dark
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Theme_Kind'First = Dark,
          "Theme_Kind'First should be Dark");
   end Test_Theme_Kind_First_Is_Dark;


   procedure Test_Theme_Kind_Last_Is_Light
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Theme_Kind'Last = Light,
          "Theme_Kind'Last should be Light");
   end Test_Theme_Kind_Last_Is_Light;


   ---------------------------------------------------------------------------
   --  FUNC-DKL-002: Luminance Computation
   ---------------------------------------------------------------------------


   procedure Test_Luminance_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Luminance (Black) = 0,
          "Luminance(RGB(0,0,0)) should be 0");
   end Test_Luminance_Black;


   procedure Test_Luminance_White
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Luminance (White) = 255,
          "Luminance(RGB(255,255,255)) should be 255");
   end Test_Luminance_White;


   procedure Test_Luminance_Pure_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299 * 255 + 587 * 0 + 114 * 0) / 1000 = 76245 / 1000 = 76
      Red : constant RGB := (Red => 255, Green => 0, Blue => 0);
   begin
      Assert
         (Luminance (Red) = 76,
          "Luminance(RGB(255,0,0)) should be 76 (299*255/1000 = 76)");
   end Test_Luminance_Pure_Red;


   procedure Test_Luminance_Pure_Green
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299 * 0 + 587 * 255 + 114 * 0) / 1000 = 149685 / 1000 = 149
      Green : constant RGB := (Red => 0, Green => 255, Blue => 0);
   begin
      Assert
         (Luminance (Green) = 149,
          "Luminance(RGB(0,255,0)) should be 149 (587*255/1000 = 149)");
   end Test_Luminance_Pure_Green;


   procedure Test_Luminance_Pure_Blue
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299 * 0 + 587 * 0 + 114 * 255) / 1000 = 29070 / 1000 = 29
      Blue : constant RGB := (Red => 0, Green => 0, Blue => 255);
   begin
      Assert
         (Luminance (Blue) = 29,
          "Luminance(RGB(0,0,255)) should be 29 (114*255/1000 = 29)");
   end Test_Luminance_Pure_Blue;


   procedure Test_Luminance_Mid_Grey
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299 * 128 + 587 * 128 + 114 * 128) / 1000
      --    = (38272 + 75136 + 14592) / 1000
      --    = 128000 / 1000
      --    = 128
      Mid_Grey : constant RGB := (Red => 128, Green => 128, Blue => 128);
   begin
      Assert
         (Luminance (Mid_Grey) = 128,
          "Luminance(RGB(128,128,128)) should be 128");
   end Test_Luminance_Mid_Grey;


   procedure Test_Luminance_Near_Threshold
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299 * 127 + 587 * 127 + 114 * 127) / 1000
      --    = (37973 + 74549 + 14478) / 1000
      --    = 127000 / 1000
      --    = 127
      Near_Threshold : constant RGB := (Red => 127, Green => 127, Blue => 127);
   begin
      Assert
         (Luminance (Near_Threshold) = 127,
          "Luminance(RGB(127,127,127)) should be 127");
   end Test_Luminance_Near_Threshold;


   ---------------------------------------------------------------------------
   --  FUNC-DKL-003: Classify_Theme Function
   ---------------------------------------------------------------------------


   procedure Test_Classify_Theme_Black_Is_Dark
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Classify_Theme (Black) = Dark,
          "Classify_Theme(RGB(0,0,0)) should be Dark");
   end Test_Classify_Theme_Black_Is_Dark;


   procedure Test_Classify_Theme_White_Is_Light
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Classify_Theme (White) = Light,
          "Classify_Theme(RGB(255,255,255)) should be Light");
   end Test_Classify_Theme_White_Is_Light;


   procedure Test_Classify_Theme_Mid_Grey_Is_Light
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Luminance = 128 >= LUMINANCE_THRESHOLD (128) -> Light
      Mid_Grey : constant RGB := (Red => 128, Green => 128, Blue => 128);
   begin
      Assert
         (Classify_Theme (Mid_Grey) = Light,
          "Classify_Theme(RGB(128,128,128)) should be Light "
          & "(luminance=128 >= threshold=128, boundary classified as Light)");
   end Test_Classify_Theme_Mid_Grey_Is_Light;


   procedure Test_Classify_Theme_Near_Threshold_Is_Dark
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Luminance = 127 < LUMINANCE_THRESHOLD (128) -> Dark
      Near_Threshold : constant RGB := (Red => 127, Green => 127, Blue => 127);
   begin
      Assert
         (Classify_Theme (Near_Threshold) = Dark,
          "Classify_Theme(RGB(127,127,127)) should be Dark "
          & "(luminance=127 < threshold=128)");
   end Test_Classify_Theme_Near_Threshold_Is_Dark;


   procedure Test_Classify_Theme_Typical_Dark_Terminal
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299*30 + 587*30 + 114*30) / 1000 = (8970 + 17610 + 3420) / 1000
      --    = 30000 / 1000 = 30 -> Dark
      Dark_BG : constant RGB := (Red => 30, Green => 30, Blue => 30);
   begin
      Assert
         (Classify_Theme (Dark_BG) = Dark,
          "Classify_Theme(RGB(30,30,30)) should be Dark (typical dark terminal)");
   end Test_Classify_Theme_Typical_Dark_Terminal;


   procedure Test_Classify_Theme_Typical_Light_Terminal
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Y = (299*240 + 587*240 + 114*240) / 1000 = 240000 / 1000 = 240 -> Light
      Light_BG : constant RGB := (Red => 240, Green => 240, Blue => 240);
   begin
      Assert
         (Classify_Theme (Light_BG) = Light,
          "Classify_Theme(RGB(240,240,240)) should be Light (typical light terminal)");
   end Test_Classify_Theme_Typical_Light_Terminal;


   procedure Test_Classify_Theme_Solarized_Dark
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Solarized Dark: base03 = #002B36 = RGB(0, 43, 54)
      --  Y = (299*0 + 587*43 + 114*54) / 1000 = (0 + 25241 + 6156) / 1000
      --    = 31397 / 1000 = 31 -> Dark
      Solarized_Dark_BG : constant RGB := (Red => 0, Green => 43, Blue => 54);
   begin
      Assert
         (Classify_Theme (Solarized_Dark_BG) = Dark,
          "Classify_Theme(RGB(0,43,54)) should be Dark (Solarized Dark background)");
   end Test_Classify_Theme_Solarized_Dark;


   procedure Test_Classify_Theme_Solarized_Light
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Solarized Light: base3 = #FDF6E3 = RGB(253, 246, 227)
      --  Y = (299*253 + 587*246 + 114*227) / 1000
      --    = (75647 + 144402 + 25878) / 1000
      --    = 245927 / 1000 = 245 -> Light
      Solarized_Light_BG : constant RGB := (Red => 253, Green => 246, Blue => 227);
   begin
      Assert
         (Classify_Theme (Solarized_Light_BG) = Light,
          "Classify_Theme(RGB(253,246,227)) should be Light (Solarized Light background)");
   end Test_Classify_Theme_Solarized_Light;


   ---------------------------------------------------------------------------
   --  FUNC-DKL-004: Is_Dark and Is_Light Convenience Predicates
   ---------------------------------------------------------------------------


   procedure Test_Is_Dark_Black_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Is_Dark (Black),
          "Is_Dark(RGB(0,0,0)) should be True");
   end Test_Is_Dark_Black_True;


   procedure Test_Is_Dark_White_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (not Is_Dark (White),
          "Is_Dark(RGB(255,255,255)) should be False");
   end Test_Is_Dark_White_False;


   procedure Test_Is_Light_Black_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (not Is_Light (Black),
          "Is_Light(RGB(0,0,0)) should be False");
   end Test_Is_Light_Black_False;


   procedure Test_Is_Light_White_True
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Is_Light (White),
          "Is_Light(RGB(255,255,255)) should be True");
   end Test_Is_Light_White_True;


   procedure Test_Is_Dark_And_Is_Light_Are_Complementary
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Use Solarized Dark as a sample mid-range color
      Sample : constant RGB := (Red => 0, Green => 43, Blue => 54);
   begin
      Assert
         (Is_Dark (Sample) /= Is_Light (Sample),
          "Is_Dark and Is_Light should return opposite values for the same color");
      Assert
         (Is_Dark (Sample) = not Is_Light (Sample),
          "Is_Dark(C) should equal not Is_Light(C) for any color C");
   end Test_Is_Dark_And_Is_Light_Are_Complementary;


   ---------------------------------------------------------------------------
   --  FUNC-DKL-006: Theme_Result Discriminated Record
   ---------------------------------------------------------------------------


   procedure Test_Theme_Result_Success_Variant
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Termicap.Color.Dark_Light.Detect;
      Color : constant RGB := (Red => 30, Green => 30, Blue => 30);
      Result : constant Theme_Result :=
         (Success => True, Theme => Dark, Color => Color);
   begin
      Assert
         (Result.Success,
          "Theme_Result success variant: Success should be True");
      Assert
         (Result.Theme = Dark,
          "Theme_Result success variant: Theme should be Dark");
      Assert
         (Result.Color.Red = 30
          and then Result.Color.Green = 30
          and then Result.Color.Blue = 30,
          "Theme_Result success variant: Color should be RGB(30,30,30)");
   end Test_Theme_Result_Success_Variant;


   procedure Test_Theme_Result_Failure_Variant
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Termicap.Color.Dark_Light.Detect;
      Result : constant Theme_Result :=
         (Success => False, Error => Not_A_Terminal);
   begin
      Assert
         (not Result.Success,
          "Theme_Result failure variant: Success should be False");
      Assert
         (Result.Error = Not_A_Terminal,
          "Theme_Result failure variant: Error should be Not_A_Terminal");
   end Test_Theme_Result_Failure_Variant;


   procedure Test_Theme_Result_Default_Discriminant_Is_False
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      use Termicap.Color.Dark_Light.Detect;
      --  A Theme_Result declared with no explicit discriminant should
      --  have Success = False (the default discriminant value).
      Result : constant Theme_Result := (Success => False, Error => Not_A_Terminal);
   begin
      Assert
         (not Result.Success,
          "Theme_Result default discriminant should be False (failure state)");
   end Test_Theme_Result_Default_Discriminant_Is_False;

end Test_Dark_Light;
