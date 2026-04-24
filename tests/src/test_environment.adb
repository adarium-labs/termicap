-------------------------------------------------------------------------------
--  Test_Environment - Unit Tests for Termicap.Environment
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Environment; use Termicap.Environment;

package body Test_Environment is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Environment");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine (T, Test_Empty_Contains'Access, "Empty environment: Contains returns False");
      Register_Routine (T, Test_Empty_Value'Access, "Empty environment: Value returns empty string");
      Register_Routine
        (T, Test_Single_Variable_Contains_True'Access, "Single variable: Contains returns True for inserted key");
      Register_Routine (T, Test_Single_Variable_Value'Access, "Single variable: Value returns inserted value");
      Register_Routine
        (T, Test_Single_Variable_Contains_Other_False'Access, "Single variable: Contains returns False for absent key");
      Register_Routine
        (T, Test_No_Color_Empty_Contains'Access, "NO_COLOR edge case: empty value, Contains returns True");
      Register_Routine
        (T, Test_No_Color_Empty_Value'Access, "NO_COLOR edge case: empty value, Value returns empty string");
      Register_Routine (T, Test_No_Color_Set_Contains'Access, "NO_COLOR edge case: value '1', Contains returns True");
      Register_Routine (T, Test_No_Color_Set_Value'Access, "NO_COLOR edge case: value '1', Value returns '1'");
      Register_Routine (T, Test_No_Color_Absent'Access, "NO_COLOR edge case: absent, Contains returns False");
      Register_Routine
        (T, Test_Case_Insensitive_Key_Lower'Access, "Case-insensitive keys: lowercase lookup returns True");
      Register_Routine
        (T, Test_Case_Insensitive_Key_Mixed'Access, "Case-insensitive keys: mixed-case lookup returns True");
      Register_Routine
        (T, Test_Case_Insensitive_Key_Value'Access, "Case-insensitive keys: Value is same for any casing");
      Register_Routine (T, Test_Value_Overwrite'Access, "Value overwrite: second Insert replaces first");
      Register_Routine
        (T, Test_Equal_Case_Insensitive_Match'Access, "Equal_Case_Insensitive: matching strings differing in case");
      Register_Routine (T, Test_Equal_Case_Insensitive_No_Match'Access, "Equal_Case_Insensitive: non-matching strings");
      Register_Routine (T, Test_Equal_Case_Insensitive_Empty'Access, "Equal_Case_Insensitive: both empty strings");
      Register_Routine (T, Test_Value_Matches_True'Access, "Value_Matches: value in candidates returns True");
      Register_Routine (T, Test_Value_Matches_False'Access, "Value_Matches: value not in candidates returns False");
      Register_Routine (T, Test_Value_Matches_Missing_Key'Access, "Value_Matches: absent key returns False");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   procedure Test_Empty_Contains (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      Assert (not Contains (Env, "ANYTHING"), "Empty environment should not contain any variable");
      Assert (not Contains (Env, "TERM"), "Empty environment should not contain TERM");
      Assert (not Contains (Env, "NO_COLOR"), "Empty environment should not contain NO_COLOR");
   end Test_Empty_Contains;

   procedure Test_Empty_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      Assert (Value (Env, "ANYTHING") = "", "Empty environment: Value should return empty string for any key");
      Assert (Value (Env, "TERM") = "", "Empty environment: Value (TERM) should return empty string");
   end Test_Empty_Value;

   procedure Test_Single_Variable_Contains_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm");
      Assert (Contains (Env, "TERM"), "Contains should return True for inserted key TERM");
   end Test_Single_Variable_Contains_True;

   procedure Test_Single_Variable_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm");
      Assert (Value (Env, "TERM") = "xterm", "Value should return 'xterm' for inserted key TERM");
   end Test_Single_Variable_Value;

   procedure Test_Single_Variable_Contains_Other_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm");
      Assert (not Contains (Env, "OTHER"), "Contains should return False for key OTHER not in snapshot");
      Assert (not Contains (Env, "COLORTERM"), "Contains should return False for key COLORTERM not in snapshot");
   end Test_Single_Variable_Contains_Other_False;

   procedure Test_No_Color_Empty_Contains (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "");
      Assert
        (Contains (Env, "NO_COLOR"),
         "NO_COLOR set to empty string: Contains must return True " & "(presence matters for NO_COLOR compliance)");
   end Test_No_Color_Empty_Contains;

   procedure Test_No_Color_Empty_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "");
      Assert (Value (Env, "NO_COLOR") = "", "NO_COLOR set to empty string: Value should return empty string");
   end Test_No_Color_Empty_Value;

   procedure Test_No_Color_Set_Contains (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert (Contains (Env, "NO_COLOR"), "NO_COLOR set to '1': Contains must return True");
   end Test_No_Color_Set_Contains;

   procedure Test_No_Color_Set_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert (Value (Env, "NO_COLOR") = "1", "NO_COLOR set to '1': Value should return '1'");
   end Test_No_Color_Set_Value;

   procedure Test_No_Color_Absent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : constant Environment := EMPTY_ENVIRONMENT;
   begin
      Assert (not Contains (Env, "NO_COLOR"), "NO_COLOR absent from environment: Contains must return False");
   end Test_No_Color_Absent;

   procedure Test_Case_Insensitive_Key_Lower (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert
        (Contains (Env, "no_color"),
         "Contains with lowercase key 'no_color' should return True " & "when 'NO_COLOR' was inserted");
   end Test_Case_Insensitive_Key_Lower;

   procedure Test_Case_Insensitive_Key_Mixed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert
        (Contains (Env, "No_Color"),
         "Contains with mixed-case key 'No_Color' should return True " & "when 'NO_COLOR' was inserted");
   end Test_Case_Insensitive_Key_Mixed;

   procedure Test_Case_Insensitive_Key_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "NO_COLOR", "1");
      Assert
        (Value (Env, "NO_COLOR") = Value (Env, "no_color"),
         "Value('NO_COLOR') and Value('no_color') must return the same result");
      Assert (Value (Env, "no_color") = "1", "Value with lowercase key should return the stored value '1'");
   end Test_Case_Insensitive_Key_Value;

   procedure Test_Value_Overwrite (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment := EMPTY_ENVIRONMENT;
   begin
      Insert (Env, "TERM", "xterm");
      Insert (Env, "TERM", "xterm-256color");
      Assert
        (Value (Env, "TERM") = "xterm-256color",
         "Second Insert for TERM should overwrite the first value; " & "expected 'xterm-256color'");
   end Test_Value_Overwrite;

   procedure Test_Equal_Case_Insensitive_Match (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Equal_Case_Insensitive ("truecolor", "TrueColor"),
         "Equal_Case_Insensitive('truecolor', 'TrueColor') should return True");
      Assert (Equal_Case_Insensitive ("XTERM", "xterm"), "Equal_Case_Insensitive('XTERM', 'xterm') should return True");
      Assert (Equal_Case_Insensitive ("abc", "ABC"), "Equal_Case_Insensitive('abc', 'ABC') should return True");
   end Test_Equal_Case_Insensitive_Match;

   procedure Test_Equal_Case_Insensitive_No_Match (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (not Equal_Case_Insensitive ("truecolor", "24bit"),
         "Equal_Case_Insensitive('truecolor', '24bit') should return False");
      Assert
        (not Equal_Case_Insensitive ("xterm", "rxvt"), "Equal_Case_Insensitive('xterm', 'rxvt') should return False");
   end Test_Equal_Case_Insensitive_No_Match;

   procedure Test_Equal_Case_Insensitive_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Equal_Case_Insensitive ("", ""), "Equal_Case_Insensitive('', '') should return True");
   end Test_Equal_Case_Insensitive_Empty;

   procedure Test_Value_Matches_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env        : Environment := EMPTY_ENVIRONMENT;
      Candidates : String_Vector;
   begin
      Insert (Env, "COLORTERM", "truecolor");
      String_Vectors.Append (Candidates, "truecolor");
      String_Vectors.Append (Candidates, "24bit");
      Assert
        (Value_Matches (Env, "COLORTERM", Candidates),
         "Value_Matches should return True when COLORTERM='truecolor' " & "and candidates contain 'truecolor'");
   end Test_Value_Matches_True;

   procedure Test_Value_Matches_False (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env        : Environment := EMPTY_ENVIRONMENT;
      Candidates : String_Vector;
   begin
      Insert (Env, "COLORTERM", "truecolor");
      String_Vectors.Append (Candidates, "ansi");
      String_Vectors.Append (Candidates, "256color");
      Assert
        (not Value_Matches (Env, "COLORTERM", Candidates),
         "Value_Matches should return False when COLORTERM='truecolor' " & "and candidates do not contain 'truecolor'");
   end Test_Value_Matches_False;

   procedure Test_Value_Matches_Missing_Key (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env        : constant Environment := EMPTY_ENVIRONMENT;
      Candidates : String_Vector;
   begin
      String_Vectors.Append (Candidates, "truecolor");
      Assert
        (not Value_Matches (Env, "MISSING", Candidates),
         "Value_Matches should return False when the key is absent " & "from the snapshot");
   end Test_Value_Matches_Missing_Key;

end Test_Environment;
