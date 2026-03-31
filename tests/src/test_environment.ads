-------------------------------------------------------------------------------
--  Test_Environment - Unit Tests for Termicap.Environment
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the Environment snapshot type and all query,
--  builder, and utility operations.
--
--  Requirements Coverage:
--    - @relation(FUNC-ENV-001): Environment snapshot type
--    - @relation(FUNC-ENV-002): Environment variable existence check
--    - @relation(FUNC-ENV-003): Environment variable value retrieval
--    - @relation(FUNC-ENV-005): Programmatic environment construction for testing
--    - @relation(FUNC-ENV-006): Case-insensitive value comparison
--    - @relation(FUNC-ENV-008): Multi-candidate value matching

with AUnit.Test_Cases;

package Test_Environment is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  Test Procedures
   ---------------------------------------------------------------------------

   --  FUNC-ENV-001, FUNC-ENV-005: EMPTY_ENVIRONMENT has no variables
   procedure Test_Empty_Contains
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-003, FUNC-ENV-005: Value returns "" for any name in empty env
   procedure Test_Empty_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-002, FUNC-ENV-005: Contains returns True for inserted variable
   procedure Test_Single_Variable_Contains_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-003, FUNC-ENV-005: Value returns correct string for inserted var
   procedure Test_Single_Variable_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-002: Contains returns False for absent variable
   procedure Test_Single_Variable_Contains_Other_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-002: NO_COLOR set to empty string — Contains returns True
   procedure Test_No_Color_Empty_Contains
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-003: NO_COLOR set to empty string — Value returns ""
   procedure Test_No_Color_Empty_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-002: NO_COLOR set to "1" — Contains returns True
   procedure Test_No_Color_Set_Contains
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-003: NO_COLOR set to "1" — Value returns "1"
   procedure Test_No_Color_Set_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-002: NO_COLOR absent — Contains returns False
   procedure Test_No_Color_Absent
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Contains is case-insensitive for keys (lowercase)
   procedure Test_Case_Insensitive_Key_Lower
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Contains is case-insensitive for keys (mixed case)
   procedure Test_Case_Insensitive_Key_Mixed
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Value returns same result regardless of key casing
   procedure Test_Case_Insensitive_Key_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-005: Inserting same key twice keeps last value
   procedure Test_Value_Overwrite
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Equal_Case_Insensitive — matching strings differing in case
   procedure Test_Equal_Case_Insensitive_Match
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Equal_Case_Insensitive — non-matching strings
   procedure Test_Equal_Case_Insensitive_No_Match
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-006: Equal_Case_Insensitive — both empty strings
   procedure Test_Equal_Case_Insensitive_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-008: Value_Matches returns True when value is in candidates
   procedure Test_Value_Matches_True
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-008: Value_Matches returns False when value is not in candidates
   procedure Test_Value_Matches_False
      (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-ENV-008: Value_Matches returns False when key is absent
   procedure Test_Value_Matches_Missing_Key
      (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Environment;
