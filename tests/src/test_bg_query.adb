-------------------------------------------------------------------------------
--  Test_BG_Query - Unit Tests for Termicap.Color.BG_Query
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Cases; use AUnit.Test_Cases.Registration;

with Interfaces.C; use Interfaces.C;

with Termicap.Color.BG_Query; use Termicap.Color.BG_Query;

package body Test_BG_Query is

   ---------------------------------------------------------------------------
   --  Byte constant helpers
   ---------------------------------------------------------------------------

   ESC_BYTE : constant Byte := 16#1B#;  --  ESC (0x1B)
   OSC_RBKT : constant Byte := 16#5D#;  --  ] (0x5D), OSC introducer second byte
   ST_BACK  : constant Byte := 16#5C#;  --  \ (0x5C), ST second byte
   BEL_BYTE : constant Byte := 16#07#;  --  BEL (0x07)
   SEMI     : constant Byte := 16#3B#;  --  ; (0x3B)
   SLASH    : constant Byte := 16#2F#;  --  / (0x2F)
   DIG_0    : constant Byte := 16#30#;  --  '0'
   DIG_1    : constant Byte := 16#31#;  --  '1'
   CHR_r    : constant Byte := 16#72#;  --  'r'
   CHR_g    : constant Byte := 16#67#;  --  'g'
   CHR_b    : constant Byte := 16#62#;  --  'b'
   CHR_a    : constant Byte := 16#61#;  --  'a'
   CHR_CLON : constant Byte := 16#3A#;  --  ':'
   HEX_F    : constant Byte := 16#46#;  --  'F' (uppercase)
   HEX_LOWF : constant Byte := 16#66#;  --  'f' (lowercase)
   HEX_8    : constant Byte := 16#38#;  --  '8'
   HEX_G    : constant Byte := 16#47#;  --  'G' (invalid hex)
   HEX_A    : constant Byte := 16#41#;  --  'A'
   HEX_B    : constant Byte := 16#42#;  --  'B'


   overriding function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Color.BG_Query");
   end Name;


   overriding procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-BGC-005: Query_Sequence
      Register_Routine (T, Test_Query_Sequence_BG_Length'Access,
         "FUNC-BGC-005: Background -> OSC_BG_QUERY length = 8");
      Register_Routine (T, Test_Query_Sequence_FG_Length'Access,
         "FUNC-BGC-005: Foreground -> OSC_FG_QUERY length = 8");
      Register_Routine (T, Test_Query_Sequence_BG_Starts_With_ESC_Bracket'Access,
         "FUNC-BGC-005: Background result starts with ESC ] (0x1B 0x5D)");
      Register_Routine (T, Test_Query_Sequence_FG_Has_Zero_At_Position_4'Access,
         "FUNC-BGC-005: Foreground result has '0' at position 4");

      --  FUNC-BGC-009: Parse_Hex_Channel
      Register_Routine (T, Test_Parse_Hex_Channel_FF_Two_Digit'Access,
         "FUNC-BGC-009: 2-digit FF -> Success, Value=255");
      Register_Routine (T, Test_Parse_Hex_Channel_00_Two_Digit'Access,
         "FUNC-BGC-009: 2-digit 00 -> Success, Value=0");
      Register_Routine (T, Test_Parse_Hex_Channel_80_Two_Digit'Access,
         "FUNC-BGC-009: 2-digit 80 -> Success, Value=128");
      Register_Routine (T, Test_Parse_Hex_Channel_FFFF_Four_Digit'Access,
         "FUNC-BGC-009: 4-digit FFFF -> Success, Value=255");
      Register_Routine (T, Test_Parse_Hex_Channel_8080_Four_Digit'Access,
         "FUNC-BGC-009: 4-digit 8080 -> Success, Value=128");
      Register_Routine (T, Test_Parse_Hex_Channel_0000_Four_Digit'Access,
         "FUNC-BGC-009: 4-digit 0000 -> Success, Value=0");
      Register_Routine (T, Test_Parse_Hex_Channel_F_One_Digit'Access,
         "FUNC-BGC-009: 1-digit F -> Success, Value=255 (F*17)");
      Register_Routine (T, Test_Parse_Hex_Channel_FFF_Three_Digit'Access,
         "FUNC-BGC-009: 3-digit FFF -> Success, Value=255 (FFF/16)");
      Register_Routine (T, Test_Parse_Hex_Channel_Lowercase_ff'Access,
         "FUNC-BGC-009: lowercase ff -> Success, Value=255");
      Register_Routine (T, Test_Parse_Hex_Channel_Non_Hex_GG'Access,
         "FUNC-BGC-009: non-hex GG -> Success=False");
      Register_Routine (T, Test_Parse_Hex_Channel_Mixed_Case_aB'Access,
         "FUNC-BGC-009: mixed case aB -> Success, Value=171");

      --  FUNC-BGC-008: Find_RGB_Prefix
      Register_Routine (T, Test_Find_RGB_Prefix_Found_RGB'Access,
         "FUNC-BGC-008: buffer with rgb: -> Found=True, Offset after colon");
      Register_Routine (T, Test_Find_RGB_Prefix_Found_RGBA'Access,
         "FUNC-BGC-008: buffer with rgba: -> Found=True, Offset after colon");
      Register_Routine (T, Test_Find_RGB_Prefix_Not_Found'Access,
         "FUNC-BGC-008: buffer without rgb: -> Found=False");
      Register_Routine (T, Test_Find_RGB_Prefix_Empty_Buffer'Access,
         "FUNC-BGC-008: empty buffer (Length=0) -> Found=False");
      Register_Routine (T, Test_Find_RGB_Prefix_No_Colon'Access,
         "FUNC-BGC-008: buffer with rgb but no colon -> Found=False");

      --  FUNC-BGC-008: Split_RGB_Channels
      Register_Routine (T, Test_Split_RGB_Channels_Two_Digit'Access,
         "FUNC-BGC-008: FF/FF/FF -> Success, three slices length 2");
      Register_Routine (T, Test_Split_RGB_Channels_Four_Digit'Access,
         "FUNC-BGC-008: FFFF/FFFF/FFFF -> Success, three slices length 4");
      Register_Routine (T, Test_Split_RGB_Channels_One_Slash'Access,
         "FUNC-BGC-008: FF/FF (one slash) -> Success=False");
      Register_Routine (T, Test_Split_RGB_Channels_Four_Channels'Access,
         "FUNC-BGC-008: FF/FF/FF/AA (rgba) -> Success, first three channels");
      Register_Routine (T, Test_Split_RGB_Channels_No_Slash'Access,
         "FUNC-BGC-008: FF (no slash) -> Success=False");

      --  FUNC-BGC-007: Parse_RGB_Response
      Register_Routine (T, Test_Parse_RGB_Response_All_Max'Access,
         "FUNC-BGC-007: rgb:FFFF/FFFF/FFFF -> Success, Color=(255,255,255)");
      Register_Routine (T, Test_Parse_RGB_Response_All_Zero'Access,
         "FUNC-BGC-007: rgb:0000/0000/0000 -> Success, Color=(0,0,0)");
      Register_Routine (T, Test_Parse_RGB_Response_Mid_Value'Access,
         "FUNC-BGC-007: rgb:8080/8080/8080 -> Success, Color=(128,128,128)");
      Register_Routine (T, Test_Parse_RGB_Response_RGBA'Access,
         "FUNC-BGC-007: rgba:FFFF/FFFF/FFFF/FFFF -> Success, Color=(255,255,255)");
      Register_Routine (T, Test_Parse_RGB_Response_Malformed_Channel'Access,
         "FUNC-BGC-007: rgb:GGGG/FFFF/FFFF -> Success=False");
      Register_Routine (T, Test_Parse_RGB_Response_Empty'Access,
         "FUNC-BGC-007: empty buffer -> Success=False");
      Register_Routine (T, Test_Parse_RGB_Response_Two_Digit'Access,
         "FUNC-BGC-007: rgb:FF/FF/FF (2-digit) -> Success, Color=(255,255,255)");

      --  FUNC-BGC-010: Strip_OSC_Header
      Register_Routine (T, Test_Strip_OSC_Header_BG_ST_Terminated'Access,
         "FUNC-BGC-010: BG ESC ] 1 1 ; ... ESC \\ -> Success, correct payload");
      Register_Routine (T, Test_Strip_OSC_Header_FG_ST_Terminated'Access,
         "FUNC-BGC-010: FG ESC ] 1 0 ; ... ESC \\ -> Success, correct payload");
      Register_Routine (T, Test_Strip_OSC_Header_BG_BEL_Terminated'Access,
         "FUNC-BGC-010: BG BEL-terminated -> Success");
      Register_Routine (T, Test_Strip_OSC_Header_Wrong_Kind'Access,
         "FUNC-BGC-010: BG header but Kind=Foreground -> Success=False");
      Register_Routine (T, Test_Strip_OSC_Header_Too_Short'Access,
         "FUNC-BGC-010: fewer than 5 bytes -> Success=False");
      Register_Routine (T, Test_Strip_OSC_Header_Missing_ESC'Access,
         "FUNC-BGC-010: missing ESC ] prefix -> Success=False");
      Register_Routine (T, Test_Strip_OSC_Header_Empty_Buffer'Access,
         "FUNC-BGC-010: empty buffer (Length=0) -> Success=False");

      --  FUNC-BGC-011: Parse_Colorfgbg
      Register_Routine (T, Test_Parse_Colorfgbg_Zero_Fifteen'Access,
         "FUNC-BGC-011: 0;15 -> Success, FG=0, BG=15");
      Register_Routine (T, Test_Parse_Colorfgbg_Seven_Zero'Access,
         "FUNC-BGC-011: 7;0 -> Success, FG=7, BG=0");
      Register_Routine (T, Test_Parse_Colorfgbg_Three_Fields'Access,
         "FUNC-BGC-011: 7;8;0 -> Success, FG=7, BG=0");
      Register_Routine (T, Test_Parse_Colorfgbg_FG_Out_Of_Range'Access,
         "FUNC-BGC-011: 16;0 -> Success=False (FG out of range)");
      Register_Routine (T, Test_Parse_Colorfgbg_BG_Out_Of_Range'Access,
         "FUNC-BGC-011: 0;16 -> Success=False (BG out of range)");
      Register_Routine (T, Test_Parse_Colorfgbg_Empty'Access,
         "FUNC-BGC-011: empty string -> Success=False");
      Register_Routine (T, Test_Parse_Colorfgbg_No_Semicolon'Access,
         "FUNC-BGC-011: no semicolon -> Success=False");
      Register_Routine (T, Test_Parse_Colorfgbg_Single_Value'Access,
         "FUNC-BGC-011: single value 7 -> Success=False");

      --  FUNC-BGC-012: Ansi_To_RGB
      Register_Routine (T, Test_Ansi_To_RGB_Index_0_Black'Access,
         "FUNC-BGC-012: Index 0 -> (0,0,0) Black");
      Register_Routine (T, Test_Ansi_To_RGB_Index_7_Light_Grey'Access,
         "FUNC-BGC-012: Index 7 -> (192,192,192) Light Grey");
      Register_Routine (T, Test_Ansi_To_RGB_Index_9_Bright_Red'Access,
         "FUNC-BGC-012: Index 9 -> (255,0,0) Bright Red");
      Register_Routine (T, Test_Ansi_To_RGB_Index_15_White'Access,
         "FUNC-BGC-012: Index 15 -> (255,255,255) White");

      --  FUNC-BGC-001: ANSI_COLOR_TABLE and constants
      Register_Routine (T, Test_Color_Table_Index_0_Equals_Default_BG'Access,
         "FUNC-BGC-001: ANSI_COLOR_TABLE(0) = DEFAULT_BACKGROUND = (0,0,0)");
      Register_Routine (T, Test_Default_Foreground_Value'Access,
         "FUNC-BGC-001: DEFAULT_FOREGROUND = (170,170,170)");
      Register_Routine (T, Test_Color_Table_Length'Access,
         "FUNC-BGC-001: ANSI_COLOR_TABLE'Length = 16");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  Test Bodies
   ---------------------------------------------------------------------------


   ---------------------------------------------------------------------------
   --  FUNC-BGC-005: Query_Sequence
   ---------------------------------------------------------------------------


   procedure Test_Query_Sequence_BG_Length
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Seq : constant Byte_Array := Query_Sequence (Background);
   begin
      Assert
         (Seq'Length = 8,
          "Query_Sequence(Background) length should be 8");
   end Test_Query_Sequence_BG_Length;


   procedure Test_Query_Sequence_FG_Length
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Seq : constant Byte_Array := Query_Sequence (Foreground);
   begin
      Assert
         (Seq'Length = 8,
          "Query_Sequence(Foreground) length should be 8");
   end Test_Query_Sequence_FG_Length;


   procedure Test_Query_Sequence_BG_Starts_With_ESC_Bracket
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Seq : constant Byte_Array := Query_Sequence (Background);
   begin
      Assert
         (Seq (Seq'First) = ESC_BYTE
          and then Seq (Seq'First + 1) = OSC_RBKT,
          "Query_Sequence(Background) should start with ESC ] (0x1B 0x5D)");
   end Test_Query_Sequence_BG_Starts_With_ESC_Bracket;


   procedure Test_Query_Sequence_FG_Has_Zero_At_Position_4
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  OSC_FG_QUERY: ESC ] 1 0 ; ? ESC \
      --  Position 4 (1-based relative to array start) is the '0' digit
      Seq : constant Byte_Array := Query_Sequence (Foreground);
   begin
      Assert
         (Seq (Seq'First + 3) = DIG_0,
          "Query_Sequence(Foreground) should have '0' (0x30) at position 4 "
          & "and then distinguishing it from Background '1'");
   end Test_Query_Sequence_FG_Has_Zero_At_Position_4;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-009: Parse_Hex_Channel
   ---------------------------------------------------------------------------


   procedure Test_Parse_Hex_Channel_FF_Two_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FF" -> 255
      Buf    : constant Byte_Array (1 .. 2) := [HEX_F, HEX_F];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel FF (2-digit) should succeed");
      Assert
         (Result.Value = 255,
          "Parse_Hex_Channel FF (2-digit) should return 255");
   end Test_Parse_Hex_Channel_FF_Two_Digit;


   procedure Test_Parse_Hex_Channel_00_Two_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "00" -> 0
      Buf    : constant Byte_Array (1 .. 2) := [DIG_0, DIG_0];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel 00 (2-digit) should succeed");
      Assert
         (Result.Value = 0,
          "Parse_Hex_Channel 00 (2-digit) should return 0");
   end Test_Parse_Hex_Channel_00_Two_Digit;


   procedure Test_Parse_Hex_Channel_80_Two_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "80" -> 128
      Buf    : constant Byte_Array (1 .. 2) := [HEX_8, DIG_0];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel 80 (2-digit) should succeed");
      Assert
         (Result.Value = 128,
          "Parse_Hex_Channel 80 (2-digit) should return 128");
   end Test_Parse_Hex_Channel_80_Two_Digit;


   procedure Test_Parse_Hex_Channel_FFFF_Four_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FFFF" -> 255 (high byte of 0xFFFF)
      Buf    : constant Byte_Array (1 .. 4) := [HEX_F, HEX_F, HEX_F, HEX_F];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 4);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel FFFF (4-digit) should succeed");
      Assert
         (Result.Value = 255,
          "Parse_Hex_Channel FFFF (4-digit) should return 255 (high byte)");
   end Test_Parse_Hex_Channel_FFFF_Four_Digit;


   procedure Test_Parse_Hex_Channel_8080_Four_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "8080" -> 128 (0x8080 / 256 = 0x80 = 128)
      Buf    : constant Byte_Array (1 .. 4) := [HEX_8, DIG_0, HEX_8, DIG_0];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 4);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel 8080 (4-digit) should succeed");
      Assert
         (Result.Value = 128,
          "Parse_Hex_Channel 8080 (4-digit) should return 128 (high byte)");
   end Test_Parse_Hex_Channel_8080_Four_Digit;


   procedure Test_Parse_Hex_Channel_0000_Four_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "0000" -> 0
      Buf    : constant Byte_Array (1 .. 4) := [DIG_0, DIG_0, DIG_0, DIG_0];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 4);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel 0000 (4-digit) should succeed");
      Assert
         (Result.Value = 0,
          "Parse_Hex_Channel 0000 (4-digit) should return 0");
   end Test_Parse_Hex_Channel_0000_Four_Digit;


   procedure Test_Parse_Hex_Channel_F_One_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "F" -> 255 (F = 15, 15 * 17 = 255)
      Buf    : constant Byte_Array (1 .. 1) := [HEX_F];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 1);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel F (1-digit) should succeed");
      Assert
         (Result.Value = 255,
          "Parse_Hex_Channel F (1-digit) should return 255 (15 * 17)");
   end Test_Parse_Hex_Channel_F_One_Digit;


   procedure Test_Parse_Hex_Channel_FFF_Three_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FFF" -> 255 (0xFFF = 4095, 4095 / 16 = 255)
      Buf    : constant Byte_Array (1 .. 3) := [HEX_F, HEX_F, HEX_F];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 3);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel FFF (3-digit) should succeed");
      Assert
         (Result.Value = 255,
          "Parse_Hex_Channel FFF (3-digit) should return 255 (0xFFF / 16)");
   end Test_Parse_Hex_Channel_FFF_Three_Digit;


   procedure Test_Parse_Hex_Channel_Lowercase_ff
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "ff" -> 255 (lowercase hex accepted)
      Buf    : constant Byte_Array (1 .. 2) := [HEX_LOWF, HEX_LOWF];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel ff (lowercase) should succeed");
      Assert
         (Result.Value = 255,
          "Parse_Hex_Channel ff (lowercase) should return 255");
   end Test_Parse_Hex_Channel_Lowercase_ff;


   procedure Test_Parse_Hex_Channel_Non_Hex_GG
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "GG" -> not valid hex digits
      Buf    : constant Byte_Array (1 .. 2) := [HEX_G, HEX_G];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (not Result.Success,
          "Parse_Hex_Channel GG (non-hex) should fail");
   end Test_Parse_Hex_Channel_Non_Hex_GG;


   procedure Test_Parse_Hex_Channel_Mixed_Case_aB
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "aB" -> 0xAB = 171
      Buf    : constant Byte_Array (1 .. 2) := [CHR_a, HEX_B];
      Result : constant Channel_Result := Parse_Hex_Channel (Buf, 1, 2);
   begin
      Assert
         (Result.Success,
          "Parse_Hex_Channel aB (mixed case) should succeed");
      Assert
         (Result.Value = 171,
          "Parse_Hex_Channel aB (mixed case) should return 171 (0xAB)");
   end Test_Parse_Hex_Channel_Mixed_Case_aB;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-008: Find_RGB_Prefix
   ---------------------------------------------------------------------------


   procedure Test_Find_RGB_Prefix_Found_RGB
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:FF/FF/FF" -> Found = True, Offset points after ":"
      --  r=0x72 g=0x67 b=0x62 :=0x3A F=0x46 /=0x2F
      Buf : constant Byte_Array (1 .. 12) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          HEX_F, HEX_F, SLASH, HEX_F, HEX_F, SLASH, HEX_F, HEX_F];
      Offset : Natural;
      Found  : Boolean;
   begin
      Find_RGB_Prefix (Buf, Buf'Length, Offset, Found);
      Assert
         (Found,
          "Find_RGB_Prefix with 'rgb:FF/FF/FF' should set Found=True");
      Assert
         (Offset = 5,
          "Find_RGB_Prefix with 'rgb:' should set Offset to 5 (first byte after colon)");
   end Test_Find_RGB_Prefix_Found_RGB;


   procedure Test_Find_RGB_Prefix_Found_RGBA
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgba:FF/FF/FF/FF" -> Found = True, Offset after "rgba:"
      Buf : constant Byte_Array (1 .. 16) :=
         [CHR_r, CHR_g, CHR_b, CHR_a, CHR_CLON,
          HEX_F, HEX_F, SLASH, HEX_F, HEX_F, SLASH, HEX_F, HEX_F, SLASH, HEX_F, HEX_F];
      Offset : Natural;
      Found  : Boolean;
   begin
      Find_RGB_Prefix (Buf, Buf'Length, Offset, Found);
      Assert
         (Found,
          "Find_RGB_Prefix with 'rgba:FF/FF/FF/FF' should set Found=True");
      Assert
         (Offset = 6,
          "Find_RGB_Prefix with 'rgba:' should set Offset to 6 (first byte after colon)");
   end Test_Find_RGB_Prefix_Found_RGBA;


   procedure Test_Find_RGB_Prefix_Not_Found
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FFFFFF" -- no rgb: prefix
      Buf : constant Byte_Array (1 .. 6) :=
         [HEX_F, HEX_F, HEX_F, HEX_F, HEX_F, HEX_F];
      Offset : Natural;
      Found  : Boolean;
   begin
      Find_RGB_Prefix (Buf, Buf'Length, Offset, Found);
      Assert
         (not Found,
          "Find_RGB_Prefix with no 'rgb:' prefix should set Found=False");
   end Test_Find_RGB_Prefix_Not_Found;


   procedure Test_Find_RGB_Prefix_Empty_Buffer
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Empty scan (Length = 0)
      Buf : constant Byte_Array (1 .. 4) := [CHR_r, CHR_g, CHR_b, CHR_CLON];
      Offset : Natural;
      Found  : Boolean;
   begin
      Find_RGB_Prefix (Buf, 0, Offset, Found);
      Assert
         (not Found,
          "Find_RGB_Prefix with Length=0 should set Found=False");
   end Test_Find_RGB_Prefix_Empty_Buffer;


   procedure Test_Find_RGB_Prefix_No_Colon
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgbX" -- no colon after rgb
      Buf : constant Byte_Array (1 .. 4) := [CHR_r, CHR_g, CHR_b, HEX_A];
      Offset : Natural;
      Found  : Boolean;
   begin
      Find_RGB_Prefix (Buf, Buf'Length, Offset, Found);
      Assert
         (not Found,
          "Find_RGB_Prefix with 'rgb' but no colon should set Found=False");
   end Test_Find_RGB_Prefix_No_Colon;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-008: Split_RGB_Channels
   ---------------------------------------------------------------------------


   procedure Test_Split_RGB_Channels_Two_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FF/FF/FF" -> three slices of length 2 each
      Buf : constant Byte_Array (1 .. 8) :=
         [HEX_F, HEX_F, SLASH, HEX_F, HEX_F, SLASH, HEX_F, HEX_F];
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Success          : Boolean;
   begin
      Split_RGB_Channels (Buf, 1, 8, Ch_R, Ch_G, Ch_B, Success);
      Assert
         (Success,
          "Split_RGB_Channels 'FF/FF/FF' should succeed");
      Assert
         (Ch_R.Length = 2 and then Ch_G.Length = 2 and then Ch_B.Length = 2,
          "Split_RGB_Channels 'FF/FF/FF' should give three slices of length 2");
   end Test_Split_RGB_Channels_Two_Digit;


   procedure Test_Split_RGB_Channels_Four_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FFFF/FFFF/FFFF" -> three slices of length 4 each
      Buf : constant Byte_Array (1 .. 14) :=
         [HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F];
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Success          : Boolean;
   begin
      Split_RGB_Channels (Buf, 1, 14, Ch_R, Ch_G, Ch_B, Success);
      Assert
         (Success,
          "Split_RGB_Channels 'FFFF/FFFF/FFFF' should succeed");
      Assert
         (Ch_R.Length = 4 and then Ch_G.Length = 4 and then Ch_B.Length = 4,
          "Split_RGB_Channels 'FFFF/FFFF/FFFF' should give three slices of length 4");
   end Test_Split_RGB_Channels_Four_Digit;


   procedure Test_Split_RGB_Channels_One_Slash
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FF/FF" -- only one slash, insufficient for three channels
      Buf : constant Byte_Array (1 .. 5) :=
         [HEX_F, HEX_F, SLASH, HEX_F, HEX_F];
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Success          : Boolean;
   begin
      Split_RGB_Channels (Buf, 1, 5, Ch_R, Ch_G, Ch_B, Success);
      Assert
         (not Success,
          "Split_RGB_Channels 'FF/FF' (one slash) should fail");
   end Test_Split_RGB_Channels_One_Slash;


   procedure Test_Split_RGB_Channels_Four_Channels
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FF/FF/FF/AA" -- rgba with four fields, first three extracted
      Buf : constant Byte_Array (1 .. 11) :=
         [HEX_F, HEX_F, SLASH, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, SLASH, HEX_A, HEX_A];
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Success          : Boolean;
   begin
      Split_RGB_Channels (Buf, 1, 11, Ch_R, Ch_G, Ch_B, Success);
      Assert
         (Success,
          "Split_RGB_Channels 'FF/FF/FF/AA' (four channels) should succeed");
      Assert
         (Ch_R.Length = 2 and then Ch_G.Length = 2 and then Ch_B.Length = 2,
          "Split_RGB_Channels 'FF/FF/FF/AA' should extract first three channels of length 2");
   end Test_Split_RGB_Channels_Four_Channels;


   procedure Test_Split_RGB_Channels_No_Slash
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "FF" -- no slash at all
      Buf : constant Byte_Array (1 .. 2) := [HEX_F, HEX_F];
      Ch_R, Ch_G, Ch_B : Channel_Slice;
      Success          : Boolean;
   begin
      Split_RGB_Channels (Buf, 1, 2, Ch_R, Ch_G, Ch_B, Success);
      Assert
         (not Success,
          "Split_RGB_Channels 'FF' (no slash) should fail");
   end Test_Split_RGB_Channels_No_Slash;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-007: Parse_RGB_Response
   ---------------------------------------------------------------------------


   procedure Test_Parse_RGB_Response_All_Max
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:FFFF/FFFF/FFFF" -> (255, 255, 255)
      Buf : constant Byte_Array (1 .. 19) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F,
          DIG_0];  --  extra byte to keep length valid
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 18);
   begin
      Assert
         (Result.Success,
          "Parse_RGB_Response 'rgb:FFFF/FFFF/FFFF' should succeed");
      Assert
         (Result.Color.Red = 255
          and then Result.Color.Green = 255
          and then Result.Color.Blue = 255,
          "Parse_RGB_Response 'rgb:FFFF/FFFF/FFFF' should return (255,255,255)");
   end Test_Parse_RGB_Response_All_Max;


   procedure Test_Parse_RGB_Response_All_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:0000/0000/0000" -> (0, 0, 0)
      Buf : constant Byte_Array (1 .. 18) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          DIG_0, DIG_0, DIG_0, DIG_0, SLASH,
          DIG_0, DIG_0, DIG_0, DIG_0, SLASH,
          DIG_0, DIG_0, DIG_0, DIG_0];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 18);
   begin
      Assert
         (Result.Success,
          "Parse_RGB_Response 'rgb:0000/0000/0000' should succeed");
      Assert
         (Result.Color.Red = 0
          and then Result.Color.Green = 0
          and then Result.Color.Blue = 0,
          "Parse_RGB_Response 'rgb:0000/0000/0000' should return (0,0,0)");
   end Test_Parse_RGB_Response_All_Zero;


   procedure Test_Parse_RGB_Response_Mid_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:8080/8080/8080" -> (128, 128, 128)
      Buf : constant Byte_Array (1 .. 18) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          HEX_8, DIG_0, HEX_8, DIG_0, SLASH,
          HEX_8, DIG_0, HEX_8, DIG_0, SLASH,
          HEX_8, DIG_0, HEX_8, DIG_0];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 18);
   begin
      Assert
         (Result.Success,
          "Parse_RGB_Response 'rgb:8080/8080/8080' should succeed");
      Assert
         (Result.Color.Red = 128
          and then Result.Color.Green = 128
          and then Result.Color.Blue = 128,
          "Parse_RGB_Response 'rgb:8080/8080/8080' should return (128,128,128)");
   end Test_Parse_RGB_Response_Mid_Value;


   procedure Test_Parse_RGB_Response_RGBA
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgba:FFFF/FFFF/FFFF/FFFF" -> (255, 255, 255)
      Buf : constant Byte_Array (1 .. 24) :=
         [CHR_r, CHR_g, CHR_b, CHR_a, CHR_CLON,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 24);
   begin
      Assert
         (Result.Success,
          "Parse_RGB_Response 'rgba:FFFF/FFFF/FFFF/FFFF' should succeed");
      Assert
         (Result.Color.Red = 255
          and then Result.Color.Green = 255
          and then Result.Color.Blue = 255,
          "Parse_RGB_Response 'rgba:FFFF/FFFF/FFFF/FFFF' should return (255,255,255)");
   end Test_Parse_RGB_Response_RGBA;


   procedure Test_Parse_RGB_Response_Malformed_Channel
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:GGGG/FFFF/FFFF" -- invalid hex in red channel
      Buf : constant Byte_Array (1 .. 18) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          HEX_G, HEX_G, HEX_G, HEX_G, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, HEX_F, HEX_F];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 18);
   begin
      Assert
         (not Result.Success,
          "Parse_RGB_Response 'rgb:GGGG/FFFF/FFFF' (invalid hex) should fail");
   end Test_Parse_RGB_Response_Malformed_Channel;


   procedure Test_Parse_RGB_Response_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buf : constant Byte_Array (1 .. 4) := [others => DIG_0];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 0);
   begin
      Assert
         (not Result.Success,
          "Parse_RGB_Response with Length=0 should fail");
   end Test_Parse_RGB_Response_Empty;


   procedure Test_Parse_RGB_Response_Two_Digit
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "rgb:FF/FF/FF" -> (255, 255, 255)
      Buf : constant Byte_Array (1 .. 12) :=
         [CHR_r, CHR_g, CHR_b, CHR_CLON,
          HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F, SLASH,
          HEX_F, HEX_F];
      Result : constant Parse_Result := Parse_RGB_Response (Buf, 12);
   begin
      Assert
         (Result.Success,
          "Parse_RGB_Response 'rgb:FF/FF/FF' (2-digit) should succeed");
      Assert
         (Result.Color.Red = 255
          and then Result.Color.Green = 255
          and then Result.Color.Blue = 255,
          "Parse_RGB_Response 'rgb:FF/FF/FF' (2-digit) should return (255,255,255)");
   end Test_Parse_RGB_Response_Two_Digit;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-010: Strip_OSC_Header
   ---------------------------------------------------------------------------


   procedure Test_Strip_OSC_Header_BG_ST_Terminated
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC ] 1 1 ; r g b : F F ESC \
      --  Header: bytes 1..5 = ESC ] 1 1 ;
      --  Payload: bytes 6..10 = r g b : F F
      --  Terminator: bytes 11..12 = ESC \
      Buf : constant Byte_Array (1 .. 12) :=
         [ESC_BYTE, OSC_RBKT, DIG_1, DIG_1, SEMI,
          CHR_r, CHR_g, CHR_b, CHR_CLON, HEX_F,
          ESC_BYTE, ST_BACK];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 12, Background);
   begin
      Assert
         (Result.Success,
          "Strip_OSC_Header BG ST-terminated should succeed");
      Assert
         (Result.Offset = 6,
          "Strip_OSC_Header BG should set Offset=6 (first payload byte after header)");
      Assert
         (Result.Payload_Length = 5,
          "Strip_OSC_Header BG should set Payload_Length=5 (excluding ST terminator)");
   end Test_Strip_OSC_Header_BG_ST_Terminated;


   procedure Test_Strip_OSC_Header_FG_ST_Terminated
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC ] 1 0 ; r g b : F F ESC \
      --  Header: bytes 1..5 = ESC ] 1 0 ;
      --  Payload: bytes 6..10 = r g b : F F
      --  Terminator: bytes 11..12 = ESC \
      Buf : constant Byte_Array (1 .. 12) :=
         [ESC_BYTE, OSC_RBKT, DIG_1, DIG_0, SEMI,
          CHR_r, CHR_g, CHR_b, CHR_CLON, HEX_F,
          ESC_BYTE, ST_BACK];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 12, Foreground);
   begin
      Assert
         (Result.Success,
          "Strip_OSC_Header FG ST-terminated should succeed");
      Assert
         (Result.Offset = 6,
          "Strip_OSC_Header FG should set Offset=6 (first payload byte after header)");
   end Test_Strip_OSC_Header_FG_ST_Terminated;


   procedure Test_Strip_OSC_Header_BG_BEL_Terminated
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  ESC ] 1 1 ; r g b : F F BEL
      --  Header: bytes 1..5 = ESC ] 1 1 ;
      --  Payload: bytes 6..10 = r g b : F F
      --  Terminator: byte 11 = BEL
      Buf : constant Byte_Array (1 .. 11) :=
         [ESC_BYTE, OSC_RBKT, DIG_1, DIG_1, SEMI,
          CHR_r, CHR_g, CHR_b, CHR_CLON, HEX_F,
          BEL_BYTE];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 11, Background);
   begin
      Assert
         (Result.Success,
          "Strip_OSC_Header BG BEL-terminated should succeed");
      Assert
         (Result.Payload_Length = 5,
          "Strip_OSC_Header BG BEL-terminated should set Payload_Length=5 "
          & "and then excluding BEL byte");
   end Test_Strip_OSC_Header_BG_BEL_Terminated;


   procedure Test_Strip_OSC_Header_Wrong_Kind
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  BG header (OSC 11) but Kind = Foreground -> mismatch on digit
      Buf : constant Byte_Array (1 .. 12) :=
         [ESC_BYTE, OSC_RBKT, DIG_1, DIG_1, SEMI,
          CHR_r, CHR_g, CHR_b, CHR_CLON, HEX_F,
          ESC_BYTE, ST_BACK];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 12, Foreground);
   begin
      Assert
         (not Result.Success,
          "Strip_OSC_Header with BG header but Kind=Foreground should fail");
   end Test_Strip_OSC_Header_Wrong_Kind;


   procedure Test_Strip_OSC_Header_Too_Short
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Only 4 bytes -- shorter than minimum 5-byte header
      Buf : constant Byte_Array (1 .. 4) :=
         [ESC_BYTE, OSC_RBKT, DIG_1, DIG_1];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 4, Background);
   begin
      Assert
         (not Result.Success,
          "Strip_OSC_Header with fewer than 5 bytes should fail");
   end Test_Strip_OSC_Header_Too_Short;


   procedure Test_Strip_OSC_Header_Missing_ESC
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Starts with 'r' not ESC -- missing ESC ] prefix
      Buf : constant Byte_Array (1 .. 7) :=
         [CHR_r, OSC_RBKT, DIG_1, DIG_1, SEMI, CHR_r, CHR_g];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 7, Background);
   begin
      Assert
         (not Result.Success,
          "Strip_OSC_Header with missing ESC ] prefix should fail");
   end Test_Strip_OSC_Header_Missing_ESC;


   procedure Test_Strip_OSC_Header_Empty_Buffer
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Buf : constant Byte_Array (1 .. 4) := [others => DIG_0];
      Result : constant Strip_Result := Strip_OSC_Header (Buf, 0, Background);
   begin
      Assert
         (not Result.Success,
          "Strip_OSC_Header with Length=0 should fail");
   end Test_Strip_OSC_Header_Empty_Buffer;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-011: Parse_Colorfgbg
   ---------------------------------------------------------------------------


   procedure Test_Parse_Colorfgbg_Zero_Fifteen
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("0;15");
   begin
      Assert
         (Result.Success,
          "Parse_Colorfgbg '0;15' should succeed");
      Assert
         (Result.Foreground = 0,
          "Parse_Colorfgbg '0;15' should set Foreground=0");
      Assert
         (Result.Background = 15,
          "Parse_Colorfgbg '0;15' should set Background=15");
   end Test_Parse_Colorfgbg_Zero_Fifteen;


   procedure Test_Parse_Colorfgbg_Seven_Zero
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("7;0");
   begin
      Assert
         (Result.Success,
          "Parse_Colorfgbg '7;0' should succeed");
      Assert
         (Result.Foreground = 7,
          "Parse_Colorfgbg '7;0' should set Foreground=7");
      Assert
         (Result.Background = 0,
          "Parse_Colorfgbg '7;0' should set Background=0");
   end Test_Parse_Colorfgbg_Seven_Zero;


   procedure Test_Parse_Colorfgbg_Three_Fields
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "7;8;0" -> FG from first field = 7, BG from last field = 0
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("7;8;0");
   begin
      Assert
         (Result.Success,
          "Parse_Colorfgbg '7;8;0' (three fields) should succeed");
      Assert
         (Result.Foreground = 7,
          "Parse_Colorfgbg '7;8;0' should set Foreground=7 (first field)");
      Assert
         (Result.Background = 0,
          "Parse_Colorfgbg '7;8;0' should set Background=0 (last field)");
   end Test_Parse_Colorfgbg_Three_Fields;


   procedure Test_Parse_Colorfgbg_FG_Out_Of_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "16;0" -> FG = 16, out of 0..15 range
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("16;0");
   begin
      Assert
         (not Result.Success,
          "Parse_Colorfgbg '16;0' (FG=16 out of range) should fail");
   end Test_Parse_Colorfgbg_FG_Out_Of_Range;


   procedure Test_Parse_Colorfgbg_BG_Out_Of_Range
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "0;16" -> BG = 16, out of 0..15 range
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("0;16");
   begin
      Assert
         (not Result.Success,
          "Parse_Colorfgbg '0;16' (BG=16 out of range) should fail");
   end Test_Parse_Colorfgbg_BG_Out_Of_Range;


   procedure Test_Parse_Colorfgbg_Empty
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("");
   begin
      Assert
         (not Result.Success,
          "Parse_Colorfgbg '' (empty string) should fail");
   end Test_Parse_Colorfgbg_Empty;


   procedure Test_Parse_Colorfgbg_No_Semicolon
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("no_semicolon");
   begin
      Assert
         (not Result.Success,
          "Parse_Colorfgbg 'no_semicolon' (no semicolon) should fail");
   end Test_Parse_Colorfgbg_No_Semicolon;


   procedure Test_Parse_Colorfgbg_Single_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  "7" -> no semicolon, single field
      Result : constant Colorfgbg_Result := Parse_Colorfgbg ("7");
   begin
      Assert
         (not Result.Success,
          "Parse_Colorfgbg '7' (single value, no semicolon) should fail");
   end Test_Parse_Colorfgbg_Single_Value;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-012: Ansi_To_RGB
   ---------------------------------------------------------------------------


   procedure Test_Ansi_To_RGB_Index_0_Black
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant RGB := Ansi_To_RGB (0);
   begin
      Assert
         (C.Red = 0 and then C.Green = 0 and then C.Blue = 0,
          "Ansi_To_RGB(0) should return (0,0,0) Black");
   end Test_Ansi_To_RGB_Index_0_Black;


   procedure Test_Ansi_To_RGB_Index_7_Light_Grey
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant RGB := Ansi_To_RGB (7);
   begin
      Assert
         (C.Red = 192 and then C.Green = 192 and then C.Blue = 192,
          "Ansi_To_RGB(7) should return (192,192,192) Light Grey");
   end Test_Ansi_To_RGB_Index_7_Light_Grey;


   procedure Test_Ansi_To_RGB_Index_9_Bright_Red
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant RGB := Ansi_To_RGB (9);
   begin
      Assert
         (C.Red = 255 and then C.Green = 0 and then C.Blue = 0,
          "Ansi_To_RGB(9) should return (255,0,0) Bright Red");
   end Test_Ansi_To_RGB_Index_9_Bright_Red;


   procedure Test_Ansi_To_RGB_Index_15_White
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant RGB := Ansi_To_RGB (15);
   begin
      Assert
         (C.Red = 255 and then C.Green = 255 and then C.Blue = 255,
          "Ansi_To_RGB(15) should return (255,255,255) White");
   end Test_Ansi_To_RGB_Index_15_White;


   ---------------------------------------------------------------------------
   --  FUNC-BGC-001: ANSI_COLOR_TABLE and constants
   ---------------------------------------------------------------------------


   procedure Test_Color_Table_Index_0_Equals_Default_BG
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C : constant RGB := ANSI_COLOR_TABLE (0);
   begin
      Assert
         (C.Red = DEFAULT_BACKGROUND.Red
          and then C.Green = DEFAULT_BACKGROUND.Green
          and then C.Blue = DEFAULT_BACKGROUND.Blue,
          "ANSI_COLOR_TABLE(0) should equal DEFAULT_BACKGROUND (0,0,0)");
   end Test_Color_Table_Index_0_Equals_Default_BG;


   procedure Test_Default_Foreground_Value
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (DEFAULT_FOREGROUND.Red = 170
          and then DEFAULT_FOREGROUND.Green = 170
          and then DEFAULT_FOREGROUND.Blue = 170,
          "DEFAULT_FOREGROUND should be (170,170,170)");
   end Test_Default_Foreground_Value;


   procedure Test_Color_Table_Length
      (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Assert
         (ANSI_COLOR_TABLE'Length = 16,
          "ANSI_COLOR_TABLE'Length should be 16");
   end Test_Color_Table_Length;

end Test_BG_Query;
