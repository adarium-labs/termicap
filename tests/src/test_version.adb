-------------------------------------------------------------------------------
--  Test_Version - Unit Tests for Termicap.Version
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Version; use Termicap.Version;

package body Test_Version is

   ---------------------------------------------------------------------------
   --  Helper: parse a string and assert success; return the Version
   ---------------------------------------------------------------------------

   function Parse_OK (S : String) return Version is
      V    : Version;
      Succ : Boolean;
   begin
      Parse (S, V, Succ);
      Assert (Succ, "Parse (""" & S & """) expected success but returned False");
      return V;
   end Parse_OK;

   ---------------------------------------------------------------------------
   --  Helper: parse a string and assert failure
   ---------------------------------------------------------------------------

   procedure Parse_Fail (S : String) is
      V    : Version;
      Succ : Boolean;
   begin
      Parse (S, V, Succ);
      Assert (not Succ, "Parse (""" & S & """) expected failure but returned True");
   end Parse_Fail;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Version");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  Parse — valid
      Register_Routine (T, Test_Parse_Single_Zero'Access,    "FUNC-HYP-013: Parse(0) -> Count=1, Parts(1)=0");
      Register_Routine (T, Test_Parse_Zero_Dot_Zero'Access,  "FUNC-HYP-013: Parse(0.0) -> Count=2");
      Register_Routine (T, Test_Parse_Zero_Dot_50'Access,    "FUNC-HYP-013: Parse(0.50) -> Count=2, Parts(2)=50");
      Register_Routine (T, Test_Parse_Zero_Dot_50_Dot_0'Access, "FUNC-HYP-013: Parse(0.50.0) -> Count=3");
      Register_Routine (T, Test_Parse_Three_One_Zero'Access, "FUNC-HYP-013: Parse(3.1.0) -> Count=3");
      Register_Routine (T, Test_Parse_Single_Integer'Access, "FUNC-HYP-013: Parse(357) -> Count=1, Parts(1)=357");
      Register_Routine (T, Test_Parse_Four_Components'Access, "FUNC-HYP-013: Parse(1.2.3.4) -> Count=4");
      Register_Routine (T, Test_Parse_Eight_Components'Access, "FUNC-HYP-013: Parse(8-component) -> Count=8 (MAX boundary)");

      --  Parse — invalid
      Register_Routine (T, Test_Parse_Empty_String'Access,    "FUNC-HYP-013: Parse("""") -> Failure");
      Register_Routine (T, Test_Parse_Trailing_Dot'Access,    "FUNC-HYP-013: Parse(1.) -> Failure");
      Register_Routine (T, Test_Parse_Leading_Dot'Access,     "FUNC-HYP-013: Parse(.1) -> Failure");
      Register_Routine (T, Test_Parse_Double_Dot'Access,      "FUNC-HYP-013: Parse(1..2) -> Failure");
      Register_Routine (T, Test_Parse_Alpha_Component'Access, "FUNC-HYP-013: Parse(1.a) -> Failure");
      Register_Routine (T, Test_Parse_All_Alpha'Access,       "FUNC-HYP-013: Parse(abc) -> Failure");
      Register_Routine (T, Test_Parse_Nine_Components'Access, "FUNC-HYP-013: Parse(9 components) -> Failure (>MAX)");
      Register_Routine (T, Test_Parse_Space_Separator'Access, "FUNC-HYP-013: Parse(1 2) -> Failure");
      Register_Routine (T, Test_Parse_Leading_Space'Access,   "FUNC-HYP-013: Parse( 1.2) -> Failure");
      Register_Routine (T, Test_Parse_Trailing_Space'Access,  "FUNC-HYP-013: Parse(1.2 ) -> Failure");
      Register_Routine (T, Test_Parse_Negative'Access,        "FUNC-HYP-013: Parse(-1) -> Failure");
      Register_Routine (T, Test_Parse_Explicit_Positive'Access, "FUNC-HYP-013: Parse(+1) -> Failure");

      --  Parse — overflow
      Register_Routine (T, Test_Parse_Overflow_Component'Access,
                        "FUNC-HYP-013: Parse(Natural_Last+1) -> Failure (overflow)");

      --  Parse — SPARK postcondition coverage
      Register_Routine (T, Test_Parse_Success_Count_Bounds'Access,
                        "FUNC-HYP-013: Parse success => Count in 1..MAX_VERSION_COMPONENTS");
      Register_Routine (T, Test_Parse_Failure_Yields_Zero_Version'Access,
                        "FUNC-HYP-013: Parse failure => Count = 0 (ZERO_VERSION)");

      --  Compare
      Register_Routine (T, Test_Compare_Equal'Access,               "FUNC-HYP-013: Compare(3.1.0, 3.1.0) = Equal");
      Register_Routine (T, Test_Compare_Equal_Single'Access,         "FUNC-HYP-013: Compare(357, 357) = Equal");
      Register_Routine (T, Test_Compare_Less'Access,                 "FUNC-HYP-013: Compare(3.0.0, 3.1.0) = Less_Than");
      Register_Routine (T, Test_Compare_Greater'Access,              "FUNC-HYP-013: Compare(3.1.0, 3.0.0) = Greater_Than");
      Register_Routine (T, Test_Compare_Prefix_Rule_Less'Access,     "FUNC-HYP-013: Compare(0.50, 0.50.0) = Less_Than");
      Register_Routine (T, Test_Compare_Prefix_Rule_Greater'Access,  "FUNC-HYP-013: Compare(0.50.0, 0.50) = Greater_Than");
      Register_Routine (T, Test_Compare_Single_Integer_Less'Access,  "FUNC-HYP-013: Compare(357, 380) = Less_Than");
      Register_Routine (T, Test_Compare_Zero_Version_Less'Access,    "FUNC-HYP-013: Compare(ZERO, 0.1) = Less_Than");
      Register_Routine (T, Test_Compare_Zero_Version_Equal'Access,   "FUNC-HYP-013: Compare(ZERO, ZERO) = Equal");
      Register_Routine (T, Test_Compare_Mixed_Length_Leading_Differs'Access,
                        "FUNC-HYP-013: Compare(1.0, 0.50) = Greater_Than");
      Register_Routine (T, Test_Compare_Antisymmetry'Access,
                        "FUNC-HYP-013: antisymmetry: Less_Than <-> Greater_Than");

      --  Make
      Register_Routine (T, Test_Make_One_Component'Access,    "FUNC-HYP-013: Make(3) -> Count=1");
      Register_Routine (T, Test_Make_Two_Components'Access,   "FUNC-HYP-013: Make(0,50) -> Count=2, Parts(2)=50");
      Register_Routine (T, Test_Make_Three_Components'Access, "FUNC-HYP-013: Make(3,1,0) -> Count=3");
      Register_Routine (T, Test_Make_No_Patch'Access,         "FUNC-HYP-013: Make(Has_Patch=>False) -> Count=2");
      Register_Routine (T, Test_Make_No_Minor'Access,         "FUNC-HYP-013: Make(Has_Minor=>False) -> Count=1");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Parse — valid inputs
   ---------------------------------------------------------------------------

   procedure Test_Parse_Single_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("0");
   begin
      Assert (V.Count = 1, "Parse(0): Count should be 1");
      Assert (V.Parts (1) = 0, "Parse(0): Parts(1) should be 0");
   end Test_Parse_Single_Zero;

   procedure Test_Parse_Zero_Dot_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("0.0");
   begin
      Assert (V.Count = 2, "Parse(0.0): Count should be 2");
      Assert (V.Parts (1) = 0, "Parse(0.0): Parts(1) should be 0");
      Assert (V.Parts (2) = 0, "Parse(0.0): Parts(2) should be 0");
   end Test_Parse_Zero_Dot_Zero;

   procedure Test_Parse_Zero_Dot_50 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("0.50");
   begin
      Assert (V.Count = 2, "Parse(0.50): Count should be 2");
      Assert (V.Parts (1) = 0, "Parse(0.50): Parts(1) should be 0");
      Assert (V.Parts (2) = 50, "Parse(0.50): Parts(2) should be 50");
   end Test_Parse_Zero_Dot_50;

   procedure Test_Parse_Zero_Dot_50_Dot_0 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("0.50.0");
   begin
      Assert (V.Count = 3, "Parse(0.50.0): Count should be 3");
      Assert (V.Parts (2) = 50, "Parse(0.50.0): Parts(2) should be 50");
      Assert (V.Parts (3) = 0, "Parse(0.50.0): Parts(3) should be 0");
   end Test_Parse_Zero_Dot_50_Dot_0;

   procedure Test_Parse_Three_One_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("3.1.0");
   begin
      Assert (V.Count = 3, "Parse(3.1.0): Count should be 3");
      Assert (V.Parts (1) = 3, "Parse(3.1.0): Parts(1) should be 3");
      Assert (V.Parts (2) = 1, "Parse(3.1.0): Parts(2) should be 1");
      Assert (V.Parts (3) = 0, "Parse(3.1.0): Parts(3) should be 0");
   end Test_Parse_Three_One_Zero;

   procedure Test_Parse_Single_Integer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("357");
   begin
      Assert (V.Count = 1, "Parse(357): Count should be 1");
      Assert (V.Parts (1) = 357, "Parse(357): Parts(1) should be 357");
   end Test_Parse_Single_Integer;

   procedure Test_Parse_Four_Components (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("1.2.3.4");
   begin
      Assert (V.Count = 4, "Parse(1.2.3.4): Count should be 4");
      Assert (V.Parts (1) = 1, "Parse(1.2.3.4): Parts(1) should be 1");
      Assert (V.Parts (4) = 4, "Parse(1.2.3.4): Parts(4) should be 4");
   end Test_Parse_Four_Components;

   procedure Test_Parse_Eight_Components (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Exactly MAX_VERSION_COMPONENTS (8) components — boundary case
      V : constant Version := Parse_OK ("0.0.0.0.0.0.0.0");
   begin
      Assert (V.Count = 8, "Parse(8 components): Count should be 8 (= MAX_VERSION_COMPONENTS)");
   end Test_Parse_Eight_Components;

   ---------------------------------------------------------------------------
   --  Parse — invalid inputs
   ---------------------------------------------------------------------------

   procedure Test_Parse_Empty_String (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("");
   end Test_Parse_Empty_String;

   procedure Test_Parse_Trailing_Dot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1.");
   end Test_Parse_Trailing_Dot;

   procedure Test_Parse_Leading_Dot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail (".1");
   end Test_Parse_Leading_Dot;

   procedure Test_Parse_Double_Dot (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1..2");
   end Test_Parse_Double_Dot;

   procedure Test_Parse_Alpha_Component (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1.a");
   end Test_Parse_Alpha_Component;

   procedure Test_Parse_All_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("abc");
   end Test_Parse_All_Alpha;

   procedure Test_Parse_Nine_Components (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1.2.3.4.5.6.7.8.9");
   end Test_Parse_Nine_Components;

   procedure Test_Parse_Space_Separator (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1 2");
   end Test_Parse_Space_Separator;

   procedure Test_Parse_Leading_Space (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail (" 1.2");
   end Test_Parse_Leading_Space;

   procedure Test_Parse_Trailing_Space (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("1.2 ");
   end Test_Parse_Trailing_Space;

   procedure Test_Parse_Negative (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("-1");
   end Test_Parse_Negative;

   procedure Test_Parse_Explicit_Positive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Parse_Fail ("+1");
   end Test_Parse_Explicit_Positive;

   ---------------------------------------------------------------------------
   --  Parse — overflow protection
   ---------------------------------------------------------------------------

   procedure Test_Parse_Overflow_Component (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Natural'Last is at least 2^31-1 = 2147483647 (10 digits).
      --  Appending one more digit produces a value > Natural'Last, which
      --  the parser must detect and reject before integer overflow occurs.
      V    : Version;
      Succ : Boolean;
   begin
      Parse ("99999999999999999999999", V, Succ);
      Assert (not Succ, "Parse of absurdly large component should return False (overflow guard)");
   end Test_Parse_Overflow_Component;

   ---------------------------------------------------------------------------
   --  Parse — SPARK postcondition coverage
   ---------------------------------------------------------------------------

   procedure Test_Parse_Success_Count_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V    : Version;
      Succ : Boolean;
   begin
      Parse ("1.72.0", V, Succ);
      Assert (Succ, "Parse(1.72.0) should succeed");
      Assert (V.Count >= 1, "Count should be >= 1 on success");
      Assert (V.Count <= MAX_VERSION_COMPONENTS, "Count should be <= MAX_VERSION_COMPONENTS on success");
   end Test_Parse_Success_Count_Bounds;

   procedure Test_Parse_Failure_Yields_Zero_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V    : Version;
      Succ : Boolean;
   begin
      Parse ("bad.input", V, Succ);
      Assert (not Succ, "Parse of invalid input should fail");
      Assert (V.Count = 0, "Failed parse should leave Count = 0 (ZERO_VERSION)");
   end Test_Parse_Failure_Yields_Zero_Version;

   ---------------------------------------------------------------------------
   --  Compare
   ---------------------------------------------------------------------------

   procedure Test_Compare_Equal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("3.1.0");
      V2 : constant Version := Parse_OK ("3.1.0");
   begin
      Assert (Compare (V1, V2) = Equal, "Compare(3.1.0, 3.1.0) should be Equal");
   end Test_Compare_Equal;

   procedure Test_Compare_Equal_Single (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("357");
      V2 : constant Version := Parse_OK ("357");
   begin
      Assert (Compare (V1, V2) = Equal, "Compare(357, 357) should be Equal");
   end Test_Compare_Equal_Single;

   procedure Test_Compare_Less (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("3.0.0");
      V2 : constant Version := Parse_OK ("3.1.0");
   begin
      Assert (Compare (V1, V2) = Less_Than, "Compare(3.0.0, 3.1.0) should be Less_Than");
   end Test_Compare_Less;

   procedure Test_Compare_Greater (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("3.1.0");
      V2 : constant Version := Parse_OK ("3.0.0");
   begin
      Assert (Compare (V1, V2) = Greater_Than, "Compare(3.1.0, 3.0.0) should be Greater_Than");
   end Test_Compare_Greater;

   procedure Test_Compare_Prefix_Rule_Less (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("0.50");
      V2 : constant Version := Parse_OK ("0.50.0");
   begin
      Assert (Compare (V1, V2) = Less_Than,
              "Compare(0.50, 0.50.0) should be Less_Than (prefix rule: shorter is less)");
   end Test_Compare_Prefix_Rule_Less;

   procedure Test_Compare_Prefix_Rule_Greater (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("0.50.0");
      V2 : constant Version := Parse_OK ("0.50");
   begin
      Assert (Compare (V1, V2) = Greater_Than,
              "Compare(0.50.0, 0.50) should be Greater_Than (prefix rule: longer is greater)");
   end Test_Compare_Prefix_Rule_Greater;

   procedure Test_Compare_Single_Integer_Less (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("357");
      V2 : constant Version := Parse_OK ("380");
   begin
      Assert (Compare (V1, V2) = Less_Than, "Compare(357, 380) should be Less_Than");
   end Test_Compare_Single_Integer_Less;

   procedure Test_Compare_Zero_Version_Less (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Parse_OK ("0.1");
   begin
      Assert (Compare (ZERO_VERSION, V) = Less_Than,
              "Compare(ZERO_VERSION, 0.1) should be Less_Than (0-count < any non-zero)");
   end Test_Compare_Zero_Version_Less;

   procedure Test_Compare_Zero_Version_Equal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Compare (ZERO_VERSION, ZERO_VERSION) = Equal,
              "Compare(ZERO_VERSION, ZERO_VERSION) should be Equal");
   end Test_Compare_Zero_Version_Equal;

   procedure Test_Compare_Mixed_Length_Leading_Differs (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V1 : constant Version := Parse_OK ("1.0");
      V2 : constant Version := Parse_OK ("0.50");
   begin
      Assert (Compare (V1, V2) = Greater_Than,
              "Compare(1.0, 0.50) should be Greater_Than (1 > 0 in first component)");
   end Test_Compare_Mixed_Length_Leading_Differs;

   procedure Test_Compare_Antisymmetry (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Va : constant Version := Parse_OK ("0.49.99");
      Vb : constant Version := Parse_OK ("0.50.0");
   begin
      Assert (Compare (Va, Vb) = Less_Than, "Compare(0.49.99, 0.50.0) should be Less_Than");
      Assert (Compare (Vb, Va) = Greater_Than,
              "Compare(0.50.0, 0.49.99) should be Greater_Than (antisymmetry)");
   end Test_Compare_Antisymmetry;

   ---------------------------------------------------------------------------
   --  Make
   ---------------------------------------------------------------------------

   procedure Test_Make_One_Component (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Make (Major => 3, Has_Minor => False);
   begin
      Assert (V.Count = 1, "Make(3, Has_Minor=>False): Count should be 1");
      Assert (V.Parts (1) = 3, "Make(3, Has_Minor=>False): Parts(1) should be 3");
   end Test_Make_One_Component;

   procedure Test_Make_Two_Components (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Make (Major => 0, Minor => 50, Has_Patch => False);
   begin
      Assert (V.Count = 2, "Make(0, 50, Has_Patch=>False): Count should be 2");
      Assert (V.Parts (1) = 0,  "Make(0, 50, Has_Patch=>False): Parts(1) should be 0");
      Assert (V.Parts (2) = 50, "Make(0, 50, Has_Patch=>False): Parts(2) should be 50");
   end Test_Make_Two_Components;

   procedure Test_Make_Three_Components (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Make (Major => 3, Minor => 1, Patch => 0);
   begin
      Assert (V.Count = 3, "Make(3,1,0): Count should be 3");
      Assert (V.Parts (1) = 3, "Make(3,1,0): Parts(1) should be 3");
      Assert (V.Parts (2) = 1, "Make(3,1,0): Parts(2) should be 1");
      Assert (V.Parts (3) = 0, "Make(3,1,0): Parts(3) should be 0");
   end Test_Make_Three_Components;

   procedure Test_Make_No_Patch (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Make (Major => 1, Minor => 4, Has_Patch => False);
   begin
      Assert (V.Count = 2, "Make(1,4, Has_Patch=>False): Count should be 2");
   end Test_Make_No_Patch;

   procedure Test_Make_No_Minor (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Version := Make (Major => 357, Has_Minor => False);
   begin
      Assert (V.Count = 1, "Make(357, Has_Minor=>False): Count should be 1");
      Assert (V.Parts (1) = 357, "Make(357, Has_Minor=>False): Parts(1) should be 357");
   end Test_Make_No_Minor;

end Test_Version;
