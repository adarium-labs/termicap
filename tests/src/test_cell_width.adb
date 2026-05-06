-------------------------------------------------------------------------------
--  Test_Cell_Width - Unit Tests for Termicap.Cell_Width and
--                   Termicap.Cell_Width.Tables
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Termicap.Cell_Width;        use Termicap.Cell_Width;
with Termicap.Cell_Width.Tables; use Termicap.Cell_Width.Tables;

package body Test_Cell_Width is

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Cell_Width");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-CWM-004: Table_Version enumeration ordering
      Register_Routine
        (T, Test_Table_Version_Unicode3_Is_First'Access,
         "FUNC-CWM-004: Unicode_3 is Table_Version'First");
      Register_Routine
        (T, Test_Table_Version_Unicode16_Is_Last'Access,
         "FUNC-CWM-004: Unicode_16 is Table_Version'Last");
      Register_Routine
        (T, Test_Table_Version_Ordering'Access,
         "FUNC-CWM-004: ordering Unicode_3 < Unicode_13 < Unicode_16");

      --  FUNC-CWM-006: Default version selection
      Register_Routine
        (T, Test_Active_Version_Valid'Access,
         "FUNC-CWM-006: Active_Version returns a valid Table_Version");
      Register_Routine
        (T, Test_Active_Version_In_Bounds'Access,
         "FUNC-CWM-006: Active_Version is within Table_Version enumeration bounds");

      --  FUNC-CWM-010: ASCII printable fast path
      Register_Routine
        (T, Test_ASCII_Space'Access,
         "FUNC-CWM-010: U+0020 SPACE returns 1");
      Register_Routine
        (T, Test_ASCII_Capital_A'Access,
         "FUNC-CWM-010: U+0041 LATIN CAPITAL LETTER A returns 1");
      Register_Routine
        (T, Test_ASCII_Tilde'Access,
         "FUNC-CWM-010: U+007E TILDE returns 1 (last ASCII printable)");
      Register_Routine
        (T, Test_ASCII_Exclamation'Access,
         "FUNC-CWM-010: U+0021 EXCLAMATION MARK returns 1");
      Register_Routine
        (T, Test_ASCII_Digit_Zero'Access,
         "FUNC-CWM-010: U+0030 DIGIT ZERO returns 1");
      Register_Routine
        (T, Test_ASCII_Lower_Z'Access,
         "FUNC-CWM-010: U+007A LATIN SMALL LETTER Z returns 1");
      Register_Routine
        (T, Test_ASCII_All_Printables'Access,
         "FUNC-CWM-010: all codepoints U+0020..U+007E return 1");
      Register_Routine
        (T, Test_ASCII_Fast_Path_All_Versions_Unicode3'Access,
         "FUNC-CWM-010: ASCII fast path holds for Unicode_3 table");
      Register_Routine
        (T, Test_ASCII_Fast_Path_All_Versions_Unicode13'Access,
         "FUNC-CWM-010: ASCII fast path holds for Unicode_13 table");
      Register_Routine
        (T, Test_ASCII_Fast_Path_All_Versions_Unicode16'Access,
         "FUNC-CWM-010: ASCII fast path holds for Unicode_16 table");

      --  FUNC-CWM-011: Control characters return 0
      Register_Routine
        (T, Test_Control_NUL'Access,
         "FUNC-CWM-011: U+0000 NUL returns 0");
      Register_Routine
        (T, Test_Control_TAB'Access,
         "FUNC-CWM-011: U+0009 TAB returns 0");
      Register_Routine
        (T, Test_Control_LF'Access,
         "FUNC-CWM-011: U+000A LINE FEED returns 0");
      Register_Routine
        (T, Test_Control_CR'Access,
         "FUNC-CWM-011: U+000D CARRIAGE RETURN returns 0");
      Register_Routine
        (T, Test_Control_ESC'Access,
         "FUNC-CWM-011: U+001B ESCAPE returns 0");
      Register_Routine
        (T, Test_Control_US'Access,
         "FUNC-CWM-011: U+001F UNIT SEPARATOR returns 0 (last C0 control)");
      Register_Routine
        (T, Test_Control_DEL'Access,
         "FUNC-CWM-011: U+007F DEL returns 0");
      Register_Routine
        (T, Test_Control_C1_PAD'Access,
         "FUNC-CWM-011: U+0080 PAD (first C1 control) returns 0");
      Register_Routine
        (T, Test_Control_C1_APC'Access,
         "FUNC-CWM-011: U+009F APPLICATION PROGRAM COMMAND (last C1) returns 0");
      Register_Routine
        (T, Test_Control_C1_NEL'Access,
         "FUNC-CWM-011: U+0085 NEXT LINE (mid C1 range) returns 0");

      --  FUNC-CWM-007: ZWJ returns 0
      Register_Routine
        (T, Test_ZWJ_Active_Version'Access,
         "FUNC-CWM-007: U+200D ZWJ returns 0 (active version)");
      Register_Routine
        (T, Test_ZWJ_Unicode3'Access,
         "FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_3 table");
      Register_Routine
        (T, Test_ZWJ_Unicode13'Access,
         "FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_13 table");
      Register_Routine
        (T, Test_ZWJ_Unicode16'Access,
         "FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_16 table");

      --  FUNC-CWM-008: VS16 returns 0
      Register_Routine
        (T, Test_VS16_Active_Version'Access,
         "FUNC-CWM-008: U+FE0F VS16 returns 0 (active version)");
      Register_Routine
        (T, Test_VS16_Unicode3'Access,
         "FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_3 table");
      Register_Routine
        (T, Test_VS16_Unicode13'Access,
         "FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_13 table");
      Register_Routine
        (T, Test_VS16_Unicode16'Access,
         "FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_16 table");

      --  FUNC-CWM-009: Combining characters return 0
      Register_Routine
        (T, Test_Combining_Grave_Accent'Access,
         "FUNC-CWM-009: U+0300 COMBINING GRAVE ACCENT returns 0");
      Register_Routine
        (T, Test_Combining_Latin_Small_X'Access,
         "FUNC-CWM-009: U+036F COMBINING LATIN SMALL LETTER X returns 0");
      Register_Routine
        (T, Test_Combining_Acute_Accent'Access,
         "FUNC-CWM-009: U+0301 COMBINING ACUTE ACCENT returns 0");
      Register_Routine
        (T, Test_Combining_Left_Harpoon'Access,
         "FUNC-CWM-009: U+20D0 COMBINING LEFT HARPOON ABOVE returns 0");
      Register_Routine
        (T, Test_Combining_Unicode3_Table'Access,
         "FUNC-CWM-009: U+0300 returns 0 with Unicode_3 table");
      Register_Routine
        (T, Test_Combining_Unicode13_Table'Access,
         "FUNC-CWM-009: U+0300 returns 0 with Unicode_13 table");
      Register_Routine
        (T, Test_Combining_Unicode16_Table'Access,
         "FUNC-CWM-009: U+0300 returns 0 with Unicode_16 table");

      --  Wide / fullwidth characters (FUNC-CWM-016 category 6)
      Register_Routine
        (T, Test_Wide_CJK_4E00'Access,
         "FUNC-CWM-016: U+4E00 CJK UNIFIED IDEOGRAPH returns 2");
      Register_Routine
        (T, Test_Wide_Fullwidth_Exclamation'Access,
         "FUNC-CWM-016: U+FF01 FULLWIDTH EXCLAMATION MARK returns 2");
      Register_Routine
        (T, Test_Wide_Emoji_Grinning_Face'Access,
         "FUNC-CWM-016: U+1F600 GRINNING FACE emoji returns 2");
      Register_Routine
        (T, Test_Wide_CJK_Unicode16'Access,
         "FUNC-CWM-016: U+4E00 CJK returns 2 with Unicode_16 table");
      Register_Routine
        (T, Test_Wide_Fullwidth_Unicode13'Access,
         "FUNC-CWM-016: U+FF01 FULLWIDTH EXCLAMATION returns 2 with Unicode_13 table");

      --  Narrow non-ASCII characters (FUNC-CWM-016 category 7)
      Register_Routine
        (T, Test_Narrow_E_Acute'Access,
         "FUNC-CWM-016: U+00E9 LATIN SMALL LETTER E WITH ACUTE returns 1");
      Register_Routine
        (T, Test_Narrow_Greek_Alpha'Access,
         "FUNC-CWM-016: U+03B1 GREEK SMALL LETTER ALPHA returns 1");
      Register_Routine
        (T, Test_Narrow_A_Grave'Access,
         "FUNC-CWM-016: U+00C0 LATIN CAPITAL LETTER A WITH GRAVE returns 1");

      --  Version-specific boundary codepoints (FUNC-CWM-016 category 8)
      Register_Routine
        (T, Test_Version_Braille_Unicode3'Access,
         "FUNC-CWM-016: U+28FF BRAILLE PATTERN DOTS-12345678 with Unicode_3 returns 1");
      Register_Routine
        (T, Test_Version_Sextant_Unicode13'Access,
         "FUNC-CWM-016: U+1FB38 with Unicode_13 table returns 1");
      Register_Routine
        (T, Test_Version_Legacy_Supplement_Unicode16'Access,
         "FUNC-CWM-016: U+1CD00 with Unicode_16 table returns 1");

      --  FUNC-CWM-003: Binary search edge cases
      Register_Routine
        (T, Test_Binary_Search_Min_Codepoint'Access,
         "FUNC-CWM-003: U+0000 (minimum) returns 0 via C0 control path");
      Register_Routine
        (T, Test_Binary_Search_Max_Codepoint'Access,
         "FUNC-CWM-003: U+10FFFF (maximum) returns valid Cell_Width_Value");
      Register_Routine
        (T, Test_Binary_Search_Unmatched_Defaults_One'Access,
         "FUNC-CWM-003: codepoint not in any range defaults to 1 (narrow)");
      Register_Routine
        (T, Test_Binary_Search_First_Range_Boundary'Access,
         "FUNC-CWM-003: first combining range boundary returns 0");
      Register_Routine
        (T, Test_Binary_Search_Before_Range'Access,
         "FUNC-CWM-003: codepoint just before CDM range (U+02FF) returns 1");
      Register_Routine
        (T, Test_Binary_Search_After_Range'Access,
         "FUNC-CWM-003: codepoint just after CDM range (U+0370) returns 1");

      --  FUNC-CWM-012: Public API — both overloads
      Register_Routine
        (T, Test_API_Single_Arg_Returns_Valid'Access,
         "FUNC-CWM-012: single-argument Cell_Width returns valid Cell_Width_Value");
      Register_Routine
        (T, Test_API_Two_Arg_Returns_Valid'Access,
         "FUNC-CWM-012: two-argument Cell_Width returns valid Cell_Width_Value");
      Register_Routine
        (T, Test_API_Both_Overloads_Agree'Access,
         "FUNC-CWM-012: single-arg and two-arg overloads agree for same codepoint");
      Register_Routine
        (T, Test_API_Return_In_Range'Access,
         "FUNC-CWM-012: Cell_Width always returns value in 0..2 for sampled codepoints");

      --  FUNC-CWM-001/FUNC-CWM-002: Table data invariants
      Register_Routine
        (T, Test_Table_Unicode3_Non_Empty'Access,
         "FUNC-CWM-001: TABLE_UNICODE_3 has at least one entry");
      Register_Routine
        (T, Test_Table_Unicode13_Non_Empty'Access,
         "FUNC-CWM-001: TABLE_UNICODE_13 has at least one entry");
      Register_Routine
        (T, Test_Table_Unicode16_Non_Empty'Access,
         "FUNC-CWM-001: TABLE_UNICODE_16 has at least one entry");
      Register_Routine
        (T, Test_Table_Unicode3_Widths_Valid'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_3 entries have Width in 0..2");
      Register_Routine
        (T, Test_Table_Unicode13_Widths_Valid'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_13 entries have Width in 0..2");
      Register_Routine
        (T, Test_Table_Unicode16_Widths_Valid'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_16 entries have Width in 0..2");
      Register_Routine
        (T, Test_Table_Unicode3_Last_Ge_First'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_3 entries have Last >= First");
      Register_Routine
        (T, Test_Table_Unicode13_Last_Ge_First'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_13 entries have Last >= First");
      Register_Routine
        (T, Test_Table_Unicode16_Last_Ge_First'Access,
         "FUNC-CWM-002: all TABLE_UNICODE_16 entries have Last >= First");
      Register_Routine
        (T, Test_Table_Unicode3_Sorted'Access,
         "FUNC-CWM-002: TABLE_UNICODE_3 is sorted with non-overlapping ranges");
      Register_Routine
        (T, Test_Table_Unicode13_Sorted'Access,
         "FUNC-CWM-002: TABLE_UNICODE_13 is sorted with non-overlapping ranges");
      Register_Routine
        (T, Test_Table_Unicode16_Sorted'Access,
         "FUNC-CWM-002: TABLE_UNICODE_16 is sorted with non-overlapping ranges");
   end Register_Tests;

   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  FUNC-CWM-004: Table_Version Enumeration
   ---------------------------------------------------------------------------

   procedure Test_Table_Version_Unicode3_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Table_Version'First = Unicode_3,
         "Table_Version'First should be Unicode_3 (oldest/smallest version)");
   end Test_Table_Version_Unicode3_Is_First;

   procedure Test_Table_Version_Unicode16_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Table_Version'Last = Unicode_16,
         "Table_Version'Last should be Unicode_16 (latest bundled version)");
   end Test_Table_Version_Unicode16_Is_Last;

   procedure Test_Table_Version_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Verify the ordering via ordinal position (Table_Version'Pos).
      --  This is meaningful: if someone reorders the enum literals the ordinals change.
   begin
      Assert
        (Table_Version'Pos (Unicode_3) < Table_Version'Pos (Unicode_13),
         "Unicode_3 ordinal should be less than Unicode_13 ordinal");
      Assert
        (Table_Version'Pos (Unicode_13) < Table_Version'Pos (Unicode_16),
         "Unicode_13 ordinal should be less than Unicode_16 ordinal");
      Assert
        (Table_Version'Pos (Unicode_3) < Table_Version'Pos (Unicode_16),
         "Unicode_3 ordinal should be less than Unicode_16 ordinal");
   end Test_Table_Version_Ordering;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-006: Default Version Selection
   ---------------------------------------------------------------------------

   procedure Test_Active_Version_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Table_Version := Active_Version;
   begin
      --  When UNICODE_VERSION is not set, Active_Version defaults to Table_Version'Last
      --  (FUNC-CWM-006).  Verify that is the value returned under normal test conditions.
      Assert
        (V = Table_Version'Last,
         "Active_Version should equal Table_Version'Last when UNICODE_VERSION is not set");
   end Test_Active_Version_Valid;

   procedure Test_Active_Version_In_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      V : constant Table_Version := Active_Version;
   begin
      --  Verify Active_Version is at least Table_Version'First (non-negative ordinal check).
      Assert
        (Table_Version'Pos (V) >= Table_Version'Pos (Table_Version'First),
         "Active_Version ordinal should be >= Table_Version'First ordinal");
      Assert
        (Table_Version'Pos (V) <= Table_Version'Pos (Table_Version'Last),
         "Active_Version ordinal should be <= Table_Version'Last ordinal");
   end Test_Active_Version_In_Bounds;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-010: ASCII Printable Fast Path (U+0020..U+007E)
   ---------------------------------------------------------------------------

   procedure Test_ASCII_Space (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0020#) = 1, "U+0020 SPACE should have cell width 1");
   end Test_ASCII_Space;

   procedure Test_ASCII_Capital_A (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0041#) = 1, "U+0041 LATIN CAPITAL LETTER A should have cell width 1");
   end Test_ASCII_Capital_A;

   procedure Test_ASCII_Tilde (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#007E#) = 1, "U+007E TILDE should have cell width 1 (last ASCII printable)");
   end Test_ASCII_Tilde;

   procedure Test_ASCII_Exclamation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0021#) = 1, "U+0021 EXCLAMATION MARK should have cell width 1");
   end Test_ASCII_Exclamation;

   procedure Test_ASCII_Digit_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0030#) = 1, "U+0030 DIGIT ZERO should have cell width 1");
   end Test_ASCII_Digit_Zero;

   procedure Test_ASCII_Lower_Z (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#007A#) = 1, "U+007A LATIN SMALL LETTER Z should have cell width 1");
   end Test_ASCII_Lower_Z;

   procedure Test_ASCII_All_Printables (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Sweep all ASCII printable codepoints U+0020..U+007E.
      --  Each must return exactly 1 (the fast-path result).
      for CP in 16#0020# .. 16#007E# loop
         Assert
           (Cell_Width (CP) = 1,
            "Every codepoint in U+0020..U+007E should have cell width 1 (ASCII fast path)");
      end loop;
   end Test_ASCII_All_Printables;

   procedure Test_ASCII_Fast_Path_All_Versions_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0020#, Unicode_3) = 1,
         "U+0020 SPACE should return 1 with Unicode_3 table (ASCII fast path is version-independent)");
      Assert
        (Cell_Width (16#0041#, Unicode_3) = 1,
         "U+0041 'A' should return 1 with Unicode_3 table");
      Assert
        (Cell_Width (16#007E#, Unicode_3) = 1,
         "U+007E TILDE should return 1 with Unicode_3 table");
   end Test_ASCII_Fast_Path_All_Versions_Unicode3;

   procedure Test_ASCII_Fast_Path_All_Versions_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0020#, Unicode_13) = 1,
         "U+0020 SPACE should return 1 with Unicode_13 table (ASCII fast path is version-independent)");
      Assert
        (Cell_Width (16#0041#, Unicode_13) = 1,
         "U+0041 'A' should return 1 with Unicode_13 table");
      Assert
        (Cell_Width (16#007E#, Unicode_13) = 1,
         "U+007E TILDE should return 1 with Unicode_13 table");
   end Test_ASCII_Fast_Path_All_Versions_Unicode13;

   procedure Test_ASCII_Fast_Path_All_Versions_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0020#, Unicode_16) = 1,
         "U+0020 SPACE should return 1 with Unicode_16 table (ASCII fast path is version-independent)");
      Assert
        (Cell_Width (16#0041#, Unicode_16) = 1,
         "U+0041 'A' should return 1 with Unicode_16 table");
      Assert
        (Cell_Width (16#007E#, Unicode_16) = 1,
         "U+007E TILDE should return 1 with Unicode_16 table");
   end Test_ASCII_Fast_Path_All_Versions_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-011: Control Characters Return 0
   ---------------------------------------------------------------------------

   procedure Test_Control_NUL (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0000#) = 0, "U+0000 NUL should have cell width 0");
   end Test_Control_NUL;

   procedure Test_Control_TAB (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0009#) = 0, "U+0009 TAB should have cell width 0");
   end Test_Control_TAB;

   procedure Test_Control_LF (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#000A#) = 0, "U+000A LINE FEED should have cell width 0");
   end Test_Control_LF;

   procedure Test_Control_CR (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#000D#) = 0, "U+000D CARRIAGE RETURN should have cell width 0");
   end Test_Control_CR;

   procedure Test_Control_ESC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#001B#) = 0, "U+001B ESCAPE should have cell width 0");
   end Test_Control_ESC;

   procedure Test_Control_US (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#001F#) = 0, "U+001F UNIT SEPARATOR should have cell width 0 (last C0 control)");
   end Test_Control_US;

   procedure Test_Control_DEL (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#007F#) = 0, "U+007F DEL should have cell width 0");
   end Test_Control_DEL;

   procedure Test_Control_C1_PAD (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0080#) = 0, "U+0080 PAD (first C1 control) should have cell width 0");
   end Test_Control_C1_PAD;

   procedure Test_Control_C1_APC (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#009F#) = 0, "U+009F APPLICATION PROGRAM COMMAND (last C1) should have cell width 0");
   end Test_Control_C1_APC;

   procedure Test_Control_C1_NEL (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Cell_Width (16#0085#) = 0, "U+0085 NEXT LINE (C1 control) should have cell width 0");
   end Test_Control_C1_NEL;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-007: ZWJ (U+200D) Returns 0
   ---------------------------------------------------------------------------

   procedure Test_ZWJ_Active_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#200D#) = 0,
         "U+200D ZERO WIDTH JOINER should have cell width 0 (active table version)");
   end Test_ZWJ_Active_Version;

   procedure Test_ZWJ_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#200D#, Unicode_3) = 0,
         "U+200D ZWJ should have cell width 0 with Unicode_3 table");
   end Test_ZWJ_Unicode3;

   procedure Test_ZWJ_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#200D#, Unicode_13) = 0,
         "U+200D ZWJ should have cell width 0 with Unicode_13 table");
   end Test_ZWJ_Unicode13;

   procedure Test_ZWJ_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#200D#, Unicode_16) = 0,
         "U+200D ZWJ should have cell width 0 with Unicode_16 table");
   end Test_ZWJ_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-008: VS16 (U+FE0F) Returns 0
   ---------------------------------------------------------------------------

   procedure Test_VS16_Active_Version (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FE0F#) = 0,
         "U+FE0F VARIATION SELECTOR-16 should have cell width 0 (active table version)");
   end Test_VS16_Active_Version;

   procedure Test_VS16_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FE0F#, Unicode_3) = 0,
         "U+FE0F VS16 should have cell width 0 with Unicode_3 table");
   end Test_VS16_Unicode3;

   procedure Test_VS16_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FE0F#, Unicode_13) = 0,
         "U+FE0F VS16 should have cell width 0 with Unicode_13 table");
   end Test_VS16_Unicode13;

   procedure Test_VS16_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FE0F#, Unicode_16) = 0,
         "U+FE0F VS16 should have cell width 0 with Unicode_16 table");
   end Test_VS16_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-009: Combining Characters (Category M) Return 0
   ---------------------------------------------------------------------------

   procedure Test_Combining_Grave_Accent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0300#) = 0,
         "U+0300 COMBINING GRAVE ACCENT should have cell width 0");
   end Test_Combining_Grave_Accent;

   procedure Test_Combining_Latin_Small_X (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#036F#) = 0,
         "U+036F COMBINING LATIN SMALL LETTER X should have cell width 0 (end of CDM block)");
   end Test_Combining_Latin_Small_X;

   procedure Test_Combining_Acute_Accent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0301#) = 0,
         "U+0301 COMBINING ACUTE ACCENT should have cell width 0");
   end Test_Combining_Acute_Accent;

   procedure Test_Combining_Left_Harpoon (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#20D0#) = 0,
         "U+20D0 COMBINING LEFT HARPOON ABOVE should have cell width 0");
   end Test_Combining_Left_Harpoon;

   procedure Test_Combining_Unicode3_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0300#, Unicode_3) = 0,
         "U+0300 COMBINING GRAVE ACCENT should have cell width 0 with Unicode_3 table");
   end Test_Combining_Unicode3_Table;

   procedure Test_Combining_Unicode13_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0300#, Unicode_13) = 0,
         "U+0300 COMBINING GRAVE ACCENT should have cell width 0 with Unicode_13 table");
   end Test_Combining_Unicode13_Table;

   procedure Test_Combining_Unicode16_Table (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#0300#, Unicode_16) = 0,
         "U+0300 COMBINING GRAVE ACCENT should have cell width 0 with Unicode_16 table");
   end Test_Combining_Unicode16_Table;

   ---------------------------------------------------------------------------
   --  Wide / Fullwidth Characters (FUNC-CWM-016 category 6)
   ---------------------------------------------------------------------------

   procedure Test_Wide_CJK_4E00 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#4E00#) = 2,
         "U+4E00 CJK UNIFIED IDEOGRAPH-4E00 should have cell width 2");
   end Test_Wide_CJK_4E00;

   procedure Test_Wide_Fullwidth_Exclamation (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FF01#) = 2,
         "U+FF01 FULLWIDTH EXCLAMATION MARK should have cell width 2");
   end Test_Wide_Fullwidth_Exclamation;

   procedure Test_Wide_Emoji_Grinning_Face (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#1F600#) = 2,
         "U+1F600 GRINNING FACE emoji should have cell width 2");
   end Test_Wide_Emoji_Grinning_Face;

   procedure Test_Wide_CJK_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#4E00#, Unicode_16) = 2,
         "U+4E00 CJK UNIFIED IDEOGRAPH should have cell width 2 with Unicode_16 table");
   end Test_Wide_CJK_Unicode16;

   procedure Test_Wide_Fullwidth_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#FF01#, Unicode_13) = 2,
         "U+FF01 FULLWIDTH EXCLAMATION MARK should have cell width 2 with Unicode_13 table");
   end Test_Wide_Fullwidth_Unicode13;

   ---------------------------------------------------------------------------
   --  Narrow Non-ASCII Characters (FUNC-CWM-016 category 7)
   ---------------------------------------------------------------------------

   procedure Test_Narrow_E_Acute (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#00E9#) = 1,
         "U+00E9 LATIN SMALL LETTER E WITH ACUTE should have cell width 1");
   end Test_Narrow_E_Acute;

   procedure Test_Narrow_Greek_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#03B1#) = 1,
         "U+03B1 GREEK SMALL LETTER ALPHA should have cell width 1");
   end Test_Narrow_Greek_Alpha;

   procedure Test_Narrow_A_Grave (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Cell_Width (16#00C0#) = 1,
         "U+00C0 LATIN CAPITAL LETTER A WITH GRAVE should have cell width 1");
   end Test_Narrow_A_Grave;

   ---------------------------------------------------------------------------
   --  Version-Specific Boundary Codepoints (FUNC-CWM-016 category 8)
   ---------------------------------------------------------------------------

   procedure Test_Version_Braille_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+28FF BRAILLE PATTERN DOTS-12345678 was introduced in Unicode 3.0.
      --  It is a narrow character (width 1) in all table versions.
      Assert
        (Cell_Width (16#28FF#, Unicode_3) = 1,
         "U+28FF BRAILLE PATTERN DOTS-12345678 should have cell width 1 with Unicode_3 table");
   end Test_Version_Braille_Unicode3;

   procedure Test_Version_Sextant_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+1FB38 is in the Symbols for Legacy Computing block introduced in Unicode 13.0.
      --  It is a narrow character (width 1).
      Assert
        (Cell_Width (16#1FB38#, Unicode_13) = 1,
         "U+1FB38 (Legacy Computing block, Unicode 13.0) should have cell width 1 with Unicode_13 table");
   end Test_Version_Sextant_Unicode13;

   procedure Test_Version_Legacy_Supplement_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+1CD00 is in the Symbols for Legacy Computing Supplement introduced in Unicode 16.0.
      --  It is a narrow character (width 1).
      Assert
        (Cell_Width (16#1CD00#, Unicode_16) = 1,
         "U+1CD00 (Legacy Computing Supplement, Unicode 16.0) should have cell width 1 with Unicode_16 table");
   end Test_Version_Legacy_Supplement_Unicode16;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-003: Binary Search Edge Cases
   ---------------------------------------------------------------------------

   procedure Test_Binary_Search_Min_Codepoint (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+0000 is the minimum Unicode scalar value; it falls in the C0 control
      --  fast-path (U+0000..U+001F) and returns 0 before any binary search.
      Assert
        (Cell_Width (0) = 0,
         "U+0000 NUL (minimum codepoint) should have cell width 0 via C0 control fast path");
   end Test_Binary_Search_Min_Codepoint;

   procedure Test_Binary_Search_Max_Codepoint (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      W : constant Cell_Width_Value := Cell_Width (16#10_FFFF#);
   begin
      --  U+10FFFF is the maximum Unicode scalar value; the binary search must not
      --  overflow or access out-of-bounds memory.  The exact width is not
      --  specified by this test (it depends on table content) but must be 0, 1, or 2.
      Assert
        (W = 0 or else W = 1 or else W = 2,
         "U+10FFFF (maximum codepoint) should return 0, 1, or 2");
   end Test_Binary_Search_Max_Codepoint;

   procedure Test_Binary_Search_Unmatched_Defaults_One (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+FFFFF is a high private-use codepoint unlikely to appear in any width
      --  table.  The binary search should return the default narrow width of 1.
      Assert
        (Cell_Width (16#FFFFF#) = 1,
         "U+FFFFF (unmatched codepoint) should default to cell width 1 (narrow)");
   end Test_Binary_Search_Unmatched_Defaults_One;

   procedure Test_Binary_Search_First_Range_Boundary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+0300 is at the start of the Combining Diacritical Marks range
      --  (U+0300..U+036F), which is the first (or one of the first) entries in the
      --  Unicode_3 table.  Verifying it returns 0 exercises the binary search at
      --  the lower table boundary.
      Assert
        (Cell_Width (16#0300#, Unicode_3) = 0,
         "U+0300 at first CDM range boundary should have cell width 0 (binary search lower boundary)");
   end Test_Binary_Search_First_Range_Boundary;

   procedure Test_Binary_Search_Before_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+02FF is just before the Combining Diacritical Marks block (U+0300..U+036F).
      --  It should not fall in any zero-width or wide range and must return 1.
      Assert
        (Cell_Width (16#02FF#, Unicode_3) = 1,
         "U+02FF (just before CDM range U+0300) should have cell width 1 (default narrow)");
   end Test_Binary_Search_Before_Range;

   procedure Test_Binary_Search_After_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+0370 is just after the Combining Diacritical Marks block (U+0300..U+036F).
      --  It is the start of Greek and Coptic block, a narrow character (width 1).
      Assert
        (Cell_Width (16#0370#, Unicode_3) = 1,
         "U+0370 (just after CDM range U+036F) should have cell width 1 (default narrow)");
   end Test_Binary_Search_After_Range;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-012: Public API — Both Overloads
   ---------------------------------------------------------------------------

   procedure Test_API_Single_Arg_Returns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+0041 'A' is ASCII printable and must return 1.  This verifies the
      --  single-argument overload compiles and executes without raising an exception.
      Assert
        (Cell_Width (16#0041#) = 1,
         "Single-argument Cell_Width (U+0041 'A') should return 1");
   end Test_API_Single_Arg_Returns_Valid;

   procedure Test_API_Two_Arg_Returns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  U+0041 'A' is ASCII printable and must return 1 regardless of version.
      --  This verifies the two-argument overload compiles and executes correctly.
      Assert
        (Cell_Width (16#0041#, Unicode_16) = 1,
         "Two-argument Cell_Width (U+0041 'A', Unicode_16) should return 1");
   end Test_API_Two_Arg_Returns_Valid;

   procedure Test_API_Both_Overloads_Agree (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  When called with Active_Version as the explicit version, both overloads
      --  must return the same result for the same codepoint.
      V  : constant Table_Version   := Active_Version;
      W1 : constant Cell_Width_Value := Cell_Width (16#4E00#);
      W2 : constant Cell_Width_Value := Cell_Width (16#4E00#, V);
   begin
      Assert
        (W1 = W2,
         "Cell_Width(CP) and Cell_Width(CP, Active_Version) should return the same value");
   end Test_API_Both_Overloads_Agree;

   procedure Test_API_Return_In_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Spot-check a representative set of codepoints across all categories to
      --  verify the return value is always 0, 1, or 2.
      Codepoints : constant array (1 .. 14) of Unicode_Scalar_Value :=
        [16#0000#, 16#001F#, 16#0020#, 16#007E#, 16#007F#, 16#0080#, 16#009F#,
         16#0300#, 16#200D#, 16#FE0F#, 16#4E00#, 16#FF01#, 16#1F600#, 16#10_FFFF#];
   begin
      for CP of Codepoints loop
         declare
            W : constant Cell_Width_Value := Cell_Width (CP);
         begin
            Assert
              (W = 0 or else W = 1 or else W = 2,
               "Cell_Width should always return 0, 1, or 2");
         end;
      end loop;
   end Test_API_Return_In_Range;

   ---------------------------------------------------------------------------
   --  FUNC-CWM-001/FUNC-CWM-002: Table Data Structure Invariants
   ---------------------------------------------------------------------------

   procedure Test_Table_Unicode3_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TABLE_UNICODE_3'Length > 0,
         "TABLE_UNICODE_3 should contain at least one width entry");
   end Test_Table_Unicode3_Non_Empty;

   procedure Test_Table_Unicode13_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TABLE_UNICODE_13'Length > 0,
         "TABLE_UNICODE_13 should contain at least one width entry");
   end Test_Table_Unicode13_Non_Empty;

   procedure Test_Table_Unicode16_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (TABLE_UNICODE_16'Length > 0,
         "TABLE_UNICODE_16 should contain at least one width entry");
   end Test_Table_Unicode16_Non_Empty;

   procedure Test_Table_Unicode3_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  All_Widths_Valid is a ghost predicate (not callable from test code).
      --  Verify the same invariant via an explicit loop.
      for I in TABLE_UNICODE_3'Range loop
         Assert
           (TABLE_UNICODE_3 (I).Width = 0
            or else TABLE_UNICODE_3 (I).Width = 1
            or else TABLE_UNICODE_3 (I).Width = 2,
            "TABLE_UNICODE_3: entry Width should be in 0..2");
         Assert
           (TABLE_UNICODE_3 (I).Last >= TABLE_UNICODE_3 (I).First,
            "TABLE_UNICODE_3: entry Last should be >= First");
      end loop;
   end Test_Table_Unicode3_Widths_Valid;

   procedure Test_Table_Unicode13_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_13'Range loop
         Assert
           (TABLE_UNICODE_13 (I).Width = 0
            or else TABLE_UNICODE_13 (I).Width = 1
            or else TABLE_UNICODE_13 (I).Width = 2,
            "TABLE_UNICODE_13: entry Width should be in 0..2");
         Assert
           (TABLE_UNICODE_13 (I).Last >= TABLE_UNICODE_13 (I).First,
            "TABLE_UNICODE_13: entry Last should be >= First");
      end loop;
   end Test_Table_Unicode13_Widths_Valid;

   procedure Test_Table_Unicode16_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_16'Range loop
         Assert
           (TABLE_UNICODE_16 (I).Width = 0
            or else TABLE_UNICODE_16 (I).Width = 1
            or else TABLE_UNICODE_16 (I).Width = 2,
            "TABLE_UNICODE_16: entry Width should be in 0..2");
         Assert
           (TABLE_UNICODE_16 (I).Last >= TABLE_UNICODE_16 (I).First,
            "TABLE_UNICODE_16: entry Last should be >= First");
      end loop;
   end Test_Table_Unicode16_Widths_Valid;

   procedure Test_Table_Unicode3_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  All_Widths_Valid already checks Last >= First; verify this explicitly via
      --  a loop so the assertion message is unambiguous about which invariant fails.
      for I in TABLE_UNICODE_3'Range loop
         Assert
           (TABLE_UNICODE_3 (I).Last >= TABLE_UNICODE_3 (I).First,
            "TABLE_UNICODE_3: entry Last should be >= First for all entries");
      end loop;
   end Test_Table_Unicode3_Last_Ge_First;

   procedure Test_Table_Unicode13_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_13'Range loop
         Assert
           (TABLE_UNICODE_13 (I).Last >= TABLE_UNICODE_13 (I).First,
            "TABLE_UNICODE_13: entry Last should be >= First for all entries");
      end loop;
   end Test_Table_Unicode13_Last_Ge_First;

   procedure Test_Table_Unicode16_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_16'Range loop
         Assert
           (TABLE_UNICODE_16 (I).Last >= TABLE_UNICODE_16 (I).First,
            "TABLE_UNICODE_16: entry Last should be >= First for all entries");
      end loop;
   end Test_Table_Unicode16_Last_Ge_First;

   procedure Test_Table_Unicode3_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      --  Is_Sorted_Non_Overlapping is a ghost predicate (not callable from test code).
      --  Verify the same invariant: for all adjacent entries I and I+1, Last(I) < First(I+1).
      for I in TABLE_UNICODE_3'First .. Table_Index'Pred (TABLE_UNICODE_3'Last) loop
         Assert
           (TABLE_UNICODE_3 (I).Last < TABLE_UNICODE_3 (Table_Index'Succ (I)).First,
            "TABLE_UNICODE_3: adjacent entries should be sorted with Last(I) < First(I+1)");
      end loop;
   end Test_Table_Unicode3_Sorted;

   procedure Test_Table_Unicode13_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_13'First .. Table_Index'Pred (TABLE_UNICODE_13'Last) loop
         Assert
           (TABLE_UNICODE_13 (I).Last < TABLE_UNICODE_13 (Table_Index'Succ (I)).First,
            "TABLE_UNICODE_13: adjacent entries should be sorted with Last(I) < First(I+1)");
      end loop;
   end Test_Table_Unicode13_Sorted;

   procedure Test_Table_Unicode16_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      for I in TABLE_UNICODE_16'First .. Table_Index'Pred (TABLE_UNICODE_16'Last) loop
         Assert
           (TABLE_UNICODE_16 (I).Last < TABLE_UNICODE_16 (Table_Index'Succ (I)).First,
            "TABLE_UNICODE_16: adjacent entries should be sorted with Last(I) < First(I+1)");
      end loop;
   end Test_Table_Unicode16_Sorted;

end Test_Cell_Width;
