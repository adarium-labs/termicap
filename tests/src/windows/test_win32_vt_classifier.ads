-------------------------------------------------------------------------------
--  Test_Win32_VT_Classifier - Unit Tests for Termicap.Win32_VT classifier
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the ConPTY-aware active-probe gate classifier
--  exposed by Termicap.Win32_VT.  These tests run only on Windows hosts and
--  require the test binary to be invoked under a real console (the existing
--  test runner satisfies this).
--
--  Requirements Coverage:
--    - @relation(FUNC-WIN-014): ConPTY-aware active-probe gate

with AUnit.Test_Cases;

package Test_Win32_VT_Classifier is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-WIN-014: Classifier Tests
   ---------------------------------------------------------------------------

   --  FUNC-WIN-014: Classifier returns one of the three documented enum values
   procedure Test_Classifier_Returns_Sane_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-014: Should_Skip_Active_Probes is True iff classifier = Legacy_Conhost
   procedure Test_Should_Skip_Iff_Legacy_Conhost (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-014: When classifier returns ConPTY_VT_Enabled, the
   --  ENABLE_VIRTUAL_TERMINAL_PROCESSING bit is set on STD_OUTPUT_HANDLE.
   procedure Test_VT_Bit_Set_After_ConPTY_Probe (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-WIN-014: Repeated classification calls are idempotent and return
   --  the same value.
   procedure Test_Idempotent_Repeated_Classification (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Win32_VT_Classifier;
