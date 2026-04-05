# Tech Spec: Dark / Light Theme Classification (DARK-LIGHT)

**Feature ID:** DARK-LIGHT
**Requirements:** `docs/requirements/dark-light.sdoc`
**Status:** Design
**Date:** 2026-04-05

---

## 1. Overview

This feature adds dark/light background theme classification to the Termicap library. Given an RGB color (typically obtained from the background color detection cascade in `Termicap.Color.Detection`), the feature computes the ITU-R BT.601 perceived luminance using integer-only arithmetic and classifies the result as `Dark` (luminance < 128) or `Light` (luminance >= 128).

The feature consists of:

- **Pure SPARK Gold functions** for luminance computation, threshold classification, and boolean convenience predicates -- all provably free of runtime errors.
- **A high-level `Detect_Theme` wrapper** that combines background color detection with classification into a single call, returning a discriminated `Theme_Result` record.

The classification algorithm is deliberately simple: a single weighted sum and a threshold comparison. The design value lies in the SPARK Gold proof guarantee and in providing a clean API surface that downstream callers can use without understanding the BT.601 formula.

---

## 2. Framework Survey

### 2.1 termbg (Rust)

**Source:** `reference-frameworks/termbg/src/lib.rs`

termbg defines a `Theme` enum with two variants (`Light`, `Dark`) and a `theme()` function that:

1. Calls `rgb(timeout)` to detect the terminal background color (16-bit per channel: 0..65535).
2. Computes BT.601 luminance using floating-point arithmetic: `y = r * 0.299 + g * 0.587 + b * 0.114`.
3. Compares against the midpoint of the 16-bit range: `if y > 32768.0 { Light } else { Dark }`.

Key observations:
- Uses **floating-point** for the luminance calculation (not suitable for SPARK Gold without additional proof complexity).
- The threshold `32768.0` corresponds to `0.5 * 65536` because termbg operates on 16-bit channel values, not 8-bit. This is equivalent to the 128 threshold on an 8-bit scale.
- The boundary case (y == 32768.0) is classified as `Dark` (uses `>` not `>=`). This differs from our requirement which classifies the boundary as `Light` (uses `>=`).
- The `theme()` function wraps `rgb()` and returns `Result<Theme, Error>`, matching our `Theme_Result` discriminated record pattern.

### 2.2 termenv (Go)

**Source:** `reference-frameworks/termenv/output.go`

termenv provides `HasDarkBackground() bool` on its `Output` type:

1. Calls `BackgroundColor()` to get the terminal background color.
2. Converts to RGB, then computes HSL (Hue, Saturation, Lightness).
3. Returns `lightness < 0.5`.

Key observations:
- Uses **HSL lightness** rather than BT.601 luminance. HSL lightness is `(max(R,G,B) + min(R,G,B)) / 2`, which does not account for perceptual luminance differences between color channels.
- Returns a bare `bool` rather than a result type -- errors in color detection are handled upstream.
- The `< 0.5` threshold (strict less-than) means the exact midpoint is classified as Light, consistent with our requirement.
- No separate `Theme` type -- the result is just a boolean.

### 2.3 Summary of Design Choices for Termicap

| Aspect | termbg | termenv | Termicap (this design) |
|--------|--------|---------|----------------------|
| Algorithm | BT.601 (float) | HSL lightness | BT.601 (integer) |
| Threshold | 32768 on 16-bit | 0.5 on [0,1] | 128 on 8-bit |
| Boundary case | Dark | Light | Light |
| Return type | `Result<Theme>` | `bool` | `Theme_Result` (discriminated record) |
| SPARK provable | N/A | N/A | Gold level |

Termicap follows BT.601 (like termbg) because it accounts for perceptual weighting of color channels, but uses integer arithmetic (unlike termbg) for SPARK Gold provability. The 128 threshold on the 8-bit scale is mathematically equivalent to termbg's 32768 on 16-bit. The boundary case is classified as `Light`, matching termenv's convention.

---

## 3. Package Design

### 3.1 New Package: `Termicap.Color.Dark_Light`

A new child package of `Termicap.Color` containing all SPARK Gold-provable classification logic.

| Property | Value |
|----------|-------|
| File (spec) | `src/termicap-color-dark_light.ads` |
| File (body) | `src/termicap-color-dark_light.adb` |
| SPARK_Mode | On (package-level) |
| Dependencies | `Termicap.Color.BG_Query` (for `RGB` type) |

This package declares:
- `Theme_Kind` enumeration
- `LUMINANCE_THRESHOLD` constant
- `Luminance` function
- `Classify_Theme` function
- `Is_Dark` / `Is_Light` expression functions

### 3.2 New Package: `Termicap.Color.Dark_Light.Detect`

A child of the SPARK Gold package, but with SPARK_Mode Off, containing the I/O-dependent detection wrapper.

| Property | Value |
|----------|-------|
| File (spec) | `src/termicap-color-dark_light-detect.ads` |
| File (body) | `src/termicap-color-dark_light-detect.adb` |
| SPARK_Mode | Off (on spec, propagated to body) |
| Dependencies | `Termicap.Color.BG_Query` (for `RGB`), `Termicap.Color.Detection` (for `Detect_Background_Color`, `Detect_Error`), `Termicap.Color.Dark_Light` (for `Theme_Kind`, `Classify_Theme`) |

This package declares:
- `Theme_Result` discriminated record
- `Detect_Theme` function

### 3.3 Package Hierarchy After This Feature

```
Termicap.Color
├── Termicap.Color.BG_Query           [SPARK Silver] -- RGB type, parsing
│   └── Termicap.Color.BG_Query.IO    [SPARK_Mode Off] -- I/O
├── Termicap.Color.Detection          [SPARK_Mode Off] -- detection cascade
└── Termicap.Color.Dark_Light         [SPARK Gold] -- luminance, classification
    └── Termicap.Color.Dark_Light.Detect  [SPARK_Mode Off] -- Detect_Theme wrapper
```

### 3.4 Rationale for Separate Detect Sub-package

FUNC-DKL-007 requires that "all Gold-level functions shall be placed in a package separate from any package containing SPARK_Mode => Off code." Placing `Detect_Theme` (SPARK Off) into a child package of the Gold-level parent cleanly enforces this separation at the compilation unit boundary. This mirrors the existing pattern where `Termicap.Color.BG_Query` (SPARK On) has a child `Termicap.Color.BG_Query.IO` (SPARK Off).

### 3.5 Modifications to Existing Packages

**`Termicap.Capabilities`** (`src/termicap-capabilities.ads`): The `Terminal_Capabilities` record currently has no theme field. A `Theme` field of type `Theme_Kind` (or an optional wrapper) should be added in a future iteration when the capabilities record is extended. This tech spec does **not** propose modifying the capabilities record at this time -- see Section 7 for the integration discussion.

---

## 4. Type Design

### 4.1 Theme_Kind Enumeration

```ada
type Theme_Kind is (Dark, Light);
```

Declared in `Termicap.Color.Dark_Light`. A two-literal enumeration providing an exhaustive, strongly-typed classification result. The SPARK prover can verify completeness of case statements over this type.

### 4.2 Luminance Threshold Constant

```ada
LUMINANCE_THRESHOLD : constant := 128;
```

A named number (not a typed constant) so it can participate in static expressions. Corresponds to 0.5 on the normalised [0.0, 1.0] scale.

### 4.3 Theme_Result Discriminated Record

```ada
type Theme_Result (Success : Boolean := False) is record
   case Success is
      when True =>
         Theme : Dark_Light.Theme_Kind;
         Color : BG_Query.RGB;
      when False =>
         Error : Detection.Detect_Error;
   end case;
end record;
```

Declared in `Termicap.Color.Dark_Light.Detect`. Reuses `RGB` from `BG_Query` and `Detect_Error` from `Detection`. The default discriminant `False` ensures uninitialized values are always in the failure state. This follows the established Termicap pattern (cf. `Parse_Result`, `Detection_Result`).

### 4.4 Relationship to Existing Types

| New Type/Constant | Depends On |
|-------------------|-----------|
| `Theme_Kind` | None (self-contained enumeration) |
| `LUMINANCE_THRESHOLD` | None (named number) |
| `Theme_Result` | `BG_Query.RGB`, `Detection.Detect_Error`, `Dark_Light.Theme_Kind` |

The `Luminance` function takes `BG_Query.RGB` as input. No new subtypes of RGB are needed because the component ranges (0..255) are already constrained in the RGB record definition.

### 4.5 Maximum Timeout Constant

```ada
MAX_TIMEOUT_MS : constant := 30_000;
```

Declared in `Termicap.Color.Dark_Light.Detect`. Mirrors the timeout clamping policy from FUNC-BGC-015.

---

## 5. Function Signatures

### 5.1 `Termicap.Color.Dark_Light` (SPARK Gold)

```ada
-------------------------------------------------------------------------------
--  Termicap.Color.Dark_Light - Theme Classification (SPARK Gold)
-------------------------------------------------------------------------------

with Termicap.Color.BG_Query;

package Termicap.Color.Dark_Light
  with SPARK_Mode
is

   use Termicap.Color.BG_Query;

   type Theme_Kind is (Dark, Light);

   LUMINANCE_THRESHOLD : constant := 128;

   --  @relation(FUNC-DKL-002): BT.601 perceived luminance, integer arithmetic
   function Luminance (Color : RGB) return Natural
     with Post => Luminance'Result in 0 .. 255;

   --  @relation(FUNC-DKL-003): Threshold-based dark/light classification
   function Classify_Theme (Color : RGB) return Theme_Kind;

   --  @relation(FUNC-DKL-004): Boolean convenience predicate (dark)
   function Is_Dark (Color : RGB) return Boolean
     with Post => Is_Dark'Result = (Classify_Theme (Color) = Dark);

   --  @relation(FUNC-DKL-004): Boolean convenience predicate (light)
   function Is_Light (Color : RGB) return Boolean
     with Post => Is_Light'Result = (Classify_Theme (Color) = Light);

end Termicap.Color.Dark_Light;
```

### 5.2 `Termicap.Color.Dark_Light.Detect` (SPARK Off)

```ada
-------------------------------------------------------------------------------
--  Termicap.Color.Dark_Light.Detect - High-Level Theme Detection
-------------------------------------------------------------------------------

pragma SPARK_Mode (Off);

with Termicap.Color.BG_Query;
with Termicap.Color.Detection;

package Termicap.Color.Dark_Light.Detect is

   use Termicap.Color.BG_Query;
   use Termicap.Color.Detection;

   MAX_TIMEOUT_MS : constant := 30_000;

   type Theme_Result (Success : Boolean := False) is record
      case Success is
         when True =>
            Theme : Dark_Light.Theme_Kind;
            Color : RGB;
         when False =>
            Error : Detect_Error;
      end case;
   end record;

   --  @relation(FUNC-DKL-005): Combined detection + classification
   function Detect_Theme
     (Timeout_Ms : Natural := 1_000) return Theme_Result;

end Termicap.Color.Dark_Light.Detect;
```

### 5.3 Expression Function Bodies (in `.adb`)

`Is_Dark` and `Is_Light` are expression functions:

```ada
function Is_Dark (Color : RGB) return Boolean is
  (Classify_Theme (Color) = Dark);

function Is_Light (Color : RGB) return Boolean is
  (Classify_Theme (Color) = Light);
```

These may alternatively be declared as expression functions directly in the spec, which would make the body unnecessary for these two functions and allow GNATprove to inline the definition at call sites. This is the recommended approach -- declare them as expression functions in the `.ads` file.

---

## 6. Algorithm Details

### 6.1 Luminance Formula

The BT.601 perceived luminance formula, scaled to integer arithmetic:

```
Y = (299 * R + 587 * G + 114 * B) / 1000
```

where R, G, B are each in the range 0..255.

**Implementation sketch:**

```ada
function Luminance (Color : RGB) return Natural is
  ((299 * Color.Red + 587 * Color.Green + 114 * Color.Blue) / 1_000);
```

This is an expression function. The entire computation is a single expression with no temporary variables needed.

### 6.2 Overflow Analysis

The intermediate sum before division:

```
Max_Sum = 299 * 255 + 587 * 255 + 114 * 255
        = 76_245 + 149_685 + 29_070
        = 255_000
```

`Natural'Last` is at least `2**31 - 1 = 2_147_483_647` on all Termicap target platforms. Since `255_000 << 2_147_483_647`, no overflow can occur on any valid RGB input.

Minimum intermediate sum:

```
Min_Sum = 299 * 0 + 587 * 0 + 114 * 0 = 0
```

Result range: `0 / 1000 = 0` to `255_000 / 1000 = 255`. The postcondition `Luminance'Result in 0 .. 255` is satisfiable for all inputs.

**GNATprove discharge path:** The prover will compute the range of `299 * Color.Red` as `0..76_245` (from `Color.Red in 0..255`), similarly for the other two terms, sum them to `0..255_000`, verify this fits in `Natural`, then divide by 1000 to get `0..255`. No loop invariants, no manual lemmas.

### 6.3 Division Truncation

Ada integer division truncates toward zero (ARM 4.5.5). For non-negative operands this is equivalent to floor division. Example boundary case:

```
RGB(128, 128, 128):
  Y = (299*128 + 587*128 + 114*128) / 1000
    = (38_272 + 75_136 + 14_592) / 1000
    = 128_000 / 1000
    = 128
```

Since 128 >= LUMINANCE_THRESHOLD (128), this is classified as `Light`. This matches the convention documented in FUNC-DKL-003.

### 6.4 Classify_Theme Algorithm

```ada
function Classify_Theme (Color : RGB) return Theme_Kind is
  (if Luminance (Color) < LUMINANCE_THRESHOLD then Dark else Light);
```

Two-branch conditional, exhaustive over the full range `0..255`. The `< 128` / `>= 128` split partitions the range without gaps.

### 6.5 Detect_Theme Algorithm

```
1. Clamp: Effective_Timeout := Natural'Min (Timeout_Ms, MAX_TIMEOUT_MS)
2. Result := Detect_Background_Color (Effective_Timeout)
3. If Result.Success:
     Theme := Classify_Theme (Result.Color)
     Return Theme_Result'(Success => True, Theme => Theme, Color => Result.Color)
4. Else:
     Return Theme_Result'(Success => False, Error => Result.Error)
```

No exception can be raised: `Detect_Background_Color` is documented as exception-free, and the discriminated record construction is statically safe.

---

## 7. Integration with Capabilities Record

### 7.1 Current State

The `Terminal_Capabilities` record in `Termicap.Capabilities` currently contains:

```ada
TTY_Stdin, TTY_Stdout, TTY_Stderr : Boolean
Color : Color_Level
Size : Terminal_Size
Unicode : Unicode_Level
Identity : Terminal_Identity
Downsampling_Available : Boolean
```

There is no theme field.

### 7.2 Integration Approach

Adding a `Theme` field to `Terminal_Capabilities` is **not recommended at this time** for these reasons:

1. **Detection cost:** Theme detection requires an active OSC 11 query with a timeout (default 1 second). Adding it to the default `Detect`/`Get` path would significantly increase the latency of capability detection for callers who do not need theme information.

2. **Optional dependency:** Not all callers need dark/light classification. The current capabilities record contains only universally useful information.

3. **Separate API surface:** The `Detect_Theme` function provides a clean, self-contained entry point. Callers who need both capabilities and theme can call `Get`/`Detect` and `Detect_Theme` independently.

### 7.3 Future Extension Path

If theme integration into `Terminal_Capabilities` is desired in the future, the recommended approach is:

- Add an optional `Theme : Theme_Kind` field with a `Theme_Detected : Boolean` guard field (non-discriminated, to preserve the record's simple structure).
- Add a `With_Theme : Boolean := False` parameter to `Detect` to opt-in to theme detection.
- Update `Assemble` to accept and pass through the theme value.

This would be tracked by a separate requirements document.

---

## 8. SPARK Proof Strategy

### 8.1 Gold-Provable Functions

| Function | SPARK_Mode | Proof Target | Proof Obligations |
|----------|-----------|--------------|-------------------|
| `Luminance` | On | Gold | Overflow check on `299 * R + 587 * G + 114 * B`; range check on result `in 0..255` |
| `Classify_Theme` | On | Gold | Path completeness (two branches cover full range); return type validity (trivial for enumeration) |
| `Is_Dark` | On | Gold | Postcondition equivalence: `Result = (Classify_Theme(Color) = Dark)` |
| `Is_Light` | On | Gold | Postcondition equivalence: `Result = (Classify_Theme(Color) = Light)` |

### 8.2 Not Provable (SPARK Off)

| Function | Reason |
|----------|--------|
| `Detect_Theme` | Calls `Detect_Background_Color`, which performs terminal I/O via controlled types and OS calls |

### 8.3 Expected GNATprove Behavior

**Luminance overflow check:**
GNATprove will see:
- `Color.Red in 0..255` (from the RGB record field constraint)
- `299 * Color.Red` produces a value in `0..76_245` (fits in Natural)
- Sum of three terms: `0..255_000` (fits in Natural)
- Division by 1000: `0..255` (fits in Natural, satisfies postcondition)

All discharged automatically. No manual lemmas, ghost code, or proof pragmas needed.

**Is_Dark/Is_Light postconditions:**
Since these are expression functions whose body is identical to the postcondition predicate, GNATprove can discharge the postcondition by simple rewriting. If declared as expression functions in the spec (recommended), the prover sees the definition directly.

**Classify_Theme completeness:**
The `if ... then ... else ...` expression covers all values; no path analysis issue arises. No postcondition beyond the return type, which is an enumeration.

### 8.4 Manual Lemmas

None required. The arithmetic is simple enough that GNATprove's built-in integer range analysis handles all obligations.

---

## 9. Traceability Matrix

| Requirement UID | Title | Package | Function/Type |
|-----------------|-------|---------|---------------|
| FUNC-DKL-001 | Theme_Kind Enumeration | `Termicap.Color.Dark_Light` | `Theme_Kind` |
| FUNC-DKL-002 | Luminance Computation | `Termicap.Color.Dark_Light` | `Luminance` |
| FUNC-DKL-003 | Classify_Theme Function | `Termicap.Color.Dark_Light` | `Classify_Theme` |
| FUNC-DKL-004 | Is_Dark / Is_Light | `Termicap.Color.Dark_Light` | `Is_Dark`, `Is_Light` |
| FUNC-DKL-005 | Detect_Theme | `Termicap.Color.Dark_Light.Detect` | `Detect_Theme` |
| FUNC-DKL-006 | Theme_Result Record | `Termicap.Color.Dark_Light.Detect` | `Theme_Result` |
| FUNC-DKL-007 | SPARK Gold Boundaries | `Termicap.Color.Dark_Light` (Gold), `Termicap.Color.Dark_Light.Detect` (Off) | Package-level SPARK_Mode annotations |

---

## 10. Open Questions / ADR Candidates

### 10.1 No ADR Needed

This feature is a straightforward pure-arithmetic computation with a well-established algorithm (BT.601) and a standard threshold (128). The design decisions are:

- **BT.601 vs HSL lightness:** Mandated by the requirements (FUNC-DKL-002). BT.601 is perceptually more accurate than HSL lightness and is the industry standard for luminance-based classification.
- **Integer vs floating-point:** Mandated by the requirements for SPARK Gold provability. No alternative was considered.
- **Threshold 128:** Mandated by the requirements (FUNC-DKL-003). Consistent with reference implementations.
- **Boundary case classified as Light:** Matches termenv convention and CSS convention. Documented in requirements.

None of these warrant an ADR because they are all either mandated by approved requirements or are the obvious canonical choice with no realistic alternative.

### 10.2 Minor Open Question: Expression Functions in Spec vs Body

`Is_Dark` and `Is_Light` can be declared as expression functions directly in the `.ads` spec, or as regular functions in the spec with expression function bodies in the `.adb`. The spec-level expression function approach is recommended because:

1. GNATprove can see the function definition at every call site, making postcondition discharge trivial.
2. The implementation is a single expression with no information-hiding value.
3. It eliminates the need for a body declaration for these two functions.

This is a minor implementation choice, not an ADR candidate.

### 10.3 Minor Open Question: Capabilities Integration Timing

As discussed in Section 7, theme is not being added to `Terminal_Capabilities` in this iteration. If a future feature requires theme in the capabilities record, a separate requirements document should be written. This is noted here for tracking but does not require a decision now.
