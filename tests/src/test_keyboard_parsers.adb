-------------------------------------------------------------------------------
--  Test_Keyboard_Parsers - Unit Tests for Termicap.Keyboard Pure Parsers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;               use AUnit.Assertions;
with AUnit.Test_Cases.Registration;  use AUnit.Test_Cases.Registration;

with Termicap.Keyboard;              use Termicap.Keyboard;

package body Test_Keyboard_Parsers is

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   ESC_BYTE  : constant Byte := 16#1B#;  --  ESC  (0x1B)
   CSI_BYTE  : constant Byte := 16#5B#;  --  '['  (0x5B), CSI introducer
   QUES_BYTE : constant Byte := 16#3F#;  --  '?'  (0x3F), Kitty/XTerm discriminator
   U_BYTE    : constant Byte := 16#75#;  --  'u'  (0x75), Kitty response terminator
   M_BYTE    : constant Byte := 16#6D#;  --  'm'  (0x6D), XTerm response terminator
   SEMI_BYTE : constant Byte := 16#3B#;  --  ';'  (0x3B), XTerm separator
   FOUR_BYTE : constant Byte := 16#34#;  --  '4'  (0x34), XTerm private mode 4

   --  ASCII digit helpers
   D_0 : constant Byte := 16#30#;  --  '0'
   D_1 : constant Byte := 16#31#;  --  '1'
   D_2 : constant Byte := 16#32#;  --  '2'
   D_3 : constant Byte := 16#33#;  --  '3'
   D_4 : constant Byte := 16#34#;  --  '4'  (also used as FOUR_BYTE above)
   D_9 : constant Byte := 16#39#;  --  '9'

   --  Miscellaneous bytes used in malformed-input tests
   DCS_P_BYTE  : constant Byte := 16#50#;  --  'P'  (DCS introducer second byte)
   BANG_BYTE   : constant Byte := 16#21#;  --  '!'  wrong introducer for Kitty test
   X_BYTE      : constant Byte := 16#78#;  --  'x'  non-digit letter
   MOUSE_M     : constant Byte := 16#4D#;  --  'M'  mouse event introducer byte


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Keyboard parsers");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-KKB-005: Parse_Kitty_Flags
      Register_Routine (T, Test_Flags_Zero'Access,
         "FUNC-KKB-005: flags=0 -> all fields False");
      Register_Routine (T, Test_Flags_Bit0_Disambiguate'Access,
         "FUNC-KKB-005: flags=1 -> Disambiguate_Escape_Codes=True, rest False");
      Register_Routine (T, Test_Flags_Bit1_Event_Types'Access,
         "FUNC-KKB-005: flags=2 -> Report_Event_Types=True, rest False");
      Register_Routine (T, Test_Flags_Bit2_Alternate_Keys'Access,
         "FUNC-KKB-005: flags=4 -> Report_Alternate_Keys=True, rest False");
      Register_Routine (T, Test_Flags_Bit3_All_Keys_Escape'Access,
         "FUNC-KKB-005: flags=8 -> Report_All_Keys_As_Escape=True, rest False");
      Register_Routine (T, Test_Flags_Bit4_Associated_Text'Access,
         "FUNC-KKB-005: flags=16 -> Report_Associated_Text=True, rest False");
      Register_Routine (T, Test_Flags_All_Five_Bits'Access,
         "FUNC-KKB-005: flags=31 -> all five bits True");
      Register_Routine (T, Test_Flags_Bit5_Ignored'Access,
         "FUNC-KKB-005: flags=32 -> all False (bit 5 ignored)");
      Register_Routine (T, Test_Flags_63_High_Bit_Ignored'Access,
         "FUNC-KKB-005: flags=63 -> bits 0..4 True, bit 5 ignored -> all five True");
      Register_Routine (T, Test_Flags_Natural_Last'Access,
         "FUNC-KKB-005: flags=Natural'Last -> no exception, bits 0..4 per value pattern");

      --  FUNC-KKB-006: Parse_Kitty_Response
      Register_Routine (T, Test_Kitty_Bare_CSI_No_Digits'Access,
         "FUNC-KKB-006: ESC [ ? u (no digits) -> Valid=True, Flags_Int=0");
      Register_Routine (T, Test_Kitty_Flags_One'Access,
         "FUNC-KKB-006: ESC [ ? 1 u -> Valid=True, Flags_Int=1");
      Register_Routine (T, Test_Kitty_Flags_31'Access,
         "FUNC-KKB-006: ESC [ ? 3 1 u -> Valid=True, Flags_Int=31");
      Register_Routine (T, Test_Kitty_Flags_100'Access,
         "FUNC-KKB-006: ESC [ ? 1 0 0 u -> Valid=True, Flags_Int=100");
      Register_Routine (T, Test_Kitty_Empty_Buffer'Access,
         "FUNC-KKB-006: empty buffer (Length=0) -> Valid=False");
      Register_Routine (T, Test_Kitty_Truncated_Three_Bytes'Access,
         "FUNC-KKB-006: ESC [ ? (3 bytes, no 'u') -> Valid=False");
      Register_Routine (T, Test_Kitty_Missing_Terminator'Access,
         "FUNC-KKB-006: ESC [ ? 1 (digit, no 'u') -> Valid=False");
      Register_Routine (T, Test_Kitty_Non_Digit_In_Flags'Access,
         "FUNC-KKB-006: ESC [ ? x u (non-digit 'x') -> Valid=False");
      Register_Routine (T, Test_Kitty_Wrong_Introducer'Access,
         "FUNC-KKB-006: ESC [ ! u (wrong introducer '!') -> Valid=False");
      Register_Routine (T, Test_Kitty_Wrong_CSI_Byte'Access,
         "FUNC-KKB-006: ESC P ? u (wrong CSI byte 'P') -> Valid=False");
      Register_Routine (T, Test_Kitty_Wrong_Terminator'Access,
         "FUNC-KKB-006: ESC [ ? 1 m (wrong terminator 'm') -> Valid=False");
      Register_Routine (T, Test_Kitty_Mouse_Event_Garbage'Access,
         "FUNC-KKB-006: ESC [ M (mouse event prefix) -> Valid=False");

      --  FUNC-KKB-008: Parse_XTerm_Keyboard_Response
      Register_Routine (T, Test_XTerm_Value_1'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; 1 m (value=1) -> True");
      Register_Routine (T, Test_XTerm_Value_2'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; 2 m (value=2) -> True");
      Register_Routine (T, Test_XTerm_Value_24'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; 2 4 m (value=24) -> True");
      Register_Routine (T, Test_XTerm_No_Digits'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; m (no digits before 'm') -> False");
      Register_Routine (T, Test_XTerm_No_Semicolon'Access,
         "FUNC-KKB-008: ESC [ ? 4 m (no semicolon) -> False");
      Register_Routine (T, Test_XTerm_Non_Digit_Value'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; x m (non-digit 'x') -> False");
      Register_Routine (T, Test_XTerm_Missing_Terminator'Access,
         "FUNC-KKB-008: ESC [ ? 4 ; 1 (no 'm' terminator) -> False");
      Register_Routine (T, Test_XTerm_Empty_Buffer'Access,
         "FUNC-KKB-008: empty buffer (Length=0) -> False");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies: Parse_Kitty_Flags (FUNC-KKB-005)
   ---------------------------------------------------------------------------


   procedure Test_Flags_Zero
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 0: no bit is set; all five fields must be False.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (0);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (0): Disambiguate_Escape_Codes should be False");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (0): Report_Event_Types should be False");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (0): Report_Alternate_Keys should be False");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (0): Report_All_Keys_As_Escape should be False");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (0): Report_Associated_Text should be False");
   end Test_Flags_Zero;


   procedure Test_Flags_Bit0_Disambiguate
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 1 (bit 0): only Disambiguate_Escape_Codes must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (1);
   begin
      Assert (Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (1): Disambiguate_Escape_Codes should be True");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (1): Report_Event_Types should be False");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (1): Report_Alternate_Keys should be False");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (1): Report_All_Keys_As_Escape should be False");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (1): Report_Associated_Text should be False");
   end Test_Flags_Bit0_Disambiguate;


   procedure Test_Flags_Bit1_Event_Types
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 2 (bit 1): only Report_Event_Types must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (2);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (2): Disambiguate_Escape_Codes should be False");
      Assert (Result.Report_Event_Types,
              "Parse_Kitty_Flags (2): Report_Event_Types should be True");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (2): Report_Alternate_Keys should be False");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (2): Report_All_Keys_As_Escape should be False");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (2): Report_Associated_Text should be False");
   end Test_Flags_Bit1_Event_Types;


   procedure Test_Flags_Bit2_Alternate_Keys
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 4 (bit 2): only Report_Alternate_Keys must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (4);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (4): Disambiguate_Escape_Codes should be False");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (4): Report_Event_Types should be False");
      Assert (Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (4): Report_Alternate_Keys should be True");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (4): Report_All_Keys_As_Escape should be False");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (4): Report_Associated_Text should be False");
   end Test_Flags_Bit2_Alternate_Keys;


   procedure Test_Flags_Bit3_All_Keys_Escape
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 8 (bit 3): only Report_All_Keys_As_Escape must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (8);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (8): Disambiguate_Escape_Codes should be False");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (8): Report_Event_Types should be False");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (8): Report_Alternate_Keys should be False");
      Assert (Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (8): Report_All_Keys_As_Escape should be True");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (8): Report_Associated_Text should be False");
   end Test_Flags_Bit3_All_Keys_Escape;


   procedure Test_Flags_Bit4_Associated_Text
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 16 (bit 4): only Report_Associated_Text must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (16);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (16): Disambiguate_Escape_Codes should be False");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (16): Report_Event_Types should be False");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (16): Report_Alternate_Keys should be False");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (16): Report_All_Keys_As_Escape should be False");
      Assert (Result.Report_Associated_Text,
              "Parse_Kitty_Flags (16): Report_Associated_Text should be True");
   end Test_Flags_Bit4_Associated_Text;


   procedure Test_Flags_All_Five_Bits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 31 (bits 0..4 all set): every field must be True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (31);
   begin
      Assert (Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (31): Disambiguate_Escape_Codes should be True");
      Assert (Result.Report_Event_Types,
              "Parse_Kitty_Flags (31): Report_Event_Types should be True");
      Assert (Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (31): Report_Alternate_Keys should be True");
      Assert (Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (31): Report_All_Keys_As_Escape should be True");
      Assert (Result.Report_Associated_Text,
              "Parse_Kitty_Flags (31): Report_Associated_Text should be True");
   end Test_Flags_All_Five_Bits;


   procedure Test_Flags_Bit5_Ignored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 32 (bit 5 only): bits 0..4 are 0, so all fields must be False.
      --  Verifies the "bits >= 32 are ignored" contract in FUNC-KKB-005.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (32);
   begin
      Assert (not Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (32): Disambiguate_Escape_Codes should be False (bit 5 ignored)");
      Assert (not Result.Report_Event_Types,
              "Parse_Kitty_Flags (32): Report_Event_Types should be False (bit 5 ignored)");
      Assert (not Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (32): Report_Alternate_Keys should be False (bit 5 ignored)");
      Assert (not Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (32): Report_All_Keys_As_Escape should be False (bit 5 ignored)");
      Assert (not Result.Report_Associated_Text,
              "Parse_Kitty_Flags (32): Report_Associated_Text should be False (bit 5 ignored)");
   end Test_Flags_Bit5_Ignored;


   procedure Test_Flags_63_High_Bit_Ignored
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = 63 (bits 0..5): bit 5 is ignored; bits 0..4 all set.
      --  Result: all five defined fields True.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (63);
   begin
      Assert (Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (63): Disambiguate_Escape_Codes should be True");
      Assert (Result.Report_Event_Types,
              "Parse_Kitty_Flags (63): Report_Event_Types should be True");
      Assert (Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (63): Report_Alternate_Keys should be True");
      Assert (Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (63): Report_All_Keys_As_Escape should be True");
      Assert (Result.Report_Associated_Text,
              "Parse_Kitty_Flags (63): Report_Associated_Text should be True");
   end Test_Flags_63_High_Bit_Ignored;


   procedure Test_Flags_Natural_Last
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  flags = Natural'Last: must not raise; bits 0..4 of Natural'Last are all 1
      --  (since Natural'Last = 2**N - 1 for the platform word size; bits 0..4 = 1).
      --  All five fields must be True and no Constraint_Error must propagate.
      Result : constant Kitty_Flags := Parse_Kitty_Flags (Natural'Last);
   begin
      Assert (Result.Disambiguate_Escape_Codes,
              "Parse_Kitty_Flags (Natural'Last): Disambiguate_Escape_Codes should be True");
      Assert (Result.Report_Event_Types,
              "Parse_Kitty_Flags (Natural'Last): Report_Event_Types should be True");
      Assert (Result.Report_Alternate_Keys,
              "Parse_Kitty_Flags (Natural'Last): Report_Alternate_Keys should be True");
      Assert (Result.Report_All_Keys_As_Escape,
              "Parse_Kitty_Flags (Natural'Last): Report_All_Keys_As_Escape should be True");
      Assert (Result.Report_Associated_Text,
              "Parse_Kitty_Flags (Natural'Last): Report_Associated_Text should be True");
   end Test_Flags_Natural_Last;


   ---------------------------------------------------------------------------
   --  Test Bodies: Parse_Kitty_Response (FUNC-KKB-006)
   ---------------------------------------------------------------------------


   procedure Test_Kitty_Bare_CSI_No_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? u  — four bytes, zero digits between '?' and 'u'.
      --  Per FUNC-KKB-006: the parser REJECTS the bare form.  Real Kitty
      --  terminals always include at least one flag digit (e.g. ESC [ ? 0 u);
      --  accepting the bare form caused false-positive Kitty classifications
      --  on unrelated terminals that leaked probe bytes back.
      Buf    : constant Byte_Array (1 .. 4) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 4);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ? u): Valid should be False (bare form rejected)");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ? u): Flags_Int should be 0 when invalid");
   end Test_Kitty_Bare_CSI_No_Digits;


   procedure Test_Kitty_Flags_One
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 1 u  — five bytes, single digit '1'.
      Buf    : constant Byte_Array (1 .. 5) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 5);
   begin
      Assert (Result.Valid,
              "Parse_Kitty_Response (ESC [ ? 1 u): Valid should be True");
      Assert (Result.Flags_Int = 1,
              "Parse_Kitty_Response (ESC [ ? 1 u): Flags_Int should be 1");
   end Test_Kitty_Flags_One;


   procedure Test_Kitty_Flags_31
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 3 1 u  — six bytes, two-digit value "31".
      Buf    : constant Byte_Array (1 .. 6) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_3, D_1, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 6);
   begin
      Assert (Result.Valid,
              "Parse_Kitty_Response (ESC [ ? 3 1 u): Valid should be True");
      Assert (Result.Flags_Int = 31,
              "Parse_Kitty_Response (ESC [ ? 3 1 u): Flags_Int should be 31");
   end Test_Kitty_Flags_31;


   procedure Test_Kitty_Flags_100
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 1 0 0 u  — seven bytes, three-digit value "100".
      Buf    : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, D_0, D_0, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 7);
   begin
      Assert (Result.Valid,
              "Parse_Kitty_Response (ESC [ ? 1 0 0 u): Valid should be True");
      Assert (Result.Flags_Int = 100,
              "Parse_Kitty_Response (ESC [ ? 1 0 0 u): Flags_Int should be 100");
   end Test_Kitty_Flags_100;


   procedure Test_Kitty_Empty_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Length = 0: precondition 0 <= Buf'Length is satisfied; must return Valid=False.
      Buf    : constant Byte_Array (1 .. 4) := [others => 0];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 0);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (Length=0): Valid should be False");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (Length=0): Flags_Int should be 0 when Valid=False");
   end Test_Kitty_Empty_Buffer;


   procedure Test_Kitty_Truncated_Three_Bytes
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ?  — three bytes; minimum valid length is 4 (bare CSI ? u).
      --  Parser must return Valid=False without reading past Length.
      Buf    : constant Byte_Array (1 .. 3) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 3);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ?, Length=3): Valid should be False");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ?, Length=3): Flags_Int should be 0");
   end Test_Kitty_Truncated_Three_Bytes;


   procedure Test_Kitty_Missing_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 1  — four bytes but the last byte is '1' (a digit), not 'u'.
      --  Terminator check must fail -> Valid=False.
      Buf    : constant Byte_Array (1 .. 4) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 4);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ? 1, no 'u'): Valid should be False");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ? 1, no 'u'): Flags_Int should be 0");
   end Test_Kitty_Missing_Terminator;


   procedure Test_Kitty_Non_Digit_In_Flags
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? x u  — five bytes; 'x' (0x78) is not a decimal digit.
      --  Digit-scan must detect the non-digit and return Valid=False.
      Buf    : constant Byte_Array (1 .. 5) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, X_BYTE, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 5);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ? x u): Valid should be False (non-digit 'x')");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ? x u): Flags_Int should be 0");
   end Test_Kitty_Non_Digit_In_Flags;


   procedure Test_Kitty_Wrong_Introducer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ! u  — '!' (0x21) instead of '?' (0x3F) as introducer byte.
      --  Header check must fail at byte 3 -> Valid=False.
      Buf    : constant Byte_Array (1 .. 4) :=
        [ESC_BYTE, CSI_BYTE, BANG_BYTE, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 4);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ! u): Valid should be False (wrong introducer '!')");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ! u): Flags_Int should be 0");
   end Test_Kitty_Wrong_Introducer;


   procedure Test_Kitty_Wrong_CSI_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC P ? u  — 'P' (0x50) instead of '[' (0x5B) as CSI byte.
      --  Header check must fail at byte 2 -> Valid=False.
      Buf    : constant Byte_Array (1 .. 4) :=
        [ESC_BYTE, DCS_P_BYTE, QUES_BYTE, U_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 4);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC P ? u): Valid should be False (wrong CSI byte 'P')");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC P ? u): Flags_Int should be 0");
   end Test_Kitty_Wrong_CSI_Byte;


   procedure Test_Kitty_Wrong_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 1 m  — 'm' (0x6D) instead of 'u' (0x75) as terminator.
      --  Terminator check must fail -> Valid=False.
      Buf    : constant Byte_Array (1 .. 5) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, D_1, M_BYTE];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 5);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ ? 1 m): Valid should be False (wrong terminator 'm')");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ ? 1 m): Flags_Int should be 0");
   end Test_Kitty_Wrong_Terminator;


   procedure Test_Kitty_Mouse_Event_Garbage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ M <cb> <cx> <cy>  — six bytes of mouse event data.
      --  Byte 3 is 'M' (0x4D), not '?'; header check must fail -> Valid=False.
      Buf    : constant Byte_Array (1 .. 6) :=
        [ESC_BYTE, CSI_BYTE, MOUSE_M, D_4, D_2, D_9];
      Result : constant Parse_Result := Parse_Kitty_Response (Buf, 6);
   begin
      Assert (not Result.Valid,
              "Parse_Kitty_Response (ESC [ M ...): Valid should be False (mouse event prefix)");
      Assert (Result.Flags_Int = 0,
              "Parse_Kitty_Response (ESC [ M ...): Flags_Int should be 0");
   end Test_Kitty_Mouse_Event_Garbage;


   ---------------------------------------------------------------------------
   --  Test Bodies: Parse_XTerm_Keyboard_Response (FUNC-KKB-008)
   ---------------------------------------------------------------------------


   procedure Test_XTerm_Value_1
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; 1 m  — seven bytes, single digit value "1".
      --  Minimum well-formed XTerm modifyOtherKeys response.
      Buf : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, D_1, M_BYTE];
   begin
      Assert (Parse_XTerm_Keyboard_Response (Buf, 7),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; 1 m): should return True");
   end Test_XTerm_Value_1;


   procedure Test_XTerm_Value_2
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; 2 m  — seven bytes, value "2".
      Buf : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, D_2, M_BYTE];
   begin
      Assert (Parse_XTerm_Keyboard_Response (Buf, 7),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; 2 m): should return True");
   end Test_XTerm_Value_2;


   procedure Test_XTerm_Value_24
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; 2 4 m  — eight bytes, two-digit value "24".
      Buf : constant Byte_Array (1 .. 8) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, D_2, D_4, M_BYTE];
   begin
      Assert (Parse_XTerm_Keyboard_Response (Buf, 8),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; 2 4 m): should return True");
   end Test_XTerm_Value_24;


   procedure Test_XTerm_No_Digits
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; m  — six bytes; empty digits field violates <digits>+ constraint.
      --  Per FUNC-KKB-008: at least one digit is required -> False.
      Buf : constant Byte_Array (1 .. 6) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, M_BYTE];
   begin
      Assert (not Parse_XTerm_Keyboard_Response (Buf, 6),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; m, no digits): should return False");
   end Test_XTerm_No_Digits;


   procedure Test_XTerm_No_Semicolon
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 m  — five bytes; semicolon is absent.
      --  Header check for the ';' byte (position 5) must fail -> False.
      Buf : constant Byte_Array (1 .. 5) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, M_BYTE];
   begin
      Assert (not Parse_XTerm_Keyboard_Response (Buf, 5),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 m, no ';'): should return False");
   end Test_XTerm_No_Semicolon;


   procedure Test_XTerm_Non_Digit_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; x m  — seven bytes; 'x' (0x78) is not a decimal digit.
      --  Digit-scan must detect the non-digit -> False.
      Buf : constant Byte_Array (1 .. 7) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, X_BYTE, M_BYTE];
   begin
      Assert (not Parse_XTerm_Keyboard_Response (Buf, 7),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; x m): should return False (non-digit)");
   end Test_XTerm_Non_Digit_Value;


   procedure Test_XTerm_Missing_Terminator
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC [ ? 4 ; 1  — six bytes; 'm' terminator is absent.
      --  Terminator check must fail -> False.
      Buf : constant Byte_Array (1 .. 6) :=
        [ESC_BYTE, CSI_BYTE, QUES_BYTE, FOUR_BYTE, SEMI_BYTE, D_1];
   begin
      Assert (not Parse_XTerm_Keyboard_Response (Buf, 6),
              "Parse_XTerm_Keyboard_Response (ESC [ ? 4 ; 1, no 'm'): should return False");
   end Test_XTerm_Missing_Terminator;


   procedure Test_XTerm_Empty_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Length = 0: precondition 0 <= Buf'Length is satisfied; must return False.
      Buf : constant Byte_Array (1 .. 7) := [others => 0];
   begin
      Assert (not Parse_XTerm_Keyboard_Response (Buf, 0),
              "Parse_XTerm_Keyboard_Response (Length=0): should return False");
   end Test_XTerm_Empty_Buffer;

end Test_Keyboard_Parsers;
