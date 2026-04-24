-------------------------------------------------------------------------------
--  Test_BG_Query - Unit Tests for Termicap.Color.BG_Query
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK functions in Termicap.Color.BG_Query:
--  Query_Sequence byte constant selection, Parse_Hex_Channel normalization,
--  Find_RGB_Prefix and Split_RGB_Channels scanning, Parse_RGB_Response
--  orchestration, Strip_OSC_Header header removal, Parse_Colorfgbg parsing,
--  Ansi_To_RGB palette lookup, and ANSI_COLOR_TABLE / default constant values.
--
--  Requirements Coverage:
--    - @relation(FUNC-BGC-001): ANSI_COLOR_TABLE, DEFAULT_FOREGROUND, DEFAULT_BACKGROUND
--    - @relation(FUNC-BGC-005): Query_Sequence
--    - @relation(FUNC-BGC-007): Parse_RGB_Response
--    - @relation(FUNC-BGC-008): Find_RGB_Prefix, Split_RGB_Channels
--    - @relation(FUNC-BGC-009): Parse_Hex_Channel
--    - @relation(FUNC-BGC-010): Strip_OSC_Header
--    - @relation(FUNC-BGC-011): Parse_Colorfgbg
--    - @relation(FUNC-BGC-012): Ansi_To_RGB

with AUnit.Test_Cases;

package Test_BG_Query is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-005: Query_Sequence
   ---------------------------------------------------------------------------

   --  FUNC-BGC-005: Background kind returns OSC_BG_QUERY with length = 8
   procedure Test_Query_Sequence_BG_Length (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-005: Foreground kind returns OSC_FG_QUERY with length = 8
   procedure Test_Query_Sequence_FG_Length (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-005: Background result starts with ESC ] (0x1B, 0x5D)
   procedure Test_Query_Sequence_BG_Starts_With_ESC_Bracket (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-005: Foreground result contains '0' at position 4 (distinguishing from '1')
   procedure Test_Query_Sequence_FG_Has_Zero_At_Position_4 (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-009: Parse_Hex_Channel
   ---------------------------------------------------------------------------

   --  FUNC-BGC-009: 2-digit "FF" -> Success, Value = 255
   procedure Test_Parse_Hex_Channel_FF_Two_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 2-digit "00" -> Success, Value = 0
   procedure Test_Parse_Hex_Channel_00_Two_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 2-digit "80" -> Success, Value = 128
   procedure Test_Parse_Hex_Channel_80_Two_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 4-digit "FFFF" -> Success, Value = 255 (high byte)
   procedure Test_Parse_Hex_Channel_FFFF_Four_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 4-digit "8080" -> Success, Value = 128 (high byte)
   procedure Test_Parse_Hex_Channel_8080_Four_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 4-digit "0000" -> Success, Value = 0
   procedure Test_Parse_Hex_Channel_0000_Four_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 1-digit "F" -> Success, Value = 255 (F * 17)
   procedure Test_Parse_Hex_Channel_F_One_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: 3-digit "FFF" -> Success, Value = 255 (FFF / 16)
   procedure Test_Parse_Hex_Channel_FFF_Three_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: Lowercase "ff" -> Success, Value = 255
   procedure Test_Parse_Hex_Channel_Lowercase_ff (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: Non-hex byte "GG" -> Success = False
   procedure Test_Parse_Hex_Channel_Non_Hex_GG (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-009: Mixed case "aB" -> Success, Value = 171
   procedure Test_Parse_Hex_Channel_Mixed_Case_aB (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-008: Find_RGB_Prefix
   ---------------------------------------------------------------------------

   --  FUNC-BGC-008: Bytes containing "rgb:RRRR/GGGG/BBBB" -> Found = True
   procedure Test_Find_RGB_Prefix_Found_RGB (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: Bytes containing "rgba:RRRR/GGGG/BBBB/AAAA" -> Found = True
   procedure Test_Find_RGB_Prefix_Found_RGBA (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: Bytes with no rgb: prefix -> Found = False
   procedure Test_Find_RGB_Prefix_Not_Found (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: Empty buffer (Length = 0) -> Found = False
   procedure Test_Find_RGB_Prefix_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: Bytes with "rgb" but no colon -> Found = False
   procedure Test_Find_RGB_Prefix_No_Colon (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-008: Split_RGB_Channels
   ---------------------------------------------------------------------------

   --  FUNC-BGC-008: "FF/FF/FF" -> Success, three slices each length 2
   procedure Test_Split_RGB_Channels_Two_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: "FFFF/FFFF/FFFF" -> Success, three slices each length 4
   procedure Test_Split_RGB_Channels_Four_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: "FF/FF" (only one slash) -> Success = False
   procedure Test_Split_RGB_Channels_One_Slash (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: "FF/FF/FF/AA" (rgba, four fields) -> Success, first three channels extracted
   procedure Test_Split_RGB_Channels_Four_Channels (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-008: Single channel "FF" (no slashes) -> Success = False
   procedure Test_Split_RGB_Channels_No_Slash (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-007: Parse_RGB_Response
   ---------------------------------------------------------------------------

   --  FUNC-BGC-007: Full "rgb:FFFF/FFFF/FFFF" payload -> Success, Color = (255, 255, 255)
   procedure Test_Parse_RGB_Response_All_Max (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: Full "rgb:0000/0000/0000" payload -> Success, Color = (0, 0, 0)
   procedure Test_Parse_RGB_Response_All_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: Full "rgb:8080/8080/8080" payload -> Success, Color = (128, 128, 128)
   procedure Test_Parse_RGB_Response_Mid_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: "rgba:FFFF/FFFF/FFFF/FFFF" with alpha -> Success, Color = (255, 255, 255)
   procedure Test_Parse_RGB_Response_RGBA (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: Malformed "rgb:GGGG/FFFF/FFFF" -> Success = False
   procedure Test_Parse_RGB_Response_Malformed_Channel (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: Empty buffer -> Success = False
   procedure Test_Parse_RGB_Response_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-007: "rgb:FF/FF/FF" (2-digit) -> Success, Color = (255, 255, 255)
   procedure Test_Parse_RGB_Response_Two_Digit (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-010: Strip_OSC_Header
   ---------------------------------------------------------------------------

   --  FUNC-BGC-010: Full BG response "ESC ] 1 1 ; rgb:... ESC \" -> Success, correct payload
   procedure Test_Strip_OSC_Header_BG_ST_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: Full FG response "ESC ] 1 0 ; rgb:... ESC \" -> Success, correct payload
   procedure Test_Strip_OSC_Header_FG_ST_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: BEL-terminated response "ESC ] 1 1 ; rgb:... BEL" -> Success
   procedure Test_Strip_OSC_Header_BG_BEL_Terminated (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: Wrong kind (BG header but Kind = Foreground) -> Success = False
   procedure Test_Strip_OSC_Header_Wrong_Kind (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: Too short (< 5 bytes) -> Success = False
   procedure Test_Strip_OSC_Header_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: Missing ESC ] prefix -> Success = False
   procedure Test_Strip_OSC_Header_Missing_ESC (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-010: Empty buffer (Length = 0) -> Success = False
   procedure Test_Strip_OSC_Header_Empty_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-011: Parse_Colorfgbg
   ---------------------------------------------------------------------------

   --  FUNC-BGC-011: "0;15" -> Success, Foreground = 0, Background = 15
   procedure Test_Parse_Colorfgbg_Zero_Fifteen (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "7;0" -> Success, Foreground = 7, Background = 0
   procedure Test_Parse_Colorfgbg_Seven_Zero (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "7;8;0" (three fields) -> Success, Foreground = 7, Background = 0
   procedure Test_Parse_Colorfgbg_Three_Fields (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "16;0" -> Success = False (FG = 16, out of range)
   procedure Test_Parse_Colorfgbg_FG_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "0;16" -> Success = False (BG = 16, out of range)
   procedure Test_Parse_Colorfgbg_BG_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "" (empty) -> Success = False
   procedure Test_Parse_Colorfgbg_Empty (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "no_semicolon" -> Success = False
   procedure Test_Parse_Colorfgbg_No_Semicolon (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-011: "7" (single value) -> Success = False
   procedure Test_Parse_Colorfgbg_Single_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-012: Ansi_To_RGB
   ---------------------------------------------------------------------------

   --  FUNC-BGC-012: Index 0 -> (0, 0, 0) (Black)
   procedure Test_Ansi_To_RGB_Index_0_Black (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-012: Index 7 -> (192, 192, 192) (Light Grey)
   procedure Test_Ansi_To_RGB_Index_7_Light_Grey (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-012: Index 9 -> (255, 0, 0) (Bright Red)
   procedure Test_Ansi_To_RGB_Index_9_Bright_Red (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-012: Index 15 -> (255, 255, 255) (White)
   procedure Test_Ansi_To_RGB_Index_15_White (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-BGC-001: ANSI_COLOR_TABLE and constants
   ---------------------------------------------------------------------------

   --  FUNC-BGC-001: ANSI_COLOR_TABLE(0) = DEFAULT_BACKGROUND = (0, 0, 0)
   procedure Test_Color_Table_Index_0_Equals_Default_BG (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-001: DEFAULT_FOREGROUND = (170, 170, 170)
   procedure Test_Default_Foreground_Value (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  FUNC-BGC-001: ANSI_COLOR_TABLE'Length = 16
   procedure Test_Color_Table_Length (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_BG_Query;
