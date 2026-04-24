-------------------------------------------------------------------------------
--  Termicap.XTVERSION - Terminal Identification via XTVERSION (Active)
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and parsing functions for the XTVERSION
--  active terminal identification protocol (CSI > q / DCS >| response).
--
--  @description
--  This package provides all the SPARK-provable building blocks for the
--  XTVERSION feature: the CSI query constant encoding ESC [ > q, a
--  discriminated result type carrying terminal name and version strings,
--  and pure functions that recognise a DCS XTVERSION response, extract its
--  payload, tokenise the name/version pair, and orchestrate parsing end-to-end.
--
--  All functions carry SPARK Silver-level contracts (Pre/Post/Global => null).
--  No I/O, no global state, and no exceptions are used in this package.
--  The I/O boundary is in the child package Termicap.XTVERSION.IO (SPARK Off).
--
--  The Byte subtype and Byte_Array type are defined here independently of
--  Termicap.OSC (which is SPARK Off) using the same underlying
--  Interfaces.C.unsigned_char type, ensuring representation compatibility
--  at the I/O boundary without introducing a SPARK mode violation.
--
--  Requirements Coverage:
--    - @relation(FUNC-XTV-001): XTVERSION_Status enumeration and XTVERSION_Result record
--    - @relation(FUNC-XTV-002): CSI_XTVERSION_QUERY byte constant
--    - @relation(FUNC-XTV-003): Contains_XTVERSION_Response function
--    - @relation(FUNC-XTV-004): Extract_XTV_Payload function and Payload_Slice type
--    - @relation(FUNC-XTV-005): Split_XTV_Payload function and Token_Pair type
--    - @relation(FUNC-XTV-006): Parse_XTVERSION_Response function
--    - @relation(FUNC-XTV-007): SPARK_Mode On and Global => null contracts

with Ada.Strings.Unbounded;
with Interfaces.C;

package Termicap.XTVERSION
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK Off)
   --  to keep this package SPARK On.  The underlying type is identical, so
   --  Termicap.XTVERSION.IO can convert between the two without a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for the CSI query constant and raw response buffers
   --  passed to the parsing functions.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Capacity Constant
   ---------------------------------------------------------------------------

   --  @summary Maximum number of response bytes accumulated by Query_XTVERSION.
   --  @description Matches Termicap.OSC.MAX_RESPONSE_SIZE (4096 bytes).
   --  Used in preconditions to bound all parsing loops.
   --  @relation(FUNC-XTV-006): Response buffer capacity bound for Parse_XTVERSION_Response
   MAX_RESPONSE_SIZE : constant := 4_096;

   ---------------------------------------------------------------------------
   --  Result Types (FUNC-XTV-001)
   ---------------------------------------------------------------------------

   --  @summary Three-way outcome discriminant for an XTVERSION query.
   --  @description Success: valid terminal name and version were extracted.
   --  Timeout: the terminal did not respond within the allowed time.
   --  Parse_Error: a response was received but could not be parsed as a valid
   --  DCS XTVERSION envelope.
   --  @relation(FUNC-XTV-001): XTVERSION_Status enumeration
   type XTVERSION_Status is (Success, Timeout, Parse_Error);

   --  @summary Discriminated record carrying the outcome of an XTVERSION query.
   --  @description When Status = Success, Terminal_Name and Terminal_Version
   --  hold the name and version tokens extracted from the DCS response
   --  (e.g., Name = "xterm", Version = "388").  Both strings are trimmed of
   --  leading and trailing whitespace.  When Status /= Success, the variant
   --  part is null; accessing Terminal_Name or Terminal_Version raises
   --  Constraint_Error, preventing use of uninitialised fields.
   --  The default discriminant is Timeout (the most common non-success case),
   --  allowing unconstrained variable declarations.
   --  @relation(FUNC-XTV-001): XTVERSION_Result discriminated record
   type XTVERSION_Result (Status : XTVERSION_Status := Timeout) is record
      case Status is
         when Success =>
            Terminal_Name    : Ada.Strings.Unbounded.Unbounded_String;
            Terminal_Version : Ada.Strings.Unbounded.Unbounded_String;

         when Timeout | Parse_Error =>
            null;
      end case;
   end record;

   ---------------------------------------------------------------------------
   --  Auxiliary Types (FUNC-XTV-004, FUNC-XTV-005)
   ---------------------------------------------------------------------------

   --  @summary Zero-copy positional reference into the response byte buffer.
   --  @description Offset is the index of the first payload byte; Length is
   --  the number of payload bytes.  The pair (Offset, Length) identifies the
   --  span between the end of the ESC P > | prefix and the start of ST/BEL.
   --  No copy of the payload bytes is made during extraction.
   --  @relation(FUNC-XTV-004): Payload_Slice type
   type Payload_Slice is record
      Offset : Positive;
      Length : Natural;
   end record;

   --  @summary Intermediate tokenisation result from Split_XTV_Payload.
   --  @description Both Name and Version are Unbounded_Strings because terminal
   --  names and version strings are variable-length.  Version may be empty when
   --  no delimiter is found in the payload (name-only format).
   --  @relation(FUNC-XTV-005): Token_Pair type
   type Token_Pair is record
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Version : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   ---------------------------------------------------------------------------
   --  CSI XTVERSION Query Constant (FUNC-XTV-002)
   ---------------------------------------------------------------------------

   --  @summary Four-byte CSI sequence encoding the XTVERSION request ESC [ > q.
   --  @description Encodes 0x1B 0x5B 0x3E 0x71 (ESC [ > q), the canonical
   --  XTVERSION query as used by xterm, WezTerm, and tcell.  Defined in the
   --  SPARK On package so that both the I/O layer and test code can reference
   --  it without introducing a SPARK_Mode boundary violation.
   --  @relation(FUNC-XTV-002): CSI_XTVERSION_QUERY constant
   CSI_XTVERSION_QUERY : constant Byte_Array :=
     [16#1B#,
      16#5B#,                       --  ESC [   (CSI introducer)
      Character'Pos ('>'),                   --  >
      Character'Pos ('q')];                  --  q

   ---------------------------------------------------------------------------
   --  DCS Response Recognition (FUNC-XTV-003)
   ---------------------------------------------------------------------------

   --  @summary Return True if Bytes(1..Length) contains a valid DCS XTVERSION response.
   --  @description A valid response begins with the four-byte prefix ESC P > |
   --  (0x1B 0x50 0x3E 0x7C) and is terminated by ST (ESC \ = 0x1B 0x5C) or
   --  BEL (0x07), with at least one payload byte between the prefix and the
   --  terminator.  Returns False for any input shorter than 6 bytes, any input
   --  that does not begin with ESC P > |, or any input that lacks a valid
   --  ST or BEL terminator.
   --  @param Bytes  The raw response byte buffer.
   --  @param Length Number of valid bytes in Bytes to examine.
   --  @return True when a well-formed DCS XTVERSION envelope is present.
   --  @relation(FUNC-XTV-003): DCS XTVERSION response recognition
   function Contains_XTVERSION_Response (Bytes : Byte_Array; Length : Natural) return Boolean
   with Global => null, Pre => Length <= Bytes'Length;

   ---------------------------------------------------------------------------
   --  Payload Extraction (FUNC-XTV-004)
   ---------------------------------------------------------------------------

   --  @summary Extract the payload region from a confirmed DCS XTVERSION response.
   --  @description Returns a Payload_Slice identifying the byte span between
   --  the end of the ESC P > | prefix and the start of the ST (or BEL)
   --  terminator.  The precondition requires that Contains_XTVERSION_Response
   --  has already returned True, so this function need not handle invalid input.
   --  The postcondition guarantees a non-empty payload that lies entirely
   --  within the valid byte range.
   --  @param Bytes  The raw response byte buffer (confirmed to contain a valid response).
   --  @param Length Number of valid bytes in Bytes.
   --  @return A Payload_Slice with Offset >= Bytes'First + 4 and Length > 0.
   --  @relation(FUNC-XTV-004): DCS payload extraction
   function Extract_XTV_Payload (Bytes : Byte_Array; Length : Natural) return Payload_Slice
   with
     Global => null,
     Pre => Length <= Bytes'Length and then Contains_XTVERSION_Response (Bytes, Length),
     Post =>
       Extract_XTV_Payload'Result.Length > 0
       and then Extract_XTV_Payload'Result.Offset >= Bytes'First + 4
       and then Extract_XTV_Payload'Result.Offset + Extract_XTV_Payload'Result.Length - 1 < Bytes'First + Length;

   ---------------------------------------------------------------------------
   --  Payload Tokenisation (FUNC-XTV-005)
   ---------------------------------------------------------------------------

   --  @summary Split the XTVERSION payload bytes into a terminal name and version.
   --  @description Handles the two payload formats found in practice:
   --    Format A (space-separated): "tmux 3.4" -> Name = "tmux", Version = "3.4"
   --    Format B (parenthesised):   "xterm(388)" -> Name = "xterm", Version = "388"
   --  Format B (parenthesised version) takes priority; '(' is checked first.
   --  If neither '(' nor space is present, the entire payload becomes Name and
   --  Version is set to the empty string.  All tokens are trimmed of leading
   --  and trailing ASCII space bytes (0x20).
   --  @param Bytes  The byte buffer containing the payload span.
   --  @param Offset Index of the first payload byte (from Extract_XTV_Payload).
   --  @param Length Number of payload bytes (> 0).
   --  @return Token_Pair with Name and Version as Unbounded_Strings.
   --  @relation(FUNC-XTV-005): Name and version tokenisation (both formats)
   function Split_XTV_Payload (Bytes : Byte_Array; Offset : Positive; Length : Natural) return Token_Pair
   with Global => null, Pre => Length > 0 and then Offset >= Bytes'First and then Offset + Length - 1 <= Bytes'Last;

   ---------------------------------------------------------------------------
   --  Top-Level Parse Function (FUNC-XTV-006)
   ---------------------------------------------------------------------------

   --  @summary Orchestrate recognition, extraction, and tokenisation end-to-end.
   --  @description Applies the following steps in order:
   --    1. Return (Status => Parse_Error) when Length = 0 or Contains_XTVERSION_Response
   --       returns False.
   --    2. Call Extract_XTV_Payload to obtain the payload slice.
   --    3. Call Split_XTV_Payload on the slice to obtain name and version tokens.
   --    4. Return (Status => Success, Terminal_Name => Name, Terminal_Version => Version)
   --       when the Name token is non-empty.
   --    5. Return (Status => Parse_Error) when the Name token is empty.
   --  The postcondition guarantees that when Status = Success, Terminal_Name is
   --  non-empty.  No exception is raised on any code path.
   --  @param Bytes  The raw Sentinel_Query response byte buffer.
   --  @param Length Number of valid bytes in Bytes (0 <= Length <= MAX_RESPONSE_SIZE).
   --  @return XTVERSION_Result with Status = Success and non-empty Terminal_Name on success.
   --  @relation(FUNC-XTV-006): Top-level XTVERSION response parse
   --  @relation(FUNC-XTV-016): All malformed-input cases return Parse_Error
   function Parse_XTVERSION_Response (Bytes : Byte_Array; Length : Natural) return XTVERSION_Result
   with
     Global => null,
     Pre => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE,
     Post =>
       (if Parse_XTVERSION_Response'Result.Status = Success
        then Ada.Strings.Unbounded.Length (Parse_XTVERSION_Response'Result.Terminal_Name) > 0);

end Termicap.XTVERSION;
