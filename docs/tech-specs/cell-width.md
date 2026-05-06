# CELL-WIDTH: Cell Width Measurement Tables

**Feature:** Binary search over precomputed Unicode width tables for correct text layout
**Requirements:** FUNC-CWM-001 through FUNC-CWM-016 (`docs/requirements/cell-width.sdoc`)
**Parent Requirements:** UNI (REQ-UNI), WCW (REQ-WCW)
**Status:** Proposed
**Date:** 2026-05-06

---

## 1. Overview

The Cell Width Measurement Tables feature provides a pure, self-contained function
`Cell_Width` that returns the terminal column count (0, 1, or 2) for any Unicode
scalar value. It uses binary search over precomputed, version-tagged width tables
bundled at compile time.

This feature is complementary to the WCWIDTH feature (`Termicap.Wcwidth`): whereas
WCWIDTH probes the POSIX C library `wcwidth()` function at runtime to discover the
locale's Unicode version, CELL_WIDTH provides a static lookup independent of the OS
locale. The two approaches can be combined -- use WCWIDTH to determine which Unicode
version the terminal actually supports, then pass that version to `Cell_Width` for
consistent, cross-platform width measurements.

The width tables encode three categories:

| Width | Meaning | Examples |
|-------|---------|---------|
| 0 | Combining / non-spacing / control | Category M marks, ZWJ (U+200D), VS16 (U+FE0F), C0/C1 controls |
| 1 | Narrow (default) | ASCII, Latin, Greek, Cyrillic, most symbols |
| 2 | Wide / fullwidth | CJK ideographs, fullwidth forms, many emoji |

Multiple table versions are bundled (at minimum Unicode 3.0, 13.0, and 16.0). The
active version is selected at startup by reading the `UNICODE_VERSION` environment
variable, defaulting to the latest bundled table (`Table_Version'Last`).

The lookup function is a pure function with `Global => null`, making it eligible
for SPARK Gold proof. Tables are constant arrays (no heap allocation), ensuring
O(1) space and O(log N) time per lookup.

---

## 2. Framework Survey

### rich (Python) -- The canonical cell width table implementation

Rich's `rich/cells.py` and `rich/tools/make_width_tables.py` provide the most
complete reference for precomputed Unicode width tables:

**Table structure**: Each table is a list of `(start, end, width)` tuples, sorted
by `start`. The table generator (`make_width_tables.py`) imports its data from the
`wcwidth` Python package, which itself derives ranges from the Unicode Character
Database:

```python
# From make_width_tables.py
for version in UNICODE_VERSIONS:
    table = []
    for start, end in WIDE_EASTASIAN.get(version, []):
        table.append((start, end, 2))
    for start, end in ZERO_WIDTH.get(version, []):
        table.append((start, end, 0))
    table.sort()
```

**Lookup algorithm**: Binary search with control character early exit:

```python
def get_character_cell_size(character, unicode_version="auto"):
    codepoint = ord(character)
    if codepoint and codepoint < 32 or 0x07F <= codepoint < 0x0A0:
        return 0
    # Binary search over sorted table
    while lower_bound <= upper_bound:
        index = (lower_bound + upper_bound) >> 1
        start, end, width = table[index]
        if codepoint < start: upper_bound = index - 1
        elif codepoint > end: lower_bound = index + 1
        else: return width
    return 1  # default narrow
```

**Version selection**: Rich uses a `UNICODE_VERSION` environment variable. The value
`"auto"` auto-detects from the system's `unicodedata.unidata_version`; `"latest"`
selects the newest bundled table. Rich bundles tables for every Unicode version
from 4.1.0 through 15.1.0 (many versions).

**ZWJ and VS16 handling**: Rich handles these at the string-level `_cell_len()`
function, not in single-codepoint measurement. When `\u200d` (ZWJ) is found in a
string, it is skipped (width 0). When `\ufe0f` (VS16) follows a character in a
`narrow_to_wide` set, the preceding character's effective width is upgraded from 1
to 2. This sequence-level logic is outside Termicap's Cell_Width scope.

**Key lesson**: Rich's table format -- sorted `(start, end, width)` tuples with
only width-0 and width-2 entries, defaulting to width 1 for unmatched codepoints --
is directly transferable to Ada constant arrays. The table generator is simple:
combine `WIDE_EASTASIAN` (width 2) and `ZERO_WIDTH` (width 0), sort, done.

### lipgloss / go-runewidth (Go) -- uniseg delegation

Lipgloss and the Go TUI ecosystem delegate cell width measurement to the
`github.com/rivo/uniseg` package, which provides grapheme-cluster-aware width
measurement. The `RUNEWIDTH_EASTASIAN` environment variable controls whether East
Asian Ambiguous characters are treated as width 1 or width 2 (tcell's
`eastasian.go` reads this at `init()` time).

Go's `uniseg` uses similar sorted range tables derived from the UCD. The tables are
generated from `EastAsianWidth.txt` and `DerivedGeneralCategory.txt`. Unlike Rich,
`uniseg` bundles only the latest Unicode version's tables (no multi-version
support).

**Key lesson**: The single-version approach is simpler but less flexible.
Termicap's multi-version design follows Rich's pattern, not Go's.

### wcwidth (Python) -- The authoritative UCD source

The `wcwidth` Python package (`jquast/wcwidth` on PyPI) is the upstream data source
used by Rich's table generator. It maintains sorted range tables for zero-width and
wide characters across all Unicode versions from 4.1.0 onward, derived directly
from the UCD files `EastAsianWidth.txt` and `DerivedGeneralCategory.txt`.

**Key lesson**: `wcwidth` provides the reference data source for table generation.
Termicap's table generator should follow the same UCD derivation approach.

### notcurses (C) -- ncwidth probing

Notcurses includes `src/poc/ncwidth.c`, which probes `wcwidth()` across the full
codepoint range to build a runtime width table. This is the opposite of Termicap's
approach: notcurses queries the C library at runtime, while Termicap bundles
precomputed tables. Notcurses does not ship static width tables.

### Summary of patterns borrowed

| Aspect | Source | Termicap adaptation |
|--------|--------|---------------------|
| Table format: sorted (start, end, width) tuples | rich, wcwidth | Adopted as Ada record array |
| Binary search with default-1 for unmatched | rich | Adopted with SPARK loop invariants |
| Control character early exit | rich | Adopted; returns 0 (not -1) per FUNC-CWM-011 |
| ASCII fast path (U+0020..U+007E) | rich, wcwidth | Adopted as first check (FUNC-CWM-010) |
| Multi-version tables via UNICODE_VERSION | rich | Adopted with Table_Version enumeration |
| ZWJ/VS16 width = 0 for single codepoint | rich, wcwidth | Adopted via table entries (FUNC-CWM-007, FUNC-CWM-008) |
| Table generation from UCD data | rich, wcwidth | Adapted for Ada constant array generation |

---

## 3. Architecture

### Package hierarchy

```
Termicap
+-- Termicap.Cell_Width              [SPARK Gold] -- public API, version selection
+-- Termicap.Cell_Width.Tables       [SPARK Gold] -- table data, binary search
```

`Termicap.Cell_Width` is a sibling of `Termicap.Wcwidth` and `Termicap.Unicode`,
following the flat naming convention established by all other Termicap feature
packages (ADR-0032). The Cell_Width package is standalone: it does not depend on
`Termicap.Wcwidth`, `Termicap.Unicode`, or `Termicap.Environment` at the package
level (FUNC-CWM-012).

The child package `Termicap.Cell_Width.Tables` holds the table data and the
binary search implementation. This follows the `.IO` / `.Parsing` pattern used
by `Termicap.DA1.IO`, `Termicap.OSC.Parsing`, etc., where infrastructure is
separated from the public API.

### File layout

| File | SPARK | Description |
|------|-------|-------------|
| `src/termicap-cell_width.ads` | Gold | Package spec: `Cell_Width_Value`, `Unicode_Scalar_Value`, `Table_Version`, `Active_Version`, `Cell_Width` function specs |
| `src/termicap-cell_width.adb` | Mixed | Package body: elaboration-time env var read (SPARK Off), `Cell_Width` dispatch (SPARK On) |
| `src/termicap-cell_width-tables.ads` | Gold | Child spec: `Width_Entry`, `Width_Table`, `Cell_Width_In_Table` spec, table constants |
| `src/termicap-cell_width-tables.adb` | Gold | Child body: binary search implementation with loop invariants |

### SPARK boundary

```
                        SPARK Gold
                   +-------------------+
                   |  Cell_Width spec  |    Cell_Width_Value, Unicode_Scalar_Value,
                   |  (public API)     |    Table_Version, Cell_Width functions
                   +-------------------+
                           |
         +-----------------+-----------------+
         |                                   |
+-------------------+              +-------------------+
| Cell_Width body   |              | Tables spec+body  |
| (mixed)           |              | (SPARK Gold)      |
+-------------------+              +-------------------+
| SPARK Off:        |              | Width_Entry record |
|   Env var read    |              | Width_Table type   |
|   Active_Version  |              | Table constants    |
|   initialization  |              | Cell_Width_In_Table|
| SPARK On:         |              | (binary search)    |
|   Cell_Width      |              +-------------------+
|   dispatchers     |
+-------------------+
```

The env var read is the only non-SPARK code. All table data, the binary search
algorithm, and the public API dispatch are SPARK Gold provable.

### Dependencies

| Package | Relationship |
|---------|-------------|
| `Ada.Environment_Variables` | Used in body (SPARK Off) for UNICODE_VERSION |
| None | No dependency on Termicap.Wcwidth, Termicap.Unicode, or Termicap.Environment |

The standalone design (FUNC-CWM-012) keeps the package reusable in contexts where
only cell width measurement is needed.

---

## 4. Data Model

### Core types (FUNC-CWM-002, FUNC-CWM-012)

```ada
--  A valid Unicode scalar value: U+0000..U+10FFFF
--  (surrogate range U+D800..U+DFFF is excluded by convention but not
--  by subtype constraint, because surrogates cannot appear in valid
--  Unicode text and adding a dynamic subtype predicate would prevent
--  SPARK Gold proof).
subtype Unicode_Scalar_Value is Natural range 0 .. 16#10_FFFF#;

--  Terminal column width: 0 (combining/control), 1 (narrow), 2 (wide).
subtype Cell_Width_Value is Integer range 0 .. 2;
```

### Table version enumeration (FUNC-CWM-004)

```ada
type Table_Version is
   (Unicode_3,    -- Unicode 3.0 width tables
    Unicode_13,   -- Unicode 13.0 width tables
    Unicode_16);  -- Unicode 16.0 width tables
```

Values are ordered: `Unicode_3 < Unicode_13 < Unicode_16`. `Table_Version'Last`
is always the latest bundled version. Adding a future version (e.g., `Unicode_17`)
requires only appending a new enumeration value.

### Width table entry record (FUNC-CWM-002)

```ada
type Width_Entry is record
   First : Unicode_Scalar_Value;
   Last  : Unicode_Scalar_Value;
   Width : Cell_Width_Value;
end record;
```

Invariant: `Last >= First` for all entries. Entries are sorted by `First` with no
overlapping ranges. These invariants are established by the table generator and may
be asserted by Ghost predicates.

### Width table type

```ada
type Table_Index is range 1 .. 4_000;
--  Upper bound is generous; actual tables are expected to have ~1,500-2,000
--  entries for Unicode 16.0.

type Width_Table is array (Table_Index range <>) of Width_Entry;
```

Using an unconstrained array type allows each Unicode version's table to have a
different number of entries. The binary search function operates on
`Width_Table'Range`, making it version-agnostic.

### Table constants (FUNC-CWM-001)

```ada
--  Each table is a constant array of Width_Entry records.
--  Only width-0 and width-2 ranges are stored; unmatched codepoints
--  default to width 1.

TABLE_UNICODE_3  : constant Width_Table := [...];
TABLE_UNICODE_13 : constant Width_Table := [...];
TABLE_UNICODE_16 : constant Width_Table := [...];
```

The table data is generated from the Unicode Character Database (section 6) and
stored as Ada constant array aggregates using Ada 2022 square bracket syntax.

### Table access by version

```ada
function Get_Table (Version : Table_Version) return Width_Table
with Global => null;
```

This function uses a case statement to return the appropriate table constant. Since
all tables are compile-time constants, the function is pure and SPARK-provable.

Alternatively, an array of access-to-constant values indexed by `Table_Version`
could be used, but a simple case statement is more SPARK-friendly and avoids access
types entirely. See **ADR-0033** for the rationale.

---

## 5. Algorithm

### Cell_Width dispatch (FUNC-CWM-012)

The single-argument `Cell_Width` delegates to the two-argument overload using
`Active_Version`:

```ada
function Cell_Width (Codepoint : Unicode_Scalar_Value) return Cell_Width_Value is
begin
   return Cell_Width (Codepoint, Active_Version);
end Cell_Width;
```

The two-argument overload performs fast-path checks and then delegates to the
binary search:

```ada
function Cell_Width
   (Codepoint : Unicode_Scalar_Value;
    Version   : Table_Version)
    return Cell_Width_Value
is
begin
   --  Step 1: ASCII printable fast path (FUNC-CWM-010)
   if Codepoint in 16#0020# .. 16#007E# then
      return 1;
   end if;

   --  Step 2: C0 control characters (FUNC-CWM-011)
   if Codepoint in 16#0000# .. 16#001F# then
      return 0;
   end if;

   --  Step 3: DEL (FUNC-CWM-011)
   if Codepoint = 16#007F# then
      return 0;
   end if;

   --  Step 4: C1 control characters (FUNC-CWM-011)
   if Codepoint in 16#0080# .. 16#009F# then
      return 0;
   end if;

   --  Step 5: Binary search over version-specific table (FUNC-CWM-003)
   return Cell_Width_In_Table (Codepoint, Get_Table (Version));
end Cell_Width;
```

**Note**: Steps 1-4 handle the most frequent codepoints (ASCII) and the edge cases
(controls) before any table access, reducing average-case cost to a few
comparisons. The ordering ensures that step 1 catches the dominant case (ASCII
printable) with a single range check.

### Binary search (FUNC-CWM-003)

```ada
function Cell_Width_In_Table
   (Codepoint : Unicode_Scalar_Value;
    Table     : Width_Table)
    return Cell_Width_Value
with Global => null
is
   Low  : Table_Index := Table'First;
   High : Table_Index := Table'Last;
   Mid  : Table_Index;
begin
   --  Early exit: codepoint beyond all table entries
   if Codepoint > Table (Table'Last).Last then
      return 1;
   end if;

   --  Early exit: codepoint before all table entries
   if Codepoint < Table (Table'First).First then
      return 1;
   end if;

   while Low <= High loop
      pragma Loop_Invariant
        (Low in Table'Range and then High in Table'Range);
      pragma Loop_Invariant
        (for all I in Table'First .. Low - 1 =>
           Table (I).Last < Codepoint);
      pragma Loop_Invariant
        (for all I in High + 1 .. Table'Last =>
           Table (I).First > Codepoint);
      pragma Loop_Variant (Decreases => High - Low);

      Mid := Low + (High - Low) / 2;

      if Codepoint < Table (Mid).First then
         exit when Mid = Table'First;
         High := Mid - 1;
      elsif Codepoint > Table (Mid).Last then
         exit when Mid = Table'Last;
         Low := Mid + 1;
      else
         --  Codepoint is within [First, Last] -> return stored width
         return Table (Mid).Width;
      end if;
   end loop;

   --  No matching range found: default to narrow (width 1)
   return 1;
end Cell_Width_In_Table;
```

**Key algorithmic properties:**

1. **Overflow-safe mid computation**: `Mid := Low + (High - Low) / 2` avoids
   overflow when `Low + High` exceeds the index type range.

2. **Loop invariants**: Three invariants assert that:
   - `Low` and `High` remain within `Table'Range`.
   - All entries before `Low` have `Last < Codepoint` (searched and excluded).
   - All entries after `High` have `First > Codepoint` (searched and excluded).

3. **Loop variant**: `High - Low` strictly decreases on every iteration,
   guaranteeing termination.

4. **Exit guards**: The `exit when Mid = Table'First` and `exit when Mid = Table'Last`
   guards prevent underflow/overflow when adjusting `Low` and `High` at the array
   boundaries. This is critical for SPARK proof because `Mid - 1` when
   `Mid = Table'First` would violate the index subtype constraint.

5. **Worst-case comparisons**: For N entries, at most ceil(log2(N)) + 1
   iterations. For N = 2,000 (Unicode 16.0), this is approximately 12
   comparisons.

### Ghost predicates for table validation

```ada
function Is_Sorted_Non_Overlapping (Table : Width_Table) return Boolean is
   (for all I in Table'First .. Table'Last - 1 =>
      Table (I).Last < Table (I + 1).First)
with Ghost;

function All_Widths_Valid (Table : Width_Table) return Boolean is
   (for all I in Table'Range =>
      Table (I).Width in Cell_Width_Value
      and then Table (I).Last >= Table (I).First)
with Ghost;
```

These Ghost predicates can be used in preconditions of `Cell_Width_In_Table` to
strengthen the SPARK proof without runtime overhead:

```ada
function Cell_Width_In_Table
   (Codepoint : Unicode_Scalar_Value;
    Table     : Width_Table)
    return Cell_Width_Value
with Global => null,
     Pre => Table'Length > 0
            and then Is_Sorted_Non_Overlapping (Table)
            and then All_Widths_Valid (Table);
```

Whether to include these Ghost preconditions depends on GNATprove's ability to
discharge them automatically. If the prover can verify them from the constant table
data, they add value; otherwise, they may require manual lemmas and should be
omitted in favor of test-based validation.

---

## 6. Table Generation

### Source data

The Unicode width tables are derived from two files in the Unicode Character
Database (UCD):

1. **EastAsianWidth.txt** -- Assigns each codepoint an East Asian Width property
   (W = Wide, F = Fullwidth, H = Halfwidth, Na = Narrow, A = Ambiguous, N =
   Neutral). Codepoints with property W or F have cell width 2.

2. **DerivedGeneralCategory.txt** -- Assigns each codepoint a General Category.
   Codepoints with category Mn (Non-spacing Mark), Mc (Spacing Mark), Me
   (Enclosing Mark), and Cf (Format) contribute to width-0 ranges. Codepoints
   with category Cc (Control) are handled by the early-exit fast path, not by
   table entries.

### Generation algorithm

```
For each Unicode version (3.0, 13.0, 16.0):

  1. Parse EastAsianWidth.txt for the version.
     - Collect all codepoints with property W or F -> mark as width 2.

  2. Parse DerivedGeneralCategory.txt for the version.
     - Collect all codepoints with category Mn, Mc, Me -> mark as width 0.
     - Collect all codepoints with category Cf -> mark as width 0.
       (This includes ZWJ U+200D and other format characters.)

  3. Ensure VS16 (U+FE0F) is in the width-0 set (FUNC-CWM-008).
     (It has category Mn, so it should already be included, but this is
     a defensive check.)

  4. Ensure ZWJ (U+200D) is in the width-0 set (FUNC-CWM-007).
     (It has category Cf, so it should already be included.)

  5. Merge overlapping ranges and sort by start codepoint.

  6. Remove any ranges that cover codepoints in the control character
     fast-path ranges (U+0000..U+001F, U+007F, U+0080..U+009F), since
     these are handled before the table lookup. This is optional --
     including them in the table would produce correct results but
     waste a few table entries.

  7. Exclude codepoints with default width 1 (they do not need table
     entries since 1 is the default).

  8. Output as Ada constant array aggregate:
     TABLE_UNICODE_16 : constant Width_Table :=
       [(First => 16#0300#, Last => 16#036F#, Width => 0),
        (First => 16#0483#, Last => 16#0489#, Width => 0),
        ...
        (First => 16#4E00#, Last => 16#9FFF#, Width => 2),
        ...];
```

### Table format

Each table is an Ada constant array using the Ada 2022 square bracket aggregate
syntax:

```ada
TABLE_UNICODE_16 : constant Width_Table (1 .. TABLE_UNICODE_16_LENGTH) :=
  [(First => 16#0300#, Last => 16#036F#, Width => 0),   -- Combining Diacritical Marks
   (First => 16#0483#, Last => 16#0489#, Width => 0),   -- Cyrillic combining marks
   ...
   (First => 16#1100#, Last => 16#115F#, Width => 2),   -- Hangul Jamo (lead consonants)
   ...
   (First => 16#4E00#, Last => 16#9FFF#, Width => 2),   -- CJK Unified Ideographs
   ...
   (First => 16#FE0F#, Last => 16#FE0F#, Width => 0),   -- VS16
   ...];
```

### Expected table sizes

Based on analysis of the UCD data:

| Unicode version | Estimated entries (width 0 + width 2) |
|-----------------|---------------------------------------|
| Unicode 3.0     | ~800-1,000 |
| Unicode 13.0    | ~1,200-1,500 |
| Unicode 16.0    | ~1,500-2,000 |

Each entry is 12 bytes (three 32-bit integers), so the total data footprint for
all three tables is approximately 48-60 KB in the read-only data segment. This is
well within acceptable limits for a terminal capability library.

### Generator tool

The table generator should be a standalone script (Python, following the pattern
established by Rich's `make_width_tables.py`) that:

1. Downloads UCD files for the target Unicode version.
2. Parses `EastAsianWidth.txt` and `DerivedGeneralCategory.txt`.
3. Generates the merged, sorted table.
4. Outputs an Ada package body fragment (or a separate `.ads` file containing
   only the constant declarations).

The generator is not part of the Termicap Ada source code; it is a build-time
tool stored in `tools/generate_width_tables.py` (or similar). The generated Ada
source is checked into version control so that no Python dependency exists at
compile time.

---

## 7. SPARK Considerations

### Gold-level proof obligations (FUNC-CWM-014)

The following properties are established by GNATprove without manual lemmas:

| Property | Mechanism |
|----------|-----------|
| No array out-of-bounds | Loop invariants on `Low` and `High`; exit guards at boundaries |
| No integer overflow | `Mid := Low + (High - Low) / 2`; all arithmetic on bounded subtypes |
| Return value in range | `Cell_Width_Value` subtype; all table entries constrained; fast paths return literals |
| Termination | Loop variant `Decreases => High - Low` |
| No side effects | `Global => null` on all public functions |

### SPARK boundary placement

| Element | SPARK Mode | Level |
|---------|-----------|-------|
| `Cell_Width_Value` subtype | On | N/A (type) |
| `Unicode_Scalar_Value` subtype | On | N/A (type) |
| `Table_Version` enumeration | On | N/A (type) |
| `Width_Entry` record | On | N/A (type) |
| `Width_Table` array type | On | N/A (type) |
| `Cell_Width` (1-arg) | On | Gold |
| `Cell_Width` (2-arg) | On | Gold |
| `Cell_Width_In_Table` | On | Gold |
| `Get_Table` | On | Gold |
| Ghost predicates | On (Ghost) | N/A |
| Table constants | On | N/A (constant) |
| `Active_Version` initialization | Off | N/A (env var read) |

### Active_Version isolation pattern

The env var read for `UNICODE_VERSION` must be isolated from the SPARK-proved
lookup path. The pattern follows the same approach used throughout Termicap
(TTY detection, WCWIDTH, OSC query):

```ada
package body Termicap.Cell_Width is

   --  SPARK Off: environment variable read at elaboration time
   pragma SPARK_Mode (Off);

   function Read_Unicode_Version return Table_Version is
      --  (reads UNICODE_VERSION, parses, returns Table_Version)
   begin
      ...
   end Read_Unicode_Version;

   Active_Version_Value : constant Table_Version := Read_Unicode_Version;

   --  Re-enable SPARK for the lookup functions
   pragma SPARK_Mode (On);

   function Active_Version return Table_Version is
   begin
      return Active_Version_Value;
   end Active_Version;

   function Cell_Width (Codepoint : Unicode_Scalar_Value) return Cell_Width_Value is
   begin
      return Cell_Width (Codepoint, Active_Version_Value);
   end Cell_Width;

   function Cell_Width
      (Codepoint : Unicode_Scalar_Value;
       Version   : Table_Version)
       return Cell_Width_Value
   is
   begin
      --  Fast paths + binary search delegation (fully SPARK Gold)
      ...
   end Cell_Width;

end Termicap.Cell_Width;
```

**Note on `Active_Version` as a constant**: The spec declares
`Active_Version : constant Table_Version;` as a deferred constant. The body
completes it via the elaboration-time `Read_Unicode_Version` call. Once
elaboration completes, `Active_Version_Value` is a fixed constant for the
remainder of the process lifetime (FUNC-CWM-005).

An alternative design exposes `Active_Version` as a parameterless function
rather than a deferred constant. This avoids the deferred constant pattern,
which can interact subtly with SPARK elaboration analysis. The function
approach is simpler for SPARK:

```ada
--  In spec:
function Active_Version return Table_Version
with Global => null;

--  In body (SPARK On section):
function Active_Version return Table_Version is
begin
   return Active_Version_Value;
end Active_Version;
```

The function reads a body-level constant, but since `Active_Version_Value` is
initialized at elaboration time and never changes, `Global => null` is
semantically accurate (the value is a constant, not a variable). GNATprove may
require a `Global => (Input => Active_Version_Value)` contract or a pragma
Annotate to justify the null contract. If so, the function should be annotated
accordingly.

---

## 8. Integration

### Relationship to Termicap.Wcwidth

`Termicap.Cell_Width` and `Termicap.Wcwidth` serve the same domain -- measuring
character width -- through different mechanisms:

| Aspect | Cell_Width | Wcwidth |
|--------|-----------|---------|
| Mechanism | Static table lookup | Runtime C FFI (`wcwidth()`) |
| Complexity | O(log N) | O(1) (single C call) |
| Platform | All (no OS dependency) | POSIX only |
| SPARK level | Gold | Spec only (body Off) |
| Consistency | Same result everywhere | Locale-dependent |
| Version selection | `UNICODE_VERSION` env var | Locale's C library tables |

The integration pattern documented in FUNC-CWM-013:

```ada
--  Step 1: Determine locale's Unicode version via wcwidth probing
Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

--  Step 2: Map Wcwidth_Level to Table_Version
Resolved_Version := (case Wcw_Level is
   when Unknown    => Termicap.Cell_Width.Active_Version,
   when Unicode_3  => Termicap.Cell_Width.Unicode_3,
   when Unicode_13 => Termicap.Cell_Width.Unicode_13,
   when Unicode_16 => Termicap.Cell_Width.Unicode_16);

--  Step 3: Use Cell_Width with the locale-matched table
Width := Termicap.Cell_Width.Cell_Width (Codepoint, Resolved_Version);
```

This integration is advisory and lives at the caller level. `Termicap.Cell_Width`
does not `with` `Termicap.Wcwidth` (FUNC-CWM-012).

### Relationship to Termicap.Unicode

`Termicap.Cell_Width` does not depend on `Termicap.Unicode`. The `Unicode_Level`
type (None/Basic/Extended) describes whether Unicode is supported at all, while
`Cell_Width` measures the display width of individual codepoints. These are
orthogonal concerns: a caller might use `Unicode_Level` to decide whether to
emit Unicode characters, and `Cell_Width` to compute the column offset for layout.

### Capability Record

The `Terminal_Capabilities` record in `Termicap.Capabilities` does not need a
dedicated field for `Cell_Width` data. Cell width measurement is a utility
function, not a detected capability. However, `Active_Version` could optionally
be stored in the record for diagnostics:

```ada
type Terminal_Capabilities is record
   ...
   Cell_Width_Version : Termicap.Cell_Width.Table_Version;
   ...
end record;
```

This is a "Could" and can be deferred without breaking changes.

---

## 9. Environment Variable Handling

### UNICODE_VERSION parsing (FUNC-CWM-005)

The `Read_Unicode_Version` function, called once at elaboration time, implements
the following logic:

```ada
function Read_Unicode_Version return Table_Version is
begin
   --  Step 1: Check if UNICODE_VERSION is set
   if not Ada.Environment_Variables.Exists ("UNICODE_VERSION") then
      return Table_Version'Last;  -- FUNC-CWM-006: default to latest
   end if;

   declare
      Value : constant String :=
        Ada.Environment_Variables.Value ("UNICODE_VERSION");
   begin
      --  Step 2: Empty value -> default
      if Value'Length = 0 then
         return Table_Version'Last;
      end if;

      --  Step 3: Parse version string (case-insensitive matching)
      if Value = "3" or else Value = "3.0" then
         return Unicode_3;
      elsif Value = "13" or else Value = "13.0" then
         return Unicode_13;
      elsif Value = "16" or else Value = "16.0" then
         return Unicode_16;
      else
         --  Step 4: Unrecognised version -> default (FUNC-CWM-006)
         return Table_Version'Last;
      end if;
   end;
end Read_Unicode_Version;
```

**Key properties:**

1. **One-time evaluation**: Called at elaboration time, result stored in a
   body-level constant. Subsequent `Cell_Width` calls never read the environment.

2. **Silent fallback**: Unrecognised values default to `Table_Version'Last`
   (FUNC-CWM-006). No exception, no diagnostic output.

3. **SPARK_Mode => Off**: The entire function body is in the SPARK Off region
   because `Ada.Environment_Variables` is not SPARK-compatible (I/O).

4. **Extensibility**: When Unicode 17.0 is added, only the parsing logic needs
   a new `elsif` branch (in addition to the table data and enumeration value).

---

## 10. Testing Strategy

### Test categories (FUNC-CWM-016)

#### Category 1: ASCII fast path (FUNC-CWM-010)

```ada
pragma Assert (Cell_Width (16#0020#) = 1);  -- SPACE
pragma Assert (Cell_Width (16#0041#) = 1);  -- 'A'
pragma Assert (Cell_Width (16#007E#) = 1);  -- '~'
```

Verify that ASCII printable characters return 1 without table access.

#### Category 2: Control characters (FUNC-CWM-011)

```ada
pragma Assert (Cell_Width (16#0000#) = 0);  -- NUL
pragma Assert (Cell_Width (16#000A#) = 0);  -- LF
pragma Assert (Cell_Width (16#001F#) = 0);  -- US
pragma Assert (Cell_Width (16#007F#) = 0);  -- DEL
pragma Assert (Cell_Width (16#0080#) = 0);  -- PAD (C1)
pragma Assert (Cell_Width (16#009F#) = 0);  -- APC (C1)
```

Verify that all C0 and C1 controls return 0.

#### Category 3: ZWJ (FUNC-CWM-007)

```ada
pragma Assert (Cell_Width (16#200D#) = 0);  -- ZWJ
```

#### Category 4: VS16 (FUNC-CWM-008)

```ada
pragma Assert (Cell_Width (16#FE0F#) = 0);  -- VS16
```

#### Category 5: Combining characters (FUNC-CWM-009)

```ada
pragma Assert (Cell_Width (16#0300#) = 0);  -- COMBINING GRAVE ACCENT
pragma Assert (Cell_Width (16#036F#) = 0);  -- COMBINING LATIN SMALL LETTER X
pragma Assert (Cell_Width (16#20D0#) = 0);  -- COMBINING LEFT HARPOON ABOVE
```

#### Category 6: Wide / fullwidth characters

```ada
pragma Assert (Cell_Width (16#4E00#) = 2);    -- CJK ideograph
pragma Assert (Cell_Width (16#FF01#) = 2);    -- FULLWIDTH EXCLAMATION MARK
pragma Assert (Cell_Width (16#1F600#) = 2);   -- GRINNING FACE emoji
```

#### Category 7: Narrow non-ASCII characters

```ada
pragma Assert (Cell_Width (16#00E9#) = 1);  -- e with acute
pragma Assert (Cell_Width (16#03B1#) = 1);  -- Greek alpha
```

#### Category 8: Version-specific boundary codepoints

Test that version-specific codepoints have appropriate widths under different
table versions:

```ada
--  Braille was introduced in Unicode 3.0
pragma Assert (Cell_Width (16#28FF#, Unicode_3) = 1);

--  Sextant block was introduced in Unicode 13.0
pragma Assert (Cell_Width (16#1FB38#, Unicode_13) = 1);

--  Legacy Computing Supplement introduced in Unicode 16.0
pragma Assert (Cell_Width (16#1CD00#, Unicode_16) = 1);
```

These sentinel codepoints are the same ones used by the WCWIDTH feature
(FUNC-WCW-002), enabling cross-validation.

#### Category 9: Binary search edge cases

```ada
--  First entry in table
pragma Assert (Cell_Width (Table_First_Codepoint, Version) = Expected);

--  Last entry in table
pragma Assert (Cell_Width (Table_Last_Codepoint, Version) = Expected);

--  Codepoint not in any range (should return 1)
pragma Assert (Cell_Width (16#FFFFF#, Version) = 1);

--  Codepoint just before a range boundary
--  Codepoint just after a range boundary
--  Codepoint at U+10FFFF (maximum scalar value)
pragma Assert (Cell_Width (16#10_FFFF#) in Cell_Width_Value);
```

#### Category 10: UNICODE_VERSION parsing (FUNC-CWM-005, FUNC-CWM-006)

These tests require controlled environment variable injection. They are best
implemented as subprocess tests or as tests against the parsing logic extracted
into a testable helper:

- `"3"` and `"3.0"` both select `Unicode_3`.
- `"13"` and `"13.0"` both select `Unicode_13`.
- `"16"` and `"16.0"` both select `Unicode_16`.
- `"99.0"` (unrecognised) selects `Table_Version'Last`.
- `""` (empty) selects `Table_Version'Last`.
- Unset `UNICODE_VERSION` selects `Table_Version'Last`.

### Test implementation approach

Since `Active_Version` is determined at elaboration time, UNICODE_VERSION parsing
tests must use one of:

1. **Subprocess execution**: Run the test binary with a controlled
   `UNICODE_VERSION` env var. Verify the output.

2. **Extracted parsing function**: Make `Read_Unicode_Version`'s parsing logic
   available as a testable function that takes a `String` parameter rather than
   reading the environment directly. The actual `Read_Unicode_Version` calls
   this function with the env var value. This allows unit testing the parsing
   without subprocess overhead.

Approach 2 is preferred for unit test coverage.

### SPARK proof as testing

GNATprove verification of the binary search function is itself a form of testing:
it proves the absence of runtime errors (array bounds, overflow, range violations)
for all possible inputs, which is stronger than any finite test suite. The
`alr exec -- gnatprove -P termicap.gpr` command should discharge all proof
obligations for `Termicap.Cell_Width` and `Termicap.Cell_Width.Tables` at Gold
level.

---

## 11. Traceability

| UID | Priority | Summary | Design element / location |
|-----|----------|---------|---------------------------|
| FUNC-CWM-001 | Must | Bundled Unicode width table versions | S.4, S.6; `TABLE_UNICODE_3`, `TABLE_UNICODE_13`, `TABLE_UNICODE_16` constants in `Termicap.Cell_Width.Tables` |
| FUNC-CWM-002 | Must | Codepoint range entry format | S.4; `Width_Entry` record type, `Width_Table` array type |
| FUNC-CWM-003 | Must | Binary search over sorted ranges | S.5; `Cell_Width_In_Table` function with loop invariants |
| FUNC-CWM-004 | Must | Table_Version enumeration | S.4; `Table_Version` type in `Termicap.Cell_Width` spec |
| FUNC-CWM-005 | Must | UNICODE_VERSION env var parsing | S.9; `Read_Unicode_Version` in body (SPARK Off) |
| FUNC-CWM-006 | Must | Default version = Table_Version'Last | S.9; fallback to `Table_Version'Last` in all unmatched cases |
| FUNC-CWM-007 | Must | ZWJ (U+200D) returns 0 | S.6; ZWJ included in width-0 table ranges via UCD category Cf |
| FUNC-CWM-008 | Must | VS16 (U+FE0F) returns 0 | S.6; VS16 included in width-0 table ranges via UCD category Mn |
| FUNC-CWM-009 | Must | Combining characters (category M) return 0 | S.6; all category M ranges included in width-0 table entries |
| FUNC-CWM-010 | Must | ASCII printable fast path | S.5; first check in `Cell_Width`, returns 1 for U+0020..U+007E |
| FUNC-CWM-011 | Must | Control characters return 0 | S.5; early-exit checks for C0, DEL, C1 ranges |
| FUNC-CWM-012 | Must | Public API specification | S.3, S.4; `Cell_Width` (1-arg and 2-arg overloads), `Active_Version`, all with `Global => null` |
| FUNC-CWM-013 | Should | Complementary use with WCWIDTH | S.8; integration pattern documented, no package-level dependency |
| FUNC-CWM-014 | Must | SPARK Gold provability | S.7; proof obligations table, SPARK boundary diagram |
| FUNC-CWM-015 | Must | O(log N) lookup, constant storage | S.5; binary search algorithm, constant array tables, no heap |
| FUNC-CWM-016 | Should | Test coverage | S.10; 10 test categories covering all requirements |

---

## 12. Files to Create/Modify

### Files to create

| File | Description |
|------|-------------|
| `src/termicap-cell_width.ads` | Package spec: types, `Active_Version`, `Cell_Width` overloads |
| `src/termicap-cell_width.adb` | Package body: env var read (SPARK Off), dispatch (SPARK On) |
| `src/termicap-cell_width-tables.ads` | Child spec: `Width_Entry`, `Width_Table`, table constants, `Cell_Width_In_Table` |
| `src/termicap-cell_width-tables.adb` | Child body: binary search with loop invariants |
| `tools/generate_width_tables.py` | Table generator: UCD -> Ada constant arrays |
| `tests/src/termicap-cell_width-tests.ads` | Test package spec |
| `tests/src/termicap-cell_width-tests.adb` | Test cases: 10 categories from FUNC-CWM-016 |
| `docs/adr/0033-cell-width-table-representation.md` | ADR: flat range array vs. two-level lookup |
| `docs/adr/0034-control-character-width-zero.md` | ADR: control character width 0 (not -1) |

### Files to modify

| File | Modification |
|------|-------------|
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Cell_Width` and `Termicap.Cell_Width.Tables` to package overview |
| `docs/architecture/04-runtime-view.md` | Add cell width lookup flow |
| `docs/adr/README.md` | Add ADR-0033 and ADR-0034 entries |

---

## 13. ADRs

**ADR-0033** (`docs/adr/0033-cell-width-table-representation.md`): Documents
the decision to use a flat sorted array of `(First, Last, Width)` range entries
with binary search, rather than a two-level lookup table or a flat per-codepoint
array.

**ADR-0034** (`docs/adr/0034-control-character-width-zero.md`): Documents the
decision to return 0 (not -1) for control characters, diverging from the POSIX
`wcwidth()` convention but consistent with Ada's strongly-typed return subtype.

---

## Related Documents

- **Requirements:** `docs/requirements/cell-width.sdoc` (FUNC-CWM-001 through FUNC-CWM-016)
- **ADR-0007:** `docs/adr/0007-unicode-level-three-value-enum.md` (Unicode_Level enum)
- **ADR-0032:** `docs/adr/0032-wcwidth-package-placement.md` (Wcwidth package placement)
- **ADR-0033:** `docs/adr/0033-cell-width-table-representation.md` (table representation)
- **ADR-0034:** `docs/adr/0034-control-character-width-zero.md` (control character width)
- **Tech Spec:** `docs/tech-specs/wcwidth.md` (wcwidth probing)
- **Tech Spec:** `docs/tech-specs/unicode-support.md` (Unicode detection)
- **Architecture:** `docs/architecture/03-building-blocks.md` (package structure)
- **Global Synthesis:** `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` (section 2.10)
- **Rich cells.py:** `reference-frameworks/rich/rich/cells.py` (binary search reference)
- **Rich make_width_tables.py:** `reference-frameworks/rich/tools/make_width_tables.py` (table generation)
