-------------------------------------------------------------------------------
--  Termicap.Cell_Width - Cell Width Measurement Tables (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Implements Cell_Width using precomputed Unicode width tables.
--
--  @description
--  This body is SPARK_Mode => Off throughout because it uses
--  Ada.Environment_Variables for the UNICODE_VERSION env var read, which
--  performs OS I/O that is outside the SPARK subset.
--
--  The env var read (Read_Unicode_Version) is called exactly once at
--  elaboration time, storing the result in the body-level constant
--  Active_Version_Value.  All subsequent calls to Cell_Width and
--  Active_Version read only that constant, which never changes after
--  elaboration.
--
--  Requirements Coverage:
--    - @relation(FUNC-CWM-005): UNICODE_VERSION env var parsing
--    - @relation(FUNC-CWM-006): Default to Table_Version'Last
--    - @relation(FUNC-CWM-010): ASCII printable fast path
--    - @relation(FUNC-CWM-011): Control characters return 0
--    - @relation(FUNC-CWM-012): Public API dispatch

with Ada.Environment_Variables;

with Termicap.Cell_Width.Tables; use Termicap.Cell_Width.Tables;

package body Termicap.Cell_Width
  with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Elaboration-time environment variable read (FUNC-CWM-005)
   ---------------------------------------------------------------------------

   --  Read UNICODE_VERSION env var and map to Table_Version.
   --  Recognised values: "3", "3.0" -> Unicode_3
   --                     "13", "13.0" -> Unicode_13
   --                     "16", "16.0" -> Unicode_16
   --  Absent or unrecognised value -> Table_Version'Last (FUNC-CWM-006).
   function Read_Unicode_Version return Table_Version is
   begin
      if not Ada.Environment_Variables.Exists ("UNICODE_VERSION") then
         return Table_Version'Last;
      end if;

      declare
         Value : constant String :=
           Ada.Environment_Variables.Value ("UNICODE_VERSION");
      begin
         if Value'Length = 0 then
            return Table_Version'Last;
         end if;

         if Value = "3" or else Value = "3.0" then
            return Unicode_3;
         elsif Value = "13" or else Value = "13.0" then
            return Unicode_13;
         elsif Value = "16" or else Value = "16.0" then
            return Unicode_16;
         else
            return Table_Version'Last;
         end if;
      end;
   end Read_Unicode_Version;

   --  Body-level constant: set once at elaboration time, never changes.
   --  Subsequent calls to Active_Version read this constant; the Global => null
   --  contract in the spec is justified because the value is fixed for the
   --  process lifetime after elaboration.
   Active_Version_Value : constant Table_Version := Read_Unicode_Version;

   ---------------------------------------------------------------------------
   --  Public API (FUNC-CWM-005, FUNC-CWM-006, FUNC-CWM-010, FUNC-CWM-011,
   --              FUNC-CWM-012)
   ---------------------------------------------------------------------------

   function Active_Version return Table_Version is
   begin
      return Active_Version_Value;
   end Active_Version;

   function Cell_Width
     (Codepoint : Unicode_Scalar_Value) return Cell_Width_Value is
   begin
      return Cell_Width (Codepoint, Active_Version_Value);
   end Cell_Width;

   function Cell_Width
     (Codepoint : Unicode_Scalar_Value; Version : Table_Version)
      return Cell_Width_Value is
   begin
      --  Step 1: ASCII printable fast path (FUNC-CWM-010)
      --  U+0020..U+007E are the printable ASCII characters.  They all have
      --  width 1 and are the most common codepoints in typical terminal output.
      if Codepoint in 16#0020# .. 16#007E# then
         return 1;
      end if;

      --  Step 2: C0 control characters (FUNC-CWM-011)
      --  U+0000..U+001F: NUL, TAB, LF, CR, ESC, and the remaining C0 controls.
      if Codepoint in 16#0000# .. 16#001F# then
         return 0;
      end if;

      --  Step 3: DEL (FUNC-CWM-011)
      if Codepoint = 16#007F# then
         return 0;
      end if;

      --  Step 4: C1 control characters (FUNC-CWM-011)
      --  U+0080..U+009F: PAD through APC; include NEL (U+0085).
      if Codepoint in 16#0080# .. 16#009F# then
         return 0;
      end if;

      --  Step 5: Binary search over version-specific width table (FUNC-CWM-003)
      return Cell_Width_In_Table (Codepoint, Get_Table (Version));
   end Cell_Width;

end Termicap.Cell_Width;
