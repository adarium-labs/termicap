-------------------------------------------------------------------------------
--  Test_Environment_Capture - Integration Tests for Termicap.Environment.Capture
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture; use Termicap.Environment.Capture;

package body Test_Environment_Capture is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Environment.Capture");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine
        (T, Test_Capture_Contains_System_Variable'Access, "Capture_Current: snapshot contains a known system variable");
      Register_Routine
        (T, Test_Capture_Absent_Variable_Returns_Empty'Access, "Capture_Current: absent variable returns empty string");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   procedure Test_Capture_Contains_System_Variable (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env           : Environment;
      Has_Known_Var : Boolean;
   begin
      Capture_Current (Env);

      --  PATH or HOME must be present on any POSIX system (macOS/Linux).
      --  We accept either one so that the test is portable.  At least one of
      --  these variables is expected to be set in any normal process context.
      Has_Known_Var := Contains (Env, "PATH") or else Contains (Env, "HOME");

      Assert
        (Has_Known_Var,
         "Capture_Current: snapshot should contain at least one of " & "'PATH' or 'HOME' from the process environment");
   end Test_Capture_Contains_System_Variable;

   procedure Test_Capture_Absent_Variable_Returns_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env : Environment;
   begin
      Capture_Current (Env);

      --  A variable with a highly improbable name should not be present.
      --  Querying it must return "" without raising any exception.
      Assert
        (Value (Env, "TERMICAP_SURELY_NOT_SET_XY9Z") = "",
         "Capture_Current: Value for an absent variable should be ''");
      Assert
        (not Contains (Env, "TERMICAP_SURELY_NOT_SET_XY9Z"),
         "Capture_Current: Contains for an absent variable should be False");
   end Test_Capture_Absent_Variable_Returns_Empty;

end Test_Environment_Capture;
