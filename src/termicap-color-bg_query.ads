-------------------------------------------------------------------------------
--  Termicap.Color.BG_Query - Background / Foreground Color Query Types and Parsing
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for OSC 10/11
--  background and foreground color query responses.
--
--  @description
--  This package provides all the SPARK-provable building blocks for the
--  BG-COLOR feature: the RGB color type, discriminated result types, byte
--  array constants encoding the OSC 10 and OSC 11 query sequences, and
--  pure functions that parse the X11 rgb: response format, strip OSC
--  response headers, parse the COLORFGBG environment variable, and convert
--  ANSI color indices to RGB values.
--
--  All functions carry SPARK Silver-level contracts (Pre/Post).  No I/O,
--  no global state, and no exceptions are used in this package.  The I/O
--  boundary is in the child package Termicap.Color.BG_Query.IO (SPARK Off).
--
--  The Byte subtype and Byte_Array type are defined here independently of
--  Termicap.OSC (which is SPARK Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility
--  at the I/O boundary without introducing a SPARK mode violation.
--
--  Requirements Coverage:
--    - @relation(FUNC-BGC-001): RGB record type and default constants
--    - @relation(FUNC-BGC-002): Query_Kind enumeration
--    - @relation(FUNC-BGC-003): OSC_BG_QUERY byte constant
--    - @relation(FUNC-BGC-004): OSC_FG_QUERY byte constant
--    - @relation(FUNC-BGC-005): Query_Sequence function
--    - @relation(FUNC-BGC-007): Parse_RGB_Response function
--    - @relation(FUNC-BGC-008): Find_RGB_Prefix procedure and Split_RGB_Channels procedure
--    - @relation(FUNC-BGC-009): Parse_Hex_Channel function
--    - @relation(FUNC-BGC-010): Strip_OSC_Header function
--    - @relation(FUNC-BGC-011): Parse_Colorfgbg function and Colorfgbg_Result type
--    - @relation(FUNC-BGC-012): ANSI_COLOR_TABLE constant and Ansi_To_RGB function

with Interfaces.C;

package Termicap.Color.BG_Query
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK Off)
   --  to keep this package SPARK On.  The underlying type is identical, so
   --  Termicap.Color.BG_Query.IO can convert between the two without a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for OSC query constants, raw response slices, and
   --  return values of Query_Sequence.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  RGB Color Type (FUNC-BGC-001)
   ---------------------------------------------------------------------------

   --  @summary 24-bit terminal color value with three 8-bit channel components.
   --  @description Each component is constrained to 0..255 so that the SPARK
   --  prover can discharge range-check obligations for any arithmetic that
   --  stays within 8-bit bounds.  Using a named record rather than a packed
   --  integer keeps the API readable and enables individual field contracts.
   --  @relation(FUNC-BGC-001): RGB record type
   type RGB is record
      Red   : Natural range 0 .. 255;
      Green : Natural range 0 .. 255;
      Blue  : Natural range 0 .. 255;
   end record;

   ---------------------------------------------------------------------------
   --  Default Color Constants (FUNC-BGC-001)
   ---------------------------------------------------------------------------

   --  @summary Default foreground color: ANSI index 7 (light grey).
   --  @description Used as a fallback when neither OSC query nor COLORFGBG
   --  provides a foreground color.
   --  @relation(FUNC-BGC-001): Default foreground constant
   DEFAULT_FOREGROUND : constant RGB := (Red => 170, Green => 170, Blue => 170);

   --  @summary Default background color: ANSI index 0 (black).
   --  @description Used as a fallback when neither OSC query nor COLORFGBG
   --  provides a background color.
   --  @relation(FUNC-BGC-001): Default background constant
   DEFAULT_BACKGROUND : constant RGB := (Red => 0, Green => 0, Blue => 0);

   ---------------------------------------------------------------------------
   --  Query Kind (FUNC-BGC-002)
   ---------------------------------------------------------------------------

   --  @summary Selects whether to query the terminal background or foreground color.
   --  @description Background corresponds to OSC 11; Foreground to OSC 10.
   --  Used throughout the BG-COLOR feature to select escape sequences,
   --  COLORFGBG fallback fields, and default color constants.
   --  @relation(FUNC-BGC-002): Query_Kind enumeration
   type Query_Kind is (Background, Foreground);

   ---------------------------------------------------------------------------
   --  Capacity Constants
   ---------------------------------------------------------------------------

   --  @summary Maximum length of a single hex color channel string (2 or 4 digits).
   --  @description Channels in X11 rgb: responses are either 2-digit or 4-digit
   --  hex strings.  This constant bounds the precondition of Parse_Hex_Channel.
   --  @relation(FUNC-BGC-009): Channel length bound
   MAX_CHANNEL_LENGTH : constant := 4;

   --  @summary Maximum length of a COLORFGBG environment variable value.
   --  @description Bounds the precondition of Parse_Colorfgbg to prevent
   --  unbounded scanning of an untrusted environment variable string.
   --  @relation(FUNC-BGC-011): COLORFGBG string length bound
   MAX_COLORFGBG_LENGTH : constant := 32;

   --  @summary Maximum number of response bytes accumulated by Query_Color.
   --  @description Matches Termicap.OSC.MAX_RESPONSE_SIZE (4096 bytes).
   --  Exceeding this limit is treated as a timeout condition.
   --  @relation(FUNC-BGC-006): Response buffer capacity bound
   MAX_RESPONSE_SIZE : constant := 4_096;

   ---------------------------------------------------------------------------
   --  OSC Query Byte Constants (FUNC-BGC-003, FUNC-BGC-004)
   ---------------------------------------------------------------------------

   --  @summary OSC 11 background color query byte sequence.
   --  @description Encodes the string ESC ] 1 1 ; ? ESC \ (ST-terminated).
   --  Sent to the terminal to request its current background color via the
   --  X11 OSC 11 protocol.
   --  @relation(FUNC-BGC-003): OSC 11 background query constant
   OSC_BG_QUERY : constant Byte_Array :=
     [16#1B#, 16#5D#,                                                    --  ESC ]
      Character'Pos ('1'), Character'Pos ('1'), Character'Pos (';'),     --  1 1 ;
      Character'Pos ('?'),                                               --  ?
      16#1B#, 16#5C#];                                                   --  ESC \ (ST)

   --  @summary OSC 10 foreground color query byte sequence.
   --  @description Encodes the string ESC ] 1 0 ; ? ESC \ (ST-terminated).
   --  Sent to the terminal to request its current foreground color via the
   --  X11 OSC 10 protocol.
   --  @relation(FUNC-BGC-004): OSC 10 foreground query constant
   OSC_FG_QUERY : constant Byte_Array :=
     [16#1B#, 16#5D#,                                                    --  ESC ]
      Character'Pos ('1'), Character'Pos ('0'), Character'Pos (';'),     --  1 0 ;
      Character'Pos ('?'),                                               --  ?
      16#1B#, 16#5C#];                                                   --  ESC \ (ST)

   ---------------------------------------------------------------------------
   --  Result Types
   ---------------------------------------------------------------------------

   --  @summary Result of a full X11 rgb: color response parse.
   --  @description Discriminated record preventing access to the Color field
   --  without first checking Success.  Ada discriminant constraints enforce
   --  this at compile time.
   --  @relation(FUNC-BGC-007): Parse_Result type
   type Parse_Result (Success : Boolean := False) is record
      case Success is
         when True  => Color : RGB;
         when False => null;
      end case;
   end record;

   --  @summary Result of parsing a single hex color channel.
   --  @description When Success is True, Value is in 0..255.  This postcondition
   --  is chained into Parse_RGB_Response's postcondition by the SPARK prover.
   --  @relation(FUNC-BGC-009): Channel_Result type
   type Channel_Result (Success : Boolean := False) is record
      case Success is
         when True  => Value : Natural range 0 .. 255;
         when False => null;
      end case;
   end record;

   --  @summary Position of a single hex channel substring within a Byte_Array.
   --  @description Holds a start index and a length rather than a copy of the
   --  bytes, so no heap allocation occurs during channel extraction.
   --  @relation(FUNC-BGC-008): Channel_Slice type
   type Channel_Slice is record
      Start  : Positive;
      Length : Natural range 0 .. MAX_CHANNEL_LENGTH;
   end record;

   --  @summary Result of stripping the OSC response header from raw response bytes.
   --  @description When Success is True, Offset is the first payload byte index
   --  and Payload_Length is the number of payload bytes.  The payload is the
   --  rgb: color string without the leading ESC ] N N ; and trailing ST or BEL.
   --  @relation(FUNC-BGC-010): Strip_Result type
   type Strip_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Offset         : Positive;
            Payload_Length : Natural;
         when False => null;
      end case;
   end record;

   --  @summary Result of parsing the COLORFGBG environment variable.
   --  @description Non-discriminated record; both index fields are always present
   --  but are meaningful only when Success is True.  Both fields are constrained
   --  to 0..15 (valid ANSI color indices) to enable range-check-free array
   --  lookups in the detection cascade.
   --  @relation(FUNC-BGC-011): Colorfgbg_Result type
   type Colorfgbg_Result is record
      Success    : Boolean;
      Foreground : Natural range 0 .. 15;
      Background : Natural range 0 .. 15;
   end record;

   ---------------------------------------------------------------------------
   --  ANSI Color Table (FUNC-BGC-012)
   ---------------------------------------------------------------------------

   --  @summary Array type for the canonical xterm 16-color ANSI palette.
   --  @relation(FUNC-BGC-012): ANSI_Color_Array type
   type ANSI_Color_Array is array (Natural range 0 .. 15) of RGB;

   --  @summary Canonical xterm/VT100 16-color ANSI palette lookup table.
   --  @description Maps ANSI color indices 0..15 to their standard 8-bit RGB
   --  values as defined by the xterm default palette.  Used by Ansi_To_RGB
   --  and the COLORFGBG fallback in the detection cascade.
   --  @relation(FUNC-BGC-012): ANSI_COLOR_TABLE constant
   --  @relation(FUNC-BGC-018): Canonical xterm defaults
   ANSI_COLOR_TABLE : constant ANSI_Color_Array :=
     [0  => (Red =>   0, Green =>   0, Blue =>   0),   --  Black
      1  => (Red => 128, Green =>   0, Blue =>   0),   --  Dark Red
      2  => (Red =>   0, Green => 128, Blue =>   0),   --  Dark Green
      3  => (Red => 128, Green => 128, Blue =>   0),   --  Dark Yellow (Olive)
      4  => (Red =>   0, Green =>   0, Blue => 128),   --  Dark Blue
      5  => (Red => 128, Green =>   0, Blue => 128),   --  Dark Magenta
      6  => (Red =>   0, Green => 128, Blue => 128),   --  Dark Cyan
      7  => (Red => 192, Green => 192, Blue => 192),   --  Light Grey
      8  => (Red => 128, Green => 128, Blue => 128),   --  Dark Grey
      9  => (Red => 255, Green =>   0, Blue =>   0),   --  Bright Red
      10 => (Red =>   0, Green => 255, Blue =>   0),   --  Bright Green
      11 => (Red => 255, Green => 255, Blue =>   0),   --  Bright Yellow
      12 => (Red =>   0, Green =>   0, Blue => 255),   --  Bright Blue
      13 => (Red => 255, Green =>   0, Blue => 255),   --  Bright Magenta
      14 => (Red =>   0, Green => 255, Blue => 255),   --  Bright Cyan
      15 => (Red => 255, Green => 255, Blue => 255)];  --  White

   ---------------------------------------------------------------------------
   --  Query Sequence Selection (FUNC-BGC-005)
   ---------------------------------------------------------------------------

   --  @summary Return the OSC byte sequence to query the terminal for a color channel.
   --  @description Returns OSC_BG_QUERY when Kind = Background (OSC 11) and
   --  OSC_FG_QUERY when Kind = Foreground (OSC 10).  The exhaustive case
   --  statement ensures that adding a new Query_Kind literal causes a compile
   --  error here, forcing the implementer to handle the new case.
   --  @param Kind The color channel to query.
   --  @return The corresponding OSC escape sequence as a Byte_Array.
   --  @relation(FUNC-BGC-005): Query escape sequence selection by kind
   function Query_Sequence (Kind : Query_Kind) return Byte_Array
   with Post => Query_Sequence'Result'Length > 0;

   ---------------------------------------------------------------------------
   --  RGB Response Parsing (FUNC-BGC-007)
   ---------------------------------------------------------------------------

   --  @summary Parse an X11 rgb: color response payload and extract an RGB value.
   --  @description Orchestrates Find_RGB_Prefix, Split_RGB_Channels, and three
   --  calls to Parse_Hex_Channel.  Returns Success => False if any step fails:
   --  prefix not found, fewer than two '/' separators, or any channel is not a
   --  valid 1-to-4 digit hex string.  Accepts both 2-digit and 4-digit channel
   --  encoding; 4-digit values are normalised by taking the high byte.
   --  @param Bytes  Buffer of payload bytes (after OSC header stripping).
   --  @param Length Number of valid bytes in Bytes to examine.
   --  @return Parse_Result with Success => True and a Color if parsing succeeds.
   --  @relation(FUNC-BGC-007): X11 rgb: response parsing
   function Parse_RGB_Response
     (Bytes  : Byte_Array;
      Length : Natural)
      return Parse_Result
   with
     Pre  => Length <= Bytes'Length,
     Post =>
       (if Parse_RGB_Response'Result.Success
        then Parse_RGB_Response'Result.Color.Red   in 0 .. 255
             and then Parse_RGB_Response'Result.Color.Green in 0 .. 255
             and then Parse_RGB_Response'Result.Color.Blue  in 0 .. 255);

   ---------------------------------------------------------------------------
   --  RGB Prefix Detection (FUNC-BGC-008)
   ---------------------------------------------------------------------------

   --  @summary Locate the "rgb:" or "rgba:" prefix in a byte sequence.
   --  @description Scans Bytes(Bytes'First .. Bytes'First + Length - 1) for the
   --  four-byte subsequence "rgb:" (0x72 0x67 0x62 0x3A).  If found, sets
   --  Offset to the index of the first byte after the colon (the start of the
   --  R channel) and sets Found to True.  If not found with "rgb:", repeats
   --  the scan for "rgba:" (five bytes); the alpha channel is ignored by the
   --  caller.  If neither prefix is found, sets Found to False.
   --
   --  This is a procedure rather than a function because SPARK functions cannot
   --  have out parameters.
   --  @param Bytes  Buffer of bytes to scan.
   --  @param Length Number of valid bytes to scan.
   --  @param Offset Set to the first channel byte index when Found is True.
   --  @param Found  True if "rgb:" or "rgba:" was located in the buffer.
   --  @relation(FUNC-BGC-008): rgb: / rgba: prefix detection
   procedure Find_RGB_Prefix
     (Bytes  :     Byte_Array;
      Length :     Natural;
      Offset : out Natural;
      Found  : out Boolean)
   with
     Pre  => Length <= Bytes'Length,
     Post =>
       (if Found
        then Offset < Bytes'First + Length and then Offset >= Bytes'First + 4);

   --  @summary Extract three '/' delimited channel substrings from a Byte_Array.
   --  @description Scans Bytes starting at Start up to Start + Length - 1 for
   --  '/' separators (0x2F) and fills Ch_R, Ch_G, Ch_B with start indices and
   --  lengths identifying each channel substring.  Sets Success to False if
   --  fewer than two '/' separators are found before the end of the range.
   --  @param Bytes   Buffer containing the channel data.
   --  @param Start   Index of the first byte of the R channel.
   --  @param Length  Number of bytes to scan from Start.
   --  @param Ch_R    Channel_Slice for the Red channel.
   --  @param Ch_G    Channel_Slice for the Green channel.
   --  @param Ch_B    Channel_Slice for the Blue channel.
   --  @param Success False if fewer than two '/' separators were found.
   --  @relation(FUNC-BGC-008): RGB channel splitting
   procedure Split_RGB_Channels
     (Bytes             :     Byte_Array;
      Start             :     Natural;
      Length            :     Natural;
      Ch_R, Ch_G, Ch_B : out Channel_Slice;
      Success           : out Boolean)
   with
     Pre  =>
       Start >= Bytes'First
       and then Start + Length - 1 <= Bytes'Last
       and then Length > 0,
     Post =>
       (if Success
        then Ch_R.Length in 1 .. MAX_CHANNEL_LENGTH
             and then Ch_G.Length in 1 .. MAX_CHANNEL_LENGTH
             and then Ch_B.Length in 1 .. MAX_CHANNEL_LENGTH
             and then Ch_R.Start >= Bytes'First
             and then Ch_B.Start + Ch_B.Length - 1 <= Bytes'Last);

   ---------------------------------------------------------------------------
   --  Hex Channel Parsing (FUNC-BGC-009)
   ---------------------------------------------------------------------------

   --  @summary Parse a single hex color channel string and normalise to 8-bit.
   --  @description Accepts 1-to-4 hex digit bytes (uppercase or lowercase).
   --  Normalisation rules:
   --    1 digit  -- multiply by 17 (0xF -> 0xFF)
   --    2 digits -- use as-is (0xFF -> 0xFF)
   --    3 digits -- divide by 16 (0xFFF -> 0xFF)
   --    4 digits -- divide by 256, i.e. take the high byte (0xFFFF -> 0xFF)
   --  Returns Success => False for any non-hex byte or length outside 1..4.
   --  @param Bytes  Buffer containing the hex digit bytes.
   --  @param Start  Index of the first hex digit byte.
   --  @param Length Number of hex digit bytes (1..MAX_CHANNEL_LENGTH).
   --  @return Channel_Result with Value in 0..255 when Success is True.
   --  @relation(FUNC-BGC-009): Hex channel parsing and 8-bit normalisation
   function Parse_Hex_Channel
     (Bytes  : Byte_Array;
      Start  : Natural;
      Length : Natural)
      return Channel_Result
   with
     Pre  =>
       Length in 1 .. MAX_CHANNEL_LENGTH
       and then Start >= Bytes'First
       and then Start + Length - 1 <= Bytes'Last,
     Post =>
       (if Parse_Hex_Channel'Result.Success
        then Parse_Hex_Channel'Result.Value in 0 .. 255);

   ---------------------------------------------------------------------------
   --  OSC Header Stripping (FUNC-BGC-010)
   ---------------------------------------------------------------------------

   --  @summary Strip the OSC response header and terminator from raw response bytes.
   --  @description Verifies that Bytes(Bytes'First .. Bytes'First + Length - 1)
   --  begins with ESC ] 1 X ; (five bytes, where X depends on Kind) and returns
   --  a Strip_Result identifying the payload region that follows.  The payload
   --  ends before the ST (ESC \) or BEL (0x07) terminator if present, or at the
   --  last byte if no terminator is found.  Returns Success => False if the
   --  header pattern does not match or if the payload length would be zero.
   --  @param Bytes  Buffer of raw Sentinel_Query response bytes.
   --  @param Length Number of valid bytes in Bytes.
   --  @param Kind   Expected query kind, used to verify the OSC response number.
   --  @return Strip_Result with Offset and Payload_Length when Success is True.
   --  @relation(FUNC-BGC-010): OSC response prefix stripping
   function Strip_OSC_Header
     (Bytes  : Byte_Array;
      Length : Natural;
      Kind   : Query_Kind)
      return Strip_Result
   with
     Pre  => Length <= Bytes'Length,
     Post =>
       (if Strip_OSC_Header'Result.Success
        then Strip_OSC_Header'Result.Offset >= Bytes'First + 5
             and then Strip_OSC_Header'Result.Payload_Length > 0
             and then Strip_OSC_Header'Result.Offset
                      + Strip_OSC_Header'Result.Payload_Length - 1
                      <= Bytes'First + Length - 1);

   ---------------------------------------------------------------------------
   --  COLORFGBG Parsing (FUNC-BGC-011)
   ---------------------------------------------------------------------------

   --  @summary Parse the COLORFGBG environment variable value.
   --  @description Accepts strings of the form "fg;bg" or "fg;extra;bg" where
   --  fg and bg are decimal integers in 0..15.  The foreground index is taken
   --  from the first semicolon-delimited field; the background index from the
   --  last field.  Returns Success => False if no ';' is present, if either
   --  field cannot be parsed as a decimal integer, or if either value falls
   --  outside 0..15.
   --  @param Value The raw COLORFGBG environment variable string.
   --  @return Colorfgbg_Result; both index fields are in 0..15 when Success is True.
   --  @relation(FUNC-BGC-011): COLORFGBG string parsing
   function Parse_Colorfgbg
     (Value : String)
      return Colorfgbg_Result
   with
     Pre  => Value'Length <= MAX_COLORFGBG_LENGTH,
     Post =>
       (if Parse_Colorfgbg'Result.Success
        then Parse_Colorfgbg'Result.Foreground in 0 .. 15
             and then Parse_Colorfgbg'Result.Background in 0 .. 15);

   ---------------------------------------------------------------------------
   --  ANSI Color Index to RGB (FUNC-BGC-012)
   ---------------------------------------------------------------------------

   --  @summary Subtype for valid ANSI 4-bit color indices.
   --  @description Used as the parameter type of Ansi_To_RGB to ensure that
   --  the index is always a valid ANSI_COLOR_TABLE subscript.
   --  @relation(FUNC-BGC-012): ANSI color index subtype
   subtype ANSI_Index is Natural range 0 .. 15;

   --  @summary Convert a standard ANSI 4-bit color index to an RGB value.
   --  @description Performs a direct lookup in ANSI_COLOR_TABLE.  Because every
   --  element of the constant array is in 0..255, the SPARK prover can discharge
   --  the postcondition trivially without manual lemmas.
   --  @param Index ANSI color index in the range 0..15.
   --  @return The corresponding RGB value from the canonical xterm palette.
   --  @relation(FUNC-BGC-012): ANSI color index to RGB mapping
   function Ansi_To_RGB (Index : ANSI_Index) return RGB
   with
     Post =>
       Ansi_To_RGB'Result.Red   in 0 .. 255
       and then Ansi_To_RGB'Result.Green in 0 .. 255
       and then Ansi_To_RGB'Result.Blue  in 0 .. 255;

end Termicap.Color.BG_Query;
