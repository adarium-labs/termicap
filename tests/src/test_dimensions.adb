-------------------------------------------------------------------------------
--  Test_Dimensions - Unit Tests for Termicap.Dimensions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Dimensions;  use Termicap.Dimensions;
with Termicap.Environment; use Termicap.Environment;

package body Test_Dimensions is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Dimensions");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-DIM-001
      Register_Routine (T, Test_Default_Size'Access, "FUNC-DIM-001: Default Terminal_Size has correct field values");

      --  FUNC-DIM-004
      Register_Routine
        (T, Test_Default_Fallback_No_Env'Access, "FUNC-DIM-004: No env vars, Is_TTY=False -> 80x24, pixel=0");

      --  FUNC-DIM-003
      Register_Routine (T, Test_Env_Columns_And_Lines'Access, "FUNC-DIM-003: COLUMNS and LINES both set -> use both");
      Register_Routine (T, Test_Env_Columns_Only'Access, "FUNC-DIM-003: Only COLUMNS set -> use COLUMNS, default ROWS");
      Register_Routine (T, Test_Env_Lines_Only'Access, "FUNC-DIM-003: Only LINES set -> default COLUMNS, use LINES");
      Register_Routine
        (T,
         Test_Env_Columns_Invalid_Non_Numeric'Access,
         "FUNC-DIM-003: COLUMNS invalid (non-numeric) -> default COLUMNS");
      Register_Routine (T, Test_Env_Columns_Zero'Access, "FUNC-DIM-003: COLUMNS='0' -> default (0 is not Positive)");
      Register_Routine (T, Test_Env_Columns_Empty'Access, "FUNC-DIM-003: COLUMNS='' (empty) -> default");
      Register_Routine (T, Test_Env_Columns_Negative'Access, "FUNC-DIM-003: COLUMNS='-1' (negative) -> default");
      Register_Routine
        (T, Test_Env_Columns_Overflow'Access, "FUNC-DIM-003: COLUMNS='999999999999999' (overflow) -> default");
      Register_Routine
        (T,
         Test_Env_Lines_Invalid_Columns_Valid'Access,
         "FUNC-DIM-003: LINES invalid + COLUMNS valid -> partial detection");
      Register_Routine (T, Test_Env_Case_Insensitive'Access, "FUNC-DIM-003: Case insensitivity of env var names");

      --  FUNC-DIM-008
      Register_Routine
        (T,
         Test_Pixel_Dimensions_Zero_On_Env_Path'Access,
         "FUNC-DIM-008: Pixel dimensions are 0 on env var fallback path");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  FUNC-DIM-001: Terminal_Size Record Type
   ---------------------------------------------------------------------------

   procedure Test_Default_Size (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Size : constant Terminal_Size :=
        (Rows => DEFAULT_ROWS, Columns => DEFAULT_COLUMNS, Pixel_Width => 0, Pixel_Height => 0);
   begin
      Assert (Size.Rows = 24, "Default rows should be 24");
      Assert (Size.Columns = 80, "Default columns should be 80");
      Assert (Size.Pixel_Width = 0, "Default pixel width should be 0");
      Assert (Size.Pixel_Height = 0, "Default pixel height should be 0");
   end Test_Default_Size;

   ---------------------------------------------------------------------------
   --  FUNC-DIM-004: Default Fallback to 80x24
   ---------------------------------------------------------------------------

   procedure Test_Default_Fallback_No_Env (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : constant Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Default columns should be 80");
      Assert (Size.Rows = 24, "Default rows should be 24");
      Assert (Size.Pixel_Width = 0, "Default pixel width should be 0");
      Assert (Size.Pixel_Height = 0, "Default pixel height should be 0");
   end Test_Default_Fallback_No_Env;

   ---------------------------------------------------------------------------
   --  FUNC-DIM-003: Environment Variable Fallback
   ---------------------------------------------------------------------------

   procedure Test_Env_Columns_And_Lines (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "120");
      Insert (Env, "LINES", "40");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 120, "Columns should be 120");
      Assert (Size.Rows = 40, "Rows should be 40");
      Assert (Size.Pixel_Width = 0, "Pixel width should be 0");
      Assert (Size.Pixel_Height = 0, "Pixel height should be 0");
   end Test_Env_Columns_And_Lines;

   procedure Test_Env_Columns_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "132");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 132, "Columns should be 132");
      Assert (Size.Rows = 24, "Rows should default to 24");
   end Test_Env_Columns_Only;

   procedure Test_Env_Lines_Only (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "LINES", "50");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Columns should default to 80");
      Assert (Size.Rows = 50, "Rows should be 50");
   end Test_Env_Lines_Only;

   procedure Test_Env_Columns_Invalid_Non_Numeric (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "abc");
      Insert (Env, "LINES", "40");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Invalid COLUMNS should fall back to 80");
      Assert (Size.Rows = 40, "Valid LINES should be used");
   end Test_Env_Columns_Invalid_Non_Numeric;

   procedure Test_Env_Columns_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "0");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "COLUMNS=0 should fall back to 80");
   end Test_Env_Columns_Zero;

   procedure Test_Env_Columns_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Empty COLUMNS should fall back to 80");
   end Test_Env_Columns_Empty;

   procedure Test_Env_Columns_Negative (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "-1");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Negative COLUMNS should fall back to 80");
   end Test_Env_Columns_Negative;

   procedure Test_Env_Columns_Overflow (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "999999999999999");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 80, "Overflow COLUMNS should fall back to 80");
   end Test_Env_Columns_Overflow;

   procedure Test_Env_Lines_Invalid_Columns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "100");
      Insert (Env, "LINES", "not_a_number");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 100, "Valid COLUMNS should be used");
      Assert (Size.Rows = 24, "Invalid LINES should fall back to 24");
   end Test_Env_Lines_Invalid_Columns_Valid;

   procedure Test_Env_Case_Insensitive (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "columns", "100");
      Insert (Env, "lines", "30");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Columns = 100, "Lowercase 'columns' should work");
      Assert (Size.Rows = 30, "Lowercase 'lines' should work");
   end Test_Env_Case_Insensitive;

   ---------------------------------------------------------------------------
   --  FUNC-DIM-008: Pixel Dimensions
   ---------------------------------------------------------------------------

   procedure Test_Pixel_Dimensions_Zero_On_Env_Path (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Env  : Environment := EMPTY_ENVIRONMENT;
      Size : Terminal_Size;
   begin
      Insert (Env, "COLUMNS", "120");
      Insert (Env, "LINES", "40");
      Size := Get_Size (Env, Is_TTY => False);
      Assert (Size.Pixel_Width = 0, "Pixel width should be 0 on env var path");
      Assert (Size.Pixel_Height = 0, "Pixel height should be 0 on env var path");
   end Test_Pixel_Dimensions_Zero_On_Env_Path;

end Test_Dimensions;
