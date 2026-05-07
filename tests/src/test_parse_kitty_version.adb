-------------------------------------------------------------------------------
--  Test_Parse_Kitty_Version - Unit Tests for Termicap.Graphics.Parse_Kitty_Version
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Graphics; use Termicap.Graphics;

package body Test_Parse_Kitty_Version is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Graphics.Parse_Kitty_Version");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Valid inputs
      Register_Routine (T, Test_Parse_0_20_0'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(0.20.0) = 2000");
      Register_Routine (T, Test_Parse_0_19_0'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(0.19.0) = 1900");
      Register_Routine (T, Test_Parse_1_2_3'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(1.2.3) = 10203");
      Register_Routine (T, Test_Parse_0_0_0'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(0.0.0) = 0");
      Register_Routine (T, Test_Parse_0_35_2'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(0.35.2) = 3502");

      --  Invalid inputs -> 0
      Register_Routine (T, Test_Parse_Empty'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version("""") = 0");
      Register_Routine (T, Test_Parse_Leading_V'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(v0.20.0) = 0 (leading v)");
      Register_Routine (T, Test_Parse_Pre_Release_Suffix'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(0.20.0-rc1) = 0 (suffix)");
      Register_Routine (T, Test_Parse_Garbage'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(garbage) = 0");
      Register_Routine (T, Test_Parse_Double_Dot'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(1..2) = 0");

      --  Edge cases
      Register_Routine (T, Test_Parse_High_Major'Access,
                        "FUNC-HYP-022: Parse_Kitty_Version(2.0.0) = 20000");
      Register_Routine (T, Test_Zero_On_Failure_Regression'Access,
                        "FUNC-SXL-003: failure preserves zero (regression)");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Valid inputs
   ---------------------------------------------------------------------------

   procedure Test_Parse_0_20_0 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  0 * 10_000 + 20 * 100 + 0 = 2000
      Assert (Parse_Kitty_Version ("0.20.0") = 2000,
              "Parse_Kitty_Version(0.20.0) should return 2000");
   end Test_Parse_0_20_0;

   procedure Test_Parse_0_19_0 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  0 * 10_000 + 19 * 100 + 0 = 1900
      Assert (Parse_Kitty_Version ("0.19.0") = 1900,
              "Parse_Kitty_Version(0.19.0) should return 1900");
   end Test_Parse_0_19_0;

   procedure Test_Parse_1_2_3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  1 * 10_000 + 2 * 100 + 3 = 10203
      Assert (Parse_Kitty_Version ("1.2.3") = 10203,
              "Parse_Kitty_Version(1.2.3) should return 10203");
   end Test_Parse_1_2_3;

   procedure Test_Parse_0_0_0 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  0 * 10_000 + 0 * 100 + 0 = 0
      Assert (Parse_Kitty_Version ("0.0.0") = 0,
              "Parse_Kitty_Version(0.0.0) should return 0");
   end Test_Parse_0_0_0;

   procedure Test_Parse_0_35_2 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  0 * 10_000 + 35 * 100 + 2 = 3502
      Assert (Parse_Kitty_Version ("0.35.2") = 3502,
              "Parse_Kitty_Version(0.35.2) should return 3502");
   end Test_Parse_0_35_2;

   ---------------------------------------------------------------------------
   --  Invalid inputs — must return 0
   ---------------------------------------------------------------------------

   procedure Test_Parse_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Parse_Kitty_Version ("") = 0,
              "Parse_Kitty_Version("""") should return 0 (empty input)");
   end Test_Parse_Empty;

   procedure Test_Parse_Leading_V (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Parse_Kitty_Version ("v0.20.0") = 0,
              "Parse_Kitty_Version(v0.20.0) should return 0 (leading 'v' is invalid)");
   end Test_Parse_Leading_V;

   procedure Test_Parse_Pre_Release_Suffix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Parse_Kitty_Version ("0.20.0-rc1") = 0,
              "Parse_Kitty_Version(0.20.0-rc1) should return 0 (suffix is invalid)");
   end Test_Parse_Pre_Release_Suffix;

   procedure Test_Parse_Garbage (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Parse_Kitty_Version ("garbage") = 0,
              "Parse_Kitty_Version(garbage) should return 0");
   end Test_Parse_Garbage;

   procedure Test_Parse_Double_Dot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Parse_Kitty_Version ("1..2") = 0,
              "Parse_Kitty_Version(1..2) should return 0 (double dot)");
   end Test_Parse_Double_Dot;

   ---------------------------------------------------------------------------
   --  Edge cases
   ---------------------------------------------------------------------------

   procedure Test_Parse_High_Major (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  2 * 10_000 + 0 * 100 + 0 = 20000
      Assert (Parse_Kitty_Version ("2.0.0") = 20000,
              "Parse_Kitty_Version(2.0.0) should return 20000");
   end Test_Parse_High_Major;

   procedure Test_Zero_On_Failure_Regression (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Regression: before the Termicap.Version refactor, Parse_Kitty_Version
      --  always returned 0.  Any invalid input must still yield 0 so existing
      --  callers that compare against 0 ("version unknown") are unaffected.
   begin
      Assert (Parse_Kitty_Version ("") = 0,      "Empty string must still return 0 (regression)");
      Assert (Parse_Kitty_Version ("not-a-ver") = 0, "Malformed string must still return 0 (regression)");
      Assert (Parse_Kitty_Version ("1.") = 0,    "Trailing-dot string must still return 0 (regression)");
   end Test_Zero_On_Failure_Regression;

end Test_Parse_Kitty_Version;
