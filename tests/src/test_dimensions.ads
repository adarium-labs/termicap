-------------------------------------------------------------------------------
--  Test_Dimensions - Unit Tests for Termicap.Dimensions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering Terminal_Size type, Get_Size pure fallback path,
--  environment variable parsing, and edge cases.
--
--  Requirements Coverage:
--    - @relation(FUNC-DIM-001): Terminal_Size record type
--    - @relation(FUNC-DIM-003): Environment variable fallback
--    - @relation(FUNC-DIM-004): Default fallback to 80x24
--    - @relation(FUNC-DIM-005): Pure query function signature
--    - @relation(FUNC-DIM-008): Pixel dimensions support

with AUnit.Test_Cases;

package Test_Dimensions is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-DIM-001: Terminal_Size Record Type
   ---------------------------------------------------------------------------

   --  FUNC-DIM-001: Default size has correct field values
   procedure Test_Default_Size (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DIM-004: Default Fallback to 80x24
   ---------------------------------------------------------------------------

   --  FUNC-DIM-004: No env vars, Is_TTY=False -> 80x24, pixel=0
   procedure Test_Default_Fallback_No_Env (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DIM-003: Environment Variable Fallback
   ---------------------------------------------------------------------------

   --  FUNC-DIM-003: COLUMNS and LINES both set -> use both
   procedure Test_Env_Columns_And_Lines (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: Only COLUMNS set -> use COLUMNS, default ROWS
   procedure Test_Env_Columns_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: Only LINES set -> default COLUMNS, use LINES
   procedure Test_Env_Lines_Only (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: COLUMNS invalid (non-numeric) -> default COLUMNS
   procedure Test_Env_Columns_Invalid_Non_Numeric (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: COLUMNS="0" -> default (0 is not Positive)
   procedure Test_Env_Columns_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: COLUMNS="" (empty) -> default
   procedure Test_Env_Columns_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: COLUMNS="-1" (negative) -> default
   procedure Test_Env_Columns_Negative (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: COLUMNS="999999999999999" (overflow) -> default
   procedure Test_Env_Columns_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: LINES invalid + COLUMNS valid -> partial detection
   procedure Test_Env_Lines_Invalid_Columns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-DIM-003: Case insensitivity of env var names
   procedure Test_Env_Case_Insensitive (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-DIM-008: Pixel Dimensions
   ---------------------------------------------------------------------------

   --  FUNC-DIM-008: Pixel dimensions are 0 on env var fallback path
   procedure Test_Pixel_Dimensions_Zero_On_Env_Path (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Dimensions;
