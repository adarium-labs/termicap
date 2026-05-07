-------------------------------------------------------------------------------
--  Test_Parse_Kitty_Version - Unit Tests for Termicap.Graphics.Parse_Kitty_Version
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Parse_Kitty_Version (FUNC-HYP-022, FUNC-SXL-003).
--  Verifies the MAJOR*10_000 + MINOR*100 + PATCH encoding, failure-to-zero
--  semantics, and edge cases for the Termicap.Version-backed implementation.
--
--  All tests are purely data-driven; no live terminal is required.
--
--  Requirements Coverage:
--    - @relation(FUNC-SXL-003): Kitty_Graphics_Version field encoding
--    - @relation(FUNC-HYP-022): Sixel refactor — Parse_Kitty_Version uses Termicap.Version

with AUnit.Test_Cases;

package Test_Parse_Kitty_Version is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Valid inputs — encoding correctness
   ---------------------------------------------------------------------------

   --  "0.20.0" -> 0*10_000 + 20*100 + 0 = 2000
   procedure Test_Parse_0_20_0 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "0.19.0" -> 0*10_000 + 19*100 + 0 = 1900
   procedure Test_Parse_0_19_0 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "1.2.3" -> 1*10_000 + 2*100 + 3 = 10203
   procedure Test_Parse_1_2_3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "0.0.0" -> 0
   procedure Test_Parse_0_0_0 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "0.35.2" -> 0*10_000 + 35*100 + 2 = 3502
   procedure Test_Parse_0_35_2 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Invalid inputs — must return 0
   ---------------------------------------------------------------------------

   --  Empty string -> 0
   procedure Test_Parse_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "v0.20.0" (leading "v") -> 0
   procedure Test_Parse_Leading_V (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "0.20.0-rc1" (pre-release suffix) -> 0
   procedure Test_Parse_Pre_Release_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "garbage" -> 0
   procedure Test_Parse_Garbage (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  "1..2" (double dot) -> 0
   procedure Test_Parse_Double_Dot (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Edge cases
   ---------------------------------------------------------------------------

   --  High version components that fit in Natural -> correct encoding
   procedure Test_Parse_High_Major (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Regression: existing "always zero" behaviour on failure is preserved
   procedure Test_Zero_On_Failure_Regression (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Parse_Kitty_Version;
