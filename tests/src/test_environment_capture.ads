-------------------------------------------------------------------------------
--  Test_Environment_Capture - Integration Tests for Termicap.Environment.Capture
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case for the Capture_Current procedure, which reads the live
--  process environment into an Environment snapshot.
--
--  Requirements Coverage:
--    - @relation(FUNC-ENV-004): Capture current process environment

with AUnit.Test_Cases;

package Test_Environment_Capture is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Test Procedures
   ---------------------------------------------------------------------------

   --  FUNC-ENV-004: Captured snapshot contains at least one known system variable
   procedure Test_Capture_Contains_System_Variable
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-004: After capture, querying an absent variable returns ""
   procedure Test_Capture_Absent_Variable_Returns_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Environment_Capture;
