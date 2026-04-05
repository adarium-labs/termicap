-------------------------------------------------------------------------------
--  Termicap.OSC.Parsing - Pure SPARK DA1 Parsing and Passthrough Wrapping
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK functions for DA1 response parsing, sentinel detection, and
--  multiplexer passthrough query wrapping.
--
--  @description
--  This child package of Termicap.OSC contains the pure, side-effect-free
--  functions used by the sentinel-bounded query pattern.  All subprograms
--  operate only on Byte_Array values inherited from the parent package and
--  carry SPARK contracts provable at Silver level without manual lemmas.
--
--  DA1 response format (ECMA-48 Primary Device Attributes response):
--    ESC [ ? Ps ; Ps ; ... c
--  where ESC = 0x1B, [ = 0x5B, ? = 0x3F, Ps are decimal digit sequences
--  separated by semicolons (0x3B), and c = 0x63.
--
--  Contains_DA1_Response detects this pattern in an accumulated byte buffer.
--  DA1_Response_Start locates the ESC byte that begins the DA1 response,
--  allowing Sentinel_Query to extract only the pre-sentinel bytes.
--  Parse_DA1_Response extracts the numeric parameters from the matched sequence.
--  Wrap_For_Passthrough wraps a query in the DCS passthrough syntax required
--  by tmux and screen so that the inner escape sequence reaches the outer
--  terminal emulator.
--
--  This package carries SPARK_Mode => On.  It references only types from the
--  parent package (Byte, Byte_Array) which are SPARK-compatible integer and
--  array types, and Interfaces.C for the Byte subtype definition.
--
--  Requirements Coverage:
--    - @relation(FUNC-OSC-006): DA1 sentinel detection predicate
--    - @relation(FUNC-OSC-010): DA1 response parsing
--    - @relation(FUNC-OSC-014): Multiplexer passthrough query wrapping
--    - @relation(FUNC-OSC-015): SPARK Silver boundary

pragma SPARK_Mode (On);

package Termicap.OSC.Parsing
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  DA1 Parameter Types (FUNC-OSC-010)
   ---------------------------------------------------------------------------

   --  @summary Maximum number of DA1 parameters that Parse_DA1_Response extracts.
   --  @description ECMA-48 does not define an upper bound on DA1 parameters;
   --  xterm documents up to 12.  16 provides headroom for future extensions.
   --  @relation(FUNC-OSC-010): DA1 parameter array bound
   MAX_DA1_PARAMS : constant := 16;

   --  @summary Fixed-size array holding up to MAX_DA1_PARAMS decimal parameter values.
   --  @description Indexed from 1.  Only Values(1..Count) are meaningful;
   --  Values(Count+1..MAX_DA1_PARAMS) are zero-initialised.
   --  @relation(FUNC-OSC-010): DA1 parameter value array
   type DA1_Value_Array is
     array (Positive range 1 .. MAX_DA1_PARAMS) of Natural;

   --  @summary Record aggregating the count and values from a parsed DA1 response.
   --  @description Count = 0 indicates that no valid DA1 response was found.
   --  Values is zero-initialised beyond index Count.
   --  @relation(FUNC-OSC-010): DA1 parameter record
   type DA1_Params is record
      Count  : Natural range 0 .. MAX_DA1_PARAMS := 0;
      Values : DA1_Value_Array := [others => 0];
   end record;

   ---------------------------------------------------------------------------
   --  Multiplexer Passthrough Mode (FUNC-OSC-014)
   ---------------------------------------------------------------------------

   --  @summary Identifies which terminal multiplexer (if any) is wrapping the session.
   --  @description Used by Wrap_For_Passthrough to select the correct DCS
   --  passthrough syntax.  No_Passthrough means the query is sent directly
   --  without wrapping.  Callers derive the appropriate value from a
   --  Termicap.Terminal_Id.Terminal_Identity result.
   --  @relation(FUNC-OSC-014): Multiplexer kind for passthrough selection
   type Passthrough_Mode is
     (No_Passthrough, Tmux_Passthrough, Screen_Passthrough);

   ---------------------------------------------------------------------------
   --  DA1 Sentinel Detection (FUNC-OSC-006)
   ---------------------------------------------------------------------------

   --  @summary Return True if the byte buffer contains a complete DA1 response.
   --  @description Scans Bytes(1..Length) for the pattern:
   --    0x1B 0x5B 0x3F <one-or-more digits/semicolons> 0x63
   --  Returns True as soon as the terminating 0x63 byte is found after a valid
   --  CSI ? prefix.  Does not require the entire response to be parsed; presence
   --  detection is sufficient for boundary determination in Sentinel_Query.
   --  @param Bytes  Buffer of accumulated response bytes.
   --  @param Length Number of valid bytes in Bytes to inspect.
   --  @return True if a complete DA1 response pattern is present.
   --  @relation(FUNC-OSC-006): Sentinel detection predicate for query accumulation
   function Contains_DA1_Response
     (Bytes : Byte_Array; Length : Natural) return Boolean
   with Pre => Length <= Bytes'Length;

   --  @summary Return the index of the first ESC byte that starts a DA1 response.
   --  @description Scans Bytes(1..Length) for the DA1 pattern (ESC [ ? ... c).
   --  Returns the 1-based index of the ESC byte (0x1B) when found.  Returns
   --  Length when no DA1 response is present (a sentinel value meaning "not found
   --  within the valid range"), allowing the caller to slice Bytes(1..Result-1)
   --  as the pre-sentinel response.
   --  @param Bytes  Buffer of accumulated response bytes.
   --  @param Length Number of valid bytes in Bytes to inspect.
   --  @return 1-based index of the DA1 ESC byte, or Length if not found.
   --  @relation(FUNC-OSC-006): Pre-sentinel byte extraction support
   function DA1_Response_Start
     (Bytes : Byte_Array; Length : Natural) return Natural
   with
     Pre  => Length <= Bytes'Length,
     Post => DA1_Response_Start'Result <= Length;

   ---------------------------------------------------------------------------
   --  DA1 Response Parsing (FUNC-OSC-010)
   ---------------------------------------------------------------------------

   --  @summary Parse a DA1 response byte sequence and extract its parameters.
   --  @description Verifies that Bytes(1..Length) matches the pattern
   --  ESC [ ? <decimal-or-semicolons>* c, then splits the parameter string on
   --  semicolons and converts each segment to a Natural.  Returns Count = 0
   --  if the pattern does not match, if Length = 0, or if no digit bytes are
   --  present between the ? and the terminating c.
   --  @param Bytes  Buffer containing the DA1 response bytes.
   --  @param Length Number of valid bytes to parse; must satisfy Length <= Bytes'Length
   --                and Length <= MAX_RESPONSE_SIZE.
   --  @return A DA1_Params record.  Result.Count <= MAX_DA1_PARAMS always holds.
   --  @relation(FUNC-OSC-010): Pure DA1 response parser with SPARK postcondition
   function Parse_DA1_Response
     (Bytes : Byte_Array; Length : Natural) return DA1_Params
   with
     Pre  => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE,
     Post => Parse_DA1_Response'Result.Count <= MAX_DA1_PARAMS;

   ---------------------------------------------------------------------------
   --  Multiplexer Passthrough Wrapping (FUNC-OSC-014)
   ---------------------------------------------------------------------------

   --  @summary Wrap a query byte sequence in the DCS passthrough syntax for a multiplexer.
   --  @description When Passthrough = No_Passthrough, returns Query unchanged.
   --
   --  When Passthrough = Tmux_Passthrough, wraps with the tmux DCS passthrough:
   --    ESC P tmux ; ESC <Query> ESC \
   --  i.e.: 0x1B 0x50 "tmux;" 0x1B <Query bytes> 0x1B 0x5C
   --
   --  When Passthrough = Screen_Passthrough, wraps with the screen DCS passthrough:
   --    ESC P <Query> ESC \
   --  i.e.: 0x1B 0x50 <Query bytes> 0x1B 0x5C
   --
   --  The returned Byte_Array is a new value; the caller owns the result.
   --  @param Query       The raw escape sequence bytes to be sent to the terminal.
   --  @param Passthrough The multiplexer wrapping mode to apply.
   --  @return The wrapped byte sequence, or Query unchanged for No_Passthrough.
   --  @relation(FUNC-OSC-014): Pure passthrough wrapping: tmux DCS, screen DCS
   function Wrap_For_Passthrough
     (Query : Byte_Array; Passthrough : Passthrough_Mode) return Byte_Array;

end Termicap.OSC.Parsing;
