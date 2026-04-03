-------------------------------------------------------------------------------
--  Test_Downsampling - Unit Tests for Termicap.Downsampling
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering all color downsampling conversion functions and the
--  general Downsample dispatch with identity, strip-to-none, and monotonicity
--  properties.
--
--  Requirements Coverage:
--    - @relation(FUNC-DSP-001): Color_Component subtype and RGB record
--    - @relation(FUNC-DSP-002): Color_Index_256 subtype
--    - @relation(FUNC-DSP-003): Color_Index_16 subtype
--    - @relation(FUNC-DSP-004): Downsample_True_To_256 function
--    - @relation(FUNC-DSP-005): Downsample_True_To_16 function
--    - @relation(FUNC-DSP-006): Downsample_256_To_16 function
--    - @relation(FUNC-DSP-007): Strip-to-None sentinel
--    - @relation(FUNC-DSP-008): General Downsample dispatch functions
--    - @relation(FUNC-DSP-009): Idempotency: downsampling to same level is identity
--    - @relation(FUNC-DSP-010): Monotonicity: Color_Level_Of and level bounds
--    - @relation(FUNC-DSP-012): Unit testability of each conversion path

with AUnit.Test_Cases;

package Test_Downsampling is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-004: Downsample_True_To_256
   ---------------------------------------------------------------------------

   --  FUNC-DSP-004/DSP-012: Pure black (0,0,0) -> 16 (cube origin)
   procedure Test_True_To_256_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-004/DSP-012: Pure white (255,255,255) -> 231 (cube maximum)
   procedure Test_True_To_256_White
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-004/DSP-012: Mid-gray (128,128,128) -> grayscale ramp 232..255
   procedure Test_True_To_256_Mid_Gray
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-004/DSP-012: Non-gray red (255,0,0) -> cube index 16..231
   procedure Test_True_To_256_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-004: Result always in 16..255 (postcondition check)
   procedure Test_True_To_256_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-005: Downsample_True_To_16
   ---------------------------------------------------------------------------

   --  FUNC-DSP-005/DSP-012: Pure black (0,0,0) -> 0 (Black)
   procedure Test_True_To_16_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-005/DSP-012: Pure white (255,255,255) -> 15 (Bright White)
   procedure Test_True_To_16_White
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-005/DSP-012: Canonical Bright Red (255,85,85) -> 9 (Bright Red)
   procedure Test_True_To_16_Bright_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-005: Result always in 0..15
   procedure Test_True_To_16_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-005: Each canonical ANSI color maps to itself (identity)
   procedure Test_True_To_16_Canonical_Black_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_True_To_16_Canonical_Red_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   procedure Test_True_To_16_Canonical_Bright_White_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-006: Downsample_256_To_16
   ---------------------------------------------------------------------------

   --  FUNC-DSP-006/DSP-012: Index 0 -> 0 (pass-through, already Basic_16)
   procedure Test_256_To_16_Index_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-006/DSP-012: Index 15 -> 15 (pass-through, already Basic_16)
   procedure Test_256_To_16_Index_Fifteen
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-006/DSP-012: Index 231 -> 15 (nearest to (255,255,255) = Bright White)
   procedure Test_256_To_16_Index_231_White
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-006: All 16-color pass-through indices preserve values
   procedure Test_256_To_16_Passthrough_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-006: Result always in 0..15
   procedure Test_256_To_16_Result_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-008 / FUNC-DSP-009: General Downsample Identity Cases
   ---------------------------------------------------------------------------

   --  FUNC-DSP-009/DSP-012: Downsample(RGB, True_Color) -> Level=True_Color, RGB preserved
   procedure Test_Downsample_Rgb_Identity_Level
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-009/DSP-012: Downsample(RGB, True_Color) RGB components match source
   procedure Test_Downsample_Rgb_Identity_Components
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-009/DSP-012: Downsample(index 42, Extended_256) -> Level=Extended_256, Index=42
   procedure Test_Downsample_256_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-009/DSP-012: Downsample(index 7, Extended_256) -> Level=Extended_256, Index=7
   procedure Test_Downsample_256_Identity_Low_Index
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-008/DSP-012: Downsample(index 7, Basic_16) -> Level=Basic_16, via 256_To_16
   procedure Test_Downsample_256_To_Basic16_Low_Index
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-009: Upsample request (Extended_256 source, True_Color target)
   --  -> identity at Extended_256 per no-upsampling rule
   procedure Test_Downsample_256_Upsample_Is_Identity
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-007 / FUNC-DSP-008: Strip-to-None
   ---------------------------------------------------------------------------

   --  FUNC-DSP-007/DSP-012: Downsample(RGB, None) -> Level=None
   procedure Test_Downsample_Rgb_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-007/DSP-012: Downsample(index 100, None) -> Level=None
   procedure Test_Downsample_256_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-007: Downsample(white RGB, None) -> Level=None
   procedure Test_Downsample_Rgb_White_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-007: Downsample(index 0, None) -> Level=None
   procedure Test_Downsample_256_Zero_Strip_To_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DSP-010: Color_Level_Of and Monotonicity
   ---------------------------------------------------------------------------

   --  FUNC-DSP-010: Color_Level_Of on a None result returns None
   procedure Test_Color_Level_Of_None
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-010: Color_Level_Of on a True_Color identity result returns True_Color
   procedure Test_Color_Level_Of_True_Color
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-010: Color_Level_Of on Extended_256 result returns Extended_256
   procedure Test_Color_Level_Of_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-010/DSP-012: Monotonicity: Downsample(RGB, Basic_16) level <= Basic_16
   procedure Test_Monotonicity_Rgb_To_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-010: Monotonicity: Downsample(RGB, Extended_256) level <= Extended_256
   procedure Test_Monotonicity_Rgb_To_Extended_256
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DSP-010: Monotonicity: Downsample(index, Basic_16) level <= Basic_16
   procedure Test_Monotonicity_256_To_Basic_16
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Downsampling;
