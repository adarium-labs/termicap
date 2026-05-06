# API Reference: `Termicap.Cell_Width`

Package providing a pure, self-contained function for measuring the terminal column width (0, 1, or 2) of any Unicode scalar value. Uses precomputed, version-tagged width tables bundled at compile time. The active table version is selected once at elaboration time from the `UNICODE_VERSION` environment variable.

**Files:**
- `src/termicap-cell_width.ads`
- `src/termicap-cell_width.adb`
- `src/termicap-cell_width-tables.ads`
- `src/termicap-cell_width-tables.adb`

**SPARK_Mode:** On (spec + body); env-var read region is locally Off during elaboration only
**License:** Apache-2.0

---

## Overview

The CELL-WIDTH feature answers the question "how many terminal columns does this Unicode codepoint occupy?" The answer is always 0, 1, or 2:

| Width | Meaning | Examples |
|-------|---------|---------|
| 0 | Combining / non-spacing / control | Category M marks, ZWJ (U+200D), VS16 (U+FE0F), C0/C1 controls |
| 1 | Narrow (default) | ASCII, Latin, Greek, Cyrillic, most symbols |
| 2 | Wide / fullwidth | CJK ideographs, fullwidth forms, many emoji |

Three Unicode version tables are bundled: 3.0 (74 entries), 13.0 (80 entries), and 16.0 (82 entries). The active table is chosen at process startup by reading `UNICODE_VERSION` from the environment; absent or unrecognised values default to the latest bundled table (Unicode 16.0).

Only width-0 and width-2 ranges are stored. Any codepoint not matched by a stored range is returned as 1 (narrow), which is correct for all ASCII, Latin, Greek, and Cyrillic codepoints.

**Key distinctions from `Termicap.Wcwidth`:**

| Property | `Termicap.Wcwidth` | `Termicap.Cell_Width` |
|----------|-------------------|-----------------------|
| Source of truth | OS C locale (`wcwidth()`) | Precomputed table (compile-time constant) |
| Runtime I/O | Yes (C FFI, locale probe) | No (elaboration-time env-var read only) |
| Platform | POSIX only (stub on Windows) | All platforms |
| SPARK level | Silver (spec), Off (body) | Gold (spec + body) |
| Granularity | Per-codepoint (runtime) | Per-codepoint (static lookup) |

The recommended combined usage is: probe the OS locale version with `Termicap.Wcwidth.Probe_Wcwidth_Level`, map `Wcwidth_Level` to a `Table_Version`, then call `Cell_Width (CP, Version)` for consistent, cross-platform width measurement.

**No TTY required.** `Cell_Width` never opens `/dev/tty`, creates a `Probe_Session`, or depends on TTY status. It is safe to call at any point after package elaboration, from any thread, without preconditions on the terminal state.

**Thread safety.** Both `Cell_Width` overloads are pure functions (`Global => null`) with no shared mutable state. They may be called concurrently from any number of threads without synchronisation.

---

## Types

### `Unicode_Scalar_Value`

```ada
subtype Unicode_Scalar_Value is Natural range 0 .. 16#10_FFFF#;
```

A valid Unicode scalar value. Covers U+0000 through U+10FFFF (the full Unicode code space). The surrogate range U+D800..U+DFFF is excluded by convention in valid Unicode text; a dynamic predicate is intentionally omitted to preserve SPARK Gold provability — surrogates cannot appear in well-formed UTF-8 or UTF-32 input.

**Requirements:** FUNC-CWM-002

---

### `Cell_Width_Value`

```ada
subtype Cell_Width_Value is Integer range 0 .. 2;
```

The terminal column count for a codepoint:

| Value | Meaning |
|-------|---------|
| 0 | Combining, non-spacing, or control character. Occupies no additional columns when rendered after a base character. |
| 1 | Narrow character (the default). Occupies one column. |
| 2 | Wide or fullwidth character. Occupies two columns. |

**Requirements:** FUNC-CWM-002

---

### `Table_Version`

```ada
type Table_Version is
  (Unicode_3,    --  Unicode 3.0 width tables (74 entries)
   Unicode_13,   --  Unicode 13.0 width tables (80 entries)
   Unicode_16);  --  Unicode 16.0 width tables, latest bundled (82 entries)
```

Ordered enumeration identifying which bundled Unicode width table is used for lookup. `Table_Version'Last` is always the latest bundled version. The ordering `Unicode_3 < Unicode_13 < Unicode_16` allows `Table_Version'Max` for ceiling operations.

**Adding a future version** (e.g., Unicode 17) requires: appending a new literal to this enumeration and supplying the corresponding table constant and length constant in `Termicap.Cell_Width.Tables`.

**Requirements:** FUNC-CWM-004

---

## Constants

There are no named constants exported from `Termicap.Cell_Width` itself. Width table lengths and table constants are defined in the child package `Termicap.Cell_Width.Tables` (see below).

---

## Functions

### `Active_Version`

```ada
function Active_Version return Table_Version
with Global => null;
```

Return the Unicode table version currently active for this process.

The version is determined once at elaboration time by reading the `UNICODE_VERSION` environment variable. Recognised values:

| Env-var value | Selected version |
|---------------|-----------------|
| `"3"` or `"3.0"` | `Unicode_3` |
| `"13"` or `"13.0"` | `Unicode_13` |
| `"16"` or `"16.0"` | `Unicode_16` |
| absent, empty, or any other value | `Table_Version'Last` (`Unicode_16`) |

The result is constant for the lifetime of the process. `Active_Version` never reads the environment variable again after package elaboration.

**SPARK boundary:** The spec carries `Global => null`; the env-var read is isolated in the body under a locally `SPARK_Mode => Off` region during elaboration. GNATprove treats the post-elaboration read of the body-level constant as side-effect-free (justified via `pragma Annotate` in the body).

**Requirements:** FUNC-CWM-005, FUNC-CWM-006, FUNC-CWM-012

---

### `Cell_Width (Codepoint)`

```ada
function Cell_Width
  (Codepoint : Unicode_Scalar_Value) return Cell_Width_Value
with Global => null;
```

Return the terminal column width of a Unicode scalar value using the active table version.

Delegates to `Cell_Width (Codepoint, Active_Version)`. Four fast paths are applied before any table access:

| Codepoint range | Returned width | Reason |
|----------------|---------------|--------|
| U+0020..U+007E | 1 | ASCII printable characters |
| U+0000..U+001F | 0 | C0 control characters |
| U+007F | 0 | DEL |
| U+0080..U+009F | 0 | C1 control characters |

Codepoints outside these ranges are resolved via binary search in `Termicap.Cell_Width.Tables.Cell_Width_In_Table`.

**Parameters:**

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Codepoint` | in | A Unicode scalar value (0 .. 16#10_FFFF#). |

**Returns:** 0, 1, or 2 — the terminal column count for `Codepoint` using `Active_Version`.

**Requirements:** FUNC-CWM-010, FUNC-CWM-011, FUNC-CWM-012

---

### `Cell_Width (Codepoint, Version)`

```ada
function Cell_Width
  (Codepoint : Unicode_Scalar_Value; Version : Table_Version)
   return Cell_Width_Value
with Global => null;
```

Return the terminal column width of a Unicode scalar value using an explicitly supplied table version. This overload is pure (`Global => null`) and SPARK Gold provable.

Applies the same four fast paths as the single-argument overload, then dispatches to `Termicap.Cell_Width.Tables.Cell_Width_In_Table` with the compile-time constant table for `Version`.

**Parameters:**

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Codepoint` | in | A Unicode scalar value (0 .. 16#10_FFFF#). |
| `Version` | in | The Unicode width table version to use for lookup. |

**Returns:** 0, 1, or 2 — the terminal column count for `Codepoint` according to the `Version` table.

**When to prefer this overload:**
- When the caller has already determined the Unicode version (e.g., from `Termicap.Wcwidth.Probe_Wcwidth_Level`).
- In SPARK Gold code where the explicit version must be provably constrained.
- In tests that need to compare behaviour across table versions.

**Requirements:** FUNC-CWM-003, FUNC-CWM-010, FUNC-CWM-011, FUNC-CWM-012

---

## Child Package: `Termicap.Cell_Width.Tables`

The child package `Termicap.Cell_Width.Tables` is the data layer. It is an implementation detail — callers of `Termicap.Cell_Width` do not need to `with` it directly. It is documented here for completeness and for authors who need to audit or extend the table data.

### Types

#### `Table_Index`

```ada
type Table_Index is range 1 .. 4_000;
```

Index subtype for `Width_Table` arrays. The upper bound (4,000) is generous; actual tables use 74–82 entries.

#### `Width_Entry`

```ada
type Width_Entry is record
   First : Unicode_Scalar_Value;
   Last  : Unicode_Scalar_Value;
   Width : Cell_Width_Value;
end record;
```

A single codepoint range entry: all codepoints from `First` to `Last` (inclusive) have the given `Width`. By convention (enforced by ghost predicates, not subtype constraints): `Last >= First` and `Width in {0, 2}` (width 1 is never stored; unmatched codepoints default to 1). Entries within each table are sorted by `First` with no overlapping ranges.

#### `Width_Table`

```ada
type Width_Table is array (Table_Index range <>) of Width_Entry;
```

Unconstrained array of `Width_Entry` records. Each bundled table is a named constant of type `Width_Table (1 .. N)`.

### Ghost Predicates

#### `All_Widths_Valid`

```ada
function All_Widths_Valid (Table : Width_Table) return Boolean
is (for all I in Table'Range =>
      Table (I).Width in Cell_Width_Value
      and then Table (I).Last >= Table (I).First)
with Ghost;
```

Returns `True` when every entry has a valid `Width` and `Last >= First`. Used in the precondition of `Cell_Width_In_Table`. No runtime cost (Ghost).

#### `Is_Sorted_Non_Overlapping`

```ada
function Is_Sorted_Non_Overlapping (Table : Width_Table) return Boolean
is (for all I in Table'First .. Table_Index'Pred (Table'Last) =>
      Table (I).Last < Table (Table_Index'Succ (I)).First)
with Ghost;
```

Returns `True` when for all adjacent entries `I` and `I+1`, `Table(I).Last < Table(I+1).First`. Justifies the binary search loop invariant. No runtime cost (Ghost).

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `TABLE_UNICODE_3_LENGTH` | 74 | Entry count for the Unicode 3.0 table. |
| `TABLE_UNICODE_13_LENGTH` | 80 | Entry count for the Unicode 13.0 table. |
| `TABLE_UNICODE_16_LENGTH` | 82 | Entry count for the Unicode 16.0 table. |
| `TABLE_UNICODE_3` | `Width_Table (1 .. 74)` | Precomputed Unicode 3.0 width table. Covers basic combining marks (category M, Cf), CJK ideographs, Hangul, fullwidth forms, Yi, Variation Selectors (VS16 via U+FE00..U+FE0F), ZWJ (via U+200B..U+200F range). |
| `TABLE_UNICODE_13` | `Width_Table (1 .. 80)` | Precomputed Unicode 13.0 width table. Adds NKo combining, Samaritan combining, emoji pictographs (U+1F300..U+1F64F, U+1F900..U+1F9FF), supplementary CJK (U+20000..U+2FFFD, U+30000..U+3FFFD). |
| `TABLE_UNICODE_16` | `Width_Table (1 .. 82)` | Precomputed Unicode 16.0 width table. Adds Mandaic combining (U+0859..U+085B) and Combining Diacritical Marks Extended (U+1AB0..U+1ABE) beyond Unicode 13.0. |

### Functions

#### `Get_Table`

```ada
function Get_Table (Version : Table_Version) return Width_Table
with Global => null;
```

Return the precomputed width table for `Version`. Pure case dispatch over `Table_Version`; no heap allocation. All three tables are compile-time constants.

#### `Cell_Width_In_Table`

```ada
function Cell_Width_In_Table
  (Codepoint : Unicode_Scalar_Value; Table : Width_Table)
   return Cell_Width_Value
with
  Global => null,
  Pre    =>
    Table'Length > 0
    and then All_Widths_Valid (Table)
    and then Is_Sorted_Non_Overlapping (Table);
```

Binary search over a sorted `Width_Table`. Returns the `Width` field of the matching entry, or 1 (default narrow) when no entry covers `Codepoint`. O(log N) time; terminates in at most 7 iterations for the largest bundled table.

**Preconditions** (automatically discharged when called with the bundled constants):
- `Table'Length > 0`
- `All_Widths_Valid (Table)` — all entries have valid `Width` and `Last >= First`
- `Is_Sorted_Non_Overlapping (Table)` — entries are sorted with no overlapping ranges

**SPARK Gold proofs discharged by GNATprove:**
- No array out-of-bounds (loop invariants on `Low` and `High`)
- No integer overflow (`Low + (High - Low) / 2`)
- Return value always in `Cell_Width_Value`
- Termination (`High - Low` loop variant)
- No side effects (`Global => null`)

---

## Usage Patterns

### Pattern 1: Simple single-codepoint lookup (active version)

The simplest usage — relies on `UNICODE_VERSION` being set in the environment, or accepts the default (Unicode 16.0):

```ada
with Termicap.Cell_Width;

declare
   W : Termicap.Cell_Width.Cell_Width_Value;
begin
   W := Termicap.Cell_Width.Cell_Width (16#4E2D#);  --  U+4E2D CJK UNIFIED IDEOGRAPH
   --  W = 2 (wide)

   W := Termicap.Cell_Width.Cell_Width (Character'Pos ('A'));
   --  W = 1 (narrow, ASCII fast path)

   W := Termicap.Cell_Width.Cell_Width (16#200D#);  --  U+200D ZERO WIDTH JOINER
   --  W = 0 (combining/format)
end;
```

### Pattern 2: Explicit version lookup

Use the two-argument overload when the Unicode version is known (e.g., from `Termicap.Wcwidth`):

```ada
with Termicap.Cell_Width;

declare
   use Termicap.Cell_Width;
   Version : Table_Version := Unicode_16;
   W       : Cell_Width_Value;
begin
   W := Cell_Width (16#1F600#, Version);  --  U+1F600 GRINNING FACE
   --  W = 2 (wide emoji, present from Unicode 13.0 table onward)

   W := Cell_Width (16#0301#, Version);   --  U+0301 COMBINING ACUTE ACCENT
   --  W = 0 (combining mark — matched in all three tables)
end;
```

### Pattern 3: Combined WCWIDTH + CELL-WIDTH

The recommended production pattern — detect the OS locale Unicode version, then use the matching table for accurate, cross-platform measurement:

```ada
with Termicap.Wcwidth;
with Termicap.Cell_Width;

declare
   Wcw_Level : Termicap.Wcwidth.Wcwidth_Level;
   Version   : Termicap.Cell_Width.Table_Version;
   W         : Termicap.Cell_Width.Cell_Width_Value;
begin
   --  Phase 1: probe the OS locale (POSIX only; returns Unknown on Windows)
   --  Precondition: setlocale(LC_CTYPE, "") must have been called earlier.
   Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

   --  Phase 2: map Wcwidth_Level → Table_Version
   case Wcw_Level is
      when Termicap.Wcwidth.Unicode_16 | Termicap.Wcwidth.Unknown =>
         Version := Termicap.Cell_Width.Unicode_16;  --  use latest on Unknown
      when Termicap.Wcwidth.Unicode_13 =>
         Version := Termicap.Cell_Width.Unicode_13;
      when Termicap.Wcwidth.Unicode_3 =>
         Version := Termicap.Cell_Width.Unicode_3;
   end case;

   --  Phase 3: measure column width consistently
   W := Termicap.Cell_Width.Cell_Width (16#4E2D#, Version);  --  CJK ideograph
   pragma Assert (W = 2);
end;
```

### Pattern 4: Measuring a string's display width

Accumulate column widths across all codepoints in a UTF-32 encoded string:

```ada
with Termicap.Cell_Width;

function Display_Width (Codepoints : UTF32_String) return Natural is
   Total : Natural := 0;
begin
   for CP of Codepoints loop
      Total := Total + Termicap.Cell_Width.Cell_Width (Natural (CP));
   end loop;
   return Total;
end Display_Width;
```

For the full working demo, see `examples/cell_width_demo/`.

### Pattern 5: Querying the active version at runtime

Inspect which table version is currently active (useful for diagnostics or logging):

```ada
with Termicap.Cell_Width;
with Ada.Text_IO;

declare
   V : Termicap.Cell_Width.Table_Version;
begin
   V := Termicap.Cell_Width.Active_Version;
   Ada.Text_IO.Put_Line ("Active Unicode table: " & V'Image);
   --  Prints: Active Unicode table: UNICODE_16  (by default)
end;
```

---

## Version Selection Reference

The `UNICODE_VERSION` environment variable controls which width table is used. It is read once during package elaboration and never changes for the process lifetime.

| `UNICODE_VERSION` value | `Active_Version` result | Table entries |
|------------------------|------------------------|---------------|
| `"3"` or `"3.0"` | `Unicode_3` | 74 |
| `"13"` or `"13.0"` | `Unicode_13` | 80 |
| `"16"` or `"16.0"` | `Unicode_16` (default) | 82 |
| absent, empty, or unrecognised | `Unicode_16` (default) | 82 |

**Setting the version before process start:**

```bash
# Use Unicode 13.0 tables for this run:
UNICODE_VERSION=13 ./my_application

# Use the default (Unicode 16.0):
./my_application
```

**At runtime (Ada):**

```ada
--  The env-var has no effect after process start.
--  To select a version programmatically, use the two-argument overload:
W := Termicap.Cell_Width.Cell_Width (CP, Termicap.Cell_Width.Unicode_13);
```

---

## Preconditions and Constraints

### No locale precondition

Unlike `Termicap.Wcwidth.Probe_Wcwidth_Level`, `Cell_Width` has no locale precondition. It reads precomputed compile-time constants; the C runtime locale is irrelevant.

### Surrogate codepoints

The `Unicode_Scalar_Value` subtype covers 0..16#10_FFFF# without excluding surrogates (U+D800..U+DFFF). Surrogates cannot appear in valid UTF-8 or UTF-32 input. If a surrogate codepoint is passed:
- The fast paths do not match it.
- Binary search looks it up; it will likely fall in a gap between stored ranges and return 1 (narrow).
- No exception is raised; no undefined behaviour occurs.

Applications that process validated UTF-8 or UTF-32 will never pass a surrogate to `Cell_Width`.

### Thread safety

`Cell_Width` and `Active_Version` are pure functions. They read only the elaboration-time constant `Active_Version_Value` (never mutated after elaboration) and the compile-time table constants. They are safe to call from any number of concurrent threads without synchronisation.

---

## Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-CWM-001 | `TABLE_UNICODE_3`, `TABLE_UNICODE_13`, `TABLE_UNICODE_16` constants | Gold (spec + body) |
| FUNC-CWM-002 | `Unicode_Scalar_Value`, `Cell_Width_Value`, `Width_Entry`, `Width_Table` | Gold (spec) |
| FUNC-CWM-003 | `Cell_Width_In_Table` binary search | Gold (spec + body) |
| FUNC-CWM-004 | `Table_Version` enumeration | Gold (spec) |
| FUNC-CWM-005 | `Active_Version` (UNICODE_VERSION env-var parsing) | Spec: Gold; elaboration body: Off |
| FUNC-CWM-006 | Default to `Table_Version'Last` when env-var absent/unrecognised | Elaboration body: Off |
| FUNC-CWM-007 | ZWJ (U+200D) in width-0 table entries | Gold (table constants) |
| FUNC-CWM-008 | VS16 (U+FE0F) in width-0 table entries | Gold (table constants) |
| FUNC-CWM-009 | Combining character ranges (category M) in width-0 entries | Gold (table constants) |
| FUNC-CWM-010 | ASCII printable fast path (U+0020..U+007E → 1) | Gold (body) |
| FUNC-CWM-011 | Control character fast paths → 0 | Gold (body) |
| FUNC-CWM-012 | Public API: `Unicode_Scalar_Value`, `Cell_Width_Value`, `Table_Version`, `Active_Version`, `Cell_Width` | Gold (spec) |
| FUNC-CWM-014 | SPARK Gold provability; GNATprove proofs discharged | Gold (spec + body) |
| FUNC-CWM-015 | O(log N) lookup; compile-time constant storage | Gold (body) |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Cell_Width` and `Termicap.Cell_Width.Tables` entries
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 32: Cell Width Measurement Lookup runtime sequence
- **API Reference: `Termicap.Wcwidth`** (`docs/guide/reference/termicap-wcwidth.md`) — `Wcwidth_Level`, `Probe_Wcwidth_Level`, `Refine_Unicode_Level`; the complementary OS locale probe
- **Tech Spec CELL-WIDTH** (`docs/tech-specs/cell-width.md`) — full design rationale, framework survey, algorithm design, SPARK strategy, testing strategy
- **Example: `cell_width_demo`** (`examples/cell_width_demo/`) — working Ada program demonstrating `Cell_Width` usage across all three table versions
