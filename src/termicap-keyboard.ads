-------------------------------------------------------------------------------
--  Termicap.Keyboard - Kitty Keyboard Protocol Detection Types and Parsers
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for the Kitty Keyboard
--  Protocol detection feature (KITTY-KB, Tier 4 Stretch Goal).
--
--  @description
--  This package provides all the SPARK-provable building blocks for keyboard
--  protocol detection: the Keyboard_Protocol enumeration for the four protocol
--  levels (Win32 / Kitty / XTerm_CSI / Legacy / Unknown), the Kitty_Flags
--  record for per-bit capability fields, the Keyboard_Capability aggregate
--  result record, the CSI query byte constants for both keyboard probes, and
--  three pure parser functions that recognise and decode terminal responses.
--
--  All functions carry SPARK Silver-level contracts (Pre/Post/Global => null).
--  No I/O, no global state, and no exceptions are used in this package.
--  The I/O boundary and caching are in the child package
--  Termicap.Keyboard.IO (SPARK_Mode Off).
--
--  The Byte subtype and Byte_Array type are defined here independently of
--  Termicap.OSC (which is SPARK_Mode Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility
--  at the I/O boundary without introducing a SPARK mode violation.  This
--  mirrors the pattern established by Termicap.XTVERSION and Termicap.DA1.
--
--  Requirements Coverage:
--    - @relation(FUNC-KKB-001): Keyboard_Protocol enumeration
--    - @relation(FUNC-KKB-002): Kitty_Flags record type
--    - @relation(FUNC-KKB-003): Keyboard_Capability result record
--    - @relation(FUNC-KKB-004): CSI_KITTY_QUERY byte constant
--    - @relation(FUNC-KKB-005): Parse_Kitty_Flags function
--    - @relation(FUNC-KKB-006): Parse_Kitty_Response function / Parse_Result type
--    - @relation(FUNC-KKB-007): CSI_XTERM_KBD_QUERY byte constant
--    - @relation(FUNC-KKB-008): Parse_XTerm_Keyboard_Response function
--    - @relation(FUNC-KKB-013): KITTY_PROBE_TIMEOUT_MS / XTERM_KBD_PROBE_TIMEOUT_MS
--    - @relation(FUNC-KKB-018): Package structure and SPARK boundary

with Interfaces.C;

package Termicap.Keyboard
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK_Mode Off)
   --  to keep this package SPARK On.  The underlying type is identical, so
   --  Termicap.Keyboard.IO can pass slices of these arrays directly to
   --  Termicap.OSC.Sentinel_Query without a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for the CSI query constants and raw response buffers
   --  passed to the parsing functions.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Capacity Constant
   ---------------------------------------------------------------------------

   --  @summary Maximum number of response bytes accumulated by Sentinel_Query.
   --  @description Matches Termicap.OSC.MAX_RESPONSE_SIZE (4096 bytes).
   --  Used in preconditions to bound all parsing loops.
   MAX_RESPONSE_SIZE : constant := 4_096;

   ---------------------------------------------------------------------------
   --  Keyboard_Protocol Enumeration (FUNC-KKB-001)
   ---------------------------------------------------------------------------

   --  @summary Detected keyboard input protocol level.
   --  @description The five values represent the four detectable keyboard
   --  protocol levels plus the Unknown sentinel for "could not determine":
   --    Unknown   — detection was not performed or could not be completed
   --                (stdin not a TTY, foreground guard failed, timeout, error).
   --    Legacy    — probed successfully; no enhanced protocol acknowledged.
   --    XTerm_CSI — XTerm modifyOtherKeys detected (CSI ? 4 m response).
   --    Kitty     — Kitty Keyboard Protocol detected (CSI ? <flags> u response).
   --    Win32     — Windows Console API keyboard; set without probing.
   --  Ordering: Unknown first so default-initialised variables are Unknown.
   --  @relation(FUNC-KKB-001): Keyboard protocol level enumeration
   type Keyboard_Protocol is
     (Unknown,
      --  Detection not performed or not possible (non-TTY, foreground guard
      --  failed, probe timed out entirely, or any other error condition).
      Legacy,
      --  Probed successfully; terminal acknowledged DA1 but neither the Kitty
      --  nor the XTerm modifyOtherKeys query before the DA1 sentinel.
      XTerm_CSI,
      --  XTerm modifyOtherKeys protocol detected; terminal responded with
      --  CSI ? 4 ; <value> m before the DA1 sentinel.
      Kitty,
      --  Kitty Keyboard Protocol detected; terminal responded with
      --  CSI ? <flags> u before the DA1 sentinel.
      Win32
      --  Windows Console API keyboard mode.  Set by platform gate without
      --  performing any escape-sequence probe (FUNC-KKB-010).
     );

   ---------------------------------------------------------------------------
   --  Kitty_Flags Record (FUNC-KKB-002)
   ---------------------------------------------------------------------------

   --  @summary Per-bit capability flags returned in a Kitty Keyboard Protocol
   --  response (CSI ? <flags> u).
   --  @description Each Boolean field corresponds to one bit of the numeric
   --  flags parameter in the Kitty response.  All fields default to False so
   --  that a zero flags value (CSI ? 0 u) or a non-Kitty Keyboard_Capability
   --  record is safe without an explicit aggregate.
   --  @relation(FUNC-KKB-002): Kitty flags bit-field record
   type Kitty_Flags is record
      Disambiguate_Escape_Codes : Boolean := False;
      --  Bit 0 (value 1): terminal disambiguates escape codes that are
      --  ambiguous in legacy VT encoding (e.g., ESC vs CSI leader byte,
      --  Ctrl+letter vs bare letter).
      Report_Event_Types        : Boolean := False;
      --  Bit 1 (value 2): terminal reports key-press, key-repeat, and
      --  key-release events as distinct event types.
      Report_Alternate_Keys     : Boolean := False;
      --  Bit 2 (value 4): terminal reports shifted and alternate key symbols
      --  alongside the base key symbol.
      Report_All_Keys_As_Escape : Boolean := False;
      --  Bit 3 (value 8): terminal reports every key using CSI u encoding,
      --  even for keys that have traditional ASCII representations.
      Report_Associated_Text    : Boolean := False;
      --  Bit 4 (value 16): terminal reports associated Unicode text for
      --  composed key events.
   end record;

   ---------------------------------------------------------------------------
   --  Named Constant for Empty Kitty Flags
   ---------------------------------------------------------------------------

   --  @summary All-False Kitty_Flags value for non-Kitty protocol results.
   --  @description Used as the Flags component of Legacy, XTerm_CSI, Unknown,
   --  Win32, and CSI ? 0 u responses (minimal Kitty support without any flag).
   --  @relation(FUNC-KKB-002): Zero flags constant
   NO_KITTY_FLAGS : constant Kitty_Flags :=
     (Disambiguate_Escape_Codes => False,
      Report_Event_Types        => False,
      Report_Alternate_Keys     => False,
      Report_All_Keys_As_Escape => False,
      Report_Associated_Text    => False);

   ---------------------------------------------------------------------------
   --  Keyboard_Capability Result Record (FUNC-KKB-003)
   ---------------------------------------------------------------------------

   --  @summary Immutable aggregate result of keyboard protocol detection.
   --  @description Combines the detected protocol level, the Kitty capability
   --  flags (meaningful only when Protocol = Kitty), and a flag recording
   --  whether an active escape-sequence probe was attempted.
   --    Protocol = Unknown, Probed = False: could not probe (non-TTY, timeout,
   --    foreground guard failed, or Win32 non-PTY without a Kitty probe).
   --    Protocol = Legacy,  Probed = True:  probed; no enhanced protocol found.
   --    Protocol = Kitty,   Probed = True:  Kitty response received; Flags set.
   --    Protocol = XTerm_CSI, Probed = True: XTerm modifyOtherKeys received.
   --    Protocol = Win32,   Probed = False: Windows Console gate fired.
   --  Callers should inspect Flags only when Protocol = Kitty.
   --  @relation(FUNC-KKB-003): Keyboard capability result record
   type Keyboard_Capability is record
      Protocol : Keyboard_Protocol := Unknown;
      Flags    : Kitty_Flags := NO_KITTY_FLAGS;
      Probed   : Boolean := False;
   end record;

   ---------------------------------------------------------------------------
   --  Canonical "No Result" Constant
   ---------------------------------------------------------------------------

   --  @summary Canonical initial / "no result" Keyboard_Capability value.
   --  @description Represents the state before probing has been performed, or
   --  when probing could not be completed.  Used as the cache initial value
   --  and as the fallback on every error path of Detect_Keyboard_Protocol.
   --  @relation(FUNC-KKB-003): Canonical unknown / unprobed value
   NO_KEYBOARD_CAPABILITY : constant Keyboard_Capability :=
     (Protocol => Unknown, Flags => NO_KITTY_FLAGS, Probed => False);

   ---------------------------------------------------------------------------
   --  Parse_Result Record (FUNC-KKB-006)
   ---------------------------------------------------------------------------

   --  @summary Two-field result of Parse_Kitty_Response.
   --  @description Valid = True when the buffer matches the Kitty response
   --  pattern; Flags_Int carries the extracted decimal integer when Valid.
   --  When Valid = False, Flags_Int is always 0 (guaranteed by postcondition).
   --  @relation(FUNC-KKB-006): Kitty response parse result record
   type Parse_Result is record
      Valid     : Boolean := False;
      Flags_Int : Natural := 0;
   end record;

   ---------------------------------------------------------------------------
   --  CSI Query Constants (FUNC-KKB-004, FUNC-KKB-007)
   ---------------------------------------------------------------------------

   --  @summary Four-byte CSI sequence encoding the Kitty keyboard query ESC [ ? u.
   --  @description Encodes 0x1B 0x5B 0x3F 0x75.  Sent to the terminal as the
   --  first sentinel-bounded probe in the detection cascade (FUNC-KKB-004).
   --  Defined in the SPARK On spec so both the I/O child and test code can
   --  reference it without a SPARK_Mode boundary violation.
   --  @relation(FUNC-KKB-004): Kitty keyboard protocol query constant
   CSI_KITTY_QUERY : constant Byte_Array :=
     [16#1B#,   --  ESC
      16#5B#,   --  [   (CSI introducer second byte)
      16#3F#,   --  ?
      16#75#];  --  u

   --  @summary Five-byte CSI sequence encoding the XTerm modifyOtherKeys query ESC [ ? 4 m.
   --  @description Encodes 0x1B 0x5B 0x3F 0x34 0x6D.  Sent as the second
   --  sentinel-bounded probe in the detection cascade (FUNC-KKB-007).
   --  @relation(FUNC-KKB-007): XTerm modifyOtherKeys query constant
   CSI_XTERM_KBD_QUERY : constant Byte_Array :=
     [16#1B#,   --  ESC
      16#5B#,   --  [   (CSI introducer second byte)
      16#3F#,   --  ?
      16#34#,   --  4
      16#6D#];  --  m

   ---------------------------------------------------------------------------
   --  Probe Timeout Constants (FUNC-KKB-013)
   ---------------------------------------------------------------------------

   --  @summary Millisecond timeout for each Kitty keyboard sentinel probe.
   --  @description Applied per probe; the XTerm probe resets this deadline
   --  independently of the Kitty probe outcome.  1000 ms matches the
   --  project-wide default for Sentinel_Query (FUNC-OSC-004).
   --  @relation(FUNC-KKB-013): Per-probe timeout value
   KITTY_PROBE_TIMEOUT_MS : constant Natural := 1_000;

   --  @summary Millisecond timeout for each XTerm modifyOtherKeys sentinel probe.
   --  @description Separate constant from KITTY_PROBE_TIMEOUT_MS to allow
   --  independent tuning in a future optimisation pass.  Both are 1000 ms
   --  in this release (FUNC-KKB-013).
   --  @relation(FUNC-KKB-013): Per-probe timeout value
   XTERM_KBD_PROBE_TIMEOUT_MS : constant Natural := 1_000;

   ---------------------------------------------------------------------------
   --  Kitty Flags Integer Parser (FUNC-KKB-005)
   ---------------------------------------------------------------------------

   --  @summary Decompose a Kitty flags integer into a Kitty_Flags record.
   --  @description Maps each of the five low-order bits of Flags_Int to the
   --  corresponding Boolean field in the result.  Bits at positions 5 and
   --  above are ignored; the function never raises for any value of Flags_Int,
   --  including values with high bits set.
   --  @param Flags_Int  Non-negative integer extracted from CSI ? <flags> u.
   --  @return Kitty_Flags record with each field set from the corresponding bit.
   --  @relation(FUNC-KKB-005): Kitty flags bit-field parser (SPARK Silver)
   function Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags
   with SPARK_Mode => On, Global => null, Pre => True, Post => True;

   ---------------------------------------------------------------------------
   --  Kitty Response Byte Sequence Parser (FUNC-KKB-006)
   ---------------------------------------------------------------------------

   --  @summary Recognise a Kitty Keyboard Protocol response and extract the flags integer.
   --  @description Returns (Valid => True, Flags_Int => N) when
   --  Buffer (Buffer'First .. Buffer'First + Length - 1) matches the pattern:
   --    ESC (0x1B)  '['  (0x5B)  '?'  (0x3F)  <digits>+  'u'  (0x75)
   --  where <digits>+ is one or more ASCII decimal digits (0x30 .. 0x39).
   --  The minimum valid length is 5 (e.g. ESC [ ? 0 u for flags = 0); a bare
   --  CSI ? u with no digits is REJECTED — real Kitty terminals always include
   --  at least one flag digit, and accepting the bare form produced false
   --  positives on terminals that leaked probe bytes into the pre-sentinel
   --  region.  Returns (Valid => False, Flags_Int => 0) for any non-matching
   --  input, including partial responses, garbled bytes, or a missing 'u'
   --  terminator.
   --  @param Buffer  The raw response byte buffer.
   --  @param Length  Number of valid bytes in Buffer to examine.
   --  @return Parse_Result with Valid = True and the extracted Flags_Int on success.
   --  @relation(FUNC-KKB-006): Kitty response byte sequence parser (SPARK Silver)
   function Parse_Kitty_Response (Buffer : Byte_Array; Length : Natural) return Parse_Result
   with
     SPARK_Mode => On,
     Global => null,
     Pre => Length <= Buffer'Length,
     Post => (if not Parse_Kitty_Response'Result.Valid then Parse_Kitty_Response'Result.Flags_Int = 0);

   ---------------------------------------------------------------------------
   --  XTerm modifyOtherKeys Response Byte Sequence Parser (FUNC-KKB-008)
   ---------------------------------------------------------------------------

   --  @summary Recognise an XTerm modifyOtherKeys response byte sequence.
   --  @description Returns True when Buffer (Buffer'First .. Buffer'First + Length - 1)
   --  matches the pattern:
   --    ESC (0x1B)  '['  (0x5B)  '?'  (0x3F)  '4'  (0x34)  ';'  (0x3B)
   --    <digits>+  'm'  (0x6D)
   --  where <digits>+ is one or more ASCII decimal digits (0x30 .. 0x39).
   --  Returns False for any non-matching input, including a response with zero
   --  digits before 'm', a missing ';', a missing '4', or an unexpected
   --  terminator byte.  The numeric <value> field is not extracted; presence
   --  of the response alone constitutes XTerm modifyOtherKeys detection.
   --  @param Buffer  The raw response byte buffer.
   --  @param Length  Number of valid bytes in Buffer to examine.
   --  @return True when a well-formed XTerm modifyOtherKeys response is present.
   --  @relation(FUNC-KKB-008): XTerm modifyOtherKeys response parser (SPARK Silver)
   function Parse_XTerm_Keyboard_Response (Buffer : Byte_Array; Length : Natural) return Boolean
   with SPARK_Mode => On, Global => null, Pre => Length <= Buffer'Length, Post => True;

end Termicap.Keyboard;
