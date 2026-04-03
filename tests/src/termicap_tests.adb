-------------------------------------------------------------------------------
--  Termicap_Tests - Test Runner for Termicap Library
--
--  Copyright (c) 2025 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Run;
with AUnit.Reporter.Text;
with AUnit.Test_Suites;

with Test_Color;
with Test_Dimensions;
with Test_Environment;
with Test_Environment_Capture;
with Test_Terminal_Id;
with Test_TTY;
with Test_Unicode;

procedure Termicap_Tests is

   function All_Tests return AUnit.Test_Suites.Access_Test_Suite;

   function All_Tests return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      AUnit.Test_Suites.Add_Test (Result, new Test_Environment.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_Environment_Capture.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_TTY.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_Color.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_Dimensions.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_Unicode.Test_Case);
      AUnit.Test_Suites.Add_Test (Result, new Test_Terminal_Id.Test_Case);
      return Result;
   end All_Tests;

   procedure Run is new AUnit.Run.Test_Runner (All_Tests);
   Reporter : AUnit.Reporter.Text.Text_Reporter;

begin
   Run (Reporter);
end Termicap_Tests;
