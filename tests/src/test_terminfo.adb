-------------------------------------------------------------------------------
--  Test_Terminfo - Unit Tests for Termicap.Terminfo Binary Parsing Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

with AUnit.Assertions;              use AUnit.Assertions;
with AUnit.Test_Cases.Registration; use AUnit.Test_Cases.Registration;

with Interfaces.C;

with Termicap.Terminfo; use Termicap.Terminfo;
use Termicap;

use type Termicap.Terminfo.Terminfo_Format;
use type Termicap.Terminfo.Boolean_Cap_Value;

package body Test_Terminfo is

   ---------------------------------------------------------------------------
   --  Byte helper
   ---------------------------------------------------------------------------

   --  Convert a Natural literal to the Byte subtype (Interfaces.C.unsigned_char).
   function B (V : Natural) return Byte
   is (Byte (V));

   --  Encode a 16-bit value as two little-endian bytes: (low, high).
   function LE16_Lo (V : Natural) return Byte
   is (B (V mod 256));
   function LE16_Hi (V : Natural) return Byte
   is (B ((V / 256) mod 256));

   ---------------------------------------------------------------------------
   --  Helper: build a minimal valid legacy buffer
   --
   --  Layout (all 1-based offsets):
   --    Bytes  1..12  : header
   --      1..2  magic  = 0x1A 0x01  (legacy)
   --      3..4  names_size  = 2
   --      5..6  bool_count  = 0
   --      7..8  num_count   = N_Num
   --      9..10 string_count= N_Str
   --     11..12 table_size  = T_Size
   --    Bytes 13..14  : names section ("x\0")
   --    Bytes 15..14+N_Num*2-1 : numeric section (all-absent: 0xFF,0xFF per entry)
   --    Then string offset table (N_Str * 2 bytes, all-absent 0xFF,0xFF)
   --    Then string data (T_Size bytes)
   --
   --  names_size=2, bool_count=0 -> names_size+bool_count=2 (even, no padding)
   --  Bool_Section_Offset = 15 (after 12-byte header + 2-byte names + 1-based)
   --    Actually: Bool_Section_Offset = HEADER_SIZE + names_size + 1 = 12 + 2 + 1 = 15
   --  Num_Section_Offset  = 15  (bool_count=0, no bool bytes, no padding)
   --  String_Table_Offset = 15 + N_Num * 2
   --  String_Data_Offset  = 15 + N_Num * 2 + N_Str * 2
   --  Total_Standard_Size = 14 + N_Num * 2 + N_Str * 2 + T_Size
   ---------------------------------------------------------------------------

   --  Build the 12-byte header for a legacy buffer.
   function Make_Legacy_Header
     (Names_Size : Natural; Bool_Count : Natural; Num_Count : Natural; String_Count : Natural; Table_Size : Natural)
      return Byte_Array
   is
      H : Byte_Array (1 .. 12) :=
        [16#1A#,
         16#01#,                                --  Magic: Legacy_16bit
         LE16_Lo (Names_Size),
         LE16_Hi (Names_Size),  --  Names_Size
         LE16_Lo (Bool_Count),
         LE16_Hi (Bool_Count),  --  Bool_Count
         LE16_Lo (Num_Count),
         LE16_Hi (Num_Count),   --  Num_Count
         LE16_Lo (String_Count),
         LE16_Hi (String_Count), --  String_Count
         LE16_Lo (Table_Size),
         LE16_Hi (Table_Size)]; --  Table_Size
   begin
      return H;
   end Make_Legacy_Header;

   --  Build the 12-byte header for an extended-32bit buffer.
   function Make_Extended_Header_Bytes
     (Names_Size : Natural; Bool_Count : Natural; Num_Count : Natural; String_Count : Natural; Table_Size : Natural)
      return Byte_Array
   is
      H : Byte_Array (1 .. 12) :=
        [16#1E#,
         16#02#,                                --  Magic: Extended_32bit
         LE16_Lo (Names_Size),
         LE16_Hi (Names_Size),
         LE16_Lo (Bool_Count),
         LE16_Hi (Bool_Count),
         LE16_Lo (Num_Count),
         LE16_Hi (Num_Count),
         LE16_Lo (String_Count),
         LE16_Hi (String_Count),
         LE16_Lo (Table_Size),
         LE16_Hi (Table_Size)];
   begin
      return H;
   end Make_Extended_Header_Bytes;

   overriding
   function Name (T : Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Termicap.Terminfo");
   end Name;

   overriding
   procedure Register_Tests (T : in out Test_Case) is
   begin
      --  FUNC-TIF-007: Detect_Format
      Register_Routine
        (T, Test_TIF007_Detect_Legacy_Magic'Access, "FUNC-TIF-007: magic 0x011A (LE: 0x1A 0x01) -> Legacy_16bit");
      Register_Routine
        (T, Test_TIF007_Detect_Extended_Magic'Access, "FUNC-TIF-007: magic 0x021E (LE: 0x1E 0x02) -> Extended_32bit");
      Register_Routine (T, Test_TIF007_Detect_Unknown_Magic'Access, "FUNC-TIF-007: magic 0xDEAD -> Unknown");
      Register_Routine (T, Test_TIF007_Minimum_Buffer'Access, "FUNC-TIF-007: minimum 2-byte buffer is accepted");

      --  FUNC-TIF-008: Parse_Header
      Register_Routine
        (T,
         Test_TIF008_Valid_Legacy_Header'Access,
         "FUNC-TIF-008: valid legacy header -> Success=True, offsets correct");
      Register_Routine
        (T,
         Test_TIF008_Names_Size_Exceeds_Max'Access,
         "FUNC-TIF-008: Names_Size > MAX_NAMES_SECTION_SIZE -> Success=False");
      Register_Routine
        (T, Test_TIF008_Total_Size_Exceeds_Buffer'Access, "FUNC-TIF-008: total size > buffer size -> Success=False");
      Register_Routine
        (T,
         Test_TIF008_Alignment_Padding'Access,
         "FUNC-TIF-008: odd (Names_Size+Bool_Count) -> alignment padding applied");

      --  FUNC-TIF-009: Get_Boolean
      Register_Routine (T, Test_TIF009_Bool_True_Value'Access, "FUNC-TIF-009: bool byte=1 -> True_Value");
      Register_Routine (T, Test_TIF009_Bool_False_Value'Access, "FUNC-TIF-009: bool byte=0 -> False_Value");
      Register_Routine (T, Test_TIF009_Bool_Cancelled'Access, "FUNC-TIF-009: bool byte=0xFF -> Cancelled");
      Register_Routine (T, Test_TIF009_Bool_Absent_Byte'Access, "FUNC-TIF-009: bool byte=0xFE -> Absent");
      Register_Routine (T, Test_TIF009_Bool_Out_Of_Range'Access, "FUNC-TIF-009: index >= Bool_Count -> Absent");

      --  FUNC-TIF-010: Get_Numeric
      Register_Routine
        (T, Test_TIF010_Colors_256_Legacy'Access, "FUNC-TIF-010: COLORS_INDEX=13 value=256 (LE 0x00 0x01) -> 256");
      Register_Routine (T, Test_TIF010_Absent_Numeric'Access, "FUNC-TIF-010: numeric LE 0xFF 0xFF -> ABSENT_NUMERIC");
      Register_Routine
        (T, Test_TIF010_Cancelled_Numeric'Access, "FUNC-TIF-010: numeric LE 0xFE 0xFF -> CANCELLED_NUMERIC");
      Register_Routine
        (T, Test_TIF010_Numeric_Out_Of_Range'Access, "FUNC-TIF-010: index >= Num_Count -> ABSENT_NUMERIC");
      Register_Routine
        (T,
         Test_TIF010_Colors_16M_Extended'Access,
         "FUNC-TIF-010: Extended_32bit colors=16777216 (LE 0x00 0x00 0x00 0x01)");

      --  FUNC-TIF-011: Get_String
      Register_Routine
        (T, Test_TIF011_Setaf_Present'Access, "FUNC-TIF-011: setaf at SETAF_INDEX -> Present=True, non-empty");
      Register_Routine
        (T, Test_TIF011_String_Absent'Access, "FUNC-TIF-011: string offset=-1 -> Present=False, Length=0");
      Register_Routine
        (T, Test_TIF011_String_Out_Of_Range'Access, "FUNC-TIF-011: index >= String_Count -> Present=False, Length=0");
      Register_Routine
        (T,
         Test_TIF011_String_Truncated'Access,
         "FUNC-TIF-011: string > MAX_CAPABILITY_STRING_LENGTH -> truncated to max");

      --  FUNC-TIF-012: Parse_Extended_Header
      Register_Routine
        (T,
         Test_TIF012_No_Extended_Section'Access,
         "FUNC-TIF-012: buffer ends at Total_Standard_Size -> Success=False");
      Register_Routine
        (T, Test_TIF012_Valid_Extended_Header'Access, "FUNC-TIF-012: valid extended header -> Success=True");

      --  FUNC-TIF-014: Extract_Truecolor_Flags
      Register_Routine (T, Test_TIF014_RGB_Flag_True'Access, "FUNC-TIF-014: extended boolean RGB=1 -> Has_RGB=True");
      Register_Routine (T, Test_TIF014_Tc_Flag_True'Access, "FUNC-TIF-014: extended boolean Tc=1 -> Has_Tc=True");
      Register_Routine
        (T, Test_TIF014_No_Truecolor_Flags'Access, "FUNC-TIF-014: no RGB or Tc in extended section -> both False");

      --  Parse_Buffer convenience function
      Register_Routine
        (T,
         Test_Parse_Buffer_Valid_Legacy'Access,
         "Parse_Buffer: valid legacy buffer -> Success=True, snapshot populated");
      Register_Routine (T, Test_Parse_Buffer_Wrong_Magic'Access, "Parse_Buffer: wrong magic -> Error_Invalid_Magic");
      Register_Routine
        (T, Test_Parse_Buffer_Too_Short'Access, "Parse_Buffer: 2-byte buffer with valid magic but no room for header");
   end Register_Tests;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-007: Detect_Format
   ---------------------------------------------------------------------------

   procedure Test_TIF007_Detect_Legacy_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer : constant Byte_Array (1 .. 2) := [16#1A#, 16#01#];
      Result : constant Terminfo_Format := Detect_Format (Buffer, 2);
   begin
      Assert (Result = Legacy_16bit, "Detect_Format: LE bytes 0x1A 0x01 should yield Legacy_16bit");
   end Test_TIF007_Detect_Legacy_Magic;

   procedure Test_TIF007_Detect_Extended_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer : constant Byte_Array (1 .. 2) := [16#1E#, 16#02#];
      Result : constant Terminfo_Format := Detect_Format (Buffer, 2);
   begin
      Assert (Result = Extended_32bit, "Detect_Format: LE bytes 0x1E 0x02 should yield Extended_32bit");
   end Test_TIF007_Detect_Extended_Magic;

   procedure Test_TIF007_Detect_Unknown_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  0xDEAD in LE is byte1=0xAD, byte2=0xDE
      Buffer : constant Byte_Array (1 .. 2) := [16#AD#, 16#DE#];
      Result : constant Terminfo_Format := Detect_Format (Buffer, 2);
   begin
      Assert (Result = Unknown, "Detect_Format: LE bytes 0xAD 0xDE (0xDEAD) should yield Unknown");
   end Test_TIF007_Detect_Unknown_Magic;

   procedure Test_TIF007_Minimum_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  A buffer of exactly 2 bytes satisfies the precondition Size >= 2.
      Buffer : constant Byte_Array (1 .. 2) := [16#1A#, 16#01#];
      Result : constant Terminfo_Format := Detect_Format (Buffer, 2);
   begin
      --  Just verify no exception is raised and a valid result is returned.
      Assert
        (Result in Legacy_16bit | Extended_32bit | Unknown,
         "Detect_Format: minimum 2-byte buffer must return a valid Terminfo_Format");
   end Test_TIF007_Minimum_Buffer;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-008: Parse_Header
   ---------------------------------------------------------------------------

   procedure Test_TIF008_Valid_Legacy_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Minimal valid legacy buffer:
      --    names_size=2, bool_count=0, num_count=1, string_count=0, table_size=0
      --  Layout:
      --    1..12  header
      --   13..14  names ("x\0")
      --   15..16  numeric section (1 entry, 2 bytes: 0x00,0x00 = 0)
      --  Total_Standard_Size = 12 + 2 + 0 + 0 + 1*2 + 0*2 + 0 = 16
      Hdr     : constant Byte_Array (1 .. 12) :=
        Make_Legacy_Header (Names_Size => 2, Bool_Count => 0, Num_Count => 1, String_Count => 0, Table_Size => 0);
      --  Full buffer: header + names + 1 numeric entry
      Buffer  : constant Byte_Array (1 .. 16) :=
        [Hdr (1),
         Hdr (2),
         Hdr (3),
         Hdr (4),
         Hdr (5),
         Hdr (6),
         Hdr (7),
         Hdr (8),
         Hdr (9),
         Hdr (10),
         Hdr (11),
         Hdr (12),
         16#78#,
         16#00#,   --  names: "x\0"
         16#00#,
         16#00#];  --  numeric entry: 0
      Header  : Parsed_Header;
      Success : Boolean;
   begin
      Parse_Header (Buffer => Buffer, Size => 16, Format => Legacy_16bit, Header => Header, Success => Success);
      Assert (Success, "Parse_Header: valid legacy header should succeed");
      Assert (Header.Names_Size = 2, "Parse_Header: Names_Size should be 2");
      Assert (Header.Bool_Count = 0, "Parse_Header: Bool_Count should be 0");
      Assert (Header.Num_Count = 1, "Parse_Header: Num_Count should be 1");
      Assert (Header.String_Count = 0, "Parse_Header: String_Count should be 0");
      --  Bool_Section_Offset = HEADER_SIZE + Names_Size + 1 = 12 + 2 + 1 = 15
      Assert (Header.Bool_Section_Offset = 15, "Parse_Header: Bool_Section_Offset should be 15");
      --  Num_Section_Offset = 15 (no bools, no padding: 2+0=2 even)
      Assert (Header.Num_Section_Offset = 15, "Parse_Header: Num_Section_Offset should be 15");
      Assert (Header.Total_Standard_Size = 16, "Parse_Header: Total_Standard_Size should be 16");
   end Test_TIF008_Valid_Legacy_Header;

   procedure Test_TIF008_Names_Size_Exceeds_Max (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  MAX_NAMES_SECTION_SIZE = 512.  Use names_size = 513 (0x0201).
      --  Buffer must be at least HEADER_SIZE=12 to satisfy precondition.
      --  We give it exactly 12 bytes; the header parser should reject it.
      Buffer  : constant Byte_Array (1 .. 12) :=
        [16#1A#,
         16#01#,   --  Magic: Legacy_16bit
         16#01#,
         16#02#,   --  Names_Size = 513 (LE: 0x01, 0x02)
         16#00#,
         16#00#,   --  Bool_Count = 0
         16#00#,
         16#00#,   --  Num_Count = 0
         16#00#,
         16#00#,   --  String_Count = 0
         16#00#,
         16#00#];  --  Table_Size = 0
      Header  : Parsed_Header;
      Success : Boolean;
   begin
      Parse_Header (Buffer => Buffer, Size => 12, Format => Legacy_16bit, Header => Header, Success => Success);
      Assert (not Success, "Parse_Header: Names_Size=513 > MAX_NAMES_SECTION_SIZE=512 should fail");
   end Test_TIF008_Names_Size_Exceeds_Max;

   procedure Test_TIF008_Total_Size_Exceeds_Buffer (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Header claims num_count=100 (200 bytes of numerics) but buffer is only 14 bytes.
      --  names_size=1, bool_count=0, num_count=100, string_count=0, table_size=0.
      --  Total_Standard_Size = 12 + 1 + 0 + 0 + 100*2 + 0 + 0 = 213  > 14.
      Buffer  : constant Byte_Array (1 .. 14) :=
        [16#1A#,
         16#01#,   --  Magic: Legacy_16bit
         16#01#,
         16#00#,   --  Names_Size = 1
         16#00#,
         16#00#,   --  Bool_Count = 0
         16#64#,
         16#00#,   --  Num_Count = 100 (LE: 0x64, 0x00)
         16#00#,
         16#00#,   --  String_Count = 0
         16#00#,
         16#00#,   --  Table_Size = 0
         16#78#,           --  names section (1 byte: NUL-terminated empty)
         16#00#];          --  padding / extra
      Header  : Parsed_Header;
      Success : Boolean;
   begin
      Parse_Header (Buffer => Buffer, Size => 14, Format => Legacy_16bit, Header => Header, Success => Success);
      Assert (not Success, "Parse_Header: total computed size > buffer size should fail");
   end Test_TIF008_Total_Size_Exceeds_Buffer;

   procedure Test_TIF008_Alignment_Padding (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  names_size=3 ("vt\0"), bool_count=2.
      --  names_size + bool_count = 3 + 2 = 5 (odd) -> 1 byte alignment padding.
      --  Layout:
      --   1..12  header
      --  13..15  names (3 bytes: "vt\0")
      --  16..17  bool section (2 bytes)
      --  18      alignment pad (1 byte, because 3+2=5 is odd)
      --  19..20  numeric section (1 entry, 2 bytes)
      --  Total_Standard_Size = 12 + 3 + 2 + 1 + 1*2 + 0 + 0 = 20
      Buffer  : constant Byte_Array (1 .. 20) :=
        [16#1A#,
         16#01#,   --  Magic: Legacy_16bit
         16#03#,
         16#00#,   --  Names_Size = 3
         16#02#,
         16#00#,   --  Bool_Count = 2
         16#01#,
         16#00#,   --  Num_Count = 1
         16#00#,
         16#00#,   --  String_Count = 0
         16#00#,
         16#00#,   --  Table_Size = 0
         16#76#,
         16#74#,
         16#00#,  --  names: "vt\0"
         16#01#,
         16#00#,   --  bool[0]=1 (True_Value), bool[1]=0 (False_Value)
         16#00#,           --  alignment padding
         16#08#,
         16#00#];  --  numeric[0] = 8 (LE)
      Header  : Parsed_Header;
      Success : Boolean;
   begin
      Parse_Header (Buffer => Buffer, Size => 20, Format => Legacy_16bit, Header => Header, Success => Success);
      Assert (Success, "Parse_Header: odd names+bools (3+2=5) with alignment padding should succeed");
      Assert (Header.Names_Size = 3, "Parse_Header (padding): Names_Size should be 3");
      Assert (Header.Bool_Count = 2, "Parse_Header (padding): Bool_Count should be 2");
      --  Bool_Section_Offset = 12 + 3 + 1 = 16
      Assert (Header.Bool_Section_Offset = 16, "Parse_Header (padding): Bool_Section_Offset should be 16");
      --  Num_Section_Offset = 16 + 2 + 1 (pad) = 19
      Assert (Header.Num_Section_Offset = 19, "Parse_Header (padding): Num_Section_Offset should be 19 (after pad)");
      Assert (Header.Total_Standard_Size = 20, "Parse_Header (padding): Total_Standard_Size should be 20");
   end Test_TIF008_Alignment_Padding;


   ---------------------------------------------------------------------------
   --  Shared helper: build a small valid buffer for boolean/numeric tests.
   --
   --  names_size=2, bool_count=4, num_count=4, string_count=0, table_size=0.
   --  names+bools = 2+4 = 6 (even, no padding).
   --  Layout:
   --   1..12  header
   --  13..14  names ("t\0")
   --  15..18  bool section (4 bytes)
   --  19..26  numeric section (4 entries * 2 bytes each)
   --  Total_Standard_Size = 12 + 2 + 4 + 4*2 + 0 + 0 = 26
   ---------------------------------------------------------------------------

   function Make_Bool_Num_Buffer
     (Bool_0 : Byte;
      Bool_1 : Byte;
      Bool_2 : Byte;
      Bool_3 : Byte;
      Num_0  : Integer;
      Num_1  : Integer;
      Num_2  : Integer;
      Num_3  : Integer) return Byte_Array
   is
      --  Encode a signed integer as two LE bytes (handle negative via mod).
      function Enc_Lo (V : Integer) return Byte
      is (B (V mod 256 + (if V < 0 then 256 else 0)));
      function Enc_Hi (V : Integer) return Byte
      is (B ((V / 256 + (if V < -127 then 256 else 0)) mod 256));

      Buf : Byte_Array (1 .. 26) :=
        [16#1A#,
         16#01#,  --  Magic: Legacy_16bit
         16#02#,
         16#00#,  --  Names_Size = 2
         16#04#,
         16#00#,  --  Bool_Count = 4
         16#04#,
         16#00#,  --  Num_Count = 4
         16#00#,
         16#00#,  --  String_Count = 0
         16#00#,
         16#00#,  --  Table_Size = 0
         16#74#,
         16#00#,  --  names: "t\0"
         Bool_0,
         Bool_1,
         Bool_2,
         Bool_3,  --  boolean section (4 bytes)
         Enc_Lo (Num_0),
         Enc_Hi (Num_0),  --  numeric[0]
         Enc_Lo (Num_1),
         Enc_Hi (Num_1),  --  numeric[1]
         Enc_Lo (Num_2),
         Enc_Hi (Num_2),  --  numeric[2]
         Enc_Lo (Num_3),
         Enc_Hi (Num_3)]; --  numeric[3]
   begin
      return Buf;
   end Make_Bool_Num_Buffer;

   --  Parse the shared bool/num buffer and return a validated header.
   procedure Get_Bool_Num_Header (Buffer : Byte_Array; Header : out Parsed_Header; Success : out Boolean) is
   begin
      Parse_Header
        (Buffer => Buffer, Size => Buffer'Length, Format => Legacy_16bit, Header => Header, Success => Success);
   end Get_Bool_Num_Header;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-009: Get_Boolean
   ---------------------------------------------------------------------------

   procedure Test_TIF009_Bool_True_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer  : constant Byte_Array := Make_Bool_Num_Buffer (16#01#, 16#00#, 16#FF#, 16#FE#, 0, 0, 0, 0);
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Boolean_Cap_Value;
   begin
      Get_Bool_Num_Header (Buffer, Header, Success);
      Assert (Success, "Test_TIF009_Bool_True_Value: Parse_Header must succeed");
      Result := Get_Boolean (Buffer, Header, 0);
      Assert (Result = True_Value, "Get_Boolean: byte=1 should return True_Value");
   end Test_TIF009_Bool_True_Value;

   procedure Test_TIF009_Bool_False_Value (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer  : constant Byte_Array := Make_Bool_Num_Buffer (16#01#, 16#00#, 16#FF#, 16#FE#, 0, 0, 0, 0);
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Boolean_Cap_Value;
   begin
      Get_Bool_Num_Header (Buffer, Header, Success);
      Assert (Success, "Test_TIF009_Bool_False_Value: Parse_Header must succeed");
      Result := Get_Boolean (Buffer, Header, 1);
      Assert (Result = False_Value, "Get_Boolean: byte=0 should return False_Value");
   end Test_TIF009_Bool_False_Value;

   procedure Test_TIF009_Bool_Cancelled (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer  : constant Byte_Array := Make_Bool_Num_Buffer (16#01#, 16#00#, 16#FF#, 16#FE#, 0, 0, 0, 0);
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Boolean_Cap_Value;
   begin
      Get_Bool_Num_Header (Buffer, Header, Success);
      Assert (Success, "Test_TIF009_Bool_Cancelled: Parse_Header must succeed");
      Result := Get_Boolean (Buffer, Header, 2);
      Assert (Result = Cancelled, "Get_Boolean: byte=0xFF should return Cancelled");
   end Test_TIF009_Bool_Cancelled;

   procedure Test_TIF009_Bool_Absent_Byte (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer  : constant Byte_Array := Make_Bool_Num_Buffer (16#01#, 16#00#, 16#FF#, 16#FE#, 0, 0, 0, 0);
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Boolean_Cap_Value;
   begin
      Get_Bool_Num_Header (Buffer, Header, Success);
      Assert (Success, "Test_TIF009_Bool_Absent_Byte: Parse_Header must succeed");
      Result := Get_Boolean (Buffer, Header, 3);
      Assert (Result = Absent, "Get_Boolean: byte=0xFE should return Absent");
   end Test_TIF009_Bool_Absent_Byte;

   procedure Test_TIF009_Bool_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Buffer  : constant Byte_Array := Make_Bool_Num_Buffer (16#01#, 16#00#, 16#FF#, 16#FE#, 0, 0, 0, 0);
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Boolean_Cap_Value;
   begin
      Get_Bool_Num_Header (Buffer, Header, Success);
      Assert (Success, "Test_TIF009_Bool_Out_Of_Range: Parse_Header must succeed");
      --  Bool_Count = 4, so index 4 is out of range.
      Result := Get_Boolean (Buffer, Header, 4);
      Assert (Result = Absent, "Get_Boolean: index >= Bool_Count should return Absent");
   end Test_TIF009_Bool_Out_Of_Range;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-010: Get_Numeric
   ---------------------------------------------------------------------------

   procedure Test_TIF010_Colors_256_Legacy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Build a buffer with num_count=14 (to cover COLORS_INDEX=13, 0-based).
      --  names_size=2, bool_count=0, num_count=14, string_count=0, table_size=0.
      --  names+bools=2+0=2 (even, no padding).
      --  Numeric section starts at offset 15 (1-based).
      --  COLORS_INDEX=13 entry is at: 15 + 13*2 = 15 + 26 = 41 (1-based).
      --  Value 256 (0x0100) in LE: 0x00, 0x01.
      --  Total_Standard_Size = 12 + 2 + 0 + 14*2 + 0 + 0 = 42.
      Buffer : Byte_Array (1 .. 42) := [others => 16#FF#];
   begin
      --  Write header
      Buffer (1) := 16#1A#;
      Buffer (2) := 16#01#;  --  magic
      Buffer (3) := 16#02#;
      Buffer (4) := 16#00#;  --  names_size=2
      Buffer (5) := 16#00#;
      Buffer (6) := 16#00#;  --  bool_count=0
      Buffer (7) := 16#0E#;
      Buffer (8) := 16#00#;  --  num_count=14 (0x0E)
      Buffer (9) := 16#00#;
      Buffer (10) := 16#00#;  --  string_count=0
      Buffer (11) := 16#00#;
      Buffer (12) := 16#00#;  --  table_size=0
      --  Names section (bytes 13..14)
      Buffer (13) := 16#74#;
      Buffer (14) := 16#00#;  --  "t\0"
      --  Numeric section starts at 15.  Set all to absent (0xFF, 0xFF).
      --  (Already set by `others => 16#FF#` for bytes 15..42.)
      --  Override COLORS_INDEX=13: bytes at 15 + 13*2 = 41 and 42.
      Buffer (41) := 16#00#;
      Buffer (42) := 16#01#;  --  256 in LE
      declare
         Header  : Parsed_Header;
         Success : Boolean;
         Colors  : Integer;
      begin
         Parse_Header (Buffer => Buffer, Size => 42, Format => Legacy_16bit, Header => Header, Success => Success);
         Assert (Success, "Test_TIF010_Colors_256: Parse_Header must succeed");
         Colors := Get_Numeric (Buffer, Header, Legacy_16bit, COLORS_INDEX);
         Assert (Colors = 256, "Get_Numeric: COLORS_INDEX with LE 0x00 0x01 should return 256");
      end;
   end Test_TIF010_Colors_256_Legacy;

   procedure Test_TIF010_Absent_Numeric (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Single numeric entry with value 0xFFFF (-1 when signed LE) -> ABSENT_NUMERIC.
      --  names_size=2, bool_count=0, num_count=1, string_count=0, table_size=0.
      --  Total_Standard_Size = 12 + 2 + 0 + 1*2 + 0 + 0 = 16.
      Buffer  : constant Byte_Array (1 .. 16) :=
        [16#1A#,
         16#01#,  --  magic
         16#02#,
         16#00#,  --  names_size=2
         16#00#,
         16#00#,  --  bool_count=0
         16#01#,
         16#00#,  --  num_count=1
         16#00#,
         16#00#,  --  string_count=0
         16#00#,
         16#00#,  --  table_size=0
         16#74#,
         16#00#,  --  names "t\0"
         16#FF#,
         16#FF#]; --  numeric[0] = -1 (ABSENT_NUMERIC)
      Header  : Parsed_Header;
      Success : Boolean;
      Value   : Integer;
   begin
      Parse_Header (Buffer, 16, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF010_Absent: Parse_Header must succeed");
      Value := Get_Numeric (Buffer, Header, Legacy_16bit, 0);
      Assert (Value = ABSENT_NUMERIC, "Get_Numeric: LE 0xFF 0xFF should return ABSENT_NUMERIC (-1)");
   end Test_TIF010_Absent_Numeric;

   procedure Test_TIF010_Cancelled_Numeric (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Single numeric entry with value 0xFFFE (-2 signed LE) -> CANCELLED_NUMERIC.
      --  Encoding -2 as LE 16-bit: 0xFFFE -> byte1=0xFE, byte2=0xFF.
      Buffer  : constant Byte_Array (1 .. 16) :=
        [16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#01#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#74#,
         16#00#,
         16#FE#,
         16#FF#];  --  numeric[0] = -2 (CANCELLED_NUMERIC)
      Header  : Parsed_Header;
      Success : Boolean;
      Value   : Integer;
   begin
      Parse_Header (Buffer, 16, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF010_Cancelled: Parse_Header must succeed");
      Value := Get_Numeric (Buffer, Header, Legacy_16bit, 0);
      Assert (Value = CANCELLED_NUMERIC, "Get_Numeric: LE 0xFE 0xFF should return CANCELLED_NUMERIC (-2)");
   end Test_TIF010_Cancelled_Numeric;

   procedure Test_TIF010_Numeric_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  num_count=2, query index=5 (out of range) -> ABSENT_NUMERIC.
      Buffer  : constant Byte_Array (1 .. 18) :=
        [16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#02#,
         16#00#,  --  num_count=2
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#74#,
         16#00#,
         16#08#,
         16#00#,  --  numeric[0] = 8
         16#10#,
         16#00#]; --  numeric[1] = 16
      Header  : Parsed_Header;
      Success : Boolean;
      Value   : Integer;
   begin
      Parse_Header (Buffer, 18, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF010_OutOfRange: Parse_Header must succeed");
      Value := Get_Numeric (Buffer, Header, Legacy_16bit, 5);
      Assert (Value = ABSENT_NUMERIC, "Get_Numeric: index >= Num_Count should return ABSENT_NUMERIC");
   end Test_TIF010_Numeric_Out_Of_Range;

   procedure Test_TIF010_Colors_16M_Extended (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Extended_32bit format: numerics are 4 bytes each.
      --  COLORS_INDEX=13 with value 16777216 (0x01000000) in LE 32-bit:
      --    bytes: 0x00, 0x00, 0x00, 0x01.
      --  names_size=2, bool_count=0, num_count=14, string_count=0, table_size=0.
      --  Numeric section starts at 15 (1-based).
      --  COLORS_INDEX=13 entry at: 15 + 13*4 = 15 + 52 = 67 (1-based), 4 bytes.
      --  Total_Standard_Size = 12 + 2 + 0 + 14*4 + 0 + 0 = 70.
      Buffer : Byte_Array (1 .. 70) := [others => 16#FF#];
   begin
      Buffer (1) := 16#1E#;
      Buffer (2) := 16#02#;  --  magic Extended_32bit
      Buffer (3) := 16#02#;
      Buffer (4) := 16#00#;  --  names_size=2
      Buffer (5) := 16#00#;
      Buffer (6) := 16#00#;  --  bool_count=0
      Buffer (7) := 16#0E#;
      Buffer (8) := 16#00#;  --  num_count=14
      Buffer (9) := 16#00#;
      Buffer (10) := 16#00#;  --  string_count=0
      Buffer (11) := 16#00#;
      Buffer (12) := 16#00#;  --  table_size=0
      Buffer (13) := 16#74#;
      Buffer (14) := 16#00#;  --  names "t\0"
      --  Bytes 15..70 are all 0xFF (absent sentinels for 32-bit: 0xFFFFFFFF = -1).
      --  Override COLORS_INDEX=13 at bytes 67..70 with 16777216 (LE 32-bit).
      Buffer (67) := 16#00#;
      Buffer (68) := 16#00#;
      Buffer (69) := 16#00#;
      Buffer (70) := 16#01#;  --  0x01000000 = 16777216
      declare
         Header  : Parsed_Header;
         Success : Boolean;
         Colors  : Integer;
      begin
         Parse_Header (Buffer => Buffer, Size => 70, Format => Extended_32bit, Header => Header, Success => Success);
         Assert (Success, "Test_TIF010_Colors_16M: Parse_Header must succeed");
         Colors := Get_Numeric (Buffer, Header, Extended_32bit, COLORS_INDEX);
         Assert (Colors = 16_777_216, "Get_Numeric: Extended_32bit LE 0x00 0x00 0x00 0x01 should return 16777216");
      end;
   end Test_TIF010_Colors_16M_Extended;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-011: Get_String
   --
   --  For Get_String tests we build buffers with a small string_count.
   --  The setaf-present test (SETAF_INDEX=359) requires string_count >= 360;
   --  all absent offsets use 0xFF,0xFF (-1).
   ---------------------------------------------------------------------------

   --  Build a buffer for string tests.
   --  names_size=2, bool_count=0, num_count=0, string_count=Str_Count,
   --  table_size=Tab_Size.  The string data immediately follows the offset table.
   --  Bool_Section_Offset = 15, Num_Section_Offset = 15 (no bools, even),
   --  String_Table_Offset = 15 (no numerics),
   --  String_Data_Offset  = 15 + Str_Count*2.
   --  Total_Standard_Size = 12 + 2 + Str_Count*2 + Tab_Size.

   procedure Test_TIF011_Setaf_Present (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  string_count=360, table_size=9 (setaf value "\x1b[%p1%dm\0").
      --  String offset table: all absent (-1) except SETAF_INDEX=359.
      --  SETAF_INDEX entry is the last entry in the offset table:
      --    bytes at: 15 + 359*2 = 15 + 718 = 733 (1-based), value = 0x00 0x00.
      --  String data starts at: 15 + 360*2 = 15 + 720 = 735.
      --  The setaf string at data offset 0: ESC [ %p1 %d m NUL = 7 chars + NUL.
      --  Total_Standard_Size = 12 + 2 + 360*2 + 9 = 743.
      N_Str     : constant Positive := 360;
      Tab_Size  : constant Positive := 9;
      Buf_Size  : constant Positive := 12 + 2 + N_Str * 2 + Tab_Size;
      --  Buf_Size = 12 + 2 + 720 + 9 = 743
      Buffer    : Byte_Array (1 .. Buf_Size) := [others => 16#FF#];
      --  Setaf string data: ESC '[' '%' 'p' '1' '%' 'd' 'm' NUL
      Setaf_Str : constant Byte_Array (1 .. 9) :=
        [16#1B#, 16#5B#, 16#25#, 16#70#, 16#31#, 16#25#, 16#64#, 16#6D#, 16#00#];
   begin
      --  Header
      Buffer (1) := 16#1A#;
      Buffer (2) := 16#01#;  --  magic Legacy
      Buffer (3) := 16#02#;
      Buffer (4) := 16#00#;  --  names_size=2
      Buffer (5) := 16#00#;
      Buffer (6) := 16#00#;  --  bool_count=0
      Buffer (7) := 16#00#;
      Buffer (8) := 16#00#;  --  num_count=0
      --  string_count=360 (0x0168)
      Buffer (9) := 16#68#;
      Buffer (10) := 16#01#;
      --  table_size=9
      Buffer (11) := 16#09#;
      Buffer (12) := 16#00#;
      --  Names section (bytes 13..14): "t\0"
      Buffer (13) := 16#74#;
      Buffer (14) := 16#00#;
      --  String offset table: bytes 15..734 (720 bytes).
      --  Already set to 0xFF by `others => 16#FF#`.
      --  Override SETAF_INDEX=359 entry: bytes at 15 + 359*2 = 733 and 734.
      --  Value = 0 (offset 0 in string data table) -> LE: 0x00, 0x00.
      Buffer (733) := 16#00#;
      Buffer (734) := 16#00#;
      --  String data section: bytes 735..743 (9 bytes).
      for I in 1 .. 9 loop
         Buffer (734 + I) := Setaf_Str (I);
      end loop;
      declare
         Header  : Parsed_Header;
         Success : Boolean;
         Result  : Capability_String;
         Present : Boolean;
      begin
         Parse_Header
           (Buffer => Buffer, Size => Buf_Size, Format => Legacy_16bit, Header => Header, Success => Success);
         Assert (Success, "Test_TIF011_Setaf_Present: Parse_Header must succeed");
         Get_String (Buffer, Header, SETAF_INDEX, Result, Present);
         Assert (Present, "Get_String: setaf at SETAF_INDEX should be Present=True");
         Assert (Result.Length > 0, "Get_String: setaf result should have non-zero Length");
         --  First byte of setaf should be ESC (0x1B = Character'Val (27))
         Assert (Result.Data (1) = Character'Val (16#1B#), "Get_String: first byte of setaf should be ESC (0x1B)");
      end;
   end Test_TIF011_Setaf_Present;

   procedure Test_TIF011_String_Absent (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  string_count=2, both offset entries = -1 (0xFF, 0xFF).
      --  Total_Standard_Size = 12 + 2 + 2*2 + 0 = 18.
      Buffer  : constant Byte_Array (1 .. 18) :=
        [16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#02#,
         16#00#,  --  string_count=2
         16#00#,
         16#00#,  --  table_size=0
         16#74#,
         16#00#,  --  names "t\0"
         16#FF#,
         16#FF#,  --  string offset[0] = -1 (absent)
         16#FF#,
         16#FF#]; --  string offset[1] = -1 (absent)
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Capability_String;
      Present : Boolean;
   begin
      Parse_Header (Buffer, 18, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF011_String_Absent: Parse_Header must succeed");
      Get_String (Buffer, Header, 0, Result, Present);
      Assert (not Present, "Get_String: absent offset (-1) should return Present=False");
      Assert (Result.Length = 0, "Get_String: absent string should have Length=0");
   end Test_TIF011_String_Absent;

   procedure Test_TIF011_String_Out_Of_Range (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  string_count=1, query index=5 (out of range).
      Buffer  : constant Byte_Array (1 .. 16) :=
        [16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#01#,
         16#00#,  --  string_count=1
         16#00#,
         16#00#,  --  table_size=0
         16#74#,
         16#00#,  --  names
         16#00#,
         16#00#]; --  string offset[0] = 0 (would be valid, but index 5 is OOB)
      Header  : Parsed_Header;
      Success : Boolean;
      Result  : Capability_String;
      Present : Boolean;
   begin
      Parse_Header (Buffer, 16, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF011_String_OOB: Parse_Header must succeed");
      --  String_Count=1, so index 5 is out of range.
      Get_String (Buffer, Header, 5, Result, Present);
      Assert (not Present, "Get_String: index >= String_Count should return Present=False");
      Assert (Result.Length = 0, "Get_String: out-of-range string should have Length=0");
   end Test_TIF011_String_Out_Of_Range;

   procedure Test_TIF011_String_Truncated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Build a string that is MAX_CAPABILITY_STRING_LENGTH + 10 bytes long
      --  (without NUL terminator within the range), so that the copy stops
      --  at MAX_CAPABILITY_STRING_LENGTH bytes.
      --  string_count=1, table_size = MAX + 10 + 1 (extra NUL well beyond max).
      Long_Size : constant Positive := MAX_CAPABILITY_STRING_LENGTH + 11;
      --  names_size=2, bool_count=0, num_count=0, string_count=1, table_size=Long_Size
      --  Total_Standard_Size = 12 + 2 + 1*2 + Long_Size = 16 + Long_Size = 16 + 75 = 91.
      Buf_Size  : constant Positive := 16 + Long_Size;
      Buffer    : Byte_Array (1 .. Buf_Size) := [others => 16#41#];  --  fill with 'A'
   begin
      --  Header
      Buffer (1) := 16#1A#;
      Buffer (2) := 16#01#;
      Buffer (3) := 16#02#;
      Buffer (4) := 16#00#;  --  names_size=2
      Buffer (5) := 16#00#;
      Buffer (6) := 16#00#;  --  bool_count=0
      Buffer (7) := 16#00#;
      Buffer (8) := 16#00#;  --  num_count=0
      Buffer (9) := 16#01#;
      Buffer (10) := 16#00#;  --  string_count=1
      Buffer (11) := LE16_Lo (Long_Size);
      Buffer (12) := LE16_Hi (Long_Size);              --  table_size
      Buffer (13) := 16#74#;
      Buffer (14) := 16#00#;  --  names "t\0"
      Buffer (15) := 16#00#;
      Buffer (16) := 16#00#;  --  offset[0] = 0
      --  String data section: bytes 17..17+Long_Size-1.
      --  Already filled with 0x41 ('A').
      --  Place NUL at the very last byte (well beyond MAX_CAPABILITY_STRING_LENGTH).
      Buffer (16 + Long_Size) := 16#00#;
      declare
         Header  : Parsed_Header;
         Success : Boolean;
         Result  : Capability_String;
         Present : Boolean;
      begin
         Parse_Header
           (Buffer => Buffer, Size => Buf_Size, Format => Legacy_16bit, Header => Header, Success => Success);
         Assert (Success, "Test_TIF011_Truncated: Parse_Header must succeed");
         Get_String (Buffer, Header, 0, Result, Present);
         Assert (Present, "Get_String: long string should still be Present=True");
         Assert
           (Result.Length = MAX_CAPABILITY_STRING_LENGTH,
            "Get_String: string longer than MAX should be truncated to MAX_CAPABILITY_STRING_LENGTH");
      end;
   end Test_TIF011_String_Truncated;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-012: Parse_Extended_Header
   ---------------------------------------------------------------------------

   procedure Test_TIF012_No_Extended_Section (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Buffer ends exactly at Total_Standard_Size (no room for extended section).
      --  names_size=2, bool_count=0, num_count=0, string_count=0, table_size=0.
      --  Total_Standard_Size = 12 + 2 = 14.  Buffer is exactly 14 bytes.
      Buffer  : constant Byte_Array (1 .. 14) :=
        [16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#74#,
         16#00#];
      Header  : Parsed_Header;
      Ext     : Extended_Header;
      Success : Boolean;
      Ext_Ok  : Boolean;
   begin
      Parse_Header (Buffer, 14, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF012_No_Ext: Parse_Header must succeed");
      Parse_Extended_Header (Buffer, 14, Header, Ext, Ext_Ok);
      Assert (not Ext_Ok, "Parse_Extended_Header: no room for extended section -> Success=False");
   end Test_TIF012_No_Extended_Section;

   procedure Test_TIF012_Valid_Extended_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Build a buffer with standard section + minimal extended section.
      --  Standard section:
      --    names_size=2, bool_count=0, num_count=0, string_count=0, table_size=0.
      --    Total_Standard_Size=14.  Standard bytes: 1..14.
      --  Extended section (starts at byte 15, i.e. Total_Standard_Size+1):
      --    Extended header (10 bytes):
      --      Ext_Bool_Count=1, Ext_Num_Count=0, Ext_String_Count=1,
      --      Ext_String_Entries=1, Ext_Table_Size=4.
      --    Extended bool values: 1 byte (bool[0]=1).
      --    Alignment pad: (1 bool byte) is odd -> 1 pad byte.
      --    Extended string offset table: 1 entry * 2 bytes = 2 bytes.
      --    Extended string data: 4 bytes ("RGB\0").
      --  Layout from byte 15:
      --   15..24  extended header (10 bytes)
      --   25      ext bool[0] = 1
      --   26      alignment pad
      --   27..28  ext string offset table (1 entry: 0x00 0x00)
      --   29..32  ext string data ("RGB\0")
      --  Total buffer size = 32.
      Buffer  : constant Byte_Array (1 .. 32) :=
        [ --  Standard header
         16#1A#,
         16#01#,   --  magic Legacy
         16#02#,
         16#00#,   --  names_size=2
         16#00#,
         16#00#,   --  bool_count=0
         16#00#,
         16#00#,   --  num_count=0
         16#00#,
         16#00#,   --  string_count=0
         16#00#,
         16#00#,   --  table_size=0
         16#74#,
         16#00#,   --  names "t\0"
         --  Extended section header (bytes 15..24)
         16#01#,
         16#00#,   --  Ext_Bool_Count=1
         16#00#,
         16#00#,   --  Ext_Num_Count=0
         16#01#,
         16#00#,   --  Ext_String_Count=1
         16#01#,
         16#00#,   --  Ext_String_Entries=1
         16#04#,
         16#00#,   --  Ext_Table_Size=4
         --  Extended bool values (byte 25)
         16#01#,           --  ext bool[0] = 1 (True_Value)
         --  Alignment pad (byte 26): 1 bool byte is odd -> pad
         16#00#,
         --  Extended string offset table (bytes 27..28): 1 entry, offset=0
         16#00#,
         16#00#,
         --  Extended string data (bytes 29..32): "RGB\0"
         16#52#,
         16#47#,
         16#42#,
         16#00#];
      Header  : Parsed_Header;
      Ext     : Extended_Header;
      Success : Boolean;
      Ext_Ok  : Boolean;
   begin
      Parse_Header (Buffer, 32, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF012_Valid_Ext: Parse_Header must succeed");
      Parse_Extended_Header (Buffer, 32, Header, Ext, Ext_Ok);
      Assert (Ext_Ok, "Parse_Extended_Header: valid extended section should succeed");
      Assert (Ext.Ext_Bool_Count = 1, "Parse_Extended_Header: Ext_Bool_Count should be 1");
      Assert (Ext.Ext_Num_Count = 0, "Parse_Extended_Header: Ext_Num_Count should be 0");
   end Test_TIF012_Valid_Extended_Header;


   ---------------------------------------------------------------------------
   --  FUNC-TIF-014: Extract_Truecolor_Flags
   --
   --  We reuse the same buffer layout as Test_TIF012_Valid_Extended_Header but
   --  vary the extended name content and boolean values.
   ---------------------------------------------------------------------------

   --  Build a 32-byte buffer with an extended section having one extended boolean.
   --  The extended name is given by the 4-byte Name_Data parameter ("RGB\0" or "Tc\0\0").
   function Make_Ext_Bool_Buffer (Name_Data : Byte_Array; Bool_Val : Byte) return Byte_Array is
      --  Name_Data must be exactly 4 bytes (name + NUL + optional pad).
      Buf : Byte_Array (1 .. 32) :=
        [ --  Standard header
         16#1A#,
         16#01#,
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#74#,
         16#00#,
         --  Extended header (bytes 15..24)
         16#01#,
         16#00#,  --  Ext_Bool_Count=1
         16#00#,
         16#00#,  --  Ext_Num_Count=0
         16#01#,
         16#00#,  --  Ext_String_Count=1
         16#01#,
         16#00#,  --  Ext_String_Entries=1
         16#04#,
         16#00#,  --  Ext_Table_Size=4
         --  Extended bool values (byte 25)
         Bool_Val,
         --  Alignment pad (byte 26)
         16#00#,
         --  Extended string offset table (bytes 27..28): offset=0
         16#00#,
         16#00#,
         --  Extended string data (bytes 29..32): Name_Data
         Name_Data (Name_Data'First),
         Name_Data (Name_Data'First + 1),
         Name_Data (Name_Data'First + 2),
         Name_Data (Name_Data'First + 3)];
   begin
      return Buf;
   end Make_Ext_Bool_Buffer;

   procedure Test_TIF014_RGB_Flag_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Extended boolean named "RGB" with value 1 -> Has_RGB = True.
      --  Name "RGB\0" = 0x52 0x47 0x42 0x00.
      RGB_Name : constant Byte_Array (1 .. 4) := [16#52#, 16#47#, 16#42#, 16#00#];
      Buffer   : constant Byte_Array := Make_Ext_Bool_Buffer (RGB_Name, 16#01#);
      Header   : Parsed_Header;
      Ext      : Extended_Header;
      Success  : Boolean;
      Ext_Ok   : Boolean;
      Has_RGB  : Boolean;
      Has_Tc   : Boolean;
   begin
      Parse_Header (Buffer, 32, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF014_RGB: Parse_Header must succeed");
      Parse_Extended_Header (Buffer, 32, Header, Ext, Ext_Ok);
      Assert (Ext_Ok, "Test_TIF014_RGB: Parse_Extended_Header must succeed");
      Extract_Truecolor_Flags (Buffer, Header, Ext, Legacy_16bit, Has_RGB, Has_Tc);
      Assert (Has_RGB, "Extract_Truecolor_Flags: extended bool 'RGB'=1 should set Has_RGB=True");
      Assert (not Has_Tc, "Extract_Truecolor_Flags: no 'Tc' present, Has_Tc should be False");
   end Test_TIF014_RGB_Flag_True;

   procedure Test_TIF014_Tc_Flag_True (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Extended boolean named "Tc" with value 1 -> Has_Tc = True.
      --  Name "Tc\0\0" = 0x54 0x63 0x00 0x00 (padded to 4 bytes).
      Tc_Name : constant Byte_Array (1 .. 4) := [16#54#, 16#63#, 16#00#, 16#00#];
      Buffer  : constant Byte_Array := Make_Ext_Bool_Buffer (Tc_Name, 16#01#);
      Header  : Parsed_Header;
      Ext     : Extended_Header;
      Success : Boolean;
      Ext_Ok  : Boolean;
      Has_RGB : Boolean;
      Has_Tc  : Boolean;
   begin
      Parse_Header (Buffer, 32, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF014_Tc: Parse_Header must succeed");
      Parse_Extended_Header (Buffer, 32, Header, Ext, Ext_Ok);
      Assert (Ext_Ok, "Test_TIF014_Tc: Parse_Extended_Header must succeed");
      Extract_Truecolor_Flags (Buffer, Header, Ext, Legacy_16bit, Has_RGB, Has_Tc);
      Assert (Has_Tc, "Extract_Truecolor_Flags: extended bool 'Tc'=1 should set Has_Tc=True");
      Assert (not Has_RGB, "Extract_Truecolor_Flags: no 'RGB' present, Has_RGB should be False");
   end Test_TIF014_Tc_Flag_True;

   procedure Test_TIF014_No_Truecolor_Flags (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Extended boolean named "Xy" (neither RGB nor Tc) -> both flags False.
      --  Name "Xy\0\0" = 0x58 0x79 0x00 0x00.
      Other_Name : constant Byte_Array (1 .. 4) := [16#58#, 16#79#, 16#00#, 16#00#];
      Buffer     : constant Byte_Array := Make_Ext_Bool_Buffer (Other_Name, 16#01#);
      Header     : Parsed_Header;
      Ext        : Extended_Header;
      Success    : Boolean;
      Ext_Ok     : Boolean;
      Has_RGB    : Boolean;
      Has_Tc     : Boolean;
   begin
      Parse_Header (Buffer, 32, Legacy_16bit, Header, Success);
      Assert (Success, "Test_TIF014_No_Flags: Parse_Header must succeed");
      Parse_Extended_Header (Buffer, 32, Header, Ext, Ext_Ok);
      Assert (Ext_Ok, "Test_TIF014_No_Flags: Parse_Extended_Header must succeed");
      Extract_Truecolor_Flags (Buffer, Header, Ext, Legacy_16bit, Has_RGB, Has_Tc);
      Assert (not Has_RGB, "Extract_Truecolor_Flags: unrelated extended bool -> Has_RGB=False");
      Assert (not Has_Tc, "Extract_Truecolor_Flags: unrelated extended bool -> Has_Tc=False");
   end Test_TIF014_No_Truecolor_Flags;


   ---------------------------------------------------------------------------
   --  Parse_Buffer (convenience function)
   ---------------------------------------------------------------------------

   procedure Test_Parse_Buffer_Valid_Legacy (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Minimal valid legacy buffer with colors=8 at COLORS_INDEX=13.
      --  names_size=2, bool_count=0, num_count=14, string_count=0, table_size=0.
      --  Total_Standard_Size = 12 + 2 + 14*2 + 0 + 0 = 42.
      --  COLORS_INDEX=13 at bytes 41..42 (15 + 13*2 = 41), value 8 (LE: 0x08, 0x00).
      Buffer : Byte_Array (1 .. 42) := [others => 16#FF#];
      Result : Terminfo_Result;
   begin
      Buffer (1) := 16#1A#;
      Buffer (2) := 16#01#;
      Buffer (3) := 16#02#;
      Buffer (4) := 16#00#;  --  names_size=2
      Buffer (5) := 16#00#;
      Buffer (6) := 16#00#;  --  bool_count=0
      Buffer (7) := 16#0E#;
      Buffer (8) := 16#00#;  --  num_count=14
      Buffer (9) := 16#00#;
      Buffer (10) := 16#00#;  --  string_count=0
      Buffer (11) := 16#00#;
      Buffer (12) := 16#00#;  --  table_size=0
      Buffer (13) := 16#74#;
      Buffer (14) := 16#00#;  --  names "t\0"
      --  bytes 15..42: 0xFF (absent for all 14 numerics).
      --  Override COLORS_INDEX=13 at bytes 41..42 with value 8.
      Buffer (41) := 16#08#;
      Buffer (42) := 16#00#;
      Result := Parse_Buffer (Buffer, 42);
      Assert (Result.Success, "Parse_Buffer: valid legacy buffer should return Success=True");
      Assert (Result.Snapshot.Colors = 8, "Parse_Buffer: Colors capability should be 8");
      Assert (not Result.Snapshot.Has_Setaf, "Parse_Buffer: Has_Setaf should be False (no string capabilities)");
      Assert (not Result.Snapshot.Has_Setab, "Parse_Buffer: Has_Setab should be False (no string capabilities)");
      Assert (not Result.Snapshot.Has_RGB_Flag, "Parse_Buffer: Has_RGB_Flag should be False (no extended section)");
      Assert (not Result.Snapshot.Has_Tc_Flag, "Parse_Buffer: Has_Tc_Flag should be False (no extended section)");
   end Test_Parse_Buffer_Valid_Legacy;

   procedure Test_Parse_Buffer_Wrong_Magic (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  First two bytes 0xAD 0xDE (0xDEAD) -> Error_Invalid_Magic.
      Buffer : constant Byte_Array (1 .. 14) :=
        [16#AD#,
         16#DE#,  --  wrong magic
         16#02#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#00#,
         16#74#,
         16#00#];
      Result : constant Terminfo_Result := Parse_Buffer (Buffer, 14);
   begin
      Assert (not Result.Success, "Parse_Buffer: wrong magic should return Success=False");
      Assert (Result.Error = Error_Invalid_Magic, "Parse_Buffer: wrong magic should return Error_Invalid_Magic");
   end Test_Parse_Buffer_Wrong_Magic;

   procedure Test_Parse_Buffer_Too_Short (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Valid legacy magic but only 2 bytes total.  The precondition Size >= 2
      --  is satisfied, but Parse_Header requires Size >= HEADER_SIZE=12 which fails,
      --  so Parse_Buffer should return Error_Header_Corrupt.
      Buffer : constant Byte_Array (1 .. 2) := [16#1A#, 16#01#];
      Result : constant Terminfo_Result := Parse_Buffer (Buffer, 2);
   begin
      Assert (not Result.Success, "Parse_Buffer: 2-byte buffer with valid magic but no header should fail");
      --  The implementation may return Error_Header_Corrupt since header parsing fails.
      Assert
        (Result.Error = Error_Header_Corrupt,
         "Parse_Buffer: buffer too short for header should return Error_Header_Corrupt");
   end Test_Parse_Buffer_Too_Short;

end Test_Terminfo;
