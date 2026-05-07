-------------------------------------------------------------------------------
--  Termicap.Terminfo - Terminfo Database Binary Parser Types and Functions (Body)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK implementations of all terminfo binary parsing functions.
--
--  @description
--  All functions operate on a Byte_Array bounded by a Size parameter.
--  No heap allocation occurs.  Loop bounds are explicit for SPARK Silver proof.
--  Little-endian byte reconstruction is performed explicitly from byte pairs
--  (or quadruples for 32-bit fields) to avoid Unchecked_Conversion.
--
--  Requirements Coverage:
--    - @relation(FUNC-TIF-007): Detect_Format
--    - @relation(FUNC-TIF-008): Parse_Header
--    - @relation(FUNC-TIF-009): Get_Boolean
--    - @relation(FUNC-TIF-010): Get_Numeric
--    - @relation(FUNC-TIF-011): Get_String
--    - @relation(FUNC-TIF-012): Parse_Extended_Header
--    - @relation(FUNC-TIF-013): Extended capability name resolution
--    - @relation(FUNC-TIF-014): Extract_Truecolor_Flags
--    - @relation(FUNC-TIF-018): SPARK Silver target

pragma SPARK_Mode (On);

with Interfaces.C;

package body Termicap.Terminfo
  with SPARK_Mode
is

   use type Interfaces.C.unsigned_char;

   ---------------------------------------------------------------------------
   --  Internal helpers
   ---------------------------------------------------------------------------

   --  Read two bytes at Buffer(Offset) and Buffer(Offset+1) as a
   --  little-endian unsigned 16-bit value, then sign-extend to Integer.
   --  Pre: Offset >= Buffer'First and then Offset + 1 <= Buffer'Last.
   function Read_LE16 (Buffer : Byte_Array; Offset : Positive) return Integer is
      Low  : constant Integer := Integer (Buffer (Offset));
      High : constant Integer := Integer (Buffer (Offset + 1));
      Raw  : Integer := Low + High * 256;
   begin
      if Raw >= 32768 then
         Raw := Raw - 65536;
      end if;
      return Raw;
   end Read_LE16;

   --  Read four bytes at Buffer(Offset..Offset+3) as a little-endian unsigned
   --  32-bit value, then sign-extend to Integer.
   --  Pre: Offset >= Buffer'First and then Offset + 3 <= Buffer'Last.
   function Read_LE32 (Buffer : Byte_Array; Offset : Positive) return Integer is
      B0  : constant Integer := Integer (Buffer (Offset));
      B1  : constant Integer := Integer (Buffer (Offset + 1));
      B2  : constant Integer := Integer (Buffer (Offset + 2));
      B3  : constant Integer := Integer (Buffer (Offset + 3));
      Raw : Integer := B0 + B1 * 256 + B2 * 65536 + B3 * 16777216;
   begin
      --  Sign-extend: if the high bit (bit 31) is set, the value is negative.
      --  We detect this by checking B3 >= 128 (MSB of the 4th byte).
      if B3 >= 128 then
         --  Recompute as signed 32-bit: subtract 2**32 = 4294967296.
         --  Use the two-complement formula directly from bytes to avoid overflow.
         Raw := B0 + B1 * 256 + B2 * 65536 + (B3 - 256) * 16777216;
      end if;
      return Raw;
   end Read_LE32;

   ---------------------------------------------------------------------------
   --  Format Detection (FUNC-TIF-007)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-007): Detect_Format pure function with SPARK contract
   function Detect_Format (Buffer : Byte_Array; Size : Natural) return Terminfo_Format is
      pragma Unreferenced (Size);
      Low   : constant Integer := Integer (Buffer (Buffer'First));
      High  : constant Integer := Integer (Buffer (Buffer'First + 1));
      Magic : constant Integer := Low + High * 256;
   begin
      if Magic = MAGIC_LEGACY then
         return Legacy_16bit;
      elsif Magic = MAGIC_EXTENDED then
         return Extended_32bit;
      else
         return Unknown;
      end if;
   end Detect_Format;

   ---------------------------------------------------------------------------
   --  Header Parsing (FUNC-TIF-008)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-008): Parse_Header procedure with SPARK pre/post contracts
   procedure Parse_Header
     (Buffer : Byte_Array; Size : Natural; Format : Terminfo_Format; Header : out Parsed_Header; Success : out Boolean)
   is
      --  Byte size of each numeric field: 2 for Legacy_16bit, 4 for Extended_32bit.
      Num_Size : constant Natural := (if Format = Extended_32bit then 4 else 2);

      --  Offsets of the five header fields (1-based in Buffer, starting at byte 3).
      Names_Size_Offset   : constant Positive := Buffer'First + 2;
      Bool_Count_Offset   : constant Positive := Buffer'First + 4;
      Num_Count_Offset    : constant Positive := Buffer'First + 6;
      String_Count_Offset : constant Positive := Buffer'First + 8;
      Table_Size_Offset   : constant Positive := Buffer'First + 10;

      Names_Size_Val   : Natural;
      Bool_Count_Val   : Natural;
      Num_Count_Val    : Natural;
      String_Count_Val : Natural;
      Table_Size_Val   : Natural;

      --  Computed section offsets (all 1-based indices into Buffer).
      Bool_Off      : Positive;
      Num_Off       : Positive;
      Str_Table_Off : Positive;
      Str_Data_Off  : Positive;
      Total_Size    : Natural;

      Align_Pad : Natural;

      Raw_Val : Integer;
   begin
      --  Initialise output to a safe default.
      Header :=
        (Format              => Format,
         Names_Size          => 0,
         Bool_Count          => 0,
         Num_Count           => 0,
         String_Count        => 0,
         Table_Size          => 0,
         Bool_Section_Offset => 1,
         Num_Section_Offset  => 1,
         String_Table_Offset => 1,
         String_Data_Offset  => 1,
         Total_Standard_Size => 1);
      Success := False;

      --  Verify the buffer is large enough for the header (precondition guarantees
      --  Size >= HEADER_SIZE, but we also need Buffer'First + 11 to be in range).
      if Size < HEADER_SIZE then
         return;
      end if;

      --  Bounds check: header fields span Buffer'First+2 .. Buffer'First+11.
      if Table_Size_Offset + 1 > Buffer'Last then
         return;
      end if;

      --  Read all five header fields as unsigned 16-bit LE values.
      --  Names_Size
      Raw_Val := Read_LE16 (Buffer, Names_Size_Offset);
      if Raw_Val < 1 or else Raw_Val > MAX_NAMES_SECTION_SIZE then
         return;
      end if;
      Names_Size_Val := Natural (Raw_Val);

      --  Bool_Count
      Raw_Val := Read_LE16 (Buffer, Bool_Count_Offset);
      if Raw_Val < 0 or else Raw_Val > MAX_BOOL_COUNT then
         return;
      end if;
      Bool_Count_Val := Natural (Raw_Val);

      --  Num_Count
      Raw_Val := Read_LE16 (Buffer, Num_Count_Offset);
      if Raw_Val < 0 or else Raw_Val > MAX_NUM_COUNT then
         return;
      end if;
      Num_Count_Val := Natural (Raw_Val);

      --  String_Count
      Raw_Val := Read_LE16 (Buffer, String_Count_Offset);
      if Raw_Val < 0 or else Raw_Val > MAX_STRING_COUNT then
         return;
      end if;
      String_Count_Val := Natural (Raw_Val);

      --  Table_Size
      Raw_Val := Read_LE16 (Buffer, Table_Size_Offset);
      if Raw_Val < 0 or else Raw_Val > MAX_STRING_TABLE_SIZE then
         return;
      end if;
      Table_Size_Val := Natural (Raw_Val);

      --  Compute section offsets.
      --  Boolean section starts immediately after the names section.
      --  Bool_Section_Offset = HEADER_SIZE + Names_Size + 1 (1-based).
      --  We use Buffer'First as the base to stay within Buffer bounds.
      Bool_Off := Buffer'First + HEADER_SIZE + Names_Size_Val;

      --  Alignment padding after booleans: if (Names_Size + Bool_Count) is odd,
      --  insert one padding byte before the numeric section.
      if (Names_Size_Val + Bool_Count_Val) mod 2 = 1 then
         Align_Pad := 1;
      else
         Align_Pad := 0;
      end if;

      --  Numeric section starts after booleans + alignment pad.
      Num_Off := Bool_Off + Bool_Count_Val + Align_Pad;

      --  String offset table starts after the numeric section.
      Str_Table_Off := Num_Off + Num_Count_Val * Num_Size;

      --  String data table starts after the string offset table.
      Str_Data_Off := Str_Table_Off + String_Count_Val * 2;

      --  Total bytes consumed by the standard sections.
      Total_Size := Str_Data_Off + Table_Size_Val - Buffer'First;

      --  Validate that all sections fit within the buffer.
      if Total_Size > Size then
         return;
      end if;

      --  Validate that offsets are within the Buffer index range.
      --  (Specifically, Bool_Section_Offset must be a valid Positive.)
      if Bool_Off < 1 then
         return;
      end if;

      --  Populate the output header.
      Header :=
        (Format              => Format,
         Names_Size          => Names_Size_Val,
         Bool_Count          => Bool_Count_Val,
         Num_Count           => Num_Count_Val,
         String_Count        => String_Count_Val,
         Table_Size          => Table_Size_Val,
         Bool_Section_Offset => Bool_Off,
         Num_Section_Offset  => Num_Off,
         String_Table_Offset => Str_Table_Off,
         String_Data_Offset  => Str_Data_Off,
         Total_Standard_Size => Total_Size);
      Success := True;
   end Parse_Header;

   ---------------------------------------------------------------------------
   --  Boolean Capability Extraction (FUNC-TIF-009)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-009): Get_Boolean pure function
   function Get_Boolean (Buffer : Byte_Array; Header : Parsed_Header; Index : Natural) return Boolean_Cap_Value is
      B : Byte;
   begin
      --  Out-of-range index -> Absent.
      if Index >= Header.Bool_Count then
         return Absent;
      end if;

      --  Bounds check: Bool_Section_Offset + Index must be a valid buffer index.
      if Header.Bool_Section_Offset + Index > Buffer'Last then
         return Absent;
      end if;

      B := Buffer (Header.Bool_Section_Offset + Index);

      if B = 16#01# then
         return True_Value;
      elsif B = 16#00# then
         return False_Value;
      elsif B = 16#FF# then
         return Cancelled;
      else
         return Absent;
      end if;
   end Get_Boolean;

   ---------------------------------------------------------------------------
   --  Numeric Capability Extraction (FUNC-TIF-010)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-010): Get_Numeric pure function with SPARK postcondition
   function Get_Numeric
     (Buffer : Byte_Array; Header : Parsed_Header; Format : Terminfo_Format; Index : Natural) return Integer
   is
      Num_Size : constant Positive := (if Format = Extended_32bit then 4 else 2);
      Offset   : Natural;
      Value    : Integer;
   begin
      --  Out-of-range index -> ABSENT_NUMERIC.
      if Index >= Header.Num_Count then
         return ABSENT_NUMERIC;
      end if;

      --  Compute the byte offset of this entry.
      Offset := Header.Num_Section_Offset + Index * Num_Size;

      --  Bounds check.
      if Offset + Num_Size - 1 > Buffer'Last then
         return ABSENT_NUMERIC;
      end if;

      if Format = Extended_32bit then
         Value := Read_LE32 (Buffer, Offset);
      else
         Value := Read_LE16 (Buffer, Offset);
      end if;

      --  Postcondition: result >= CANCELLED_NUMERIC.
      if Value < CANCELLED_NUMERIC then
         return CANCELLED_NUMERIC;
      end if;

      return Value;
   end Get_Numeric;

   ---------------------------------------------------------------------------
   --  String Capability Extraction (FUNC-TIF-011)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-011): Get_String procedure with SPARK pre/post contracts
   procedure Get_String
     (Buffer  : Byte_Array;
      Header  : Parsed_Header;
      Index   : Natural;
      Result  : out Capability_String;
      Present : out Boolean)
   is
      Offset_Pos   : Natural;
      Str_Offset   : Integer;
      String_Start : Natural;
      Copy_Index   : Natural;
   begin
      --  Initialise outputs.
      Result := (Data => [others => ' '], Length => 0);
      Present := False;

      --  Out-of-range index.
      if Index >= Header.String_Count then
         return;
      end if;

      --  Compute position in the string offset table.
      Offset_Pos := Header.String_Table_Offset + Index * 2;

      --  Bounds check for the 2-byte offset entry.
      if Offset_Pos + 1 > Buffer'Last then
         return;
      end if;

      --  Read the 16-bit signed offset.
      Str_Offset := Read_LE16 (Buffer, Offset_Pos);

      --  Absent (-1) or cancelled (-2) -> not present.
      if Str_Offset < 0 then
         return;
      end if;

      --  Compute the start of the string in the data table.
      String_Start := Header.String_Data_Offset + Natural (Str_Offset);

      --  Bounds check: at least one byte must be within the buffer.
      if String_Start > Buffer'Last then
         return;
      end if;

      --  Copy bytes until NUL or MAX_CAPABILITY_STRING_LENGTH, whichever first.
      Copy_Index := 1;
      loop
         pragma Loop_Variant (Increases => Copy_Index);
         pragma Loop_Invariant (Copy_Index >= 1 and then Copy_Index <= MAX_CAPABILITY_STRING_LENGTH + 1);
         exit when Copy_Index > MAX_CAPABILITY_STRING_LENGTH;
         exit when String_Start + Copy_Index - 1 > Buffer'Last;
         exit when Buffer (String_Start + Copy_Index - 1) = 0;
         Result.Data (Copy_Index) := Character'Val (Natural (Buffer (String_Start + Copy_Index - 1)));
         Copy_Index := Copy_Index + 1;
      end loop;

      Result.Length := Copy_Index - 1;
      Present := Copy_Index > 1;
   end Get_String;

   ---------------------------------------------------------------------------
   --  Extended Section Header Parsing (FUNC-TIF-012)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-012): Parse_Extended_Header procedure
   procedure Parse_Extended_Header
     (Buffer : Byte_Array; Size : Natural; Header : Parsed_Header; Ext : out Extended_Header; Success : out Boolean)
   is
      EXT_HEADER_SIZE : constant := 10;  --  5 x 2-byte LE fields

      --  Where the extended section begins (1-based buffer index).
      Ext_Start_Pos : Positive;

      --  Alignment: if Total_Standard_Size is odd (relative to file start),
      --  insert one byte of padding before the extended header.
      Align_Pad : Natural;

      --  Extended header field values.
      Ext_Bool_Count_Val     : Natural;
      Ext_Num_Count_Val      : Natural;
      Ext_String_Count_Val   : Natural;
      Ext_String_Entries_Val : Natural;
      Ext_Table_Size_Val     : Natural;

      --  Computed offsets within the extended section.
      Ext_Bool_Off      : Natural;
      Ext_Num_Off       : Natural;
      Ext_Str_Table_Off : Natural;
      Ext_Data_Off      : Natural;

      Num_Size : constant Positive := (if Header.Format = Extended_32bit then 4 else 2);

      Ext_Bool_Pad : Natural;
      Raw_Val      : Integer;
   begin
      --  Initialise output.
      Ext :=
        (Ext_Bool_Count       => 0,
         Ext_Num_Count        => 0,
         Ext_String_Count     => 0,
         Ext_String_Entries   => 0,
         Ext_Table_Size       => 0,
         Ext_Start            => 1,
         Ext_Bool_Offset      => 1,
         Ext_Num_Offset       => 1,
         Ext_Str_Table_Offset => 1,
         Ext_Data_Offset      => 1);
      Success := False;

      --  Need at least EXT_HEADER_SIZE bytes beyond the standard section.
      if Header.Total_Standard_Size + EXT_HEADER_SIZE > Size then
         return;
      end if;

      --  Compute the starting offset of the extended section.
      --  Buffer'First is the 1-based start of the buffer.
      --  Total_Standard_Size is the number of bytes consumed by standard sections.
      --  So the extended section starts at Buffer'First + Total_Standard_Size.
      --  But first apply alignment padding (file-relative offset must be even).
      if Header.Total_Standard_Size mod 2 = 1 then
         Align_Pad := 1;
      else
         Align_Pad := 0;
      end if;

      --  Extended section start index (1-based in Buffer).
      Ext_Start_Pos := Buffer'First + Header.Total_Standard_Size + Align_Pad;

      --  Recheck with alignment padding.
      if Ext_Start_Pos + EXT_HEADER_SIZE - 1 > Buffer'Last then
         return;
      end if;

      if Ext_Start_Pos + EXT_HEADER_SIZE - 1 > Size then
         return;
      end if;

      --  Read the 5 extended header fields.
      --  Ext_Bool_Count
      Raw_Val := Read_LE16 (Buffer, Ext_Start_Pos);
      if Raw_Val < 0 or else Raw_Val > 64 then
         return;
      end if;
      Ext_Bool_Count_Val := Natural (Raw_Val);

      --  Ext_Num_Count
      Raw_Val := Read_LE16 (Buffer, Ext_Start_Pos + 2);
      if Raw_Val < 0 or else Raw_Val > 128 then
         return;
      end if;
      Ext_Num_Count_Val := Natural (Raw_Val);

      --  Ext_String_Count
      Raw_Val := Read_LE16 (Buffer, Ext_Start_Pos + 4);
      if Raw_Val < 0 or else Raw_Val > 256 then
         return;
      end if;
      Ext_String_Count_Val := Natural (Raw_Val);

      --  Ext_String_Entries
      Raw_Val := Read_LE16 (Buffer, Ext_Start_Pos + 6);
      if Raw_Val < 0 or else Raw_Val > 256 then
         return;
      end if;
      Ext_String_Entries_Val := Natural (Raw_Val);

      --  Ext_Table_Size
      Raw_Val := Read_LE16 (Buffer, Ext_Start_Pos + 8);
      if Raw_Val < 0 or else Raw_Val > 8192 then
         return;
      end if;
      Ext_Table_Size_Val := Natural (Raw_Val);

      --  Compute extended section data offsets.
      --  Extended bool values start immediately after the extended header.
      Ext_Bool_Off := Ext_Start_Pos + EXT_HEADER_SIZE;

      --  Alignment after extended booleans.
      if Ext_Bool_Count_Val mod 2 = 1 then
         Ext_Bool_Pad := 1;
      else
         Ext_Bool_Pad := 0;
      end if;

      --  Extended numeric values start after extended bools + alignment.
      Ext_Num_Off := Ext_Bool_Off + Ext_Bool_Count_Val + Ext_Bool_Pad;

      --  Extended string offset table starts after extended numerics.
      Ext_Str_Table_Off := Ext_Num_Off + Ext_Num_Count_Val * Num_Size;

      --  Extended string data table starts after the extended string offset table.
      --  The offset table contains Ext_String_Count entries (values + names).
      Ext_Data_Off := Ext_Str_Table_Off + Ext_String_Count_Val * 2;

      --  Validate that all extended sections fit within the buffer.
      if Ext_Data_Off - 1 + Ext_Table_Size_Val > Size then
         return;
      end if;

      --  All offsets must be valid Positive values.
      if Ext_Bool_Off < 1 or else Ext_Num_Off < 1 or else Ext_Str_Table_Off < 1 or else Ext_Data_Off < 1 then
         return;
      end if;

      --  Populate the extended header.
      Ext :=
        (Ext_Bool_Count       => Ext_Bool_Count_Val,
         Ext_Num_Count        => Ext_Num_Count_Val,
         Ext_String_Count     => Ext_String_Count_Val,
         Ext_String_Entries   => Ext_String_Entries_Val,
         Ext_Table_Size       => Ext_Table_Size_Val,
         Ext_Start            => Ext_Start_Pos,
         Ext_Bool_Offset      => Ext_Bool_Off,
         Ext_Num_Offset       => Ext_Num_Off,
         Ext_Str_Table_Offset => Ext_Str_Table_Off,
         Ext_Data_Offset      => Ext_Data_Off);
      Success := True;
   end Parse_Extended_Header;

   ---------------------------------------------------------------------------
   --  Truecolor Flag Extraction (FUNC-TIF-013, FUNC-TIF-014)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-013): Extended capability name resolution loop
   --  @relation(FUNC-TIF-014): Extract_Truecolor_Flags procedure
   procedure Extract_Truecolor_Flags
     (Buffer  : Byte_Array;
      Header  : Parsed_Header;
      Ext     : Extended_Header;
      Format  : Terminfo_Format;
      Has_RGB : out Boolean;
      Has_Tc  : out Boolean)
   is
      pragma Unreferenced (Format);

      --  Number of pure string capability slots (not counting bools and nums).
      Ext_Str_Count : Natural;

      --  Total number of name entries = booleans + numerics + pure strings.
      Total_Name_Count : Natural;

      --  Position of name offset entries in the string table.
      Name_Offsets_Start : Natural;

      Name_Offset_Pos  : Natural;
      Name_Data_Offset : Integer;
      Name_Start       : Natural;

      --  For comparing names: read up to 4 bytes.
      C0, C1, C2, C3 : Byte;

      Is_RGB : Boolean;
      Is_Tc  : Boolean;

      Bool_Val : Byte;
   begin
      Has_RGB := False;
      Has_Tc := False;

      --  Ext_String_Count includes both value offsets and name offsets.
      --  Value offsets = Ext_Str_Count (pure string caps),
      --  Name offsets  = Total_Name_Count (bools + nums + pure strings).
      --  So: Ext_String_Count = Ext_Str_Count + Total_Name_Count
      --  i.e.: Ext_String_Count = (Ext_String_Count - Ext_Bool_Count - Ext_Num_Count)
      --                           + (Ext_Bool_Count + Ext_Num_Count + Ext_Str_Count)
      --  From the spec: Ext_Str_Count = Ext_String_Count - Ext_Bool_Count - Ext_Num_Count
      --  Total_Name_Count = Ext_Bool_Count + Ext_Num_Count + Ext_Str_Count
      --                   = Ext_Bool_Count + Ext_Num_Count
      --                     + (Ext_String_Count - Ext_Bool_Count - Ext_Num_Count)
      --                   = Ext_String_Count

      if Ext.Ext_String_Count < Ext.Ext_Bool_Count + Ext.Ext_Num_Count then
         --  Malformed extended header; treat as no names.
         return;
      end if;

      Ext_Str_Count := Ext.Ext_String_Count - Ext.Ext_Bool_Count - Ext.Ext_Num_Count;
      Total_Name_Count := Ext.Ext_Bool_Count + Ext.Ext_Num_Count + Ext_Str_Count;

      --  The name offset entries follow the value offset entries in the table.
      --  Value entries: Ext_Str_Count * 2 bytes (one 16-bit offset per pure string cap).
      --  Name entries start at: Ext_Str_Table_Offset + Ext_Str_Count * 2.
      Name_Offsets_Start := Ext.Ext_Str_Table_Offset + Ext_Str_Count * 2;

      --  Iterate over all name entries.
      for I in 0 .. Total_Name_Count - 1 loop
         pragma Loop_Variant (Increases => I);
         pragma Loop_Invariant (I >= 0 and then I < Total_Name_Count);

         --  Offset of this name's 16-bit offset entry in the string offset table.
         Name_Offset_Pos := Name_Offsets_Start + I * 2;

         --  Bounds check for the 2-byte name offset entry.
         if Name_Offset_Pos + 1 > Buffer'Last then
            exit;
         end if;

         Name_Data_Offset := Read_LE16 (Buffer, Name_Offset_Pos);

         --  Skip absent/cancelled entries.
         if Name_Data_Offset < 0 then
            goto Next_Name;
         end if;

         --  Compute the start of the name string in the data table.
         Name_Start := Ext.Ext_Data_Offset + Natural (Name_Data_Offset);

         --  We need at least one byte for the name.
         if Name_Start > Buffer'Last then
            goto Next_Name;
         end if;

         --  Read the first byte of the name.
         C0 := Buffer (Name_Start);

         --  Check for "RGB" (3 chars + NUL):
         --  'R'=0x52, 'G'=0x47, 'B'=0x42.
         Is_RGB := False;
         if C0 = 16#52# then
            --  First char is 'R'; check 'G', 'B', NUL.
            if Name_Start + 3 <= Buffer'Last then
               C1 := Buffer (Name_Start + 1);
               C2 := Buffer (Name_Start + 2);
               C3 := Buffer (Name_Start + 3);
               if C1 = 16#47# and then C2 = 16#42# and then C3 = 0 then
                  Is_RGB := True;
               end if;
            elsif Name_Start + 2 <= Buffer'Last then
               C1 := Buffer (Name_Start + 1);
               C2 := Buffer (Name_Start + 2);
               if C1 = 16#47# and then C2 = 16#42# then
                  --  No NUL found but still could be "RGB" (truncated buffer).
                  Is_RGB := True;
               end if;
            end if;
         end if;

         --  Check for "Tc" (2 chars + NUL):
         --  'T'=0x54, 'c'=0x63.
         Is_Tc := False;
         if C0 = 16#54# then
            if Name_Start + 2 <= Buffer'Last then
               C1 := Buffer (Name_Start + 1);
               C2 := Buffer (Name_Start + 2);
               if C1 = 16#63# and then C2 = 0 then
                  Is_Tc := True;
               end if;
            elsif Name_Start + 1 <= Buffer'Last then
               C1 := Buffer (Name_Start + 1);
               if C1 = 16#63# then
                  Is_Tc := True;
               end if;
            end if;
         end if;

         --  If this name matches, determine the capability type by position.
         if Is_RGB or else Is_Tc then
            if I < Ext.Ext_Bool_Count then
               --  Extended boolean: read the boolean value.
               if Ext.Ext_Bool_Offset + I <= Buffer'Last then
                  Bool_Val := Buffer (Ext.Ext_Bool_Offset + I);
                  if Bool_Val = 16#01# then
                     if Is_RGB then
                        Has_RGB := True;
                     end if;
                     if Is_Tc then
                        Has_Tc := True;
                     end if;
                  end if;
               end if;
            elsif I < Ext.Ext_Bool_Count + Ext.Ext_Num_Count then
               --  Extended numeric: value >= 1 -> set the flag.
               declare
                  Num_Idx  : constant Natural := I - Ext.Ext_Bool_Count;
                  Num_Size : constant Positive := (if Header.Format = Extended_32bit then 4 else 2);
                  Num_Off  : constant Natural := Ext.Ext_Num_Offset + Num_Idx * Num_Size;
                  Num_Val  : Integer;
               begin
                  if Num_Off + Num_Size - 1 <= Buffer'Last then
                     if Header.Format = Extended_32bit then
                        Num_Val := Read_LE32 (Buffer, Num_Off);
                     else
                        Num_Val := Read_LE16 (Buffer, Num_Off);
                     end if;
                     if Num_Val >= 1 then
                        if Is_RGB then
                           Has_RGB := True;
                        end if;
                        if Is_Tc then
                           Has_Tc := True;
                        end if;
                     end if;
                  end if;
               end;
            else
               --  Extended string: any non-empty string -> set the flag.
               --  We treat any present string (not absent, non-zero-length) as True.
               declare
                  Str_Idx     : constant Natural := I - Ext.Ext_Bool_Count - Ext.Ext_Num_Count;
                  Str_Off_Pos : constant Natural := Ext.Ext_Str_Table_Offset + Str_Idx * 2;
                  Str_Off     : Integer;
                  Str_Start   : Natural;
               begin
                  if Str_Off_Pos + 1 <= Buffer'Last then
                     Str_Off := Read_LE16 (Buffer, Str_Off_Pos);
                     if Str_Off >= 0 then
                        Str_Start := Ext.Ext_Data_Offset + Natural (Str_Off);
                        if Str_Start <= Buffer'Last and then Buffer (Str_Start) /= 0 then
                           if Is_RGB then
                              Has_RGB := True;
                           end if;
                           if Is_Tc then
                              Has_Tc := True;
                           end if;
                        end if;
                     end if;
                  end if;
               end;
            end if;
         end if;

         <<Next_Name>>
         null;
      end loop;
   end Extract_Truecolor_Flags;

   ---------------------------------------------------------------------------
   --  Terminal Name Extraction (internal helper for Parse_Buffer)
   ---------------------------------------------------------------------------

   --  Extract the primary terminal name from the names section.
   --  The names section starts at Buffer(HEADER_SIZE + 1) and is
   --  Names_Size bytes long.  We copy bytes until '|', NUL, or
   --  MAX_TERM_NAME_LENGTH, whichever comes first.
   procedure Extract_Term_Name (Buffer : Byte_Array; Header : Parsed_Header; Name : out Term_Name_String) is
      --  The names section starts at HEADER_SIZE + 1 (1-based).
      Names_Start : constant Positive := Buffer'First + HEADER_SIZE;
      Names_End   : constant Natural := Names_Start + Header.Names_Size - 1;
      Copy_Index  : Natural := 1;
      B           : Byte;
   begin
      Name := (Data => [others => ' '], Length => 0);

      loop
         pragma Loop_Variant (Increases => Copy_Index);
         pragma Loop_Invariant (Copy_Index >= 1 and then Copy_Index <= MAX_TERM_NAME_LENGTH + 1);
         exit when Copy_Index > MAX_TERM_NAME_LENGTH;
         exit when Names_Start + Copy_Index - 1 > Names_End;
         exit when Names_Start + Copy_Index - 1 > Buffer'Last;
         B := Buffer (Names_Start + Copy_Index - 1);
         exit when B = 0;            --  NUL terminator
         exit when B = Character'Pos ('|');  --  separator between names
         Name.Data (Copy_Index) := Character'Val (Natural (B));
         Copy_Index := Copy_Index + 1;
      end loop;

      Name.Length := Copy_Index - 1;
   end Extract_Term_Name;

   ---------------------------------------------------------------------------
   --  Full Buffer Parse (FUNC-TIF-007 through FUNC-TIF-014)
   ---------------------------------------------------------------------------

   --  @relation(FUNC-TIF-007): Calls Detect_Format
   --  @relation(FUNC-TIF-008): Calls Parse_Header
   --  @relation(FUNC-TIF-010): Extracts colors via Get_Numeric
   --  @relation(FUNC-TIF-011): Extracts setaf/setab via Get_String
   --  @relation(FUNC-TIF-012): Calls Parse_Extended_Header
   --  @relation(FUNC-TIF-014): Calls Extract_Truecolor_Flags
   function Parse_Buffer (Buffer : Byte_Array; Size : Natural) return Terminfo_Result is
      Format : Terminfo_Format;
      Header : Parsed_Header;
      Hdr_Ok : Boolean;
      Ext    : Extended_Header;
      Ext_Ok : Boolean;
      Snap   : Terminfo_Snapshot;
   begin
      --  Step 1: Detect format.
      Format := Detect_Format (Buffer, Size);
      if Format = Unknown then
         return (Success => False, Error => Error_Invalid_Magic);
      end if;

      --  Step 2: Parse standard header.
      if Size < HEADER_SIZE then
         return (Success => False, Error => Error_Header_Corrupt);
      end if;

      Parse_Header (Buffer => Buffer, Size => Size, Format => Format, Header => Header, Success => Hdr_Ok);

      if not Hdr_Ok then
         return (Success => False, Error => Error_Header_Corrupt);
      end if;

      --  Step 3: Extract `colors` numeric capability.
      Snap.Colors := Get_Numeric (Buffer, Header, Format, COLORS_INDEX);

      --  Step 4: Extract `setaf` string capability.
      Get_String (Buffer, Header, SETAF_INDEX, Snap.Setaf, Snap.Has_Setaf);

      --  Step 5: Extract `setab` string capability.
      Get_String (Buffer, Header, SETAB_INDEX, Snap.Setab, Snap.Has_Setab);

      --  Step 6: Extract terminal name from the names section.
      Extract_Term_Name (Buffer, Header, Snap.Term_Name);

      --  Step 7: Attempt extended section parsing (non-fatal on absence).
      Snap.Has_RGB_Flag := False;
      Snap.Has_Tc_Flag := False;

      Parse_Extended_Header (Buffer => Buffer, Size => Size, Header => Header, Ext => Ext, Success => Ext_Ok);

      --  Step 8: Extract truecolor flags if extended section is valid.
      if Ext_Ok then
         Extract_Truecolor_Flags
           (Buffer  => Buffer,
            Header  => Header,
            Ext     => Ext,
            Format  => Format,
            Has_RGB => Snap.Has_RGB_Flag,
            Has_Tc  => Snap.Has_Tc_Flag);
      end if;

      --  Step 9: Return populated snapshot.
      return (Success => True, Snapshot => Snap);
   end Parse_Buffer;

end Termicap.Terminfo;
