-------------------------------------------------------------------------------
--  Test_TTY - Unit Tests for Termicap.TTY
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the TTY detection types and functions.
--
--  Requirements Coverage:
--    - @relation(FUNC-TTY-001): Stream_Kind enumeration type
--    - @relation(FUNC-TTY-002): Per-stream TTY detection
--    - @relation(FUNC-TTY-004): Safe, non-destructive query
--    - @relation(FUNC-TTY-005): SPARK boundary
--    - @relation(FUNC-TTY-006): Bulk TTY status query

with AUnit.Test_Cases;

package Test_TTY is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Test Procedures
   ---------------------------------------------------------------------------

   --  FUNC-TTY-001: Stream_Kind has exactly three values
   procedure Test_Stream_Kind_Values
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-001: Stream_Kind positional values match fd convention
   procedure Test_Stream_Kind_Positions
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-006: TTY_Status record stores three independent Booleans
   procedure Test_TTY_Status_Record
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-002, FUNC-TTY-004: Is_TTY returns Boolean without raising
   procedure Test_Is_TTY_No_Exception
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-006: Query_All returns consistent results with Is_TTY
   procedure Test_Query_All_Consistency
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-002, FUNC-TTY-004: Is_TTY called multiple times is stable
   procedure Test_Is_TTY_Stability
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-TTY-006: TTY_Status aggregate construction
   procedure Test_TTY_Status_Aggregate
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_TTY;
