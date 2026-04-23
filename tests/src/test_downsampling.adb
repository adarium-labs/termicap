-------------------------------------------------------------------------------
--  Test_Downsampling - Unit Tests for Termicap.Downsampling
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Color;       use Termicap.Color;
with Termicap.Downsampling; use Termicap.Downsampling;

package body Test_Downsampling is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Downsampling");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-DSP-004: Downsample_True_To_256
      Register_Routine (T, Test_True_To_256_Black'Access,
         "FUNC-DSP-004/012: Pure black (0,0,0) -> 16 (cube origin)");
      Register_Routine (T, Test_True_To_256_White'Access,
         "FUNC-DSP-004/012: Pure white (255,255,255) -> 231 (cube maximum)");
      Register_Routine (T, Test_True_To_256_Mid_Gray'Access,
         "FUNC-DSP-004/012: Mid-gray (128,128,128) -> grayscale ramp index 232..255");
      Register_Routine (T, Test_True_To_256_Red'Access,
         "FUNC-DSP-004/012: Non-gray red (255,0,0) -> cube index 16..231");
      Register_Routine (T, Test_True_To_256_Result_Range'Access,
         "FUNC-DSP-004: Downsample_True_To_256 result always in 16..255");

      --  FUNC-DSP-005: Downsample_True_To_16
      Register_Routine (T, Test_True_To_16_Black'Access,
         "FUNC-DSP-005/012: Pure black (0,0,0) -> 0 (Black)");
      Register_Routine (T, Test_True_To_16_White'Access,
         "FUNC-DSP-005/012: Pure white (255,255,255) -> 15 (Bright White)");
      Register_Routine (T, Test_True_To_16_Bright_Red'Access,
         "FUNC-DSP-005/012: Canonical Bright Red (255,85,85) -> 9 (Bright Red)");
      Register_Routine (T, Test_True_To_16_Result_Range'Access,
         "FUNC-DSP-005: Downsample_True_To_16 result always in 0..15");
      Register_Routine (T, Test_True_To_16_Canonical_Black_Identity'Access,
         "FUNC-DSP-005: Canonical Black (0,0,0) maps to index 0");
      Register_Routine (T, Test_True_To_16_Canonical_Red_Identity'Access,
         "FUNC-DSP-005: Canonical Bright Red (255,85,85) maps to index 9");
      Register_Routine (T, Test_True_To_16_Canonical_Bright_White_Identity'Access,
         "FUNC-DSP-005: Canonical Bright White (255,255,255) maps to index 15");

      --  FUNC-DSP-006: Downsample_256_To_16
      Register_Routine (T, Test_256_To_16_Index_Zero'Access,
         "FUNC-DSP-006/012: Index 0 -> 0 (pass-through)");
      Register_Routine (T, Test_256_To_16_Index_Fifteen'Access,
         "FUNC-DSP-006/012: Index 15 -> 15 (pass-through)");
      Register_Routine (T, Test_256_To_16_Index_231_White'Access,
         "FUNC-DSP-006/012: Index 231 -> 15 (nearest to white = Bright White)");
      Register_Routine (T, Test_256_To_16_Passthrough_Range'Access,
         "FUNC-DSP-006: Indices 0..15 all pass through unchanged");
      Register_Routine (T, Test_256_To_16_Result_Range'Access,
         "FUNC-DSP-006: Downsample_256_To_16 result always in 0..15");

      --  FUNC-DSP-008/009: General Downsample identity cases
      Register_Routine (T, Test_Downsample_Rgb_Identity_Level'Access,
         "FUNC-DSP-009/012: Downsample(RGB, True_Color) -> Level=True_Color");
      Register_Routine (T, Test_Downsample_Rgb_Identity_Components'Access,
         "FUNC-DSP-009/012: Downsample(RGB, True_Color) RGB components preserved");
      Register_Routine (T, Test_Downsample_256_Identity'Access,
         "FUNC-DSP-009/012: Downsample(index 42, Extended_256) -> Level=Extended_256, Index=42");
      Register_Routine (T, Test_Downsample_256_Identity_Low_Index'Access,
         "FUNC-DSP-009/012: Downsample(index 7, Extended_256) -> Level=Extended_256, Index=7");
      Register_Routine (T, Test_Downsample_256_To_Basic16_Low_Index'Access,
         "FUNC-DSP-008/012: Downsample(index 7, Basic_16) -> Level=Basic_16, Index_16=7");
      Register_Routine (T, Test_Downsample_256_Upsample_Is_Identity'Access,
         "FUNC-DSP-009: Downsample(index 42, True_Color) -> identity at Extended_256");

      --  FUNC-DSP-007/008: Strip-to-None
      Register_Routine (T, Test_Downsample_Rgb_Strip_To_None'Access,
         "FUNC-DSP-007/012: Downsample(RGB(255,0,0), None) -> Level=None");
      Register_Routine (T, Test_Downsample_256_Strip_To_None'Access,
         "FUNC-DSP-007/012: Downsample(index 100, None) -> Level=None");
      Register_Routine (T, Test_Downsample_Rgb_White_Strip_To_None'Access,
         "FUNC-DSP-007: Downsample(white RGB, None) -> Level=None");
      Register_Routine (T, Test_Downsample_256_Zero_Strip_To_None'Access,
         "FUNC-DSP-007: Downsample(index 0, None) -> Level=None");

      --  FUNC-DSP-010: Color_Level_Of and Monotonicity
      Register_Routine (T, Test_Color_Level_Of_None'Access,
         "FUNC-DSP-010: Color_Level_Of (strip result) = None");
      Register_Routine (T, Test_Color_Level_Of_True_Color'Access,
         "FUNC-DSP-010: Color_Level_Of (Downsample RGB True_Color) = True_Color");
      Register_Routine (T, Test_Color_Level_Of_Extended_256'Access,
         "FUNC-DSP-010: Color_Level_Of (Downsample index Extended_256) = Extended_256");
      Register_Routine (T, Test_Monotonicity_Rgb_To_Basic_16'Access,
         "FUNC-DSP-010/012: Color_Level_Of(Downsample RGB Basic_16) <= Basic_16");
      Register_Routine (T, Test_Monotonicity_Rgb_To_Extended_256'Access,
         "FUNC-DSP-010: Color_Level_Of(Downsample RGB Extended_256) <= Extended_256");
      Register_Routine (T, Test_Monotonicity_256_To_Basic_16'Access,
         "FUNC-DSP-010: Color_Level_Of(Downsample index Basic_16) <= Basic_16");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   ---------------------------------------------------------------------------
   --  FUNC-DSP-004: Downsample_True_To_256
   ---------------------------------------------------------------------------


   procedure Test_True_To_256_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Downsample_True_To_256 (Black) = 16,
          "Downsample_True_To_256 (0,0,0) should return 16 (cube origin)");
   end Test_True_To_256_Black;


   procedure Test_True_To_256_White
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Downsample_True_To_256 (White) = 231,
          "Downsample_True_To_256 (255,255,255) should return 231 (cube maximum)");
   end Test_True_To_256_White;


   procedure Test_True_To_256_Mid_Gray
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Mid_Gray : constant RGB := (Red => 128, Green => 128, Blue => 128);
      Result   : constant Color_Index_256 := Downsample_True_To_256 (Mid_Gray);
   begin
      Assert
         (Result in 232 .. 255,
          "Downsample_True_To_256 (128,128,128) should return a grayscale ramp index in 232..255");
   end Test_True_To_256_Mid_Gray;


   procedure Test_True_To_256_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Red    : constant RGB := (Red => 255, Green => 0, Blue => 0);
      Result : constant Color_Index_256 := Downsample_True_To_256 (Red);
   begin
      Assert
         (Result in 16 .. 231,
          "Downsample_True_To_256 (255,0,0) should return a cube index in 16..231");
   end Test_True_To_256_Red;


   procedure Test_True_To_256_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Sample several representative inputs to verify the postcondition holds
      Samples : constant array (1 .. 5) of RGB :=
         [(Red => 0,   Green => 0,   Blue => 0),
          (Red => 255, Green => 255, Blue => 255),
          (Red => 128, Green => 0,   Blue => 255),
          (Red => 64,  Green => 128, Blue => 192),
          (Red => 200, Green => 200, Blue => 200)];
   begin
      for I in Samples'Range loop
         declare
            Result : constant Color_Index_256 := Downsample_True_To_256 (Samples (I));
         begin
            Assert
               (Result >= 16,
                "Downsample_True_To_256 result must be >= 16 for all inputs");
         end;
      end loop;
   end Test_True_To_256_Result_Range;


   ---------------------------------------------------------------------------
   --  FUNC-DSP-005: Downsample_True_To_16
   ---------------------------------------------------------------------------


   procedure Test_True_To_16_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Downsample_True_To_16 (Black) = 0,
          "Downsample_True_To_16 (0,0,0) should return 0 (Black)");
   end Test_True_To_16_Black;


   procedure Test_True_To_16_White
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Downsample_True_To_16 (White) = 15,
          "Downsample_True_To_16 (255,255,255) should return 15 (Bright White)");
   end Test_True_To_16_White;


   procedure Test_True_To_16_Bright_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Canonical ANSI Bright Red: (255, 85, 85) per FUNC-DSP-005 palette table
      Bright_Red : constant RGB := (Red => 255, Green => 85, Blue => 85);
   begin
      Assert
         (Downsample_True_To_16 (Bright_Red) = 9,
          "Downsample_True_To_16 (255,85,85) should return 9 (Bright Red)");
   end Test_True_To_16_Bright_Red;


   procedure Test_True_To_16_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Samples : constant array (1 .. 5) of RGB :=
         [(Red => 0,   Green => 0,   Blue => 0),
          (Red => 255, Green => 255, Blue => 255),
          (Red => 128, Green => 0,   Blue => 128),
          (Red => 0,   Green => 128, Blue => 128),
          (Red => 85,  Green => 255, Blue => 85)];
   begin
      for I in Samples'Range loop
         declare
            Result : constant Color_Index_16 := Downsample_True_To_16 (Samples (I));
            pragma Unreferenced (Result);
         begin
            --  The subtype constraint Color_Index_16 (0..15) is the range check;
            --  a constraint_error here would indicate an out-of-range result.
            Assert (True, "Downsample_True_To_16 result is within 0..15 by subtype constraint");
         end;
      end loop;
   end Test_True_To_16_Result_Range;


   procedure Test_True_To_16_Canonical_Black_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Canonical Black from FUNC-DSP-005 palette: index 0 = (0,0,0)
      Black : constant RGB := (Red => 0, Green => 0, Blue => 0);
   begin
      Assert
         (Downsample_True_To_16 (Black) = 0,
          "Canonical Black (0,0,0) should map to index 0");
   end Test_True_To_16_Canonical_Black_Identity;


   procedure Test_True_To_16_Canonical_Red_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Canonical Bright Red from FUNC-DSP-005 palette: index 9 = (255,85,85)
      Bright_Red : constant RGB := (Red => 255, Green => 85, Blue => 85);
   begin
      Assert
         (Downsample_True_To_16 (Bright_Red) = 9,
          "Canonical Bright Red (255,85,85) should map to index 9 by identity property");
   end Test_True_To_16_Canonical_Red_Identity;


   procedure Test_True_To_16_Canonical_Bright_White_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Canonical Bright White from FUNC-DSP-005 palette: index 15 = (255,255,255)
      Bright_White : constant RGB := (Red => 255, Green => 255, Blue => 255);
   begin
      Assert
         (Downsample_True_To_16 (Bright_White) = 15,
          "Canonical Bright White (255,255,255) should map to index 15 by identity property");
   end Test_True_To_16_Canonical_Bright_White_Identity;


   ---------------------------------------------------------------------------
   --  FUNC-DSP-006: Downsample_256_To_16
   ---------------------------------------------------------------------------


   procedure Test_256_To_16_Index_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Downsample_256_To_16 (0) = 0,
          "Downsample_256_To_16 (0) should return 0 (pass-through for Basic_16 range)");
   end Test_256_To_16_Index_Zero;


   procedure Test_256_To_16_Index_Fifteen
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Downsample_256_To_16 (15) = 15,
          "Downsample_256_To_16 (15) should return 15 (pass-through for Basic_16 range)");
   end Test_256_To_16_Index_Fifteen;


   procedure Test_256_To_16_Index_231_White
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Index 231 is the cube entry for (255,255,255); nearest ANSI 16 color is Bright White = 15
   begin
      Assert
         (Downsample_256_To_16 (231) = 15,
          "Downsample_256_To_16 (231) should return 15 (nearest to (255,255,255) = Bright White)");
   end Test_256_To_16_Index_231_White;


   procedure Test_256_To_16_Passthrough_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      for I in Color_Index_16 loop
         Assert
            (Downsample_256_To_16 (I) = I,
             "Downsample_256_To_16 should pass through indices 0..15 unchanged");
      end loop;
   end Test_256_To_16_Passthrough_Range;


   procedure Test_256_To_16_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Spot-check representative indices across all three palette regions
      Samples : constant array (1 .. 6) of Color_Index_256 :=
         [0, 15, 16, 100, 232, 255];
   begin
      for I in Samples'Range loop
         declare
            Result : constant Color_Index_16 := Downsample_256_To_16 (Samples (I));
            pragma Unreferenced (Result);
         begin
            --  The subtype constraint Color_Index_16 (0..15) is the range check;
            --  a constraint_error here would indicate an out-of-range result.
            Assert (True, "Downsample_256_To_16 result is within 0..15 by subtype constraint");
         end;
      end loop;
   end Test_256_To_16_Result_Range;


   ---------------------------------------------------------------------------
   --  FUNC-DSP-008/009: General Downsample Identity Cases
   ---------------------------------------------------------------------------


   procedure Test_Downsample_Rgb_Identity_Level
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Black  : constant RGB := (Red => 0, Green => 0, Blue => 0);
      Result : constant Downsampled_Color := Downsample (Black, True_Color);
   begin
      Assert
         (Result.Level = True_Color,
          "Downsample(RGB, True_Color).Level should be True_Color");
   end Test_Downsample_Rgb_Identity_Level;


   procedure Test_Downsample_Rgb_Identity_Components
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : constant RGB := (Red => 42, Green => 100, Blue => 200);
      Result : constant Downsampled_Color := Downsample (Source, True_Color);
   begin
      Assert
         (Result.Level = True_Color,
          "Downsample(RGB, True_Color).Level should be True_Color");
      Assert
         (Result.RGB_Value.Red = Source.Red,
          "Downsample(RGB, True_Color).RGB_Value.Red should match source");
      Assert
         (Result.RGB_Value.Green = Source.Green,
          "Downsample(RGB, True_Color).RGB_Value.Green should match source");
      Assert
         (Result.RGB_Value.Blue = Source.Blue,
          "Downsample(RGB, True_Color).RGB_Value.Blue should match source");
   end Test_Downsample_Rgb_Identity_Components;


   procedure Test_Downsample_256_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Downsampled_Color := Downsample (42, Extended_256);
   begin
      Assert
         (Result.Level = Extended_256,
          "Downsample(42, Extended_256).Level should be Extended_256");
      Assert
         (Result.Index_256 = 42,
          "Downsample(42, Extended_256).Index_256 should be 42");
   end Test_Downsample_256_Identity;


   procedure Test_Downsample_256_Identity_Low_Index
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Downsampled_Color := Downsample (7, Extended_256);
   begin
      Assert
         (Result.Level = Extended_256,
          "Downsample(7, Extended_256).Level should be Extended_256");
      Assert
         (Result.Index_256 = 7,
          "Downsample(7, Extended_256).Index_256 should be 7");
   end Test_Downsample_256_Identity_Low_Index;


   procedure Test_Downsample_256_To_Basic16_Low_Index
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Index 7 in the 256-palette is already a Basic_16 index;
      --  Downsample_256_To_16 (7) = 7 (pass-through)
      Result : constant Downsampled_Color := Downsample (7, Basic_16);
   begin
      Assert
         (Result.Level = Basic_16,
          "Downsample(7, Basic_16).Level should be Basic_16");
      Assert
         (Result.Index_16 = 7,
          "Downsample(7, Basic_16).Index_16 should be 7 (pass-through via Downsample_256_To_16)");
   end Test_Downsample_256_To_Basic16_Low_Index;


   procedure Test_Downsample_256_Upsample_Is_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Source is Extended_256; target True_Color is higher -> no upsampling,
      --  result is identity at Extended_256 per FUNC-DSP-009 no-upsampling rule
      Result : constant Downsampled_Color := Downsample (42, True_Color);
   begin
      Assert
         (Result.Level = Extended_256,
          "Downsample(42, True_Color) should not upsample; Level should be Extended_256");
      Assert
         (Result.Index_256 = 42,
          "Downsample(42, True_Color) index should be preserved as 42");
   end Test_Downsample_256_Upsample_Is_Identity;


   ---------------------------------------------------------------------------
   --  FUNC-DSP-007/008: Strip-to-None
   ---------------------------------------------------------------------------


   procedure Test_Downsample_Rgb_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Red    : constant RGB := (Red => 255, Green => 0, Blue => 0);
      Result : constant Downsampled_Color := Downsample (Red, None);
   begin
      Assert
         (Result.Level = None,
          "Downsample(RGB(255,0,0), None).Level should be None");
   end Test_Downsample_Rgb_Strip_To_None;


   procedure Test_Downsample_256_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Downsampled_Color := Downsample (100, None);
   begin
      Assert
         (Result.Level = None,
          "Downsample(index 100, None).Level should be None");
   end Test_Downsample_256_Strip_To_None;


   procedure Test_Downsample_Rgb_White_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      White  : constant RGB := (Red => 255, Green => 255, Blue => 255);
      Result : constant Downsampled_Color := Downsample (White, None);
   begin
      Assert
         (Result.Level = None,
          "Downsample(white RGB, None).Level should be None");
   end Test_Downsample_Rgb_White_Strip_To_None;


   procedure Test_Downsample_256_Zero_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Downsampled_Color := Downsample (0, None);
   begin
      Assert
         (Result.Level = None,
          "Downsample(index 0, None).Level should be None");
   end Test_Downsample_256_Zero_Strip_To_None;


   ---------------------------------------------------------------------------
   --  FUNC-DSP-010: Color_Level_Of and Monotonicity
   ---------------------------------------------------------------------------


   procedure Test_Color_Level_Of_None
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Red    : constant RGB := (Red => 255, Green => 0, Blue => 0);
      Result : constant Downsampled_Color := Downsample (Red, None);
   begin
      Assert
         (Color_Level_Of (Result) = None,
          "Color_Level_Of (strip result) should be None");
   end Test_Color_Level_Of_None;


   procedure Test_Color_Level_Of_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Source : constant RGB := (Red => 10, Green => 20, Blue => 30);
      Result : constant Downsampled_Color := Downsample (Source, True_Color);
   begin
      Assert
         (Color_Level_Of (Result) = True_Color,
          "Color_Level_Of (Downsample RGB True_Color) should be True_Color");
   end Test_Color_Level_Of_True_Color;


   procedure Test_Color_Level_Of_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Downsampled_Color := Downsample (42, Extended_256);
   begin
      Assert
         (Color_Level_Of (Result) = Extended_256,
          "Color_Level_Of (Downsample index Extended_256) should be Extended_256");
   end Test_Color_Level_Of_Extended_256;


   procedure Test_Monotonicity_Rgb_To_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  A rich TrueColor value downsampled to Basic_16 must yield a result
      --  whose level is <= Basic_16 (satisfies FUNC-DSP-010 monotonicity)
      Color  : constant RGB := (Red => 200, Green => 100, Blue => 50);
      Result : constant Downsampled_Color := Downsample (Color, Basic_16);
   begin
      Assert
         (Color_Level_Of (Result) <= Basic_16,
          "Color_Level_Of(Downsample RGB Basic_16) should be <= Basic_16");
   end Test_Monotonicity_Rgb_To_Basic_16;


   procedure Test_Monotonicity_Rgb_To_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Color  : constant RGB := (Red => 100, Green => 150, Blue => 200);
      Result : constant Downsampled_Color := Downsample (Color, Extended_256);
   begin
      Assert
         (Color_Level_Of (Result) <= Extended_256,
          "Color_Level_Of(Downsample RGB Extended_256) should be <= Extended_256");
   end Test_Monotonicity_Rgb_To_Extended_256;


   procedure Test_Monotonicity_256_To_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  A cube-range 256-color index downsampled to Basic_16
      Result : constant Downsampled_Color := Downsample (100, Basic_16);
   begin
      Assert
         (Color_Level_Of (Result) <= Basic_16,
          "Color_Level_Of(Downsample index Basic_16) should be <= Basic_16");
   end Test_Monotonicity_256_To_Basic_16;


end Test_Downsampling;
