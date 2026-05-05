-------------------------------------------------------------------------------
--  Test_Terminfo - Unit Tests for Termicap.Terminfo Binary Parsing Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  AUnit test case covering the pure SPARK parsing functions in Termicap.Terminfo:
--  Detect_Format, Parse_Header, Get_Boolean, Get_Numeric, Get_String,
--  Parse_Extended_Header, Extract_Truecolor_Flags, and Parse_Buffer.
--
--  All tests construct Byte_Array values programmatically and require no live
--  terminal or external test data files.
--
--  Requirements Coverage:
--    - @relation(FUNC-TIF-007): Detect_Format
--    - @relation(FUNC-TIF-008): Parse_Header
--    - @relation(FUNC-TIF-009): Get_Boolean
--    - @relation(FUNC-TIF-010): Get_Numeric
--    - @relation(FUNC-TIF-011): Get_String
--    - @relation(FUNC-TIF-012): Parse_Extended_Header
--    - @relation(FUNC-TIF-014): Extract_Truecolor_Flags

with AUnit.Test_Cases;

package Test_Terminfo is

   type Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String;
   overriding
   procedure Register_Tests (T : in out Test_Case);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-007: Detect_Format
   ---------------------------------------------------------------------------

   --  Magic bytes 0x1A 0x01 (LE for 0x011A) -> Legacy_16bit
   procedure Test_TIF007_Detect_Legacy_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Magic bytes 0x1E 0x02 (LE for 0x021E) -> Extended_32bit
   procedure Test_TIF007_Detect_Extended_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Magic bytes 0xAD 0xDE (LE for 0xDEAD) -> Unknown
   procedure Test_TIF007_Detect_Unknown_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Minimum buffer of exactly 2 bytes is accepted by precondition
   procedure Test_TIF007_Minimum_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-008: Parse_Header
   ---------------------------------------------------------------------------

   --  Valid legacy header with correct section offsets
   procedure Test_TIF008_Valid_Legacy_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Header with Names_Size exceeding MAX_NAMES_SECTION_SIZE -> fails
   procedure Test_TIF008_Names_Size_Exceeds_Max
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Header where total computed size exceeds buffer size -> fails
   procedure Test_TIF008_Total_Size_Exceeds_Buffer
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Header with alignment padding when (Names_Size + Bool_Count) is odd
   procedure Test_TIF008_Alignment_Padding
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-009: Get_Boolean
   ---------------------------------------------------------------------------

   --  Index in range, byte = 1 -> True_Value
   procedure Test_TIF009_Bool_True_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index in range, byte = 0 -> False_Value
   procedure Test_TIF009_Bool_False_Value
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index in range, byte = 0xFF -> Cancelled
   procedure Test_TIF009_Bool_Cancelled
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index in range, byte = 0xFE -> Absent
   procedure Test_TIF009_Bool_Absent_Byte
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index out of range (>= Bool_Count) -> Absent
   procedure Test_TIF009_Bool_Out_Of_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-010: Get_Numeric
   ---------------------------------------------------------------------------

   --  COLORS_INDEX=13 with value 256 (LE: 0x00, 0x01) -> 256
   procedure Test_TIF010_Colors_256_Legacy
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Absent numeric (-1, LE: 0xFF, 0xFF) -> ABSENT_NUMERIC
   procedure Test_TIF010_Absent_Numeric
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Cancelled numeric (-2, LE: 0xFE, 0xFF) -> CANCELLED_NUMERIC
   procedure Test_TIF010_Cancelled_Numeric
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index out of range (>= Num_Count) -> ABSENT_NUMERIC
   procedure Test_TIF010_Numeric_Out_Of_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  32-bit format with colors = 16777216 (LE: 0x00, 0x00, 0x00, 0x01)
   procedure Test_TIF010_Colors_16M_Extended
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-011: Get_String
   ---------------------------------------------------------------------------

   --  Valid setaf extraction at SETAF_INDEX: string present and non-empty
   procedure Test_TIF011_Setaf_Present
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Absent string (offset = -1 in LE) -> Present = False, Length = 0
   procedure Test_TIF011_String_Absent
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Index out of range (>= String_Count) -> Present = False, Length = 0
   procedure Test_TIF011_String_Out_Of_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  String longer than MAX_CAPABILITY_STRING_LENGTH is truncated
   procedure Test_TIF011_String_Truncated
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-012: Parse_Extended_Header
   ---------------------------------------------------------------------------

   --  Buffer ends at Total_Standard_Size -> Success = False (absent, not error)
   procedure Test_TIF012_No_Extended_Section
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Valid extended header with correct bounds -> Success = True
   procedure Test_TIF012_Valid_Extended_Header
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  FUNC-TIF-014: Extract_Truecolor_Flags
   ---------------------------------------------------------------------------

   --  Extended section with extended boolean "RGB" set -> Has_RGB = True
   procedure Test_TIF014_RGB_Flag_True
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Extended section with extended boolean "Tc" set -> Has_Tc = True
   procedure Test_TIF014_Tc_Flag_True
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Extended section without RGB or Tc -> both False
   procedure Test_TIF014_No_Truecolor_Flags
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   ---------------------------------------------------------------------------
   --  Parse_Buffer (convenience aggregation)
   ---------------------------------------------------------------------------

   --  Complete valid legacy terminfo buffer -> success with expected values
   procedure Test_Parse_Buffer_Valid_Legacy
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Buffer with wrong magic -> Error_Invalid_Magic
   procedure Test_Parse_Buffer_Wrong_Magic
     (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Buffer too short for header -> Error_Header_Corrupt or Error_Invalid_Magic
   procedure Test_Parse_Buffer_Too_Short
     (T : in out AUnit.Test_Cases.Test_Case'Class);

end Test_Terminfo;
