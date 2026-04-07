-------------------------------------------------------------------------------
--  Termicap.DECRPM - DEC Private Mode Query Types and Parsing
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for the DECRPM
--  active terminal mode query protocol (CSI ? Ps $ p / CSI ? Ps ; Pm $ y).
--
--  @description
--  This package provides all the SPARK-provable building blocks for the
--  DECRPM feature: a Mode_Id subtype for DEC private mode numbers, named
--  constants for the six most relevant modes, a Mode_Status enumeration
--  mapping the five DECRPM response codes, a Mode_Report record pairing a
--  mode number with its decoded status, fixed-size array types for batch
--  queries, the DECRPM_Query construction function, and pure recognition
--  and parsing functions for DECRPM responses.
--
--  All functions carry Global => null contracts.  No I/O, no global state,
--  and no exceptions are used in this package.  The I/O boundary is in the
--  child package Termicap.DECRPM.IO (SPARK Off).
--
--  The Byte subtype and Byte_Array type are defined here independently of
--  Termicap.OSC (which is SPARK Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility
--  at the I/O boundary without introducing a SPARK mode violation.
--
--  Requirements Coverage:
--    - @relation(FUNC-RPM-001): Mode_Id subtype and MODE_* named constants
--    - @relation(FUNC-RPM-002): Mode_Status enumeration
--    - @relation(FUNC-RPM-003): Mode_Report record
--    - @relation(FUNC-RPM-005): DECRPM_Query construction function
--    - @relation(FUNC-RPM-006): Contains_DECRPM_Response recognition function
--    - @relation(FUNC-RPM-007): Parse_DECRPM_Response parsing function
--    - @relation(FUNC-RPM-010): Mode_Id_Array, Mode_Report_Array, MAX_BATCH_MODES
--    - @relation(FUNC-RPM-015): SPARK Silver boundary partition

with Interfaces.C;

package Termicap.DECRPM
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK Off)
   --  to keep this package SPARK On.  The underlying type is identical, so
   --  Termicap.DECRPM.IO can convert between the two without a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for the DECRPM_Query function return type and raw
   --  response buffers passed to the parsing functions.  Representation-compatible
   --  with Termicap.OSC.Byte_Array, Termicap.XTVERSION.Byte_Array, and
   --  Termicap.DA1.Byte_Array.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Capacity Constant
   ---------------------------------------------------------------------------

   --  @summary Maximum number of response bytes accumulated by Query_Mode.
   --  @description Matches Termicap.OSC.MAX_RESPONSE_SIZE (4096 bytes).
   --  Used in preconditions to bound all parsing loops for SPARK provability.
   --  @relation(FUNC-RPM-007): Response buffer capacity bound
   MAX_RESPONSE_SIZE : constant := 4_096;

   ---------------------------------------------------------------------------
   --  Mode_Id Subtype and Named Constants (FUNC-RPM-001)
   ---------------------------------------------------------------------------

   --  @summary DEC private mode number: any non-negative integer.
   --  @description Using a subtype of Natural rather than a new integer type
   --  allows callers to pass literal integers for vendor-specific modes without
   --  type conversion.  The six named constants cover the modes with the broadest
   --  practical impact on terminal UI libraries.
   --  @relation(FUNC-RPM-001): Mode_Id subtype
   subtype Mode_Id is Natural;

   --  @summary DECTCEM: cursor visible (mode 25).
   --  @relation(FUNC-RPM-001): MODE_CURSOR_VISIBILITY named constant
   MODE_CURSOR_VISIBILITY : constant Mode_Id := 25;

   --  @summary X11 mouse button tracking (mode 1000).
   --  @relation(FUNC-RPM-001): MODE_MOUSE_X11 named constant
   MODE_MOUSE_X11         : constant Mode_Id := 1000;

   --  @summary SGR mouse coordinate encoding (mode 1006).
   --  @relation(FUNC-RPM-001): MODE_MOUSE_SGR named constant
   MODE_MOUSE_SGR         : constant Mode_Id := 1006;

   --  @summary Alternate screen buffer (mode 1049).
   --  @relation(FUNC-RPM-001): MODE_ALT_SCREEN named constant
   MODE_ALT_SCREEN        : constant Mode_Id := 1049;

   --  @summary Bracketed paste mode (mode 2004).
   --  @relation(FUNC-RPM-001): MODE_BRACKETED_PASTE named constant
   MODE_BRACKETED_PASTE   : constant Mode_Id := 2004;

   --  @summary Synchronized output (mode 2026).
   --  @relation(FUNC-RPM-001): MODE_SYNC_OUTPUT named constant
   MODE_SYNC_OUTPUT       : constant Mode_Id := 2026;

   ---------------------------------------------------------------------------
   --  Mode_Status Enumeration (FUNC-RPM-002)
   ---------------------------------------------------------------------------

   --  @summary Five-value enumeration for DECRPM response status codes.
   --  @description Maps the five DECRPM response parameter values (Pm = 0..4)
   --  to named literals.  Not_Recognized appears first so that a
   --  default-initialised Mode_Status is the safest value.  Any Pm value
   --  outside 0..4 is mapped to Not_Recognized.  Naming follows DEC
   --  terminology (Set/Reset rather than Enabled/Disabled).
   --
   --  Mapping:
   --    Pm = 0 => Not_Recognized  (mode not implemented)
   --    Pm = 1 => Set             (mode currently enabled)
   --    Pm = 2 => Reset           (mode currently disabled)
   --    Pm = 3 => Permanently_Set (mode always enabled, cannot be changed)
   --    Pm = 4 => Permanently_Reset (mode always disabled, cannot be changed)
   --  @relation(FUNC-RPM-002): Mode_Status enumeration
   type Mode_Status is
     (Not_Recognized,      --  Pm = 0: mode not implemented by terminal
      Set,                 --  Pm = 1: mode is currently enabled
      Reset,               --  Pm = 2: mode is currently disabled
      Permanently_Set,     --  Pm = 3: mode is always enabled, cannot be changed
      Permanently_Reset);  --  Pm = 4: mode is always disabled, cannot be changed

   ---------------------------------------------------------------------------
   --  Mode_Report Record (FUNC-RPM-003)
   ---------------------------------------------------------------------------

   --  @summary Record pairing a mode number with its decoded DECRPM status.
   --  @description Used in both single-mode results (Mode_Query_Result in
   --  Termicap.DECRPM.IO) and batch results (Mode_Report_Array).  Default
   --  initialisation produces (Mode => 0, Status => Not_Recognized), which is
   --  clearly "empty" because mode 0 is not a valid DEC private mode number.
   --  @relation(FUNC-RPM-003): Mode_Report record type
   type Mode_Report is record
      Mode   : Mode_Id     := 0;
      Status : Mode_Status := Not_Recognized;
   end record;

   ---------------------------------------------------------------------------
   --  Batch Array Types and Capacity Constant (FUNC-RPM-010)
   ---------------------------------------------------------------------------

   --  @summary Maximum number of modes that may be queried in a single batch.
   --  @description Covers the six standard modes with headroom for vendor
   --  extensions, while remaining within a reasonable stack footprint
   --  (16 * 8 = 128 bytes for Mode_Report_Array).
   --  @relation(FUNC-RPM-010): MAX_BATCH_MODES constant
   MAX_BATCH_MODES : constant := 16;

   --  @summary Fixed-size array of mode identifiers for batch query input.
   --  @description Callers populate elements 1 .. Count with the mode numbers
   --  to query; elements beyond Count are ignored.  Fixed size is required for
   --  SPARK Silver mode (no heap allocation).
   --  @relation(FUNC-RPM-010): Mode_Id_Array type
   type Mode_Id_Array is
     array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Id;

   --  @summary Fixed-size array of mode reports for batch query output.
   --  @description The I-th element corresponds to the I-th mode in the
   --  Mode_Id_Array input, regardless of whether a response was received.
   --  Modes that timed out individually have Status => Not_Recognized.
   --  @relation(FUNC-RPM-010): Mode_Report_Array type
   type Mode_Report_Array is
     array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Report;

   ---------------------------------------------------------------------------
   --  Query Construction Function (FUNC-RPM-005)
   ---------------------------------------------------------------------------

   --  @summary Construct the DECRPM query byte sequence for a given mode number.
   --  @description Produces the byte sequence encoding CSI ? Ps $ p, where Ps
   --  is the decimal ASCII representation of Mode.  The sequence is:
   --    ESC (0x1B) [ (0x5B) ? (0x3F) <digits> $ (0x24) p (0x70)
   --  Digit encoding uses ASCII (0x30..0x39) with no leading zeros, except
   --  Mode = 0 which produces the single digit '0'.
   --
   --  Result length bounds:
   --    Minimum: 6 bytes (Mode in 0..9: 3-byte prefix + 1 digit + 2-byte suffix)
   --    Maximum: 15 bytes (Natural'Last has 10 digits: 3 + 10 + 2)
   --
   --  Examples:
   --    Mode = 25   => ESC [ ? 2 5 $ p   (7 bytes)
   --    Mode = 1000 => ESC [ ? 1 0 0 0 $ p (8 bytes)
   --    Mode = 2004 => ESC [ ? 2 0 0 4 $ p (8 bytes)
   --
   --  The function is fully side-effect-free (Global => null), as required by
   --  SPARK_Mode => On.
   --  @param Mode  The DEC private mode number to query.
   --  @return Byte sequence encoding CSI ? Ps $ p, length >= 6.
   --  @relation(FUNC-RPM-005): DECRPM query byte sequence construction
   function DECRPM_Query (Mode : Mode_Id) return Byte_Array
   with
     SPARK_Mode => On,
     Global     => null,
     Post       => DECRPM_Query'Result'Length >= 6;

   ---------------------------------------------------------------------------
   --  Response Recognition Function (FUNC-RPM-006)
   ---------------------------------------------------------------------------

   --  @summary Return True if Bytes(1..Length) contains a valid DECRPM response.
   --  @description A well-formed DECRPM response has the structure:
   --    CSI ? Ps ; Pm $ y
   --  where CSI is ESC [ (0x1B 0x5B), ? is 0x3F, Ps and Pm are one or more
   --  ASCII decimal digits (0x30..0x39), and the suffix is $ y (0x24 0x79).
   --
   --  Returns True if and only if:
   --    - Length >= 7 (minimum: ESC [ ? d ; d $ y)
   --    - Bytes starts with ESC [ ? (0x1B 0x5B 0x3F)
   --    - At least one decimal digit follows ? before the semicolon (0x3B)
   --    - A semicolon is present
   --    - At least one decimal digit follows the semicolon
   --    - The sequence ends with $ y (0x24 0x79)
   --
   --  Returns False for any shorter or malformed input.  The $ y suffix is
   --  unique to DECRPM responses; the ? prefix distinguishes DEC private mode
   --  reports from ANSI mode reports.
   --  @param Bytes   The raw response byte buffer.
   --  @param Length  Number of valid bytes in Bytes to examine.
   --  @return True when a well-formed DECRPM response is present.
   --  @relation(FUNC-RPM-006): DECRPM response recognition function
   function Contains_DECRPM_Response
     (Bytes  : Byte_Array;
      Length : Natural) return Boolean
   with
     SPARK_Mode => On,
     Global     => null,
     Pre        => Length <= Bytes'Length;

   ---------------------------------------------------------------------------
   --  Response Parsing Function (FUNC-RPM-007)
   ---------------------------------------------------------------------------

   --  @summary Parse a byte buffer containing a DECRPM response into a Mode_Report.
   --  @description Applies the following steps:
   --    1. Return Mode_Report'(Mode => 0, Status => Not_Recognized) when
   --       Length = 0 or Contains_DECRPM_Response (Bytes, Length) is False.
   --    2. Scan from position 4 (after ESC [ ?) to extract the decimal Ps value
   --       (mode number) by accumulating ASCII digits until the semicolon.
   --    3. Skip the semicolon and extract the decimal Pm value (status code)
   --       by accumulating ASCII digits until $.
   --    4. Map Pm to Mode_Status:
   --         0 => Not_Recognized, 1 => Set, 2 => Reset,
   --         3 => Permanently_Set, 4 => Permanently_Reset,
   --         others => Not_Recognized.
   --    5. Return Mode_Report'(Mode => Ps, Status => <decoded status>).
   --       If Ps = 0 after extraction, return the default Mode_Report.
   --
   --  The MAX_RESPONSE_SIZE precondition bounds all parsing loops for SPARK
   --  provability.  The postcondition guarantees that a valid DECRPM response
   --  yields a positive mode number (Mode > 0), since no valid DEC private
   --  mode number is zero.
   --
   --  No exception is raised on any code path.
   --  @param Bytes   The raw response byte buffer.
   --  @param Length  Number of valid bytes in Bytes (0 <= Length <= MAX_RESPONSE_SIZE).
   --  @return Mode_Report with Mode > 0 and decoded status on success;
   --          Mode_Report'(Mode => 0, Status => Not_Recognized) on failure.
   --  @relation(FUNC-RPM-007): DECRPM response parsing function
   function Parse_DECRPM_Response
     (Bytes  : Byte_Array;
      Length : Natural) return Mode_Report
   with
     SPARK_Mode => On,
     Global     => null,
     Pre        => Length <= Bytes'Length
                     and then Length <= MAX_RESPONSE_SIZE,
     Post       =>
       (if Contains_DECRPM_Response (Bytes, Length)
        then Parse_DECRPM_Response'Result.Mode > 0);

end Termicap.DECRPM;
