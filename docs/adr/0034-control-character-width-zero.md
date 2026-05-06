# Control character width convention: 0 instead of -1

* Status: Proposed
* Deciders: Heziode
* Date: 2026-05-06

## Context and Problem Statement

The POSIX `wcwidth()` function returns -1 for non-printable characters (control codes, unassigned codepoints). The Cell Width Measurement Tables feature (FUNC-CWM-011) must choose a return value convention for control characters (U+0000..U+001F, U+007F, U+0080..U+009F). Should `Cell_Width` return -1 (following POSIX) or 0 (treating controls as zero-width)?

## Decision Drivers

* **Type safety**: The `Cell_Width_Value` return subtype should be as narrow as possible to enable SPARK Gold proof without sentinel values.
* **Caller ergonomics**: Callers computing string width by summing `Cell_Width` results should not need special -1 handling.
* **Consistency with reference implementations**: Most modern width libraries (Python wcwidth, Go uniseg) return 0 for control characters.
* **SPARK provability**: A wider return type (e.g., -1 .. 2) adds complexity to all postconditions and caller contracts.
* **Semantic accuracy**: Control characters do not advance the cursor; returning 0 is semantically correct for layout purposes.

## Considered Options

* **Option A**: Return 0 for control characters (`Cell_Width_Value` is `0 .. 2`)
* **Option B**: Return -1 for control characters (`Cell_Width_Value` is `-1 .. 2`)

## Decision Outcome

Chosen option: **Option A** (return 0), because it keeps the return type narrow (`0 .. 2`), simplifies SPARK contracts, matches the dominant convention in modern width libraries, and is semantically correct for text layout.

### Positive Consequences

* `Cell_Width_Value` is `0 .. 2`: a 3-value subtype that is trivially bounded for SPARK proof.
* Callers can compute string display width as a simple sum: `Total := Total + Cell_Width (CP)`. No special-case handling for -1 needed.
* Consistent with Python `wcwidth`, Go `uniseg`, and the way terminal layout engines handle control characters (zero-width; higher layers expand tabs, strip escapes, etc.).
* No sentinel value pollutes the return type.

### Negative Consequences

* Callers cannot distinguish "control character" (width 0) from "combining mark" (also width 0) using the return value alone. Mitigation: callers who need this distinction can inspect the codepoint range directly; providing an `Is_Control_Character` predicate is outside the scope of this feature.
* Deviates from POSIX `wcwidth()` convention, which may surprise users familiar with that API. Mitigation: the deviation is documented in the package specification (FUNC-CWM-011) and in this ADR.

## Pros and Cons of the Options

### Option A: Return 0 for control characters -- chosen

`Cell_Width_Value` is `Integer range 0 .. 2`.

* Good, because the return type is minimal (3 values: 0, 1, 2).
* Good, because SPARK postconditions need only assert `Result in 0 .. 2`, which is trivially discharged.
* Good, because string width computation is a simple sum with no edge cases.
* Good, because control characters genuinely occupy 0 terminal columns in the cursor-advancement sense.
* Good, because matches Python wcwidth, Go uniseg, and Rich's convention.
* Bad, because callers cannot distinguish controls from combining marks via return value.
* Bad, because POSIX-aware users may expect -1 for non-printable characters.

### Option B: Return -1 for control characters

`Cell_Width_Value` is `Integer range -1 .. 2`.

* Good, because matches the POSIX `wcwidth()` convention exactly.
* Good, because callers can distinguish "non-printable" (-1) from "combining mark" (0).
* Bad, because the wider return type (-1 .. 2) complicates every SPARK contract that uses `Cell_Width_Value`.
* Bad, because callers computing string width must add `if Width >= 0 then Total := Total + Width` checks.
* Bad, because -1 is not a width -- it is an error sentinel. Mixing error signalling into the return value is poor Ada style.
* Bad, because most modern reference implementations have already moved away from the -1 convention.

## Links

* [Tech Spec: CELL-WIDTH](../tech-specs/cell-width.md) -- Cell Width Measurement Tables technical specification
* [FUNC-CWM-011](../requirements/cell-width.sdoc) -- Control character width convention requirement
* [FUNC-CWM-014](../requirements/cell-width.sdoc) -- SPARK Gold provability requirement
* [Tech Spec: WCWIDTH](../tech-specs/wcwidth.md) -- wcwidth probing (uses POSIX -1 convention at the FFI layer)
