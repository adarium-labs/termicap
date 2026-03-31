-------------------------------------------------------------------------------
--  Termicap.Environment.Capture - OS Environment Capture (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Captures the current process environment using Ada.Environment_Variables.
--  This package body is outside the SPARK boundary (SPARK_Mode => Off is
--  inherited from the spec) because Ada.Environment_Variables performs OS
--  calls that cannot be verified by GNATprove.

with Ada.Environment_Variables;

package body Termicap.Environment.Capture is

   procedure Capture_Current (Env : out Environment) is

      procedure Process_Variable (Name, Value : String) is
      begin
         Insert (Env, Name, Value);
      end Process_Variable;

   begin
      Env := EMPTY_ENVIRONMENT;
      Ada.Environment_Variables.Iterate (Process_Variable'Access);
   end Capture_Current;

end Termicap.Environment.Capture;
