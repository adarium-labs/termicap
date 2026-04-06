-------------------------------------------------------------------------------
--  Termicap.DA1 - Primary Device Attributes Capability Types and Interpretation
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure SPARK types, constants, and interpretation functions for the DA1
--  Primary Device Attributes active terminal capability protocol (CSI c).
--
--  @description
--  This package provides all the SPARK-provable building blocks for the DA1
--  feature: a curated DA1_Capability enumeration naming the Ps parameter values
--  most relevant to terminal capability detection, a VT_Level enumeration for
--  the VT conformance class encoded in the first DA1 parameter, a Boolean flag
--  array type and a DA1_Capabilities aggregate record, the DA1_QUERY byte
--  constant encoding ESC [ c, and three pure interpretation functions
--  (Interpret_DA1, Has_Capability, VT_Level_Of) with Silver-level SPARK
--  contracts.
--
--  All functions carry Global => null contracts.  No I/O, no global state,
--  and no exceptions are used in this package.  The I/O boundary is in the
--  child package Termicap.DA1.IO (SPARK Off).
--
--  This package depends on Termicap.OSC.Parsing (also SPARK On) for the
--  DA1_Params and Byte_Array types.  It does not depend on Termicap.OSC
--  (SPARK Off), avoiding a SPARK mode boundary violation.
--
--  Requirements Coverage:
--    - @relation(FUNC-DA1-001): DA1_Capability enumeration
--    - @relation(FUNC-DA1-002): VT_Level enumeration
--    - @relation(FUNC-DA1-003): Capability_Flags array type and DA1_Capabilities record
--    - @relation(FUNC-DA1-004): Interpret_DA1 pure SPARK function
--    - @relation(FUNC-DA1-005): Has_Capability convenience function
--    - @relation(FUNC-DA1-006): VT_Level_Of convenience function
--    - @relation(FUNC-DA1-007): DA1_QUERY byte constant
--    - @relation(FUNC-DA1-013): SPARK Silver boundary partition

with Interfaces.C;
with Termicap.OSC.Parsing;

package Termicap.DA1
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Byte Types (representation-compatible with Termicap.OSC)
   ---------------------------------------------------------------------------

   --  @summary A single byte of terminal I/O, matching Interfaces.C.unsigned_char.
   --  @description Defined independently of Termicap.OSC (which is SPARK Off)
   --  to keep this package SPARK On.  The underlying type is identical, so
   --  Termicap.DA1.IO can convert between the two without a copy.
   subtype Byte is Interfaces.C.unsigned_char;

   --  @summary An unconstrained sequence of bytes for escape sequence data.
   --  @description Used for the DA1_QUERY constant.  Representation-compatible
   --  with Termicap.OSC.Byte_Array and Termicap.XTVERSION.Byte_Array.
   type Byte_Array is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------------
   --  Capability Enumeration (FUNC-DA1-001)
   ---------------------------------------------------------------------------

   --  @summary Curated subset of DA1 Ps parameter values relevant to capability detection.
   --  @description Each literal corresponds to a specific Ps value in the
   --  Primary Device Attributes response (ESC [ ? Ps ; Ps ; ... c).  The
   --  enumeration is intentionally limited to capabilities with practical
   --  relevance for terminal detection and feature selection.  Callers needing
   --  raw parameter inspection can use DA1_Params.Values directly via
   --  Parse_DA1_Response (FUNC-OSC-010).  Naming follows Mixed_Case per the
   --  Ada enumeration convention (not ALL_CAPS, which is reserved for constants).
   --  @relation(FUNC-DA1-001): Curated DA1 capability enumeration
   type DA1_Capability is
     (Printer,              --  Ps =  2: Printer port
      ReGIS_Graphics,       --  Ps =  3: ReGIS graphics
      Sixel_Graphics,       --  Ps =  4: Sixel graphics
      Selective_Erase,      --  Ps =  6: Selective erase
      User_Defined_Keys,    --  Ps =  8: User-defined keys (UDK)
      Windowing,            --  Ps = 18: Windowing capability
      ANSI_Color,           --  Ps = 22: ANSI colour (VT525)
      Rectangular_Editing); --  Ps = 28: Rectangular editing

   ---------------------------------------------------------------------------
   --  VT Conformance Level Enumeration (FUNC-DA1-002)
   ---------------------------------------------------------------------------

   --  @summary VT conformance level encoded in the first DA1 parameter.
   --  @description Maps the first Ps value in a DA1 response to a named
   --  conformance level.  The ordering places Unknown first so that a
   --  default-initialised DA1_Capabilities record carries Unknown as its
   --  VT_Level.  VT100 is reserved for completeness but is never assigned by
   --  Interpret_DA1, as no modern terminal emulator sends Ps = 1 as its
   --  conformance class.
   --
   --  Mapping:
   --    Ps = 62 => VT200
   --    Ps = 63 => VT300
   --    Ps = 64 => VT400
   --    Ps = 65 => VT500
   --    All other values (including 0 and 1) => Unknown
   --  @relation(FUNC-DA1-002): VT_Level conformance level enumeration
   type VT_Level is
     (Unknown,  --  No DA1 response, or first Ps unrecognised
      VT100,    --  Ps = 1 (reserved; no modern terminal sends this)
      VT200,    --  Ps = 62
      VT300,    --  Ps = 63
      VT400,    --  Ps = 64
      VT500);   --  Ps = 65

   ---------------------------------------------------------------------------
   --  Capability Flags Array and DA1_Capabilities Record (FUNC-DA1-003)
   ---------------------------------------------------------------------------

   --  @summary Boolean array indexed by DA1_Capability for O(1) capability access.
   --  @description Each element is True when the corresponding Ps value appeared
   --  in the DA1 response.  Using a Boolean array indexed by the enumeration
   --  (rather than individual Boolean fields) enables iteration with a for loop
   --  and ensures that future enumeration additions automatically default to False.
   --  @relation(FUNC-DA1-003): Capability_Flags array type
   type Capability_Flags is
     array (DA1_Capability) of Boolean;

   --  @summary Aggregated result of a DA1 response interpretation.
   --  @description Plain (non-discriminated) record.  Supported acts as a
   --  semantic guard: when False, Level is Unknown and all Flags entries are
   --  False.  This invariant is enforced by Interpret_DA1 (FUNC-DA1-004) and
   --  expressed in its postcondition.  Default initialisation produces a
   --  safe "no DA1 response" value without requiring a named aggregate.
   --  @relation(FUNC-DA1-003): DA1_Capabilities aggregate record
   type DA1_Capabilities is record
      Supported : Boolean          := False;
      Level     : VT_Level         := Unknown;
      Flags     : Capability_Flags := [others => False];
   end record;

   ---------------------------------------------------------------------------
   --  DA1 Query Constant (FUNC-DA1-007)
   ---------------------------------------------------------------------------

   --  @summary Three-byte CSI sequence encoding the DA1 query ESC [ c.
   --  @description Encodes 0x1B 0x5B 0x63 (ESC [ c), the canonical Primary
   --  Device Attributes (DA1) request.  Defined in the SPARK On package so
   --  that both the I/O layer and test code can reference it without crossing
   --  a SPARK_Mode boundary.
   --
   --  Note on dual use: the same byte sequence ESC [ c is used elsewhere in
   --  Termicap as the DA1 sentinel appended after every OSC query (FUNC-OSC-006).
   --  In that context it is a boundary marker whose response terminates the read
   --  loop.  Here, DA1_QUERY is the primary query, and the response is the
   --  capability advertisement rather than a boundary marker.
   --  @relation(FUNC-DA1-007): DA1_QUERY constant
   DA1_QUERY : constant Byte_Array :=
     [16#1B#,   --  ESC
      16#5B#,   --  [   (CSI introducer)
      16#63#];  --  c   (Primary Device Attributes)

   ---------------------------------------------------------------------------
   --  Interpretation Function (FUNC-DA1-004)
   ---------------------------------------------------------------------------

   --  @summary Interpret a parsed DA1 response into a DA1_Capabilities record.
   --  @description Converts a DA1_Params record (from Termicap.OSC.Parsing,
   --  FUNC-OSC-010) into a structured DA1_Capabilities value.
   --
   --  Algorithm:
   --    1. If Params.Count = 0, return a zeroed DA1_Capabilities
   --       (Supported => False, Level => Unknown, Flags => [others => False]).
   --    2. Set Supported := True.
   --    3. Decode the first parameter (Params.Values(1)) as the VT conformance
   --       level: 62 => VT200, 63 => VT300, 64 => VT400, 65 => VT500,
   --       others => Unknown.
   --    4. Scan Params.Values(2 .. Params.Count); for each value V, set the
   --       corresponding Flags entry to True:
   --         2 => Printer, 3 => ReGIS_Graphics, 4 => Sixel_Graphics,
   --         6 => Selective_Erase, 8 => User_Defined_Keys, 18 => Windowing,
   --         22 => ANSI_Color, 28 => Rectangular_Editing.
   --       Unrecognised values are silently ignored.
   --    5. Return DA1_Capabilities'(Supported => True, Level => <decoded level>,
   --       Flags => <populated flags>).
   --
   --  Postcondition:
   --    - Count = 0 implies Supported = False and Level = Unknown.
   --    - Count > 0 implies Supported = True.
   --  @param Params  Parsed DA1 response from Parse_DA1_Response.
   --  @return A DA1_Capabilities record reflecting the parsed response.
   --  @relation(FUNC-DA1-004): Interpret_DA1 pure SPARK function
   function Interpret_DA1
     (Params : Termicap.OSC.Parsing.DA1_Params) return DA1_Capabilities
   with
     SPARK_Mode => On,
     Global     => null,
     Post       =>
       (if Params.Count = 0
        then not Interpret_DA1'Result.Supported
               and then Interpret_DA1'Result.Level = Unknown)
       and then
       (if Params.Count > 0
        then Interpret_DA1'Result.Supported);

   ---------------------------------------------------------------------------
   --  Capability Query Functions (FUNC-DA1-005, FUNC-DA1-006)
   ---------------------------------------------------------------------------

   --  @summary Return True if and only if the named capability is present.
   --  @description Short-circuit evaluation of Caps.Supported and then
   --  Caps.Flags (Cap) ensures that False is returned whenever Supported is
   --  False, regardless of the Cap value.  This mirrors the Is_Dark / Is_Light
   --  pattern from the dark/light feature.
   --  @param Caps  The DA1_Capabilities record to query.
   --  @param Cap   The specific capability to test.
   --  @return True when Caps.Supported is True and Caps.Flags (Cap) is True.
   --  @relation(FUNC-DA1-005): Has_Capability convenience expression function
   function Has_Capability
     (Caps : DA1_Capabilities; Cap : DA1_Capability) return Boolean
   is (Caps.Supported and then Caps.Flags (Cap))
   with
     SPARK_Mode => On,
     Global     => null,
     Post       =>
       Has_Capability'Result = (Caps.Supported and then Caps.Flags (Cap));

   --  @summary Return the VT conformance level from a DA1_Capabilities record.
   --  @description Returns Caps.Level directly.  When Caps.Supported is False,
   --  this will always be Unknown by construction of Interpret_DA1 and the
   --  default initialisation of DA1_Capabilities.  The postcondition gives
   --  SPARK-annotated callers a provable fact: any call site that knows
   --  Caps.Supported = False may substitute Unknown directly.
   --  @param Caps  The DA1_Capabilities record to query.
   --  @return The VT conformance level (Unknown when Supported is False).
   --  @relation(FUNC-DA1-006): VT_Level_Of convenience expression function
   function VT_Level_Of
     (Caps : DA1_Capabilities) return VT_Level
   is (Caps.Level)
   with
     SPARK_Mode => On,
     Global     => null,
     Post       =>
       VT_Level_Of'Result = Caps.Level
       and then (if not Caps.Supported
                 then VT_Level_Of'Result = Unknown);

end Termicap.DA1;
