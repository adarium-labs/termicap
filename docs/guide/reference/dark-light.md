# API Reference: `Termicap.Color.Dark_Light` and `Termicap.Color.Dark_Light.Detect`

Package pair providing SPARK Gold-provable terminal background theme classification and a high-level detection wrapper.

**Files:**
- `src/termicap-color-dark_light.ads`, `src/termicap-color-dark_light.adb`
- `src/termicap-color-dark_light-detect.ads`, `src/termicap-color-dark_light-detect.adb`

**SPARK_Mode:** `Termicap.Color.Dark_Light` — On (spec and body, Gold level); `Termicap.Color.Dark_Light.Detect` — Off (spec and body)
**License:** Apache-2.0

---

## Overview

The DARK-LIGHT feature classifies a terminal background color as dark or light using the ITU-R BT.601 perceived luminance formula with integer-only arithmetic.

`Termicap.Color.Dark_Light` contains all classification logic: luminance computation, threshold comparison, and Boolean convenience predicates. These functions are pure — no I/O, no global state, no exceptions — and are proved at SPARK Gold level. GNATprove discharges all proof obligations (overflow safety, range postcondition, path exhaustiveness) automatically without manual lemmas.

`Termicap.Color.Dark_Light.Detect` contains the high-level `Detect_Theme` function, which combines background color detection (OSC 11 cascade via `Termicap.Color.Detection`) with classification into a single call. It carries `SPARK_Mode => Off` because it calls `Detect_Background_Color`, which manages Ada `Limited_Controlled` types and performs terminal I/O.

The typical call patterns are:

- **Already have an RGB value:** call `Classify_Theme`, `Is_Dark`, or `Is_Light` directly — no I/O, SPARK Gold provable.
- **Need to detect the theme from scratch:** call `Detect_Theme` — combines OSC 11 probing with classification, returns a `Theme_Result`.

---

## Package `Termicap.Color.Dark_Light`

### Types

#### `Theme_Kind`

```ada
type Theme_Kind is (Dark, Light);
```

Two-valued enumeration classifying a terminal background.

| Value | Meaning |
|-------|---------|
| `Dark` | Perceived luminance < 128. Background is dark-themed (e.g., black or deep-coloured). |
| `Light` | Perceived luminance >= 128. Background is light-themed (e.g., white or pale). |

Using an enumeration rather than `Boolean` makes `case` statements self-documenting (`when Dark =>` vs `when True =>`) and enables GNATprove to verify exhaustiveness of case analyses over this type.

**Requirement:** FUNC-DKL-001

---

### Constants

#### `LUMINANCE_THRESHOLD`

```ada
LUMINANCE_THRESHOLD : constant := 128;
```

The midpoint threshold on the 0..255 luminance scale. A named number (not a typed constant) so it participates in static expressions.

Corresponds to 0.5 on the normalised [0.0, 1.0] scale. Colors with luminance strictly below 128 are classified as `Dark`; colors with luminance 128 or above are classified as `Light`. The boundary value 128 is classified as `Light`, matching the CSS and termenv convention.

**Requirement:** FUNC-DKL-003

---

### Functions

#### `Luminance`

```ada
function Luminance (Color : RGB) return Natural is
  ((299 * Color.Red + 587 * Color.Green + 114 * Color.Blue) / 1_000)
with Post => Luminance'Result in 0 .. 255;
```

Compute the ITU-R BT.601 perceived luminance of an RGB color using integer arithmetic.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | RGB color value whose luminance is to be computed. Each component is in 0..255. |

**Returns:** Perceived luminance in the range 0..255.

**Formula:** `Y = (299 * R + 587 * G + 114 * B) / 1000` where division is integer division (truncation toward zero). The green channel is weighted most heavily because the human eye is most sensitive to green light.

**SPARK contract:** `Post => Luminance'Result in 0 .. 255` — machine-verified by GNATprove. The maximum intermediate value is `299 * 255 + 587 * 255 + 114 * 255 = 255_000`, well within `Natural` (`>= 2**31 - 1`); no overflow is possible on any valid RGB input.

**Boundary examples:**

| Input | Y |
|-------|---|
| `(0, 0, 0)` — pure black | 0 |
| `(30, 30, 30)` — near-black | 30 |
| `(128, 128, 128)` — mid grey | 128 |
| `(240, 240, 240)` — near-white | 240 |
| `(255, 255, 255)` — pure white | 255 |

**Requirement:** FUNC-DKL-002

---

#### `Classify_Theme`

```ada
function Classify_Theme (Color : RGB) return Theme_Kind is
  (if Luminance (Color) < LUMINANCE_THRESHOLD then Dark else Light);
```

Classify an RGB color as `Dark` or `Light` by applying the luminance threshold.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | RGB color value to classify. |

**Returns:** `Dark` if `Luminance(Color) < 128`; `Light` if `Luminance(Color) >= 128`.

The two-branch conditional is exhaustive over the full range 0..255 of possible luminance values. GNATprove verifies completeness by path analysis; no postcondition beyond the return type is required.

**Boundary case:** `RGB(128, 128, 128)` → `Y = 128 >= 128` → `Light`. This matches the CSS and termenv convention (the exact midpoint is classified as light).

**Requirement:** FUNC-DKL-003

---

#### `Is_Dark`

```ada
function Is_Dark (Color : RGB) return Boolean is
  (Classify_Theme (Color) = Dark)
with Post => Is_Dark'Result = (Classify_Theme (Color) = Dark);
```

Return `True` when the color's perceived luminance is strictly below 128.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | RGB color value to test. |

**Returns:** `True` iff `Classify_Theme(Color) = Dark`.

**SPARK contract:** The postcondition expresses the logical equivalence with `Classify_Theme`. Because this is an expression function whose body is identical to the postcondition predicate, GNATprove discharges the postcondition by rewriting.

**Note:** `Is_Dark(C) = not Is_Light(C)` for all inputs; GNATprove can prove this automatically from the two postconditions.

**Requirement:** FUNC-DKL-004

---

#### `Is_Light`

```ada
function Is_Light (Color : RGB) return Boolean is
  (Classify_Theme (Color) = Light)
with Post => Is_Light'Result = (Classify_Theme (Color) = Light);
```

Return `True` when the color's perceived luminance is 128 or above.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | RGB color value to test. |

**Returns:** `True` iff `Classify_Theme(Color) = Light`.

**SPARK contract:** Same pattern as `Is_Dark`. Postcondition discharged by rewriting.

**Requirement:** FUNC-DKL-004

---

## Package `Termicap.Color.Dark_Light.Detect`

### Types

#### `Theme_Result`

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

Discriminated record representing the outcome of a combined background color detection and theme classification operation.

| Discriminant | Fields available | Description |
|-------------|-----------------|-------------|
| `Success = True` | `Theme`, `Color` | `Theme` holds the classified `Dark` or `Light` value. `Color` holds the raw RGB value detected from the terminal. |
| `Success = False` | `Error` | `Error` holds the `Detect_Error` indicating why detection failed. |

The default discriminant value `False` ensures that an uninitialized `Theme_Result` is always in the failure state. Accessing `Theme` or `Color` on a `Success = False` record raises `Constraint_Error` at runtime.

The `Detect_Error` type is the same enumeration used by `Detect_Background_Color`:

| Value | Meaning |
|-------|---------|
| `Not_A_Terminal` | The process is not attached to an interactive terminal. |
| `Not_Foreground` | The process is in a background process group. |
| `Query_Timeout` | The OSC 11 query timed out before a response was received. |
| `Parse_Failed` | A response was received but could not be parsed as a valid RGB value. |
| `No_Fallback` | The OSC query failed and the `COLORFGBG` environment variable is absent or unparseable. |

**Requirements:** FUNC-DKL-006

---

### Constants

#### `MAX_TIMEOUT_MS`

```ada
MAX_TIMEOUT_MS : constant := 30_000;
```

Upper clamp on the `Timeout_Ms` parameter before it is passed to `Detect_Background_Color`. Consistent with the timeout policy in FUNC-BGC-015.

---

### Functions

#### `Detect_Theme`

```ada
function Detect_Theme
  (Timeout_Ms : Natural := 1_000) return Theme_Result;
```

Detect the terminal background theme (dark or light) in a single call. Combines OSC 11 background color detection with BT.601 luminance classification.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Timeout_Ms` | in | Millisecond timeout for the underlying OSC 11 query. Default: 1 000 ms. Clamped to `MAX_TIMEOUT_MS` (30 000 ms) before use. |

**Returns:** `Theme_Result` with `Success = True` and `Theme`/`Color` fields populated on success, or `Success = False` and `Error` field populated on failure.

**Algorithm:**

1. Clamp: `Effective_Timeout := Natural'Min (Timeout_Ms, MAX_TIMEOUT_MS)`.
2. Call `Detect_Background_Color (Effective_Timeout)`.
3. On success: call `Classify_Theme (Color)` and return `Theme_Result'(Success => True, Theme => <classified>, Color => Color)`.
4. On failure: return `Theme_Result'(Success => False, Error => Error)`.

**Exception safety:** Never raises an exception on any path. All failure modes are represented in the `Theme_Result` discriminant.

**SPARK_Mode:** Off. Calls `Detect_Background_Color`, which manages `Probe_Session` (`Limited_Controlled`) and performs terminal I/O. All classification logic invoked internally is individually proved at Gold level in `Termicap.Color.Dark_Light`.

**Requirements:** FUNC-DKL-005

---

## Usage Examples

### Pure classification from a known RGB value

Use the SPARK Gold functions when the RGB color is already available. No terminal I/O is performed.

```ada
with Termicap.Color.BG_Query;   use Termicap.Color.BG_Query;
with Termicap.Color.Dark_Light; use Termicap.Color.Dark_Light;

--  Classify a hardcoded color (e.g., from a test or configuration).
declare
   Dark_Color : constant RGB := (Red => 30, Green => 30, Blue => 30);
   Y          : Natural;
   Theme      : Theme_Kind;
begin
   Y     := Luminance (Dark_Color);      --  30 (< 128 → Dark)
   Theme := Classify_Theme (Dark_Color); --  Dark

   pragma Assert (Y in 0 .. 255);        --  proved by SPARK Gold contract
   pragma Assert (Is_Dark (Dark_Color));
   pragma Assert (not Is_Light (Dark_Color));
end;
```

### Live terminal theme detection

Use `Detect_Theme` when the terminal background color is not yet known.

```ada
with Termicap.Color.Dark_Light.Detect; use Termicap.Color.Dark_Light.Detect;
with Termicap.Color.Dark_Light;        use Termicap.Color.Dark_Light;

declare
   Result : constant Theme_Result := Detect_Theme;
   --  Default timeout: 1 000 ms.
begin
   if Result.Success then
      case Result.Theme is
         when Dark =>
            --  Dark background: use bright foreground colours.
            null;
         when Light =>
            --  Light background: use muted/dark foreground colours.
            null;
      end case;
   else
      --  Detection failed: fall back to a safe assumption.
      --  Result.Error identifies the reason (Not_A_Terminal, Query_Timeout, etc.)
      null;
   end if;
end;
```

### Custom timeout

```ada
Result : constant Theme_Result := Detect_Theme (Timeout_Ms => 500);
```

### Combining with previously detected background color

If `Detect_Background_Color` was already called (e.g., for another purpose), classify its result directly without a second detection round trip.

```ada
with Termicap.Color.Detection;  use Termicap.Color.Detection;
with Termicap.Color.Dark_Light; use Termicap.Color.Dark_Light;

declare
   BG     : constant Detection_Result := Detect_Background_Color;
   Theme  : Theme_Kind;
begin
   if BG.Success then
      Theme := Classify_Theme (BG.Color);
      --  Use Theme as needed.
   end if;
end;
```

See also `examples/dark_light_demo/src/dark_light_demo.adb` for a complete demonstration covering all three usage scenarios.

---

## SPARK Notes

`Termicap.Color.Dark_Light` targets SPARK Gold:

| Function | Proof obligations | Discharged by |
|----------|-------------------|---------------|
| `Luminance` | Overflow on `299*R + 587*G + 114*B`; range `Result in 0..255` | Range analysis from field constraints (0..255) and coefficient values |
| `Classify_Theme` | Path exhaustiveness of the two-branch conditional | GNATprove path analysis |
| `Is_Dark` | Postcondition equivalence `Result = (Classify_Theme(Color) = Dark)` | Expression function rewriting (body = postcondition) |
| `Is_Light` | Postcondition equivalence `Result = (Classify_Theme(Color) = Light)` | Expression function rewriting (body = postcondition) |

No manual lemmas, ghost code, or proof pragmas are required.

`Termicap.Color.Dark_Light.Detect` carries `pragma SPARK_Mode (Off)` on the spec, so SPARK-annotated callers cannot inadvertently call `Detect_Theme` without a mode barrier.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-DKL-001 | `Theme_Kind` enumeration | Gold |
| FUNC-DKL-002 | `Luminance` function, `Post => Result in 0..255` | Gold |
| FUNC-DKL-003 | `Classify_Theme` function, `LUMINANCE_THRESHOLD` constant | Gold |
| FUNC-DKL-004 | `Is_Dark` and `Is_Light` expression functions with postconditions | Gold |
| FUNC-DKL-005 | `Detect_Theme` function | Off |
| FUNC-DKL-006 | `Theme_Result` discriminated record | Off |
| FUNC-DKL-007 | SPARK Gold boundary: `Termicap.Color.Dark_Light` (On), `Termicap.Color.Dark_Light.Detect` (Off) | — |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Color.Dark_Light` and `Termicap.Color.Dark_Light.Detect` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 20: pure classification path and combined detection path
- **Tech Spec DARK-LIGHT** (`docs/tech-specs/dark-light.md`) — full design rationale, framework survey, SPARK proof strategy, and algorithm details
- **[Termicap.Color](termicap-color.md)** — color level detection; provides the `Color_Level` type
- **[Termicap.OSC](osc.md)** — OSC probe session infrastructure used internally by `Detect_Theme`
