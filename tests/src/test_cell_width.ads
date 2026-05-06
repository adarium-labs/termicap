-------------------------------------------------------------------------------
--  Test_Cell_Width - Unit Tests for Termicap.Cell_Width and
--                   Termicap.Cell_Width.Tables
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the Cell_Width public API, Table_Version
--  enumeration, binary search lookup, ASCII fast path, control character
--  handling, special codepoints (ZWJ, VS16), combining characters, wide
--  characters, and the table structure exposed by Termicap.Cell_Width.Tables.
--
--  Note: Ghost predicates All_Widths_Valid and Is_Sorted_Non_Overlapping from
--  Termicap.Cell_Width.Tables cannot be called from non-ghost test code.  The
--  equivalent table invariants are verified via explicit loops in the test bodies.
--
--  Requirements Coverage:
--    - @relation(FUNC-CWM-001): Bundled Unicode width table versions
--    - @relation(FUNC-CWM-002): Codepoint range entry format
--    - @relation(FUNC-CWM-003): Binary search over sorted ranges
--    - @relation(FUNC-CWM-004): Table_Version enumeration
--    - @relation(FUNC-CWM-006): Default version = Table_Version'Last
--    - @relation(FUNC-CWM-007): ZWJ (U+200D) returns 0
--    - @relation(FUNC-CWM-008): VS16 (U+FE0F) returns 0
--    - @relation(FUNC-CWM-009): Combining characters return 0
--    - @relation(FUNC-CWM-010): ASCII printable fast path
--    - @relation(FUNC-CWM-011): Control characters return 0
--    - @relation(FUNC-CWM-012): Public API specification
--    - @relation(FUNC-CWM-015): O(log N) binary search correctness
--    - @relation(FUNC-CWM-016): Test coverage

with AUnit.Test_Cases;

package Test_Cell_Width is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-004: Table_Version Enumeration
   ---------------------------------------------------------------------------

   --  FUNC-CWM-004: Unicode_3 is Table_Version'First (smallest / oldest)
   procedure Test_Table_Version_Unicode3_Is_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-004: Unicode_16 is Table_Version'Last (largest / latest)
   procedure Test_Table_Version_Unicode16_Is_Last (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-004: ordering Unicode_3 < Unicode_13 < Unicode_16
   procedure Test_Table_Version_Ordering (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-006: Default Version Selection
   ---------------------------------------------------------------------------

   --  FUNC-CWM-006: Active_Version returns a valid Table_Version
   procedure Test_Active_Version_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-006: Active_Version is within Table_Version enumeration bounds
   procedure Test_Active_Version_In_Bounds (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-010: ASCII Printable Fast Path (U+0020..U+007E)
   ---------------------------------------------------------------------------

   --  FUNC-CWM-010: U+0020 SPACE returns 1
   procedure Test_ASCII_Space (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: U+0041 LATIN CAPITAL LETTER A returns 1
   procedure Test_ASCII_Capital_A (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: U+007E TILDE returns 1 (last ASCII printable)
   procedure Test_ASCII_Tilde (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: U+0021 EXCLAMATION MARK returns 1
   procedure Test_ASCII_Exclamation (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: U+0030 DIGIT ZERO returns 1
   procedure Test_ASCII_Digit_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: U+007A LATIN SMALL LETTER Z returns 1
   procedure Test_ASCII_Lower_Z (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: all ASCII printables return 1 (boundary sweep)
   procedure Test_ASCII_All_Printables (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: fast path applies regardless of table version (Unicode_3)
   procedure Test_ASCII_Fast_Path_All_Versions_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: fast path applies regardless of table version (Unicode_13)
   procedure Test_ASCII_Fast_Path_All_Versions_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-010: fast path applies regardless of table version (Unicode_16)
   procedure Test_ASCII_Fast_Path_All_Versions_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-011: Control Characters Return 0
   ---------------------------------------------------------------------------

   --  FUNC-CWM-011: U+0000 NUL returns 0
   procedure Test_Control_NUL (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+0009 TAB returns 0
   procedure Test_Control_TAB (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+000A LINE FEED returns 0
   procedure Test_Control_LF (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+000D CARRIAGE RETURN returns 0
   procedure Test_Control_CR (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+001B ESCAPE returns 0
   procedure Test_Control_ESC (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+001F UNIT SEPARATOR returns 0 (last C0 control)
   procedure Test_Control_US (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+007F DEL returns 0
   procedure Test_Control_DEL (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+0080 PAD (first C1 control) returns 0
   procedure Test_Control_C1_PAD (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+009F APPLICATION PROGRAM COMMAND (last C1) returns 0
   procedure Test_Control_C1_APC (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-011: U+0085 NEXT LINE (mid C1 range) returns 0
   procedure Test_Control_C1_NEL (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-007: ZWJ (U+200D) Returns 0
   ---------------------------------------------------------------------------

   --  FUNC-CWM-007: U+200D ZERO WIDTH JOINER returns 0 (active version)
   procedure Test_ZWJ_Active_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_3 table
   procedure Test_ZWJ_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_13 table
   procedure Test_ZWJ_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-007: U+200D ZWJ returns 0 with Unicode_16 table
   procedure Test_ZWJ_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-008: VS16 (U+FE0F) Returns 0
   ---------------------------------------------------------------------------

   --  FUNC-CWM-008: U+FE0F VARIATION SELECTOR-16 returns 0 (active version)
   procedure Test_VS16_Active_Version (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_3 table
   procedure Test_VS16_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_13 table
   procedure Test_VS16_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-008: U+FE0F VS16 returns 0 with Unicode_16 table
   procedure Test_VS16_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-009: Combining Characters (Category M) Return 0
   ---------------------------------------------------------------------------

   --  FUNC-CWM-009: U+0300 COMBINING GRAVE ACCENT returns 0
   procedure Test_Combining_Grave_Accent (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+036F COMBINING LATIN SMALL LETTER X returns 0 (end of CDM block)
   procedure Test_Combining_Latin_Small_X (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+0301 COMBINING ACUTE ACCENT returns 0
   procedure Test_Combining_Acute_Accent (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+20D0 COMBINING LEFT HARPOON ABOVE returns 0
   procedure Test_Combining_Left_Harpoon (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+0300 returns 0 with explicit Unicode_3 table
   procedure Test_Combining_Unicode3_Table (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+0300 returns 0 with explicit Unicode_13 table
   procedure Test_Combining_Unicode13_Table (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-009: U+0300 returns 0 with explicit Unicode_16 table
   procedure Test_Combining_Unicode16_Table (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Wide / Fullwidth Characters (FUNC-CWM-016 category 6)
   ---------------------------------------------------------------------------

   --  U+4E00 CJK UNIFIED IDEOGRAPH returns 2
   procedure Test_Wide_CJK_4E00 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+FF01 FULLWIDTH EXCLAMATION MARK returns 2
   procedure Test_Wide_Fullwidth_Exclamation (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+1F600 GRINNING FACE emoji returns 2
   procedure Test_Wide_Emoji_Grinning_Face (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+4E00 CJK returns 2 with Unicode_16 table (explicit)
   procedure Test_Wide_CJK_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+FF01 FULLWIDTH EXCLAMATION returns 2 with Unicode_13 table
   procedure Test_Wide_Fullwidth_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Narrow Non-ASCII Characters (FUNC-CWM-016 category 7)
   ---------------------------------------------------------------------------

   --  U+00E9 LATIN SMALL LETTER E WITH ACUTE returns 1
   procedure Test_Narrow_E_Acute (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+03B1 GREEK SMALL LETTER ALPHA returns 1
   procedure Test_Narrow_Greek_Alpha (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+00C0 LATIN CAPITAL LETTER A WITH GRAVE returns 1
   procedure Test_Narrow_A_Grave (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Version-Specific Boundary Codepoints (FUNC-CWM-016 category 8)
   ---------------------------------------------------------------------------

   --  U+28FF BRAILLE PATTERN DOTS-12345678 with Unicode_3 table returns 1
   procedure Test_Version_Braille_Unicode3 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+1FB38 with Unicode_13 table returns 1 (Legacy Computing block)
   procedure Test_Version_Sextant_Unicode13 (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  U+1CD00 with Unicode_16 table returns 1 (Legacy Computing Supplement)
   procedure Test_Version_Legacy_Supplement_Unicode16 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-003: Binary Search Edge Cases (FUNC-CWM-016 category 9)
   ---------------------------------------------------------------------------

   --  FUNC-CWM-003: codepoint U+0000 (minimum scalar) returns 0 (C0 control fast path)
   procedure Test_Binary_Search_Min_Codepoint (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-003: codepoint U+10FFFF (maximum scalar) returns a valid Cell_Width_Value
   procedure Test_Binary_Search_Max_Codepoint (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-003: codepoint not in any table range defaults to 1 (narrow)
   procedure Test_Binary_Search_Unmatched_Defaults_One (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-003: codepoint at first combining range boundary (U+0300 with U_3 table)
   procedure Test_Binary_Search_First_Range_Boundary (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-003: codepoint just before a known range returns 1 (U+02FF before CDM)
   procedure Test_Binary_Search_Before_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-003: codepoint just after last CDM entry (U+0370 after U+036F) returns 1
   procedure Test_Binary_Search_After_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-012: Public API — Both Overloads
   ---------------------------------------------------------------------------

   --  FUNC-CWM-012: single-argument Cell_Width compiles and returns valid value
   procedure Test_API_Single_Arg_Returns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-012: two-argument Cell_Width compiles and returns valid value
   procedure Test_API_Two_Arg_Returns_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-012: both overloads agree for the same codepoint and active version
   procedure Test_API_Both_Overloads_Agree (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-012: return value always in Cell_Width_Value range (0..2)
   procedure Test_API_Return_In_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-CWM-001/FUNC-CWM-002: Table Data Structure Invariants
   ---------------------------------------------------------------------------

   --  FUNC-CWM-001: TABLE_UNICODE_3 has at least one entry
   procedure Test_Table_Unicode3_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-001: TABLE_UNICODE_13 has at least one entry
   procedure Test_Table_Unicode13_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-001: TABLE_UNICODE_16 has at least one entry
   procedure Test_Table_Unicode16_Non_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_3 have Width in 0..2
   procedure Test_Table_Unicode3_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_13 have Width in 0..2
   procedure Test_Table_Unicode13_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_16 have Width in 0..2
   procedure Test_Table_Unicode16_Widths_Valid (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_3 have Last >= First
   procedure Test_Table_Unicode3_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_13 have Last >= First
   procedure Test_Table_Unicode13_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: All entries in TABLE_UNICODE_16 have Last >= First
   procedure Test_Table_Unicode16_Last_Ge_First (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: TABLE_UNICODE_3 is sorted (adjacent entries non-overlapping)
   procedure Test_Table_Unicode3_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: TABLE_UNICODE_13 is sorted (adjacent entries non-overlapping)
   procedure Test_Table_Unicode13_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-CWM-002: TABLE_UNICODE_16 is sorted (adjacent entries non-overlapping)
   procedure Test_Table_Unicode16_Sorted (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Cell_Width;
