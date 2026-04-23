-------------------------------------------------------------------------------
--  Test_Keyboard_Parsers - Unit Tests for Termicap.Keyboard Pure Parsers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the three pure SPARK parser functions in
--  Termicap.Keyboard: Parse_Kitty_Flags, Parse_Kitty_Response, and
--  Parse_XTerm_Keyboard_Response.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal; every test vector is deterministic.
--
--  Requirements Coverage:
--    - @relation(FUNC-KKB-005): Parse_Kitty_Flags (10 vectors)
--    - @relation(FUNC-KKB-006): Parse_Kitty_Response (12 vectors)
--    - @relation(FUNC-KKB-008): Parse_XTerm_Keyboard_Response (8 vectors)

with AUnit.Test_Cases;

package Test_Keyboard_Parsers is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-KKB-005: Parse_Kitty_Flags
   ---------------------------------------------------------------------------

   --  FUNC-KKB-005: flags = 0 -> all False
   procedure Test_Flags_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 1 -> Disambiguate_Escape_Codes = True, rest False
   procedure Test_Flags_Bit0_Disambiguate
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 2 -> Report_Event_Types = True, rest False
   procedure Test_Flags_Bit1_Event_Types
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 4 -> Report_Alternate_Keys = True, rest False
   procedure Test_Flags_Bit2_Alternate_Keys
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 8 -> Report_All_Keys_As_Escape = True, rest False
   procedure Test_Flags_Bit3_All_Keys_Escape
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 16 -> Report_Associated_Text = True, rest False
   procedure Test_Flags_Bit4_Associated_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 31 -> all five bits True
   procedure Test_Flags_All_Five_Bits
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 32 -> all False (bit 5 is ignored)
   procedure Test_Flags_Bit5_Ignored
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = 63 -> bits 0..4 True (bit 5 ignored) -> all five True
   procedure Test_Flags_63_High_Bit_Ignored
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-005: flags = Natural'Last -> high bits ignored, low bits per pattern
   procedure Test_Flags_Natural_Last
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-KKB-006: Parse_Kitty_Response
   ---------------------------------------------------------------------------

   --  FUNC-KKB-006: ESC [ ? u (4 bytes, no digits) -> Valid=True, Flags_Int=0
   procedure Test_Kitty_Bare_CSI_No_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? 1 u (5 bytes) -> Valid=True, Flags_Int=1
   procedure Test_Kitty_Flags_One
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? 3 1 u (6 bytes) -> Valid=True, Flags_Int=31
   procedure Test_Kitty_Flags_31
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? 1 0 0 u (7 bytes) -> Valid=True, Flags_Int=100
   procedure Test_Kitty_Flags_100
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: empty buffer (Length=0) -> Valid=False, Flags_Int=0
   procedure Test_Kitty_Empty_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? (3 bytes, truncated before 'u') -> Valid=False
   procedure Test_Kitty_Truncated_Three_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? 1 (4 bytes, digit but no 'u' terminator) -> Valid=False
   procedure Test_Kitty_Missing_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? x u (non-digit in flag position) -> Valid=False
   procedure Test_Kitty_Non_Digit_In_Flags
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ! u (wrong introducer byte '!' instead of '?') -> Valid=False
   procedure Test_Kitty_Wrong_Introducer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC P ? u (wrong CSI byte 'P' instead of '[') -> Valid=False
   procedure Test_Kitty_Wrong_CSI_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: ESC [ ? 1 m (wrong terminator 'm' instead of 'u') -> Valid=False
   procedure Test_Kitty_Wrong_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-006: mouse event prefix ESC [ M (garbage bytes) -> Valid=False
   procedure Test_Kitty_Mouse_Event_Garbage
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-KKB-008: Parse_XTerm_Keyboard_Response
   ---------------------------------------------------------------------------

   --  FUNC-KKB-008: ESC [ ? 4 ; 1 m (7 bytes, value=1) -> True
   procedure Test_XTerm_Value_1
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 ; 2 m (7 bytes, value=2) -> True
   procedure Test_XTerm_Value_2
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 ; 2 4 m (8 bytes, value=24) -> True
   procedure Test_XTerm_Value_24
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 ; m (6 bytes, no digits before 'm') -> False
   procedure Test_XTerm_No_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 m (5 bytes, no semicolon) -> False
   procedure Test_XTerm_No_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 ; x m (non-digit value byte) -> False
   procedure Test_XTerm_Non_Digit_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: ESC [ ? 4 ; 1 (6 bytes, no 'm' terminator) -> False
   procedure Test_XTerm_Missing_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-KKB-008: empty buffer (Length=0) -> False
   procedure Test_XTerm_Empty_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Keyboard_Parsers;
