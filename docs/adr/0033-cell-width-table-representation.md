# Flat sorted range array for cell width table representation

* Status: Proposed
* Deciders: Heziode
* Date: 2026-05-06

## Context and Problem Statement

The Cell Width Measurement Tables feature (FUNC-CWM-001 through FUNC-CWM-016) needs a data structure to store Unicode character width information for binary search lookup. The table must map codepoint ranges to cell widths (0, 1, or 2) and support O(log N) lookup. Several representation strategies are possible. Which one best satisfies the SPARK Gold provability requirement (FUNC-CWM-014) while keeping memory usage and complexity low?

## Decision Drivers

* **SPARK Gold provability**: The table representation must be provable at Gold level by GNATprove without manual lemmas or pragma Assume.
* **Memory efficiency**: The library is lightweight; tables should not dominate the binary size.
* **Lookup performance**: O(log N) or better per codepoint lookup.
* **Simplicity**: The representation should be straightforward to generate from UCD data and to verify by inspection.
* **No heap allocation**: Tables must be compile-time constant arrays (FUNC-CWM-015).
* **Multi-version support**: Multiple Unicode versions must coexist without code duplication in the search algorithm.

## Considered Options

* **Option A**: Flat sorted array of `(First, Last, Width)` range records with binary search
* **Option B**: Two-level lookup table (block index + per-block array)
* **Option C**: Flat per-codepoint array (1 byte per codepoint, direct indexing)

## Decision Outcome

Chosen option: **Option A** (flat sorted range array), because it is the simplest representation that satisfies all constraints, is trivially SPARK-provable, and matches the proven pattern used by reference implementations (rich, wcwidth).

### Positive Consequences

* Binary search over a sorted array is a textbook algorithm with well-understood loop invariants that GNATprove can discharge at Gold level.
* Only width-0 and width-2 ranges need explicit entries; width-1 (the vast majority of codepoints) is the implicit default. This keeps table size small (~1,500-2,000 entries per version).
* The `Width_Table` type is an unconstrained array, so different Unicode versions can have different numbers of entries without code changes.
* The same `Cell_Width_In_Table` function works for all table versions -- no version-specific dispatch in the search path.
* Table generation is trivial: merge width-0 and width-2 ranges from the UCD, sort by start codepoint, output as Ada constant aggregate.

### Negative Consequences

* O(log N) lookup is slower than O(1) direct indexing (Option C). Mitigation: N < 2,000 means at most 11 comparisons; the ASCII fast path eliminates the dominant case entirely.
* Total data size (~48-60 KB for three versions) is larger than a two-level table (Option B). Mitigation: the difference is marginal for a terminal library, and the simplicity benefit outweighs the few KB savings.

## Pros and Cons of the Options

### Option A: Flat sorted range array -- chosen

Each table is a constant array of `(First, Last, Width)` records, sorted by `First`, with no overlapping ranges.

```ada
type Width_Entry is record
   First : Unicode_Scalar_Value;
   Last  : Unicode_Scalar_Value;
   Width : Cell_Width_Value;
end record;

type Width_Table is array (Table_Index range <>) of Width_Entry;
```

* Good, because the binary search algorithm is a standard textbook pattern with well-known loop invariants.
* Good, because GNATprove can verify the binary search at Gold level using simple range and index assertions.
* Good, because table generation is straightforward: merge, sort, output.
* Good, because the same search function works for all table versions (version-agnostic).
* Good, because the representation matches reference implementations (rich, wcwidth), enabling cross-validation.
* Bad, because O(log N) per lookup is slower than O(1) direct indexing.
* Bad, because each entry is 12 bytes (three 32-bit integers), whereas a per-codepoint array uses 1 byte per entry.

### Option B: Two-level lookup table

A block index (256 or 4096 entries) maps to per-block arrays. Provides O(1) lookup but with larger code complexity.

```ada
type Block_Index is array (0 .. 16#10FFFF# / BLOCK_SIZE) of Natural;
type Block_Entry is array (0 .. BLOCK_SIZE - 1) of Cell_Width_Value;
```

* Good, because O(1) lookup time.
* Good, because blocks with identical content can share storage (compression).
* Bad, because SPARK proof is more complex: requires proving index arithmetic across two array levels.
* Bad, because the block index itself is a large array (4,352 entries for 256-byte blocks).
* Bad, because multi-version support requires a separate block index per version.
* Bad, because the two-level indirection is harder to validate by inspection.

### Option C: Flat per-codepoint array

A single array of 1,114,112 entries (one byte per codepoint). O(1) lookup.

```ada
type Full_Table is array (Unicode_Scalar_Value) of Cell_Width_Value;
```

* Good, because O(1) lookup -- direct array indexing, no search.
* Good, because trivially SPARK-provable (single array access).
* Bad, because each table consumes ~1.1 MB. Three versions = ~3.3 MB. This is unacceptable for a lightweight terminal library.
* Bad, because the array must be populated for all 1,114,112 codepoints, even though >99% are width 1.
* Bad, because it does not match any reference implementation pattern.

## Links

* [Tech Spec: CELL-WIDTH](../tech-specs/cell-width.md) -- Cell Width Measurement Tables technical specification
* [FUNC-CWM-002](../requirements/cell-width.sdoc) -- Codepoint range entry format requirement
* [FUNC-CWM-014](../requirements/cell-width.sdoc) -- SPARK Gold provability requirement
* [FUNC-CWM-015](../requirements/cell-width.sdoc) -- O(log N) lookup and constant storage requirement
