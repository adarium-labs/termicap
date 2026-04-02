-------------------------------------------------------------------------------
--  Test_TTY - Unit Tests for Termicap.TTY
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases; use AUnit.Test_Cases.Registration;

with Termicap.TTY; use Termicap.TTY;

package body Test_TTY is


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.TTY");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      Register_Routine (T, Test_Stream_Kind_Values'Access,
         "Stream_Kind has exactly three values (Stdin, Stdout, Stderr)");
      Register_Routine (T, Test_Stream_Kind_Positions'Access,
         "Stream_Kind positional values match fd convention (0, 1, 2)");
      Register_Routine (T, Test_TTY_Status_Record'Access,
         "TTY_Status record stores three independent Booleans");
      Register_Routine (T, Test_Is_TTY_No_Exception'Access,
         "Is_TTY returns Boolean for all streams without raising");
      Register_Routine (T, Test_Query_All_Consistency'Access,
         "Query_All matches individual Is_TTY calls");
      Register_Routine (T, Test_Is_TTY_Stability'Access,
         "Is_TTY returns stable results on repeated calls");
      Register_Routine (T, Test_TTY_Status_Aggregate'Access,
         "TTY_Status aggregate construction works correctly");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   procedure Test_Stream_Kind_Values
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Stream_Kind'First = Stdin,
          "Stream_Kind'First should be Stdin");
      Assert
         (Stream_Kind'Last = Stderr,
          "Stream_Kind'Last should be Stderr");
      --  Verify exactly 3 values by checking Pos range
      Assert
         (Stream_Kind'Pos (Stream_Kind'Last) = 2,
          "Stream_Kind should have exactly 3 values (0..2)");
   end Test_Stream_Kind_Values;


   procedure Test_Stream_Kind_Positions
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (Stream_Kind'Pos (Stdin) = 0,
          "Stdin position should be 0");
      Assert
         (Stream_Kind'Pos (Stdout) = 1,
          "Stdout position should be 1");
      Assert
         (Stream_Kind'Pos (Stderr) = 2,
          "Stderr position should be 2");
   end Test_Stream_Kind_Positions;


   procedure Test_TTY_Status_Record
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : TTY_Status;
   begin
      --  Verify each field is independently settable
      Status := (Stdin => True, Stdout => False, Stderr => True);
      Assert (Status.Stdin = True, "Stdin field should be True");
      Assert (Status.Stdout = False, "Stdout field should be False");
      Assert (Status.Stderr = True, "Stderr field should be True");

      Status := (Stdin => False, Stdout => True, Stderr => False);
      Assert (Status.Stdin = False, "Stdin field should now be False");
      Assert (Status.Stdout = True, "Stdout field should now be True");
      Assert (Status.Stderr = False, "Stderr field should now be False");
   end Test_TTY_Status_Record;


   procedure Test_Is_TTY_No_Exception
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result_In  : Boolean;
      Result_Out : Boolean;
      Result_Err : Boolean;
      pragma Unreferenced (Result_In, Result_Out, Result_Err);
   begin
      --  The key assertion is that no exception is raised.
      --  In CI/test environments, all three are expected to return False,
      --  but we don't assert that since interactive terminals would differ.
      Result_In  := Is_TTY (Stdin);
      Result_Out := Is_TTY (Stdout);
      Result_Err := Is_TTY (Stderr);
   end Test_Is_TTY_No_Exception;


   procedure Test_Query_All_Consistency
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : constant TTY_Status := Query_All;
   begin
      Assert
         (Status.Stdin = Is_TTY (Stdin),
          "Query_All.Stdin should match Is_TTY (Stdin)");
      Assert
         (Status.Stdout = Is_TTY (Stdout),
          "Query_All.Stdout should match Is_TTY (Stdout)");
      Assert
         (Status.Stderr = Is_TTY (Stderr),
          "Query_All.Stderr should match Is_TTY (Stderr)");
   end Test_Query_All_Consistency;


   procedure Test_Is_TTY_Stability
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      First_Call  : constant Boolean := Is_TTY (Stdout);
      Second_Call : constant Boolean := Is_TTY (Stdout);
   begin
      Assert
         (First_Call = Second_Call,
          "Is_TTY (Stdout) should return the same result on consecutive calls");
   end Test_Is_TTY_Stability;


   procedure Test_TTY_Status_Aggregate
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Status : constant TTY_Status := (Stdin => False, Stdout => False, Stderr => False);
   begin
      Assert (not Status.Stdin, "All-False aggregate: Stdin should be False");
      Assert (not Status.Stdout, "All-False aggregate: Stdout should be False");
      Assert (not Status.Stderr, "All-False aggregate: Stderr should be False");
   end Test_TTY_Status_Aggregate;

end Test_TTY;
