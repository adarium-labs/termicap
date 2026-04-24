-------------------------------------------------------------------------------
--  Test_Dark_Light - Unit Tests for Termicap.Color.Dark_Light
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the SPARK Gold-provable functions in
--  Termicap.Color.Dark_Light: Theme_Kind enumeration properties,
--  the Luminance BT.601 integer computation, the Classify_Theme
--  threshold function, the Is_Dark and Is_Light Boolean convenience
--  predicates, and the Theme_Result discriminated record declared in
--  Termicap.Color.Dark_Light.Detect.
--
--  Requirements Coverage:
--    - @relation(FUNC-DKL-001): Theme_Kind enumeration
--    - @relation(FUNC-DKL-002): Luminance computation function
--    - @relation(FUNC-DKL-003): Classify_Theme function
--    - @relation(FUNC-DKL-004): Is_Dark and Is_Light convenience predicates
--    - @relation(FUNC-DKL-006): Theme_Result discriminated record

with AUnit.Test_Cases;

package Test_Dark_Light is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-DKL-001: Theme_Kind Enumeration Properties
   ---------------------------------------------------------------------------

   --  FUNC-DKL-001: Theme_Kind'First = Dark
   procedure Test_Theme_Kind_First_Is_Dark (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-001: Theme_Kind'Last = Light
   procedure Test_Theme_Kind_Last_Is_Light (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DKL-002: Luminance Computation
   ---------------------------------------------------------------------------

   --  FUNC-DKL-002: RGB(0, 0, 0) -> Luminance = 0
   procedure Test_Luminance_Black (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(255, 255, 255) -> Luminance = 255
   procedure Test_Luminance_White (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(255, 0, 0) -> Luminance = 76 (pure red)
   procedure Test_Luminance_Pure_Red (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(0, 255, 0) -> Luminance = 149 (pure green)
   procedure Test_Luminance_Pure_Green (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(0, 0, 255) -> Luminance = 29 (pure blue)
   procedure Test_Luminance_Pure_Blue (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(128, 128, 128) -> Luminance = 128 (mid grey)
   procedure Test_Luminance_Mid_Grey (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-002: RGB(127, 127, 127) -> Luminance = 127 (near-threshold)
   procedure Test_Luminance_Near_Threshold (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DKL-003: Classify_Theme Function
   ---------------------------------------------------------------------------

   --  FUNC-DKL-003: RGB(0, 0, 0) -> Dark
   procedure Test_Classify_Theme_Black_Is_Dark (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(255, 255, 255) -> Light
   procedure Test_Classify_Theme_White_Is_Light (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(128, 128, 128) -> Light (boundary: luminance = 128 >= threshold)
   procedure Test_Classify_Theme_Mid_Grey_Is_Light (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(127, 127, 127) -> Dark (just below threshold: luminance = 127)
   procedure Test_Classify_Theme_Near_Threshold_Is_Dark (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(30, 30, 30) -> Dark (typical dark terminal)
   procedure Test_Classify_Theme_Typical_Dark_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(240, 240, 240) -> Light (typical light terminal)
   procedure Test_Classify_Theme_Typical_Light_Terminal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(0, 43, 54) -> Dark (Solarized Dark background)
   procedure Test_Classify_Theme_Solarized_Dark (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-003: RGB(253, 246, 227) -> Light (Solarized Light background)
   procedure Test_Classify_Theme_Solarized_Light (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DKL-004: Is_Dark and Is_Light Convenience Predicates
   ---------------------------------------------------------------------------

   --  FUNC-DKL-004: Is_Dark(RGB(0, 0, 0)) = True
   procedure Test_Is_Dark_Black_True (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-004: Is_Dark(RGB(255, 255, 255)) = False
   procedure Test_Is_Dark_White_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-004: Is_Light(RGB(0, 0, 0)) = False
   procedure Test_Is_Light_Black_False (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-004: Is_Light(RGB(255, 255, 255)) = True
   procedure Test_Is_Light_White_True (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-004: Is_Dark and Is_Light are complementary for a sample color
   procedure Test_Is_Dark_And_Is_Light_Are_Complementary (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DKL-006: Theme_Result Discriminated Record
   ---------------------------------------------------------------------------

   --  FUNC-DKL-006: Success variant can hold Theme + Color
   procedure Test_Theme_Result_Success_Variant (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-006: Failure variant can hold Error
   procedure Test_Theme_Result_Failure_Variant (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DKL-006: Default discriminant is False (failure state)
   procedure Test_Theme_Result_Default_Discriminant_Is_False (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Dark_Light;
