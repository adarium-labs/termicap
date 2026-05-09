-------------------------------------------------------------------------------
--  Test_Win32_VT_Classifier - Unit Tests for Termicap.Win32_VT classifier
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Win32_VT; use Termicap.Win32_VT;

with Win32;
with Win32.Winbase;
with Win32.Wincon;
with Win32.Winnt;

package body Test_Win32_VT_Classifier is

   use type Win32.BOOL;
   use type Win32.DWORD;
   use type Termicap.Win32_VT.Console_VT_Status;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Win32_VT.Classify_Console_VT");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine
        (T,
         Test_Classifier_Returns_Sane_Value'Access,
         "FUNC-WIN-014: Classify_Console_VT returns one of"
         & " {Not_A_Console, Legacy_Conhost, ConPTY_VT_Enabled}");
      Register_Routine
        (T,
         Test_Should_Skip_Iff_Legacy_Conhost'Access,
         "FUNC-WIN-014: Should_Skip_Active_Probes = (Classify_Console_VT = Legacy_Conhost)");
      Register_Routine
        (T,
         Test_VT_Bit_Set_After_ConPTY_Probe'Access,
         "FUNC-WIN-014: ConPTY_VT_Enabled => ENABLE_VIRTUAL_TERMINAL_PROCESSING set on STD_OUTPUT_HANDLE");
      Register_Routine
        (T,
         Test_Idempotent_Repeated_Classification'Access,
         "FUNC-WIN-014: Repeated Classify_Console_VT calls return the same value");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   procedure Test_Classifier_Returns_Sane_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : constant Console_VT_Status := Classify_Console_VT;
   begin
      --  Smoke test: the function must be callable and must return one of the
      --  three documented enumeration values.  Because Console_VT_Status is a
      --  closed enum, this assertion is logically equivalent to asserting that
      --  the call did not raise an exception, but it documents the contract.
      Assert
        (Status = Not_A_Console
         or else Status = Legacy_Conhost
         or else Status = ConPTY_VT_Enabled,
         "Classify_Console_VT must return one of "
         & "Not_A_Console | Legacy_Conhost | ConPTY_VT_Enabled");
   end Test_Classifier_Returns_Sane_Value;

   procedure Test_Should_Skip_Iff_Legacy_Conhost (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : constant Console_VT_Status := Classify_Console_VT;
      Skip   : constant Boolean           := Should_Skip_Active_Probes;
   begin
      --  The convenience predicate must be exactly equivalent to the
      --  classifier comparison.  This guards against future drift where
      --  Should_Skip_Active_Probes might accept new "skip" cases without
      --  introducing a new enum value.
      Assert
        (Skip = (Status = Legacy_Conhost),
         "Should_Skip_Active_Probes must equal (Classify_Console_VT = Legacy_Conhost)");
   end Test_Should_Skip_Iff_Legacy_Conhost;

   procedure Test_VT_Bit_Set_After_ConPTY_Probe (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Status : constant Console_VT_Status := Classify_Console_VT;
      H      : Win32.Winnt.HANDLE;
      Mode   : aliased Win32.DWORD := 0;
      Res    : Win32.BOOL;
   begin
      if Status = ConPTY_VT_Enabled then
         --  Acquire STD_OUTPUT_HANDLE directly to verify the post-condition
         --  documented for ConPTY_VT_Enabled: the VT processing bit is set
         --  on the standard output handle (either it was already, or
         --  Classify_Console_VT successfully set it via SetConsoleMode).
         H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE);
         Assert
           (Termicap.Win32_VT.Is_Valid_Handle (H),
            "STD_OUTPUT_HANDLE must be valid when ConPTY_VT_Enabled was reported");
         Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
         Assert
           (Res /= Win32.FALSE,
            "GetConsoleMode must succeed on STD_OUTPUT_HANDLE when ConPTY_VT_Enabled was reported");
         Assert
           ((Mode and ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= 0,
            "ENABLE_VIRTUAL_TERMINAL_PROCESSING must be set on STD_OUTPUT_HANDLE"
            & " after Classify_Console_VT returns ConPTY_VT_Enabled");
      else
         --  Skip: the post-condition only applies to the ConPTY_VT_Enabled
         --  branch.  Trivially pass so the test runs to completion on hosts
         --  classified as Legacy_Conhost or Not_A_Console.
         Assert (True, "Test skipped — host is not ConPTY_VT_Enabled");
      end if;
   end Test_VT_Bit_Set_After_ConPTY_Probe;

   procedure Test_Idempotent_Repeated_Classification (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      First  : constant Console_VT_Status := Classify_Console_VT;
      Second : constant Console_VT_Status := Classify_Console_VT;
   begin
      --  Repeated classification calls must return the same value within a
      --  single process.  The function may have a side effect (it sets
      --  ENABLE_VIRTUAL_TERMINAL_PROCESSING the first time around) but the
      --  result must remain stable on subsequent invocations.
      Assert
        (First = Second,
         "Classify_Console_VT must be idempotent: two consecutive calls"
         & " returned different values");
   end Test_Idempotent_Repeated_Classification;

end Test_Win32_VT_Classifier;
