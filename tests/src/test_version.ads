-------------------------------------------------------------------------------
--  Test_Version - Unit Tests for Termicap.Version
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Termicap.Version: Parse, Compare, Make, and the
--  ZERO_VERSION / MAX_VERSION_COMPONENTS constants.  All tests are purely
--  data-driven (no live terminal required).
--
--  Requirements Coverage:
--    - @relation(FUNC-HYP-013): Version type, Parse, Compare, Make, Version_Ordering

with AUnit.Test_Cases;

package Test_Version is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Parse — valid inputs (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  Parse "0" -> Success, Count=1, Parts(1)=0
   procedure Test_Parse_Single_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "0.0" -> Success, Count=2
   procedure Test_Parse_Zero_Dot_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "0.50" -> Success, Count=2, Parts(2)=50
   procedure Test_Parse_Zero_Dot_50 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "0.50.0" -> Success, Count=3
   procedure Test_Parse_Zero_Dot_50_Dot_0 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "3.1.0" -> Success, Count=3
   procedure Test_Parse_Three_One_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "357" -> Success, Count=1, Parts(1)=357
   procedure Test_Parse_Single_Integer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1.2.3.4" -> Success, Count=4
   procedure Test_Parse_Four_Components (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse 8-component string -> Success (boundary at MAX_VERSION_COMPONENTS)
   procedure Test_Parse_Eight_Components (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Parse — invalid inputs (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  Parse "" -> Failure (empty string)
   procedure Test_Parse_Empty_String (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1." -> Failure (trailing dot)
   procedure Test_Parse_Trailing_Dot (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse ".1" -> Failure (leading dot)
   procedure Test_Parse_Leading_Dot (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1..2" -> Failure (consecutive dots)
   procedure Test_Parse_Double_Dot (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1.a" -> Failure (non-digit character)
   procedure Test_Parse_Alpha_Component (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "abc" -> Failure (all-alpha string)
   procedure Test_Parse_All_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1.2.3.4.5.6.7.8.9" -> Failure (9 components > MAX)
   procedure Test_Parse_Nine_Components (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1 2" -> Failure (space separator)
   procedure Test_Parse_Space_Separator (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse " 1.2" -> Failure (leading space)
   procedure Test_Parse_Leading_Space (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "1.2 " -> Failure (trailing space)
   procedure Test_Parse_Trailing_Space (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "-1" -> Failure (negative number)
   procedure Test_Parse_Negative (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Parse "+1" -> Failure (explicit positive sign)
   procedure Test_Parse_Explicit_Positive (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Parse — overflow protection (FUNC-HYP-013, R5 in tech-spec §12)
   ---------------------------------------------------------------------------

   --  Parse a component whose decimal value exceeds Natural'Last -> Failure
   procedure Test_Parse_Overflow_Component (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Parse — SPARK postcondition coverage (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  On success: Result.Count >= 1 and Result.Count <= MAX_VERSION_COMPONENTS
   procedure Test_Parse_Success_Count_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  On failure: Result.Count = 0 (equals ZERO_VERSION)
   procedure Test_Parse_Failure_Yields_Zero_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Compare (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  Compare (3.1.0, 3.1.0) = Equal
   procedure Test_Compare_Equal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Compare (357, 357) = Equal (single-component)
   procedure Test_Compare_Equal_Single (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Compare (3.0.0, 3.1.0) = Less_Than
   procedure Test_Compare_Less (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Compare (3.1.0, 3.0.0) = Greater_Than (symmetry)
   procedure Test_Compare_Greater (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Prefix rule: Compare (0.50, 0.50.0) = Less_Than
   procedure Test_Compare_Prefix_Rule_Less (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Prefix rule: Compare (0.50.0, 0.50) = Greater_Than
   procedure Test_Compare_Prefix_Rule_Greater (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Single-integer: Compare ("357", "380") = Less_Than
   procedure Test_Compare_Single_Integer_Less (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  ZERO_VERSION vs non-zero: Compare (ZERO_VERSION, any) = Less_Than
   procedure Test_Compare_Zero_Version_Less (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  ZERO_VERSION vs ZERO_VERSION = Equal
   procedure Test_Compare_Zero_Version_Equal (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Mixed lengths with differing leading component: (1.0, 0.50) = Greater_Than
   procedure Test_Compare_Mixed_Length_Leading_Differs (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Antisymmetry: if Compare (A, B) = Less_Than then Compare (B, A) = Greater_Than
   procedure Test_Compare_Antisymmetry (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Make (FUNC-HYP-013)
   ---------------------------------------------------------------------------

   --  Make (3) -> Count=1, Parts(1)=3
   procedure Test_Make_One_Component (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Make (0, 50) -> Count=2, Parts(2)=50
   procedure Test_Make_Two_Components (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Make (3, 1, 0) -> Count=3, Parts correct
   procedure Test_Make_Three_Components (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Make with Has_Patch = False -> Count=2
   procedure Test_Make_No_Patch (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Make with Has_Minor = False -> Count=1
   procedure Test_Make_No_Minor (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Version;
