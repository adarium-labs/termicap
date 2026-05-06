-------------------------------------------------------------------------------
--  Termicap.Cell_Width - Cell Width Measurement Tables
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Pure, self-contained function for measuring terminal column width of any
--  Unicode scalar value using precomputed, version-tagged width tables.
--
--  @description
--  Provides Cell_Width functions that return the terminal column count
--  (0, 1, or 2) for any Unicode scalar value.  Binary search is performed over
--  precomputed width tables bundled at compile time.  Three Unicode version
--  tables are available (Unicode 3.0, 13.0, 16.0); the active table is
--  selected at elaboration time from the UNICODE_VERSION environment variable,
--  defaulting to the latest bundled version.
--
--  Width semantics:
--    0 -- Combining / non-spacing / control (category M marks, C0/C1 controls,
--         ZWJ U+200D, VS16 U+FE0F)
--    1 -- Narrow (default): ASCII, Latin, Greek, Cyrillic, most symbols
--    2 -- Wide / fullwidth: CJK ideographs, fullwidth forms, many emoji
--
--  Fast paths (no table access):
--    U+0020..U+007E  ASCII printable -> 1
--    U+0000..U+001F  C0 controls     -> 0
--    U+007F          DEL             -> 0
--    U+0080..U+009F  C1 controls     -> 0
--
--  SPARK level: Gold (all public functions, Global => null).
--  The UNICODE_VERSION environment variable read is isolated in the package
--  body under SPARK_Mode => Off.  The Active_Version function reads a
--  body-level constant that is fixed for the process lifetime; its Global
--  contract is annotated null in the body because the constant never changes
--  after elaboration.
--
--  This package is standalone: it does not depend on Termicap.Wcwidth,
--  Termicap.Unicode, or Termicap.Environment.
--
--  Requirements Coverage:
--    - @relation(FUNC-CWM-001): Bundled Unicode width table versions
--    - @relation(FUNC-CWM-002): Codepoint range entry format
--    - @relation(FUNC-CWM-004): Table_Version enumeration
--    - @relation(FUNC-CWM-005): UNICODE_VERSION env var parsing
--    - @relation(FUNC-CWM-006): Default version = Table_Version'Last
--    - @relation(FUNC-CWM-010): ASCII printable fast path
--    - @relation(FUNC-CWM-011): Control characters return 0
--    - @relation(FUNC-CWM-012): Public API specification

package Termicap.Cell_Width
  with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Core Types (FUNC-CWM-002, FUNC-CWM-012)
   ---------------------------------------------------------------------------

   --  @summary A valid Unicode scalar value: U+0000..U+10FFFF.
   --  @description The surrogate range U+D800..U+DFFF is excluded by
   --  convention but not by subtype constraint.  Adding a dynamic predicate
   --  would prevent SPARK Gold proof; surrogates cannot appear in valid
   --  Unicode text.
   --  @relation(FUNC-CWM-002): Unicode scalar value type
   subtype Unicode_Scalar_Value is Natural range 0 .. 16#10_FFFF#;

   --  @summary Terminal column width: 0 (combining/control), 1 (narrow), 2 (wide).
   --  @relation(FUNC-CWM-002): Cell width return type
   subtype Cell_Width_Value is Integer range 0 .. 2;

   ---------------------------------------------------------------------------
   --  Table Version Enumeration (FUNC-CWM-004)
   ---------------------------------------------------------------------------

   --  @summary Unicode version for which width tables were generated.
   --  @description Ordered enumeration: Unicode_3 < Unicode_13 < Unicode_16.
   --  Table_Version'Last is always the latest bundled version.  Adding a
   --  future version (e.g. Unicode_17) requires appending a new literal and
   --  supplying the corresponding table data.
   --  @relation(FUNC-CWM-004): Three-valued ordered Table_Version enumeration
   type Table_Version is
     (Unicode_3,
      --  Unicode 3.0 width tables.
      Unicode_13,
      --  Unicode 13.0 width tables.
      Unicode_16
      --  Unicode 16.0 width tables (latest bundled version).
     );

   ---------------------------------------------------------------------------
   --  Version Query (FUNC-CWM-005, FUNC-CWM-006)
   ---------------------------------------------------------------------------

   --  @summary Return the Unicode table version currently active for this process.
   --  @description The version is determined once at elaboration time by reading
   --  the UNICODE_VERSION environment variable.  Recognised values: "3", "3.0",
   --  "13", "13.0", "16", "16.0".  Unrecognised or absent values default to
   --  Table_Version'Last (FUNC-CWM-006).  The result is constant for the
   --  lifetime of the process.
   --
   --  The Global => null contract is justified by a pragma Annotate in the body:
   --  the body-level constant Active_Version_Value is set at elaboration time
   --  and never changes; reading it is semantically equivalent to reading a
   --  compile-time constant.
   --  @return The active Table_Version selected at elaboration time.
   --  @relation(FUNC-CWM-005): UNICODE_VERSION env var parsing
   --  @relation(FUNC-CWM-006): Default to Table_Version'Last
   --  @relation(FUNC-CWM-012): Public API specification
   function Active_Version return Table_Version
   with Global => null;

   ---------------------------------------------------------------------------
   --  Cell Width Measurement (FUNC-CWM-003, FUNC-CWM-010, FUNC-CWM-011,
   --                          FUNC-CWM-012)
   ---------------------------------------------------------------------------

   --  @summary Return the terminal column width of a Unicode scalar value
   --           using the active table version.
   --  @description Delegates to the two-argument overload with Active_Version.
   --  Fast paths are applied before any table lookup:
   --    U+0020..U+007E -> 1 (ASCII printable)
   --    U+0000..U+001F -> 0 (C0 controls)
   --    U+007F         -> 0 (DEL)
   --    U+0080..U+009F -> 0 (C1 controls)
   --  Remaining codepoints are resolved via binary search over the version table.
   --  @param Codepoint  A Unicode scalar value (0 .. 16#10_FFFF#).
   --  @return 0, 1, or 2: the terminal column count for Codepoint.
   --  @relation(FUNC-CWM-010): ASCII printable fast path
   --  @relation(FUNC-CWM-011): Control characters return 0
   --  @relation(FUNC-CWM-012): Single-argument public API
   function Cell_Width
     (Codepoint : Unicode_Scalar_Value) return Cell_Width_Value
   with Global => null;

   --  @summary Return the terminal column width of a Unicode scalar value
   --           using an explicitly supplied table version.
   --  @description Applies the same fast paths as the single-argument overload,
   --  then performs a binary search over the table for the given Version.
   --  This overload is pure (Global => null) and SPARK Gold provable.
   --  @param Codepoint  A Unicode scalar value (0 .. 16#10_FFFF#).
   --  @param Version    The Unicode width table version to use for lookup.
   --  @return 0, 1, or 2: the terminal column count for Codepoint.
   --  @relation(FUNC-CWM-003): Binary search dispatch
   --  @relation(FUNC-CWM-010): ASCII printable fast path
   --  @relation(FUNC-CWM-011): Control characters return 0
   --  @relation(FUNC-CWM-012): Two-argument public API
   function Cell_Width
     (Codepoint : Unicode_Scalar_Value; Version : Table_Version)
      return Cell_Width_Value
   with Global => null;

end Termicap.Cell_Width;
