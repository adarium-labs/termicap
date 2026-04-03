# API Reference: `Termicap.Downsampling`

Package providing pure, SPARK Gold-provable color downsampling conversions from higher-fidelity levels (TrueColor, 256-color) to the nearest equivalent at a lower fidelity level.

**Files:** `src/termicap-downsampling.ads`, `src/termicap-downsampling.adb`
**SPARK_Mode:** On (spec and body) — Gold level
**License:** Apache-2.0

---

## Overview

`Termicap.Downsampling` is the complement to `Termicap.Color`: detection tells a caller what color level the terminal supports; downsampling converts a specific color value to that level before emitting SGR escape sequences.

The package exposes primitive color value types, three directed conversion functions, two overloaded general-dispatch functions, and a classification helper. All operations are pure integer arithmetic over bounded subtypes with no FFI, no dynamic allocation, no global state, and no unbounded loops. The `Global => null` contract and all postconditions are machine-verified by GNATprove at Gold level.

The typical call sequence is:

1. Detect the terminal's `Color_Level` using `Termicap.Color.Detect_Color_Level`.
2. Call `Downsample (Color, Target => Level)` to convert the source color.
3. Dispatch on the `Downsampled_Color` discriminant to emit the appropriate SGR sequence.

---

## Types

### `Color_Component`

```ada
subtype Color_Component is Natural range 0 .. 255;
```

One 8-bit sRGB channel value. The explicit `0 .. 255` constraint gives GNATprove the range information needed to discharge overflow obligations in cube-index and distance calculations without manual lemmas.

**Requirement:** FUNC-DSP-001

---

### `RGB`

```ada
type RGB is record
   Red   : Color_Component;
   Green : Color_Component;
   Blue  : Color_Component;
end record;
```

A 24-bit sRGB color value. Plain record with three independently readable and writable fields. No invariant constrains the relationship between components. Usable as a function parameter and return type without dynamic allocation.

**Requirement:** FUNC-DSP-001

---

### `Color_Index_256`

```ada
subtype Color_Index_256 is Natural range 0 .. 255;
```

An index into the xterm 256-color palette. The palette sub-range layout is:

| Range | Contents |
|-------|----------|
| 0–15 | Standard ANSI 16 colors |
| 16–231 | 6×6×6 RGB color cube (216 entries) |
| 232–255 | 24-step grayscale ramp |

**Requirement:** FUNC-DSP-002

---

### `Color_Index_16`

```ada
subtype Color_Index_16 is Color_Index_256 range 0 .. 15;
```

An index into the 16 standard ANSI colors. Declared as a subtype of `Color_Index_256`, not directly of `Natural`, for two reasons:

1. **Subtype compatibility.** Any `Color_Index_16` value is directly assignable to a `Color_Index_256` variable without conversion. Callers with a `Color_Index_16` value can pass it to the `Color_Index_256` overload of `Downsample` without an explicit type conversion.
2. **Type family reasoning.** SPARK can reason about both subtypes within the same type family; a `Color_Index_16` used where `Color_Index_256` is expected generates no runtime check and no extra proof obligation.

The 16 standard ANSI colors are semantically the first 16 entries of the 256-color palette — the subtype relationship captures this IS-A relationship in the type system.

**Requirement:** FUNC-DSP-003

---

### `Downsampled_Color`

```ada
type Downsampled_Color
  (Level : Termicap.Color.Color_Level := Termicap.Color.Color_Level'First)
is record
   case Level is
      when Termicap.Color.None =>
         null;

      when Termicap.Color.Basic_16 =>
         Index_16 : Color_Index_16;

      when Termicap.Color.Extended_256 =>
         Index_256 : Color_Index_256;

      when Termicap.Color.True_Color =>
         RGB_Value : RGB;
   end case;
end record;
```

A discriminated record holding a downsampled color at any level. The discriminant `Level` identifies which variant is active:

| Discriminant | Active field | Meaning |
|-------------|-------------|---------|
| `None` | *(none)* | No color data; emit no color escape sequence |
| `Basic_16` | `Index_16 : Color_Index_16` | ANSI 16-color index (SGR 30–37, 40–47, 90–97) |
| `Extended_256` | `Index_256 : Color_Index_256` | 256-color palette index (SGR 38;5;n / 48;5;n) |
| `True_Color` | `RGB_Value : RGB` | 24-bit RGB (SGR 38;2;r;g;b / 48;2;r;g;b) |

The default discriminant `Level => None` (i.e., `Color_Level'First`) allows unconstrained stack allocation. Callers dispatch on the discriminant in a case statement to extract the appropriate value before constructing an escape sequence.

**Requirements:** FUNC-DSP-007, FUNC-DSP-008

#### Discriminant dispatch pattern

```ada
with Termicap.Downsampling; use Termicap.Downsampling;
with Termicap.Color;        use Termicap.Color;

--  Result is a Downsampled_Color obtained from Downsample (...)
case Result.Level is
   when None =>
      null;  --  emit no SGR code

   when Basic_16 =>
      --  Result.Index_16 : Color_Index_16 (0 .. 15)
      Emit_SGR_16 (Result.Index_16);

   when Extended_256 =>
      --  Result.Index_256 : Color_Index_256 (0 .. 255)
      Emit_SGR_256 (Result.Index_256);

   when True_Color =>
      --  Result.RGB_Value : RGB
      Emit_SGR_RGB (Result.RGB_Value.Red,
                    Result.RGB_Value.Green,
                    Result.RGB_Value.Blue);
end case;
```

The case statement is always exhaustive — Ada requires all `Color_Level` values to be covered.

---

## Functions

### `Downsample_True_To_256`

```ada
function Downsample_True_To_256 (Color : RGB) return Color_Index_256
with Global => null, Post => Downsample_True_To_256'Result in 16 .. 255;
```

Map an RGB value to the nearest xterm 256-color palette entry.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | The 24-bit sRGB input color. |

**Returns:** A 256-color palette index in the range `16 .. 255`. The ANSI 16-color sub-range (`0–15`) is never returned.

**Algorithm:** Uses a grayscale-first check followed by 6×6×6 cube quantization:

1. Each channel is compared against the 24-step grayscale ramp thresholds. If all three channels are sufficiently close to the same grayscale ramp entry, the grayscale ramp index (`232 .. 255`) is returned.
2. Otherwise, each channel is quantized independently to the nearest of the six cube levels (`{0, 95, 135, 175, 215, 255}`), and the resulting 6×6×6 cube index (`16 .. 231`) is returned.

All arithmetic is integer-only; no floating-point and no external colour-distance library.

**SPARK contract:** `Global => null`; postcondition statically proves the result range `16 .. 255`.

**Requirement:** FUNC-DSP-004

---

### `Downsample_True_To_16`

```ada
function Downsample_True_To_16 (Color : RGB) return Color_Index_16
with Global => null;
```

Map an RGB value to the nearest of the 16 standard ANSI colors.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | The 24-bit sRGB input color. |

**Returns:** An ANSI color index in `0 .. 15`.

**Algorithm:** Brute-force nearest-neighbor search over the canonical 16-color ANSI palette using the integer redmean weighted Euclidean distance formula. Ties are broken in favor of the lower index.

The redmean formula weights the distance by the average red component, giving better perceptual accuracy than plain Euclidean distance in the RGB cube without requiring floating-point or a perceptual color space library.

**SPARK contract:** `Global => null`.

**Requirement:** FUNC-DSP-005

---

### `Downsample_256_To_16`

```ada
function Downsample_256_To_16
  (Index : Color_Index_256) return Color_Index_16
with Global => null;
```

Map a 256-color palette index to the nearest ANSI 16-color index.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Index` | in | A 256-color palette index (`0 .. 255`). `Color_Index_16` values (`0 .. 15`) may be passed directly. |

**Returns:** An ANSI color index in `0 .. 15`.

**Algorithm:** Dispatches based on the sub-range of the input index:

| Input range | Conversion |
|-------------|-----------|
| `0 .. 15` | Pass-through: the index is already an ANSI 16-color index. |
| `16 .. 231` | Reconstruct RGB via the 6×6×6 cube formula, then call `Downsample_True_To_16`. |
| `232 .. 255` | Reconstruct RGB via the grayscale ramp formula, then call `Downsample_True_To_16`. |

Because `Color_Index_16` is a subtype of `Color_Index_256`, passing a `Color_Index_16` value to this function returns it unchanged (the pass-through branch). No separate `Color_Index_16`-to-`Color_Index_16` overload exists or is needed.

**SPARK contract:** `Global => null`.

**Requirement:** FUNC-DSP-006

---

### `Downsample` (RGB overload)

```ada
function Downsample
  (Color : RGB; Target : Termicap.Color.Color_Level)
   return Downsampled_Color
with
  Global => null,
  Post   =>
    (if Target >= Termicap.Color.True_Color
     then
       Downsample'Result.Level = Termicap.Color.True_Color
       and then Downsample'Result.RGB_Value.Red   = Color.Red
       and then Downsample'Result.RGB_Value.Green = Color.Green
       and then Downsample'Result.RGB_Value.Blue  = Color.Blue)
    and then (if Target = Termicap.Color.None
              then Downsample'Result.Level = Termicap.Color.None)
    and then Color_Level_Of (Downsample'Result)
             <= Termicap.Color.Color_Level'Min
                  (Termicap.Color.True_Color, Target);
```

Downsample a TrueColor RGB value to the given target level.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Color` | in | The 24-bit sRGB source color. |
| `Target` | in | The desired output `Color_Level`, typically the result of `Detect_Color_Level`. |

**Returns:** A `Downsampled_Color` discriminated by the effective output level.

**Dispatch table:**

| Target | Result |
|--------|--------|
| `True_Color` | Identity — `RGB_Value = Color`. |
| `Extended_256` | `Downsample_True_To_256 (Color)` — index in `16 .. 255`. |
| `Basic_16` | `Downsample_True_To_16 (Color)` — index in `0 .. 15`. |
| `None` | `(Level => None)` — no color data. |

**SPARK contracts:**

- `Global => null`.
- **Idempotency postcondition (FUNC-DSP-009):** When `Target >= True_Color`, the result carries the original `Color` unchanged in `RGB_Value`.
- **Strip-to-None (FUNC-DSP-007):** When `Target = None`, the result level is `None`.
- **Monotonicity postcondition (FUNC-DSP-010):** `Color_Level_Of (result) <= Color_Level'Min (True_Color, Target)` — the output level never exceeds the requested target.

**Requirements:** FUNC-DSP-008, FUNC-DSP-009, FUNC-DSP-010

---

### `Downsample` (256-color overload)

```ada
function Downsample
  (Index : Color_Index_256; Target : Termicap.Color.Color_Level)
   return Downsampled_Color
with
  Global => null,
  Post   =>
    (if Target >= Termicap.Color.Extended_256
     then
       Downsample'Result.Level = Termicap.Color.Extended_256
       and then Downsample'Result.Index_256 = Index)
    and then (if Target = Termicap.Color.None
              then Downsample'Result.Level = Termicap.Color.None)
    and then Color_Level_Of (Downsample'Result)
             <= Termicap.Color.Color_Level'Min
                  (Termicap.Color.Extended_256, Target);
```

Downsample a 256-color palette index to the given target level.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Index` | in | A 256-color palette index (`0 .. 255`). `Color_Index_16` values (`0 .. 15`) may be passed directly because `Color_Index_16` is a subtype of `Color_Index_256`. |
| `Target` | in | The desired output `Color_Level`. |

**Returns:** A `Downsampled_Color` discriminated by the effective output level.

**Dispatch table:**

| Target | Result |
|--------|--------|
| `True_Color` or `Extended_256` | Identity — `Index_256 = Index`. Result level is `Extended_256` (a 256-color index cannot be up-converted to TrueColor). |
| `Basic_16` | `Downsample_256_To_16 (Index)` — index in `0 .. 15`. |
| `None` | `(Level => None)` — no color data. |

**SPARK contracts:**

- `Global => null`.
- **Idempotency postcondition (FUNC-DSP-009):** When `Target >= Extended_256`, the result carries the original `Index` unchanged in `Index_256` with level `Extended_256`.
- **Strip-to-None (FUNC-DSP-007):** When `Target = None`, the result level is `None`.
- **Monotonicity postcondition (FUNC-DSP-010):** `Color_Level_Of (result) <= Color_Level'Min (Extended_256, Target)` — the output level never exceeds `Extended_256` regardless of `Target`, because a palette index cannot encode TrueColor information.

**Requirements:** FUNC-DSP-008, FUNC-DSP-009, FUNC-DSP-010

---

### `Color_Level_Of`

```ada
function Color_Level_Of
  (D : Downsampled_Color) return Termicap.Color.Color_Level
with Global => null, Post => Color_Level_Of'Result = D.Level;
```

Return the `Color_Level` discriminant of a `Downsampled_Color` value.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `D` | in | A `Downsampled_Color` value. |

**Returns:** `D.Level` — the discriminant that identifies which variant is active.

This function is a trivial discriminant accessor. Its primary purpose is to appear in the postconditions of the `Downsample` overloads, where the monotonicity contract `Color_Level_Of (result) <= ...` must reference the level of the result record in a form that GNATprove can evaluate. Callers can also use it to inspect the level of a result before committing to a case dispatch.

**SPARK contract:** `Global => null`; postcondition `Color_Level_Of'Result = D.Level` is statically provable.

**Requirement:** FUNC-DSP-010

---

## Usage Examples

### Standard production use

```ada
with Termicap.Color;                   use Termicap.Color;
with Termicap.Downsampling;            use Termicap.Downsampling;
with Termicap.Environment;             use Termicap.Environment;
with Termicap.Environment.Capture;     use Termicap.Environment.Capture;
with Termicap.TTY;                     use Termicap.TTY;

procedure Main is
   Env    : Environment;
   Level  : Color_Level;
   Source : constant RGB := (Red => 220, Green => 50, Blue => 47);
   Result : Downsampled_Color;
begin
   Capture_Current (Env);
   Level  := Detect_Color_Level (Env, Is_TTY => Is_TTY (Stdout));
   Result := Downsample (Source, Target => Level);

   case Result.Level is
      when None         => null;
      when Basic_16     => Emit_SGR_16  (Result.Index_16);
      when Extended_256 => Emit_SGR_256 (Result.Index_256);
      when True_Color   => Emit_SGR_RGB (Result.RGB_Value.Red,
                                         Result.RGB_Value.Green,
                                         Result.RGB_Value.Blue);
   end case;
end Main;
```

### Downsampling a 256-color palette index

```ada
--  Source is a Color_Index_256; target terminal only supports 16 colors.
Result := Downsample (Index => 196, Target => Basic_16);
pragma Assert (Result.Level = Basic_16);
--  Result.Index_16 holds the nearest ANSI 16-color index.

--  Color_Index_16 values may be passed to the Color_Index_256 overload directly.
Result := Downsample (Index => Color_Index_16'(3), Target => Basic_16);
pragma Assert (Result.Level = Basic_16);
pragma Assert (Result.Index_16 = 3);  -- pass-through (0..15 range)
```

### Deterministic unit test (no OS interaction)

```ada
declare
   Red    : constant RGB := (Red => 220, Green => 50, Blue => 47);
   Teal   : constant RGB := (Red => 0, Green => 128, Blue => 128);
   Result : Downsampled_Color;
begin
   --  TrueColor target: identity result
   Result := Downsample (Red, Target => True_Color);
   pragma Assert (Result.Level = True_Color);
   pragma Assert (Result.RGB_Value.Red   = Red.Red);
   pragma Assert (Result.RGB_Value.Green = Red.Green);
   pragma Assert (Result.RGB_Value.Blue  = Red.Blue);

   --  256-color target
   Result := Downsample (Teal, Target => Extended_256);
   pragma Assert (Result.Level = Extended_256);
   pragma Assert (Result.Index_256 in 16 .. 255);

   --  16-color target
   Result := Downsample (Red, Target => Basic_16);
   pragma Assert (Result.Level = Basic_16);
   pragma Assert (Result.Index_16 in 0 .. 15);

   --  No-color target: strip-to-None
   Result := Downsample (Red, Target => None);
   pragma Assert (Result.Level = None);
end;
```

### Using primitive conversions directly

```ada
--  Convert an RGB value to the nearest 256-color palette entry.
Index : Color_Index_256 := Downsample_True_To_256 ((Red => 100, Green => 200, Blue => 50));
pragma Assert (Index in 16 .. 255);  -- ANSI 16-color sub-range never returned

--  Convert an RGB value directly to the nearest 16-color index.
Idx16 : Color_Index_16 := Downsample_True_To_16 ((Red => 180, Green => 30, Blue => 30));

--  Convert a 256-color index to the nearest 16-color index.
Idx16 := Downsample_256_To_16 (Index);
```

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-DSP-001 | `Color_Component` subtype, `RGB` record | Gold |
| FUNC-DSP-002 | `Color_Index_256` subtype | Gold |
| FUNC-DSP-003 | `Color_Index_16` subtype (derived from `Color_Index_256`) | Gold |
| FUNC-DSP-004 | `Downsample_True_To_256` function | Gold |
| FUNC-DSP-005 | `Downsample_True_To_16` function | Gold |
| FUNC-DSP-006 | `Downsample_256_To_16` function | Gold |
| FUNC-DSP-007 | `None` variant of `Downsampled_Color`; strip-to-None postcondition | Gold |
| FUNC-DSP-008 | `Downsample` (RGB overload), `Downsample` (256 overload) | Gold |
| FUNC-DSP-009 | Idempotency postconditions on both `Downsample` overloads | Gold |
| FUNC-DSP-010 | Monotonicity postconditions; `Color_Level_Of` function | Gold |
| FUNC-DSP-011 | SPARK Gold provability throughout (spec and body) | Gold |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — `Termicap.Downsampling` package description and SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 14: full end-to-end color downsampling flow
- **Tech Spec F7** (`docs/tech-specs/color-downsampling.md`) — full design rationale, algorithm survey, and discriminated record type design (ADR-0009)
- **[Termicap.Color](termicap-color.md)** — `Color_Level` type and `Detect_Color_Level` function that supplies the `Target` parameter
