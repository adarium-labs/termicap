-------------------------------------------------------------------------------
--  Termicap.Terminfo - Terminfo Database Binary Parser Types and Functions
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, ghost predicates, and parsing functions for
--  the ncurses compiled terminfo binary database format.
--
--  @description
--  This package provides all SPARK-provable building blocks for the TERMINFO
--  feature: the Terminfo_Snapshot result record, the Terminfo_Result
--  discriminated type, bounded byte and string types, named constants for
--  all magic numbers and capability indices, ghost functions that encapsulate
--  header structural invariants, and pure parsing functions covering the
--  complete binary parsing pipeline.
--
--  Two ncurses terminfo binary format variants are supported:
--    Legacy_16bit   (magic 0x011A): numeric fields are 16-bit signed integers.
--    Extended_32bit (magic 0x021E): numeric fields are 32-bit signed integers.
--
--  All parsing functions carry SPARK Silver contracts.  No exceptions are used
--  or propagated; all error conditions are returned via out parameters of
--  discrete types or via the Terminfo_Result discriminated record.  The
--  file-read FFI boundary is isolated in the child package Termicap.Terminfo.IO.
--
--  Parsed_Header and Extended_Header are declared in the public section because
--  they appear in the preconditions of the public parsing functions via the ghost
--  predicates Header_Is_Valid and Extended_Is_Valid.  Callers with SPARK_Mode On
--  that reference those preconditions must be able to see the types.
--
--  Requirements Coverage:
--    - @relation(FUNC-TIF-001): Terminfo_Snapshot result record
--    - @relation(FUNC-TIF-002): Terminfo_Result error enumeration
--    - @relation(FUNC-TIF-006): Read_Error type (SPARK-visible, used by IO child)
--    - @relation(FUNC-TIF-007): Detect_Format magic number validation
--    - @relation(FUNC-TIF-008): Parse_Header section parsing and bounds validation
--    - @relation(FUNC-TIF-009): Get_Boolean capability extraction
--    - @relation(FUNC-TIF-010): Get_Numeric capability extraction
--    - @relation(FUNC-TIF-011): Get_String capability extraction
--    - @relation(FUNC-TIF-012): Parse_Extended_Header extended section detection
--    - @relation(FUNC-TIF-013): Extended capability name resolution
--    - @relation(FUNC-TIF-014): Extract_Truecolor_Flags RGB and Tc extraction
--    - @relation(FUNC-TIF-016): Immutable value-copy snapshot semantics
--    - @relation(FUNC-TIF-018): SPARK Silver target for all parsing functions

pragma SPARK_Mode (On);

package Termicap.Terminfo
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  File Size Bound (FUNC-TIF-002)
   ---------------------------------------------------------------------------

   --  @summary Maximum accepted terminfo file size in bytes (32 KiB).
   --  @description Establishes a SPARK-provable upper bound on the byte array
   --  used for parsing.  Any file larger than this value is rejected by
   --  Read_File with Read_Too_Large before any parsing is attempted.  The
   --  largest known real terminfo entry (rxvt-unicode with extensions) is
   --  under 8 KiB; 32 KiB provides ample headroom.
   --  @relation(FUNC-TIF-002): MAX_TERMINFO_FILE_SIZE named constant
   MAX_TERMINFO_FILE_SIZE : constant := 32_768;

   ---------------------------------------------------------------------------
   --  Header Validation Bounds (FUNC-TIF-008)
   ---------------------------------------------------------------------------

   --  @summary Maximum byte length of the names section (includes trailing NUL).
   --  @relation(FUNC-TIF-008): MAX_NAMES_SECTION_SIZE bound for header validation
   MAX_NAMES_SECTION_SIZE : constant := 512;

   --  @summary Maximum number of standard boolean capabilities in the header.
   --  @relation(FUNC-TIF-008): MAX_BOOL_COUNT bound for header validation
   MAX_BOOL_COUNT : constant := 64;

   --  @summary Maximum number of standard numeric capabilities in the header.
   --  @relation(FUNC-TIF-008): MAX_NUM_COUNT bound for header validation
   MAX_NUM_COUNT : constant := 512;

   --  @summary Maximum number of standard string capability offset entries.
   --  @relation(FUNC-TIF-008): MAX_STRING_COUNT bound for header validation
   MAX_STRING_COUNT : constant := 512;

   --  @summary Maximum byte size of the string data table.
   --  @relation(FUNC-TIF-008): MAX_STRING_TABLE_SIZE bound for header validation
   MAX_STRING_TABLE_SIZE : constant := 16_384;

   ---------------------------------------------------------------------------
   --  Bounded String Capacity Constants (FUNC-TIF-001)
   ---------------------------------------------------------------------------

   --  @summary Maximum character length of an extracted capability string value.
   --  @relation(FUNC-TIF-001): MAX_CAPABILITY_STRING_LENGTH named constant
   MAX_CAPABILITY_STRING_LENGTH : constant := 64;

   --  @summary Maximum character length of the terminal name from the names section.
   --  @relation(FUNC-TIF-001): MAX_TERM_NAME_LENGTH named constant
   MAX_TERM_NAME_LENGTH : constant := 64;

   ---------------------------------------------------------------------------
   --  Path Construction Bound (FUNC-TIF-005)
   ---------------------------------------------------------------------------

   --  @summary Maximum character length of a constructed terminfo file path.
   --  @description Path construction (directory / first-char / TERM) is bounded
   --  to this length.  Any candidate that would produce a longer path is skipped
   --  without error.
   --  @relation(FUNC-TIF-005): MAX_PATH_LENGTH named constant
   MAX_PATH_LENGTH : constant := 512;

   ---------------------------------------------------------------------------
   --  ncurses Numeric Sentinels (FUNC-TIF-010)
   ---------------------------------------------------------------------------

   --  @summary Sentinel value for a numeric capability that is absent (-1).
   --  @description Returned by Get_Numeric when the capability is not present
   --  in the terminfo database entry.  Matches the ncurses ABSENT_NUMERIC macro.
   --  @relation(FUNC-TIF-010): ABSENT_NUMERIC constant
   ABSENT_NUMERIC : constant Integer := -1;

   --  @summary Sentinel value for a numeric capability that has been cancelled (-2).
   --  @description Returned by Get_Numeric when the capability has been explicitly
   --  cancelled in the database.  Matches the ncurses CANCELLED_NUMERIC macro.
   --  @relation(FUNC-TIF-010): CANCELLED_NUMERIC constant
   CANCELLED_NUMERIC : constant Integer := -2;

   ---------------------------------------------------------------------------
   --  Capability Index Constants (FUNC-TIF-010, FUNC-TIF-011)
   ---------------------------------------------------------------------------

   --  @summary Standard ncurses index of the `colors` numeric capability.
   --  @description Defined in ncurses/include/Caps at index 13 in the numeric
   --  section.  Stable across all ncurses versions since 5.x.
   --  @relation(FUNC-TIF-010): COLORS_INDEX standard ncurses capability index
   COLORS_INDEX : constant Natural := 13;

   --  @summary Standard ncurses index of the `setaf` string capability.
   --  @description set_a_foreground; defined at index 359 in ncurses/include/Caps.
   --  @relation(FUNC-TIF-011): SETAF_INDEX standard ncurses capability index
   SETAF_INDEX : constant Natural := 359;

   --  @summary Standard ncurses index of the `setab` string capability.
   --  @description set_a_background; defined at index 360 in ncurses/include/Caps.
   --  @relation(FUNC-TIF-011): SETAB_INDEX standard ncurses capability index
   SETAB_INDEX : constant Natural := 360;

   ---------------------------------------------------------------------------
   --  Binary Format Constants (FUNC-TIF-007, FUNC-TIF-008)
   ---------------------------------------------------------------------------

   --  @summary Fixed byte size of the terminfo binary header.
   --  @description 2 bytes magic + 5 x 2-byte little-endian fields = 12 bytes.
   --  @relation(FUNC-TIF-008): HEADER_SIZE constant
   HEADER_SIZE : constant := 12;

   --  @summary Magic number for the legacy 16-bit terminfo format.
   --  @description Little-endian bytes 0x1A 0x01 (decimal 282).
   --  @relation(FUNC-TIF-007): MAGIC_LEGACY constant
   MAGIC_LEGACY : constant := 16#011A#;

   --  @summary Magic number for the extended 32-bit terminfo format.
   --  @description Little-endian bytes 0x1E 0x02 (decimal 542).
   --  Introduced in ncurses 6.1 (2018).
   --  @relation(FUNC-TIF-007): MAGIC_EXTENDED constant
   MAGIC_EXTENDED : constant := 16#021E#;

   ---------------------------------------------------------------------------
   --  Terminfo Binary Format Variant (FUNC-TIF-007)
   ---------------------------------------------------------------------------

   --  @summary Identifies the binary format variant detected from the magic number.
   --  @description
   --    Legacy_16bit   -- numeric fields are 2-byte signed little-endian integers.
   --    Extended_32bit -- numeric fields are 4-byte signed little-endian integers.
   --    Unknown        -- first two bytes do not match either known magic value.
   --  @relation(FUNC-TIF-007): Terminfo_Format enumeration
   type Terminfo_Format is (Legacy_16bit, Extended_32bit, Unknown);

   ---------------------------------------------------------------------------
   --  Boolean Capability Value (FUNC-TIF-009)
   ---------------------------------------------------------------------------

   --  @summary Four-valued result for standard boolean capability extraction.
   --  @description Maps the ncurses byte conventions:
   --    0x01 -> True_Value  (capability is present and set)
   --    0x00 -> False_Value (capability is present but cleared)
   --    0xFF -> Cancelled   (explicitly cancelled; ncurses ABSENT_BOOLEAN)
   --    0xFE -> Absent      (absent; ncurses CANCELLED_BOOLEAN)
   --    any other byte value -> Absent
   --  @relation(FUNC-TIF-009): Boolean_Cap_Value discrete type
   type Boolean_Cap_Value is (Absent, Cancelled, True_Value, False_Value);

   ---------------------------------------------------------------------------
   --  Read Error Type (FUNC-TIF-006)
   ---------------------------------------------------------------------------

   --  @summary Status codes for the Read_File file-loading operation.
   --  @description Declared in this SPARK On package so that SPARK callers can
   --  reference the type in contracts.  The Read_File procedure itself lives in
   --  the child package Termicap.Terminfo.IO (SPARK_Mode => Off).
   --    Read_OK        -- file read successfully; Size bytes placed in Buffer.
   --    Read_Not_Found -- file does not exist or cannot be opened.
   --    Read_IO_Error  -- file found but an I/O error occurred during reading.
   --    Read_Too_Large -- file size exceeds MAX_TERMINFO_FILE_SIZE.
   --  @relation(FUNC-TIF-006): Read_Error discrete type
   type Read_Error is (Read_OK, Read_Not_Found, Read_IO_Error, Read_Too_Large);

   ---------------------------------------------------------------------------
   --  Parse Error Codes (FUNC-TIF-002)
   ---------------------------------------------------------------------------

   --  @summary Error codes for the overall terminfo parse operation.
   --  @description Each value maps to a distinct failure mode in the pipeline.
   --  @relation(FUNC-TIF-002): Terminfo_Error enumeration
   type Terminfo_Error is
     (Error_No_Term,
      --  The TERM environment variable is not set or is empty.
      Error_File_Not_Found,
      --  No terminfo file found for TERM in any searched directory.
      Error_IO_Failure,
      --  Terminfo file found but could not be read.
      Error_Invalid_Magic,
      --  First two bytes do not match a recognised magic number.
      Error_Header_Corrupt,
      --  Header field sizes are inconsistent or cause out-of-bounds access.
      Error_File_Too_Large,
      --  File size exceeds MAX_TERMINFO_FILE_SIZE.
      Error_Encoding);
   --  A string capability contains bytes outside the expected range.

   ---------------------------------------------------------------------------
   --  Bounded String Types (FUNC-TIF-001)
   ---------------------------------------------------------------------------

   --  @summary Index subtype for Capability_String length tracking.
   subtype Capability_String_Index is Natural range 0 .. MAX_CAPABILITY_STRING_LENGTH;

   --  @summary Bounded string holding an extracted terminfo string capability value.
   --  @description Data holds the raw bytes (converted to Character); Length is
   --  the number of significant characters.  Characters beyond Length are
   --  initialised to spaces but carry no meaning.  Bounded strings are required
   --  for SPARK provability â unbounded strings involve heap allocation.
   --  @relation(FUNC-TIF-001): Bounded capability string type
   type Capability_String is record
      Data   : String (1 .. MAX_CAPABILITY_STRING_LENGTH) := [others => ' '];
      Length : Capability_String_Index := 0;
   end record;

   --  @summary Bounded string holding the primary terminal name from the names section.
   --  @description Extracted from the names section of the terminfo binary
   --  (the text before the first '|' separator, NUL-terminated).
   --  @relation(FUNC-TIF-001): Bounded terminal name string type
   type Term_Name_String is record
      Data   : String (1 .. MAX_TERM_NAME_LENGTH) := [others => ' '];
      Length : Natural range 0 .. MAX_TERM_NAME_LENGTH := 0;
   end record;

   ---------------------------------------------------------------------------
   --  Terminfo_Snapshot (FUNC-TIF-001, FUNC-TIF-016)
   ---------------------------------------------------------------------------

   --  @summary Immutable record of the terminfo capabilities relevant to color detection.
   --  @description Plain Ada record (not tagged, not limited, not controlled) to
   --  ensure value-copy semantics.  Default-constructed value represents "no
   --  capabilities detected" (Colors = ABSENT_NUMERIC, all flags False).
   --
   --  Colors       -- Value of the `colors` numeric capability.
   --                  ABSENT_NUMERIC (-1) when absent; CANCELLED_NUMERIC (-2) when cancelled.
   --  Has_Setaf    -- True when `setaf` is present and non-empty.
   --  Has_Setab    -- True when `setab` is present and non-empty.
   --  Setaf        -- Raw value of `setaf`; empty when Has_Setaf = False.
   --  Setab        -- Raw value of `setab`; empty when Has_Setab = False.
   --  Has_RGB_Flag -- True when extended `RGB` capability is present and set.
   --  Has_Tc_Flag  -- True when extended `Tc` capability is present and set.
   --  Term_Name    -- Primary terminal name from the names section.
   --  @relation(FUNC-TIF-001): Terminfo_Snapshot immutable value record
   --  @relation(FUNC-TIF-016): Plain record for value-copy immutable semantics
   type Terminfo_Snapshot is record
      Colors       : Integer := ABSENT_NUMERIC;
      Has_Setaf    : Boolean := False;
      Has_Setab    : Boolean := False;
      Setaf        : Capability_String;
      Setab        : Capability_String;
      Has_RGB_Flag : Boolean := False;
      Has_Tc_Flag  : Boolean := False;
      Term_Name    : Term_Name_String;
   end record;

   ---------------------------------------------------------------------------
   --  Terminfo_Result (FUNC-TIF-002)
   ---------------------------------------------------------------------------

   --  @summary Discriminated result type wrapping either a snapshot or an error code.
   --  @description The discriminant Success forces callers to test the variant
   --  before accessing Snapshot or Error.  Default discriminant False ensures
   --  default-initialised values represent failure.
   --  @relation(FUNC-TIF-002): Terminfo_Result discriminated result type
   type Terminfo_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Snapshot : Terminfo_Snapshot;

         when False =>
            Error : Terminfo_Error;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Internal Header Types (FUNC-TIF-008, FUNC-TIF-012)
   ---------------------------------------------------------------------------
   --  Parsed_Header and Extended_Header are declared in the public section
   --  because they appear as parameters of ghost functions (Header_Is_Valid,
   --  Extended_Is_Valid) which are referenced in preconditions of public
   --  parsing functions.  SPARK requires all types used in visible contracts
   --  to be visible to callers.
   ---------------------------------------------------------------------------

   --  @summary Parsed binary header result for the standard terminfo sections.
   --  @description Produced by Parse_Header.  All offset fields are 1-based
   --  buffer indices suitable for direct use as Byte_Array index expressions.
   --  Access is only safe when Header_Is_Valid returns True for the same Buffer.
   --
   --  Format                -- Detected format variant.
   --  Names_Size            -- Byte length of the names section (includes NUL).
   --  Bool_Count            -- Number of boolean capabilities.
   --  Num_Count             -- Number of numeric capabilities.
   --  String_Count          -- Number of string offset entries.
   --  Table_Size            -- Byte size of the string data table.
   --  Bool_Section_Offset   -- 1-based buffer index of the first boolean byte.
   --  Num_Section_Offset    -- 1-based buffer index of the first numeric byte.
   --  String_Table_Offset   -- 1-based buffer index of the string offset table.
   --  String_Data_Offset    -- 1-based buffer index of the string data table.
   --  Total_Standard_Size   -- Total bytes consumed by the standard sections.
   --  @relation(FUNC-TIF-008): Parsed_Header internal type for offset tracking
   type Parsed_Header is record
      Format              : Terminfo_Format := Unknown;
      Names_Size          : Natural := 0;
      Bool_Count          : Natural := 0;
      Num_Count           : Natural := 0;
      String_Count        : Natural := 0;
      Table_Size          : Natural := 0;
      Bool_Section_Offset : Positive := 1;
      Num_Section_Offset  : Positive := 1;
      String_Table_Offset : Positive := 1;
      String_Data_Offset  : Positive := 1;
      Total_Standard_Size : Positive := 1;
   end record;

   --  @summary Parsed extended-section header and offset cache.
   --  @description Produced by Parse_Extended_Header.  All offset fields are
   --  1-based buffer indices.  Access is only safe when Extended_Is_Valid returns
   --  True for the same Buffer and Parsed_Header.
   --
   --  Ext_Bool_Count        -- Number of extended boolean capabilities.
   --  Ext_Num_Count         -- Number of extended numeric capabilities.
   --  Ext_String_Count      -- Total extended string entries (values and names).
   --  Ext_String_Entries    -- Number of string offset entries (same as Ext_String_Count).
   --  Ext_Table_Size        -- Byte size of the extended string data table.
   --  Ext_Start             -- 1-based buffer index where the extended section begins.
   --  Ext_Bool_Offset       -- 1-based buffer index of extended boolean values.
   --  Ext_Num_Offset        -- 1-based buffer index of extended numeric values.
   --  Ext_Str_Table_Offset  -- 1-based buffer index of extended string offset table.
   --  Ext_Data_Offset       -- 1-based buffer index of extended string data table.
   --  @relation(FUNC-TIF-012): Extended_Header internal type for extended section offsets
   type Extended_Header is record
      Ext_Bool_Count       : Natural := 0;
      Ext_Num_Count        : Natural := 0;
      Ext_String_Count     : Natural := 0;
      Ext_String_Entries   : Natural := 0;
      Ext_Table_Size       : Natural := 0;
      Ext_Start            : Positive := 1;
      Ext_Bool_Offset      : Positive := 1;
      Ext_Num_Offset       : Positive := 1;
      Ext_Str_Table_Offset : Positive := 1;
      Ext_Data_Offset      : Positive := 1;
   end record;

   ---------------------------------------------------------------------------
   --  Ghost Predicates (FUNC-TIF-018)
   ---------------------------------------------------------------------------

   --  @summary Ghost predicate encapsulating all structural invariants from Parse_Header.
   --  @description Asserting Header_Is_Valid (Buffer, Header) in a precondition
   --  gives the SPARK prover the complete set of bounds facts needed to discharge
   --  array-index checks in Get_Boolean, Get_Numeric, Get_String, and
   --  Parse_Extended_Header without requiring those contracts to enumerate every
   --  individual field constraint.
   --  @param Buffer  The loaded terminfo file byte array.
   --  @param Header  A Parsed_Header previously produced by Parse_Header.
   --  @return True when the header fields satisfy all structural invariants.
   --  @relation(FUNC-TIF-018): Header_Is_Valid ghost predicate
   function Header_Is_Valid (Buffer : Byte_Array; Header : Parsed_Header) return Boolean
   is (Header.Format /= Unknown
       and then Header.Names_Size >= 1
       and then Header.Names_Size <= MAX_NAMES_SECTION_SIZE
       and then Header.Bool_Count <= MAX_BOOL_COUNT
       and then Header.Num_Count <= MAX_NUM_COUNT
       and then Header.String_Count <= MAX_STRING_COUNT
       and then Header.Table_Size <= MAX_STRING_TABLE_SIZE
       and then Header.Bool_Section_Offset >= 1
       and then Header.Total_Standard_Size <= Buffer'Length)
   with Ghost;

   --  @summary Ghost predicate encapsulating extended section structural invariants.
   --  @description Implies Header_Is_Valid so that callers only need to assert
   --  Extended_Is_Valid to obtain all bounds facts for both the standard and
   --  extended sections.
   --  @param Buffer  The loaded terminfo file byte array.
   --  @param Header  A validated Parsed_Header (Header_Is_Valid must hold).
   --  @param Ext     An Extended_Header previously produced by Parse_Extended_Header.
   --  @return True when the extended header fields satisfy all structural invariants.
   --  @relation(FUNC-TIF-018): Extended_Is_Valid ghost predicate
   function Extended_Is_Valid (Buffer : Byte_Array; Header : Parsed_Header; Ext : Extended_Header) return Boolean
   is (Header_Is_Valid (Buffer, Header)
       and then Ext.Ext_Bool_Count <= 64
       and then Ext.Ext_Num_Count <= 128
       and then Ext.Ext_String_Count <= 256
       and then Ext.Ext_Table_Size <= 8_192
       and then Ext.Ext_Data_Offset + Ext.Ext_Table_Size <= Buffer'Length + 1)
   with Ghost;

   ---------------------------------------------------------------------------
   --  Format Detection (FUNC-TIF-007)
   ---------------------------------------------------------------------------

   --  @summary Inspect the first two bytes of a buffer to detect the format variant.
   --  @description Reads Buffer (1) and Buffer (2) as a little-endian 16-bit
   --  unsigned integer and compares against MAGIC_LEGACY (0x011A) and
   --  MAGIC_EXTENDED (0x021E).  Any other value yields Unknown.
   --  @param Buffer  Byte array containing the loaded terminfo file data.
   --  @param Size    Number of valid bytes in Buffer; must satisfy 2 <= Size <= Buffer'Length.
   --  @return Legacy_16bit, Extended_32bit, or Unknown.
   --  @relation(FUNC-TIF-007): Detect_Format pure function with SPARK contract
   function Detect_Format (Buffer : Byte_Array; Size : Natural) return Terminfo_Format
   with
     Pre => Size >= 2 and then Size <= Buffer'Length,
     Post => Detect_Format'Result in Legacy_16bit | Extended_32bit | Unknown;

   ---------------------------------------------------------------------------
   --  Header Parsing (FUNC-TIF-008)
   ---------------------------------------------------------------------------

   --  @summary Parse the fixed 12-byte header and compute all section offsets.
   --  @description Reads the five 16-bit little-endian fields at byte offsets 2..11,
   --  validates all MAX_* bounds, computes section offsets including the alignment
   --  padding after the boolean section, and validates that the total consumed size
   --  does not exceed Size.  On success, sets Success := True and Header to the
   --  parsed result; the ghost predicate Header_Is_Valid (Buffer, Header) will hold.
   --  On any validation failure, sets Success := False; Header is unspecified.
   --  @param Buffer   Byte array containing the loaded terminfo file.
   --  @param Size     Number of valid bytes in Buffer.
   --  @param Format   The detected format variant (must not be Unknown).
   --  @param Header   Receives the parsed header on success.
   --  @param Success  True on success; False when any validation check fails.
   --  @relation(FUNC-TIF-008): Parse_Header procedure with SPARK pre/post contracts
   procedure Parse_Header
     (Buffer : Byte_Array; Size : Natural; Format : Terminfo_Format; Header : out Parsed_Header; Success : out Boolean)
   with
     Pre => Size >= HEADER_SIZE and then Size <= Buffer'Length and then Format /= Unknown,
     Post => (if Success then Header_Is_Valid (Buffer, Header));

   ---------------------------------------------------------------------------
   --  Boolean Capability Extraction (FUNC-TIF-009)
   ---------------------------------------------------------------------------

   --  @summary Extract a single standard boolean capability by its ncurses index.
   --  @description If Index >= Header.Bool_Count, returns Absent.  Otherwise reads
   --  the byte at Header.Bool_Section_Offset + Index and maps it to
   --  Boolean_Cap_Value per the ncurses conventions (0=False_Value, 1=True_Value,
   --  0xFF=Cancelled, 0xFE=Absent, other=Absent).
   --  @param Buffer  Loaded terminfo file byte array.
   --  @param Header  Validated Parsed_Header (Header_Is_Valid must hold).
   --  @param Index   Standard ncurses boolean capability index (0-based).
   --  @return The Boolean_Cap_Value for the capability.
   --  @relation(FUNC-TIF-009): Get_Boolean pure function
   function Get_Boolean (Buffer : Byte_Array; Header : Parsed_Header; Index : Natural) return Boolean_Cap_Value
   with
     Pre => Header_Is_Valid (Buffer, Header) and then Header.Bool_Section_Offset + Header.Bool_Count <= Buffer'Length;

   ---------------------------------------------------------------------------
   --  Numeric Capability Extraction (FUNC-TIF-010)
   ---------------------------------------------------------------------------

   --  @summary Extract a single standard numeric capability by its ncurses index.
   --  @description If Index >= Header.Num_Count, returns ABSENT_NUMERIC.
   --  Otherwise computes Offset := Header.Num_Section_Offset + Index * Num_Size,
   --  verifies Offset + Num_Size - 1 <= Buffer'Length, and reads Num_Size bytes
   --  as a little-endian signed integer.  Sentinel values ABSENT_NUMERIC (-1) and
   --  CANCELLED_NUMERIC (-2) are returned unmodified.  Num_Size is 2 for
   --  Legacy_16bit and 4 for Extended_32bit.
   --  @param Buffer  Loaded terminfo file byte array.
   --  @param Header  Validated Parsed_Header (Header_Is_Valid must hold).
   --  @param Format  The detected format variant (must not be Unknown).
   --  @param Index   Standard ncurses numeric capability index (0-based).
   --  @return The integer value, or ABSENT_NUMERIC (-1) when out of range.
   --  @relation(FUNC-TIF-010): Get_Numeric pure function with SPARK postcondition
   function Get_Numeric
     (Buffer : Byte_Array; Header : Parsed_Header; Format : Terminfo_Format; Index : Natural) return Integer
   with
     Pre => Header_Is_Valid (Buffer, Header) and then Format /= Unknown,
     Post => Get_Numeric'Result >= CANCELLED_NUMERIC;

   ---------------------------------------------------------------------------
   --  String Capability Extraction (FUNC-TIF-011)
   ---------------------------------------------------------------------------

   --  @summary Extract a single standard string capability by its ncurses index.
   --  @description If Index >= Header.String_Count, sets Present := False and
   --  Result.Length := 0.  Otherwise reads the 16-bit signed offset at
   --  Header.String_Table_Offset + Index * 2; if the offset is -1 or -2
   --  (absent/cancelled), sets Present := False.  Otherwise copies bytes from
   --  Header.String_Data_Offset + offset until NUL or MAX_CAPABILITY_STRING_LENGTH
   --  bytes are copied, whichever comes first, and sets Present := True.
   --  @param Buffer   Loaded terminfo file byte array.
   --  @param Header   Validated Parsed_Header (Header_Is_Valid must hold).
   --  @param Index    Standard ncurses string capability index (0-based).
   --  @param Result   Receives the capability string on success; empty otherwise.
   --  @param Present  True when the capability was found and non-empty.
   --  @relation(FUNC-TIF-011): Get_String procedure with SPARK pre/post contracts
   procedure Get_String
     (Buffer  : Byte_Array;
      Header  : Parsed_Header;
      Index   : Natural;
      Result  : out Capability_String;
      Present : out Boolean)
   with Pre => Header_Is_Valid (Buffer, Header), Post => (if not Present then Result.Length = 0);

   ---------------------------------------------------------------------------
   --  Extended Section Header Parsing (FUNC-TIF-012)
   ---------------------------------------------------------------------------

   --  @summary Parse the extended capabilities section header and compute offsets.
   --  @description Checks whether there are at least 10 bytes beyond
   --  Header.Total_Standard_Size in Buffer.  If not, sets Success := False
   --  (extended section absent â not an error).  If present, reads the five
   --  16-bit little-endian fields from the extended header, validates bounds
   --  (Ext_Bool_Count <= 64, Ext_Num_Count <= 128, Ext_String_Count <= 256,
   --  Ext_Table_Size <= 8192), computes offset fields including alignment padding,
   --  and verifies all offsets remain within Buffer.  On success, sets
   --  Success := True and Ext to the parsed extended header; Extended_Is_Valid
   --  (Buffer, Header, Ext) will hold.
   --  @param Buffer   Loaded terminfo file byte array.
   --  @param Size     Number of valid bytes in Buffer.
   --  @param Header   A validated Parsed_Header.
   --  @param Ext      Receives the parsed extended header on success.
   --  @param Success  True when an extended section was found and validated.
   --  @relation(FUNC-TIF-012): Parse_Extended_Header procedure
   procedure Parse_Extended_Header
     (Buffer : Byte_Array; Size : Natural; Header : Parsed_Header; Ext : out Extended_Header; Success : out Boolean)
   with
     Pre => Header_Is_Valid (Buffer, Header) and then Size <= Buffer'Length,
     Post => (if Success then Extended_Is_Valid (Buffer, Header, Ext));

   ---------------------------------------------------------------------------
   --  Truecolor Flag Extraction (FUNC-TIF-013, FUNC-TIF-014)
   ---------------------------------------------------------------------------

   --  @summary Search extended capabilities for the RGB and Tc truecolor flags.
   --  @description Iterates over all extended capability name entries (bounded by
   --  Ext.Ext_String_Count) comparing each NUL-terminated name against "RGB" and
   --  "Tc" (case-sensitive).  For each match, determines the capability type by
   --  position (boolean, numeric, or string) and extracts the value:
   --    RGB as boolean True_Value or numeric >= 1 -> Has_RGB := True.
   --    Tc  as boolean True_Value or non-empty string  -> Has_Tc  := True.
   --  All other cases yield False for the corresponding flag.
   --  The search loop is bounded and carries a SPARK Loop_Variant.
   --  @param Buffer   Loaded terminfo file byte array.
   --  @param Header   Validated Parsed_Header.
   --  @param Ext      Validated Extended_Header.
   --  @param Format   The detected format variant (must not be Unknown).
   --  @param Has_RGB  Receives True when the RGB truecolor flag is set.
   --  @param Has_Tc   Receives True when the Tc truecolor flag is set.
   --  @relation(FUNC-TIF-013): Extended capability name resolution loop
   --  @relation(FUNC-TIF-014): Extract_Truecolor_Flags procedure
   procedure Extract_Truecolor_Flags
     (Buffer  : Byte_Array;
      Header  : Parsed_Header;
      Ext     : Extended_Header;
      Format  : Terminfo_Format;
      Has_RGB : out Boolean;
      Has_Tc  : out Boolean)
   with
     Pre =>
       Header_Is_Valid (Buffer, Header) and then Extended_Is_Valid (Buffer, Header, Ext) and then Format /= Unknown;

   ---------------------------------------------------------------------------
   --  Full Buffer Parse (convenience aggregation)
   ---------------------------------------------------------------------------

   --  @summary Parse a loaded terminfo byte buffer and return a Terminfo_Result.
   --  @description Executes the complete binary parsing pipeline in sequence:
   --    1. Detect_Format  -- validate magic bytes; return Error_Invalid_Magic on Unknown.
   --    2. Parse_Header   -- validate header fields and compute offsets.
   --    3. Get_Numeric    -- extract `colors` at COLORS_INDEX.
   --    4. Get_String     -- extract `setaf` at SETAF_INDEX.
   --    5. Get_String     -- extract `setab` at SETAB_INDEX.
   --    6. Extract_Term_Name -- copy primary terminal name from names section.
   --    7. Parse_Extended_Header -- attempt extended section (non-fatal on absence).
   --    8. Extract_Truecolor_Flags -- extract RGB and Tc flags (if extended present).
   --    9. Construct and return Terminfo_Result (Success => True, Snapshot => ...).
   --  On any fatal parsing error, returns the appropriate Terminfo_Result error variant.
   --  @param Buffer  Loaded terminfo file byte array.
   --  @param Size    Number of valid bytes in Buffer.
   --  @return Terminfo_Result carrying either the populated snapshot or an error code.
   --  @relation(FUNC-TIF-007): Calls Detect_Format
   --  @relation(FUNC-TIF-008): Calls Parse_Header
   --  @relation(FUNC-TIF-010): Extracts colors via Get_Numeric
   --  @relation(FUNC-TIF-011): Extracts setaf/setab via Get_String
   --  @relation(FUNC-TIF-012): Calls Parse_Extended_Header
   --  @relation(FUNC-TIF-014): Calls Extract_Truecolor_Flags
   function Parse_Buffer (Buffer : Byte_Array; Size : Natural) return Terminfo_Result
   with Pre => Size >= 2 and then Size <= Buffer'Length;

end Termicap.Terminfo;
