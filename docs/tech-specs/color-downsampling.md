# Color Downsampling

**Feature:** Color Downsampling
**Requirements:** FUNC-DSP-001 through FUNC-DSP-012
**Status:** Approved
**Date:** 2026-04-03

---

## 1. Overview

Color downsampling converts a color value expressed at a higher fidelity level (TrueColor, 256-color) to the nearest equivalent at a lower fidelity level (256-color, 16-color, or no-color). This is the complement of color level *detection* (F3): detection tells a caller *what* the terminal supports; downsampling converts a color *to* that level.

**SPARK level target: Gold.** The entire package -- spec and body -- carries `SPARK_Mode => On` with no `SPARK_Mode => Off` escapes. All functions are pure integer arithmetic over bounded subtypes, the canonical case for Gold-level provability. No FFI, no dynamic allocation, no unbounded loops, no global state.

**Scope:** The package provides:

- Primitive types: `Color_Component`, `RGB`, `Color_Index_256`, `Color_Index_16`.
- Conversion functions: `Downsample_True_To_256`, `Downsample_True_To_16`, `Downsample_256_To_16`.
- A unified return type: `Downsampled_Color` (discriminated record).
- General dispatch: overloaded `Downsample` functions accepting any source level and a target `Color_Level`.
- Classification: `Color_Level_Of` for monotonicity contracts.

---

## 2. Framework Survey

### termenv (Go)

termenv implements color downsampling in two functions in `color.go` and dispatches via `profile.go`:

**TrueColor to 256 (`hexToANSI256Color`):**
- Quantizes each RGB channel to the nearest of 6 cube levels using threshold-based buckets: `<48 -> 0`, `<115 -> 1`, else `(v-35)/40`. This maps to the same cube levels `{0, 0x5f, 0x87, 0xaf, 0xd7, 0xff}` = `{0, 95, 135, 175, 215, 255}`.
- Computes a grayscale candidate from the average of the *quantized cube indices* (not the original RGB): `grayIdx = (r+g+b)/3` where r,g,b are cube indices 0..5, clamped to 0..23.
- Compares the input to both the nearest cube color and the nearest grayscale ramp value using HSLuv perceptual distance, returning whichever is closer.
- **Key difference from Termicap's approach:** termenv uses HSLuv distance (a floating-point, CIE-derived metric requiring an external library), which is not feasible in SPARK Gold. Termicap uses the simpler grayscale-first check from the requirements, which avoids floating-point entirely.

**256 to 16 (`ansi256ToANSIColor`):**
- Converts the 256-color index to a hex string, then to an HSLuv color, and brute-force searches all 16 ANSI colors by HSLuv distance.
- **Key difference:** Again uses floating-point HSLuv. Termicap reconstructs the RGB from the index and applies the integer redmean formula.

**Dispatch (`Profile.Convert`):**
- Uses Go interface polymorphism: `Color` is an interface with `ANSIColor`, `ANSI256Color`, `RGBColor` implementing it.
- `Convert` dispatches on the runtime type of the input via type switch, combined with the target profile level.
- Identity cases are handled by returning the input unchanged.
- The `Ascii` profile returns `NoColor{}`.

**ANSI palette values:** termenv uses `{0x00, 0x80, ..., 0xC0, 0x80, 0xFF, ...}` = `{0, 128, ..., 192, 128, 255, ...}` for its 16-color palette (standard VGA/CGA values). Termicap's requirements specify a different canonical palette: `{0, 170, ..., 85, 255, ...}`. Both are defensible choices; the requirements are normative for Termicap.

### supports-color (JavaScript)

supports-color is purely a *detection* library. It does not contain any color conversion or downsampling logic. Color conversion in the JavaScript ecosystem is handled by separate libraries (e.g., `chalk` delegates to `ansi-styles` which uses the same cube quantization algorithm).

### rich (Python)

Referenced in the global synthesis (section 3.3) for its use of the redmean approximation for 16-color matching. rich's `Color._get_system_color` performs brute-force search over 16 ANSI colors using the redmean weighted Euclidean distance. This is the algorithm adopted by FUNC-DSP-005.

### Summary of adoption decisions

| Aspect | termenv | Termicap |
|--------|---------|----------|
| TrueColor to 256 distance metric | HSLuv (float) | Grayscale-first + cube quantization (integer) |
| 256 to 16 distance metric | HSLuv (float) | Redmean (integer) |
| Dispatch mechanism | Go interface + type switch | Overloaded Ada functions + discriminated record |
| No-color representation | `NoColor{}` struct | Discriminated record variant with `Level => None` |
| SPARK provability | N/A | Gold target |

---

## 3. Type Design

### 3.1 Color_Component (FUNC-DSP-001)

```ada
subtype Color_Component is Natural range 0 .. 255;
```

A constrained subtype of `Natural`. The bounds `0 .. 255` match the 8-bit channel width of sRGB. Using a named subtype rather than bare `Natural` gives the SPARK prover the range information needed to discharge overflow obligations in the cube-index and distance calculations.

### 3.2 RGB (FUNC-DSP-001)

```ada
type RGB is record
   Red   : Color_Component;
   Green : Color_Component;
   Blue  : Color_Component;
end record;
```

A plain record with three independently readable/writable fields. No invariant, no discriminant. Usable as a function parameter and return type without dynamic allocation.

### 3.3 Color_Index_256 (FUNC-DSP-002)

```ada
subtype Color_Index_256 is Natural range 0 .. 255;
```

Represents an xterm 256-color palette index. The sub-range semantics are:

- 0--15: Standard ANSI colors (the 16-color subset)
- 16--231: 6x6x6 RGB color cube (216 entries)
- 232--255: 24-step grayscale ramp

### 3.4 Color_Index_16 (FUNC-DSP-003)

```ada
subtype Color_Index_16 is Color_Index_256 range 0 .. 15;
```

**Why derived from Color_Index_256 (not directly from Natural):**

1. **Subtype compatibility.** Any `Color_Index_16` value is directly assignable to a `Color_Index_256` variable without conversion. This makes the pass-through branch of `Downsample_256_To_16` trivial: when the input index is in `0 .. 15`, the function returns it directly, and the range check is statically provable because `Color_Index_16` is a subtype of `Color_Index_256`.

2. **Type family reasoning.** SPARK can reason about both subtypes within the same type family. A `Color_Index_16` value used in a context expecting `Color_Index_256` requires no explicit conversion and generates no runtime check. This eliminates a class of potential proof obligations.

3. **Semantic correctness.** The 16 standard ANSI colors *are* the first 16 entries of the 256-color palette. The subtype relationship captures this IS-A relationship in the type system.

### 3.5 Downsampled_Color -- The Unified Return Type

This is the critical design decision for the feature. Three options were evaluated:

#### Option A: Discriminated record with Color_Level discriminant

```ada
type Downsampled_Color (Level : Color_Level := None) is record
   case Level is
      when True_Color   => RGB_Value   : RGB;
      when Extended_256  => Index_256   : Color_Index_256;
      when Basic_16      => Index_16    : Color_Index_16;
      when None          => null;
   end case;
end record;
```

#### Option B: Overloaded functions with no unified return type

Each conversion returns its natural type (`RGB`, `Color_Index_256`, `Color_Index_16`, or a separate `No_Color` sentinel). The `Downsample` function is not a single function but a family of overloaded functions, each with a specific return type.

#### Option C: Tagged type hierarchy

```ada
type Abstract_Color is abstract tagged null record;
type True_Color_Value is new Abstract_Color with record ... end record;
type Index_256_Value  is new Abstract_Color with record ... end record;
-- etc.
```

#### Evaluation

| Criterion | A (Discriminated) | B (Overloaded) | C (Tagged) |
|-----------|-------------------|----------------|------------|
| SPARK Gold | Fully supported | Fully supported | Not supported (dispatching) |
| Unified return type for `Downsample` | Yes | No -- caller must know target at compile time | Yes |
| Idempotency postcondition (FUNC-DSP-009) | Expressible on a single function | Requires per-overload postconditions | Expressible |
| Monotonicity postcondition (FUNC-DSP-010) | `Color_Level_Of` on the discriminant | Not expressible on a single function | Requires class-wide contracts |
| `Color_Level_Of` implementation | Trivial: `return D.Level` | Not applicable | Requires dispatching |
| No dynamic allocation | Guaranteed (fixed-size record) | N/A | May require heap for class-wide types |
| Complexity | Low | Medium (many overloads) | High |

#### Recommendation: Option A (Discriminated record)

**Justification:**

1. **SPARK Gold compatible.** Discriminated records are fully supported in SPARK. The discriminant is known at construction time and can be used in postconditions. No dispatching, no class-wide types, no heap allocation.

2. **Postconditions are natural.** The `Color_Level_Of` function is trivial (`return D.Level`), and the monotonicity postcondition `Color_Level_Of (Result) <= Color_Level'Min (Source_Level, Target)` is directly expressible.

3. **Idempotency is testable.** A single `Downsample` function returning `Downsampled_Color` can carry the postcondition that when `Target = True_Color`, the result's RGB fields equal the input.

4. **Caller ergonomics.** Callers can dispatch on the discriminant in a case statement to extract the appropriate value. This is idiomatic Ada.

5. **Fixed size.** The record has a known maximum size (the `True_Color` variant with 3 `Color_Component` fields = 3 bytes + discriminant overhead). No dynamic allocation is needed.

This decision is recorded in ADR-0009.

### 3.6 Intermediate Distance Subtype

The redmean distance formula (FUNC-DSP-005) computes:

```
(2 + R_mean/256) * dR^2 + 4 * dG^2 + (2 + (255-R_mean)/256) * dB^2
```

where `dR`, `dG`, `dB` are channel differences in `{-255 .. 255}`, so `dR^2` can reach `255^2 = 65,025`. The coefficient `(2 + R_mean/256)` is at most `2 + 255/256 = 2` (integer division), so each weighted term is at most `2 * 65,025 = 130,050`. But `4 * dG^2 = 4 * 65,025 = 260,100`. The maximum total distance is `130,050 + 260,100 + 130,050 = 520,200`.

To keep SPARK happy, we define:

```ada
subtype Distance_Value is Natural range 0 .. 520_200;
```

This named subtype ensures all intermediate calculations stay within `Natural` range (which goes up to `2^31 - 1 = 2,147,483,647`) and provides explicit bounds for the prover.

For individual squared differences, we define:

```ada
subtype Channel_Diff is Integer range -255 .. 255;
subtype Squared_Diff is Natural range 0 .. 65_025;
```

These help the prover discharge overflow checks at each step of the computation without manual lemmas.

---

## 4. Algorithm Design

### 4.1 TrueColor to 256 (FUNC-DSP-004)

The algorithm has two steps: a grayscale-first check and a cube quantization fallback.

#### Step 1: Grayscale check

The xterm 256-color palette includes a 24-step grayscale ramp at indices 232--255 with values `Ramp(i) = 8 + 10*i` for `i in 0..23`, producing `{8, 18, 28, ..., 238}`.

Given input `(R, G, B)`:

1. Compute a candidate grayscale index: `Gray_Idx := (R - 8) / 10`, clamped to `0 .. 23`.
   - For `R < 8`: `Gray_Idx := 0`.
   - For `R > 238`: `Gray_Idx := 23`.
   - Otherwise: `Gray_Idx := (R - 8) / 10`.

2. Compute the ramp value at that index: `Ramp_Val := 8 + 10 * Gray_Idx`.

3. Check if all three channels are close to this ramp value:
   - `|R - Ramp_Val| <= 4` AND `|G - Ramp_Val| <= 4` AND `|B - Ramp_Val| <= 4`

4. If yes: return `232 + Gray_Idx`.

The threshold of 4 is half the ramp step size (10/2 = 5, but we use 4 to exclude the boundary -- a pixel at exactly the midpoint between two ramp entries falls to the cube instead).

#### Step 2: Cube quantization

The 6x6x6 color cube uses levels `{0, 95, 135, 175, 215, 255}` at indices 0--5. The quantization function maps each channel value to its nearest cube level index:

| Channel value range | Cube index | Cube level |
|--------------------|------------|------------|
| 0 -- 47            | 0          | 0          |
| 48 -- 114          | 1          | 95         |
| 115 -- 154         | 2          | 135        |
| 155 -- 194         | 3          | 175        |
| 195 -- 234         | 4          | 215        |
| 235 -- 255         | 5          | 255        |

The thresholds are the midpoints between adjacent levels: `(0+95)/2 = 47`, `(95+135)/2 = 115`, etc.

The cube quantization function can be implemented as a lookup or a sequence of comparisons:

```ada
CUBE_LEVELS : constant array (0 .. 5) of Color_Component := (0, 95, 135, 175, 215, 255);

function Cube_Index (C : Color_Component) return Natural
  with Post => Cube_Index'Result in 0 .. 5
is
begin
   if C < 48 then return 0;
   elsif C < 115 then return 1;
   elsif C < 155 then return 2;
   elsif C < 195 then return 3;
   elsif C < 235 then return 4;
   else return 5;
   end if;
end Cube_Index;
```

The palette index is then: `16 + 36 * Cube_Index(R) + 6 * Cube_Index(G) + Cube_Index(B)`.

**Range proof:** `36*5 + 6*5 + 5 = 180 + 30 + 5 = 215`, so the maximum index is `16 + 215 = 231`, which is within `Color_Index_256`. The minimum is `16 + 0 = 16`. Both are within `0 .. 255`.

#### Worked example: (200, 100, 50)

1. **Grayscale check:** `Gray_Idx = (200 - 8) / 10 = 19`. `Ramp_Val = 8 + 10*19 = 198`. Check: `|200 - 198| = 2 <= 4` (pass), `|100 - 198| = 98 > 4` (fail). Grayscale check fails.

2. **Cube quantization:** `Cube_Index(200) = 4` (range 195--234), `Cube_Index(100) = 1` (range 48--114), `Cube_Index(50) = 1` (range 48--114). Index = `16 + 36*4 + 6*1 + 1 = 16 + 144 + 6 + 1 = 167`.

Result: palette index **167**, which represents the cube color `(215, 95, 95)`.

### 4.2 TrueColor to 16 (FUNC-DSP-005)

This function finds the ANSI color whose canonical RGB value has the smallest perceptual distance to the input, using the redmean approximation.

#### The redmean formula

```
R_mean := (c1.Red + c2.Red) / 2

Distance := (2 + R_mean / 256) * (c1.Red   - c2.Red)^2
          + 4                   * (c1.Green - c2.Green)^2
          + (2 + (255 - R_mean) / 256) * (c1.Blue  - c2.Blue)^2
```

All arithmetic is integer. The coefficient `R_mean / 256` is `0` for `R_mean < 256` (which is always the case since `R_mean <= 255`), so `(2 + R_mean/256) = 2` always, and `(2 + (255 - R_mean)/256)` is also always `2`. However, the *intent* of the formula (from CompuPhase) is to use the fractional weighting. With integer division, the formula degenerates to: `2*dR^2 + 4*dG^2 + 2*dB^2`.

To preserve the perceptual weighting, the implementation should scale the formula. A common approach is to multiply everything by 256 to avoid losing the fractional part:

```
Distance_Scaled := (512 + R_mean) * dR^2
                 + 1024           * dG^2
                 + (512 + (255 - R_mean)) * dB^2
```

This preserves the relative ordering (which is all that matters for nearest-neighbor search) while keeping everything in integers. The maximum value becomes: `(512 + 255) * 65,025 + 1024 * 65,025 + (512 + 255) * 65,025 = 767 * 65,025 + 1024 * 65,025 + 767 * 65,025 = (767 + 1024 + 767) * 65,025 = 2,558 * 65,025 = 166,333,950`.

This fits comfortably in a 32-bit signed integer (`2^31 - 1 = 2,147,483,647`), so we define:

```ada
subtype Scaled_Distance is Natural range 0 .. 166_333_950;
```

#### The canonical 16-color RGB table

```ada
ANSI_16_PALETTE : constant array (Color_Index_16) of RGB :=
  (0  => (0,   0,   0),      --  Black
   1  => (170, 0,   0),      --  Red
   2  => (0,   170, 0),      --  Green
   3  => (170, 170, 0),      --  Yellow
   4  => (0,   0,   170),    --  Blue
   5  => (170, 0,   170),    --  Magenta
   6  => (0,   170, 170),    --  Cyan
   7  => (170, 170, 170),    --  White
   8  => (85,  85,  85),     --  Bright Black
   9  => (255, 85,  85),     --  Bright Red
   10 => (85,  255, 85),     --  Bright Green
   11 => (255, 255, 85),     --  Bright Yellow
   12 => (85,  85,  255),    --  Bright Blue
   13 => (255, 85,  255),    --  Bright Magenta
   14 => (85,  255, 255),    --  Bright Cyan
   15 => (255, 255, 255));   --  Bright White
```

#### Why redmean over Euclidean

Standard Euclidean distance treats all three channels equally: `dR^2 + dG^2 + dB^2`. This does not account for the fact that the human eye is more sensitive to green differences and that the perception of red differences varies with the absolute red level. The redmean approximation weights the green channel double and adjusts the red/blue weighting based on the average red value. It is dramatically cheaper than CIE Lab or HSLuv (no floating point, no transcendental functions), making it ideal for SPARK Gold.

#### Why NOT going through 256 first

A naive approach would be: TrueColor -> 256 -> 16. This loses accuracy because the intermediate 256-color quantization discards information. Consider input `(170, 0, 0)` (exact ANSI Red):

- Direct TrueColor -> 16: distance to ANSI Red (170, 0, 0) is 0. Correct result: index 1.
- Via 256: `Cube_Index(170) = 3` (level 175), so the cube color is `(175, 0, 0)`. Then 16-color matching compares `(175, 0, 0)` against the palette, which still returns index 1, but the intermediate step introduced unnecessary error that could cause wrong results for borderline inputs.

The requirement (FUNC-DSP-005) mandates direct TrueColor-to-16 conversion, and the tech spec follows this.

### 4.3 256 to 16 (FUNC-DSP-006)

Three branches based on the input index:

#### Branch 1: 0--15 (pass-through)

Input is already a 16-color index. Return it directly as `Color_Index_16`. Since `Color_Index_16` is a subtype of `Color_Index_256`, this is a simple subtype conversion with a range check that is statically provable (the branch guard ensures `Index in 0 .. 15`).

#### Branch 2: 16--231 (cube reconstruction)

Reconstruct the RGB value from the cube index:

```
Index_In_Cube := Index - 16          -- 0 .. 215
Red_Idx       := Index_In_Cube / 36  -- 0 .. 5
Green_Idx     := (Index_In_Cube / 6) mod 6  -- 0 .. 5
Blue_Idx      := Index_In_Cube mod 6        -- 0 .. 5
```

Convert each axis index to an RGB value using the inverse formula:

```
Cube_Level(i) := (if i = 0 then 0 else 55 + 40 * i)
```

This produces `{0, 95, 135, 175, 215, 255}`, which matches the forward mapping.

Construct `Color := (Cube_Level(Red_Idx), Cube_Level(Green_Idx), Cube_Level(Blue_Idx))` and pass to `Downsample_True_To_16`.

#### Branch 3: 232--255 (grayscale reconstruction)

```
Gray := 8 + 10 * (Index - 232)    -- produces 8, 18, 28, ..., 238
Color := (Gray, Gray, Gray)
```

Pass to `Downsample_True_To_16`.

### 4.4 Strip to None (FUNC-DSP-007)

When the target `Color_Level` is `None`, the result is always:

```ada
Downsampled_Color'(Level => None)
```

This is a discriminated record with the `None` variant, which carries no color data. The caller can test `Result.Level = None` to detect the stripped state. This is distinct from mapping to index 0 (Black): a no-color result means "emit no color escape sequence", not "emit Black".

### 4.5 General Dispatch (FUNC-DSP-008)

The `Downsample` function is overloaded on the source type, with a `Target : Color_Level` parameter and a `Downsampled_Color` return type:

```ada
function Downsample (Color : RGB;             Target : Color_Level) return Downsampled_Color;
function Downsample (Index : Color_Index_256;  Target : Color_Level) return Downsampled_Color;
function Downsample (Index : Color_Index_16;   Target : Color_Level) return Downsampled_Color;
```

The full dispatch table:

| Source | Target | Action |
|--------|--------|--------|
| RGB | True_Color | Identity: return `(Level => True_Color, RGB_Value => Color)` |
| RGB | Extended_256 | `Downsample_True_To_256 (Color)` -> wrap in `(Level => Extended_256, Index_256 => result)` |
| RGB | Basic_16 | `Downsample_True_To_16 (Color)` -> wrap in `(Level => Basic_16, Index_16 => result)` |
| RGB | None | `(Level => None)` |
| Color_Index_256 | True_Color | Identity: reconstruct RGB, return as `(Level => Extended_256, Index_256 => Index)` |
| Color_Index_256 | Extended_256 | Identity: `(Level => Extended_256, Index_256 => Index)` |
| Color_Index_256 | Basic_16 | `Downsample_256_To_16 (Index)` -> wrap |
| Color_Index_256 | None | `(Level => None)` |
| Color_Index_16 | True_Color | Identity: `(Level => Basic_16, Index_16 => Index)` |
| Color_Index_16 | Extended_256 | Identity: `(Level => Basic_16, Index_16 => Index)` |
| Color_Index_16 | Basic_16 | Identity: `(Level => Basic_16, Index_16 => Index)` |
| Color_Index_16 | None | `(Level => None)` |

**Upsampling requests** (target level > source level) return the source unchanged at its original level. The library does not synthesize higher-fidelity colors.

---

## 5. Package Structure

### Package name: `Termicap.Downsampling`

**Files:** `src/termicap-downsampling.ads`, `src/termicap-downsampling.adb`

### Why a separate package (not part of Termicap.Color)

1. **Different SPARK level.** `Termicap.Color` is SPARK Silver (contracts verified, but not full flow analysis of the body). `Termicap.Downsampling` targets SPARK Gold (full body verification including absence of runtime errors). Mixing Silver and Gold logic in a single package forces the whole package to the weaker level, or requires `SPARK_Mode` annotations at the subprogram level, which adds complexity.

2. **Different concerns.** `Termicap.Color` is about *detection* (reading environment variables, applying heuristic cascades). `Termicap.Downsampling` is about *conversion* (pure arithmetic on color values). These are orthogonal responsibilities that happen to share the `Color_Level` type.

3. **Dependency direction.** `Termicap.Downsampling` depends on `Termicap.Color` (for the `Color_Level` type) but `Termicap.Color` does not depend on downsampling. Keeping them separate avoids a circular dependency and maintains a clean layering.

4. **Independent testability.** Downsampling tests require only color values and expected results. They do not need `Termicap.Environment` or any environment snapshot. A separate package keeps the test fixture simple.

### Dependencies

```
Termicap.Downsampling
   with Termicap.Color;   -- for Color_Level type
```

No dependency on `Termicap.Environment`, `Termicap.TTY`, or any FFI package.

### Updated building blocks (Level 1)

```
Termicap
+-- Termicap.Environment          [SPARK Silver]
|   +-- Termicap.Environment.Capture  [SPARK_Mode => Off]
+-- Termicap.TTY                  [spec: SPARK, body: Off]
+-- Termicap.Color                [SPARK Silver]
+-- Termicap.Downsampling         [SPARK Gold]     <-- new
+-- Termicap.Dimensions           [spec: SPARK, body: Off]
+-- Termicap.Unicode              [SPARK Silver]
+-- Termicap.Terminal_Id          [spec: SPARK, body: Off]
```

---

## 6. SPARK Contracts

### 6.1 All functions: Global => null

Every public and private function carries `Global => null`. There is no global state, no I/O, no FFI.

### 6.2 Idempotency (FUNC-DSP-009)

The identity postcondition on the RGB overload of `Downsample`:

```ada
function Downsample (Color : RGB; Target : Color_Level) return Downsampled_Color
  with
    Global => null,
    Post   =>
      (if Target >= True_Color then
         Downsample'Result.Level = True_Color
         and then Downsample'Result.RGB_Value.Red   = Color.Red
         and then Downsample'Result.RGB_Value.Green = Color.Green
         and then Downsample'Result.RGB_Value.Blue  = Color.Blue);
```

For the index overloads:

```ada
function Downsample (Index : Color_Index_256; Target : Color_Level) return Downsampled_Color
  with
    Global => null,
    Post   =>
      (if Target >= Extended_256 then
         Downsample'Result.Level = Extended_256
         and then Downsample'Result.Index_256 = Index);

function Downsample (Index : Color_Index_16; Target : Color_Level) return Downsampled_Color
  with
    Global => null,
    Post   =>
      (if Target >= Basic_16 then
         Downsample'Result.Level = Basic_16
         and then Downsample'Result.Index_16 = Index);
```

### 6.3 Monotonicity (FUNC-DSP-010)

```ada
function Color_Level_Of (D : Downsampled_Color) return Color_Level
  with
    Global => null,
    Post   => Color_Level_Of'Result = D.Level;
```

The monotonicity postcondition on `Downsample` (RGB overload as example):

```ada
Post => Color_Level_Of (Downsample'Result) <= Color_Level'Min (True_Color, Target)
```

Since `Color_Level'Min (True_Color, Target) = Target` for all `Target`, this simplifies to `Color_Level_Of (Result) <= Target`.

For the `Color_Index_256` overload: `Color_Level_Of (Result) <= Color_Level'Min (Extended_256, Target)`.

For the `Color_Index_16` overload: `Color_Level_Of (Result) <= Color_Level'Min (Basic_16, Target)`.

### 6.4 Conversion function postconditions

```ada
function Downsample_True_To_256 (Color : RGB) return Color_Index_256
  with Global => null;

function Downsample_True_To_16 (Color : RGB) return Color_Index_16
  with Global => null;

function Downsample_256_To_16 (Index : Color_Index_256) return Color_Index_16
  with Global => null;
```

The return subtypes (`Color_Index_256`, `Color_Index_16`) encode the range constraint as the postcondition. SPARK verifies that the computed index is always within bounds.

### 6.5 Proof challenges

**Redmean overflow.** The scaled redmean formula produces values up to 166,333,950. This fits in `Natural` (which is `Integer range 0 .. Integer'Last`, typically `2^31 - 1`). The `Scaled_Distance` subtype provides an explicit bound for the prover. The intermediate computations must also be annotated:

- `dR : Channel_Diff` (range -255 .. 255)
- `dR_Sq : Squared_Diff` (range 0 .. 65,025)
- `Weighted_R : Natural range 0 .. 767 * 65_025` -- the prover needs to see the multiplication stays bounded.

The key insight is that all intermediate types are subtypes of `Natural` or `Integer` with explicit ranges. The SPARK prover can discharge these bounds automatically given the subtype declarations, without manual lemmas.

**Cube index formula.** `16 + 36*R_Idx + 6*G_Idx + B_Idx` where each index is in `0 .. 5`. Maximum: `16 + 180 + 30 + 5 = 231`. Minimum: `16 + 0 + 0 + 0 = 16`. Both within `Color_Index_256`. The prover discharges this from the `0 .. 5` range of each index.

**Grayscale clamping.** The expression `(R - 8) / 10` when `R < 8` would underflow. The implementation must clamp: `if R < 8 then Gray_Idx := 0`. Similarly, `if R > 238 then Gray_Idx := 23`. The prover needs to see these guards to discharge the range check on `Gray_Idx : Natural range 0 .. 23`.

---

## 7. ADR Reference

The decision on `Downsampled_Color` representation is recorded in:

**ADR-0009:** Discriminated Record for Downsampled_Color Return Type (`docs/adr/0009-downsampling-return-type.md`)

---

## 8. Test Strategy

### 8.1 Test vectors from FUNC-DSP-012

| Function | Input | Expected | Rationale |
|----------|-------|----------|-----------|
| `Downsample_True_To_256` | `(0, 0, 0)` | 16 | Cube origin (all channels map to cube index 0) |
| `Downsample_True_To_256` | `(255, 255, 255)` | 231 | Cube maximum (all channels map to cube index 5) |
| `Downsample_True_To_256` | `(128, 128, 128)` | 244 | Grayscale ramp: `(128-8)/10 = 12`, ramp value = 128, all channels match. Result = 232 + 12 = 244 |
| `Downsample_True_To_256` | `(255, 0, 0)` | 196 | Cube index: `16 + 36*5 + 6*0 + 0 = 196` |
| `Downsample_True_To_16` | `(0, 0, 0)` | 0 | Black |
| `Downsample_True_To_16` | `(255, 255, 255)` | 15 | Bright White |
| `Downsample_True_To_16` | `(255, 0, 0)` | 9 | Bright Red (distance 0 to palette entry 9 = (255, 85, 85)... actually need to verify) |
| `Downsample_256_To_16` | 0 | 0 | Pass-through |
| `Downsample_256_To_16` | 15 | 15 | Pass-through |
| `Downsample_256_To_16` | 231 | 15 | Cube max (255,255,255) maps to Bright White |
| `Downsample (RGB, True_Color)` | `(100, 200, 50)` | Same RGB | Identity |
| `Downsample (Index_256, Extended_256)` | 42 | 42 | Identity |
| `Downsample (Index_16, Basic_16)` | 7 | 7 | Identity |
| `Downsample (RGB, None)` | any | `(Level => None)` | Strip |
| `Downsample (Index_256, None)` | any | `(Level => None)` | Strip |

### 8.2 Additional edge cases

| Test | Input | Expected | Rationale |
|------|-------|----------|-----------|
| Grayscale boundary | `(12, 12, 12)` | 232 | Just above ramp entry 0 threshold: ramp(0)=8, \|12-8\|=4 <= 4 |
| Grayscale reject (near-gray but not quite) | `(128, 128, 120)` | cube index | \|120-128\|=8 > 4, fails grayscale check |
| Cube boundary | `(47, 47, 47)` | cube idx 16 | All channels map to cube index 0 (threshold is 48) |
| Cube boundary | `(48, 48, 48)` | cube idx 59 | All channels map to cube index 1: `16+36+6+1=59` |
| Pure black via 256-to-16 | 16 | 0 | Cube entry (0,0,0) maps to ANSI Black |
| Grayscale ramp via 256-to-16 | 232 | 0 | Ramp entry (8,8,8) nearest to Black |
| Grayscale ramp max via 256-to-16 | 255 | 15 | Ramp entry (238,238,238) nearest to Bright White |
| Upsampling identity | `Downsample(idx_16=5, True_Color)` | `(Level=>Basic_16, Index_16=>5)` | No upsampling |
| Redmean tie-breaking | Two equidistant ANSI colors | Lower index wins | FUNC-DSP-005 tie-break rule |

### 8.3 Test structure

Tests live in `tests/src/` as a new test package. Each conversion function is tested independently. The general `Downsample` function is tested for dispatch correctness, identity, and strip-to-none behavior. No environment snapshot or TTY status is needed.

---

## 9. Open Questions

1. **Pure black (0,0,0) and pure white (255,255,255) -- grayscale or cube?** The grayscale check in FUNC-DSP-004 computes `Gray_Idx = (0-8)/10`. With the clamping rule (`R < 8 -> Gray_Idx := 0`), `Ramp_Val = 8`. Then `|0 - 8| = 8 > 4`, so the grayscale check fails, and both pure black and pure white fall through to cube quantization. This matches the expected test results (index 16 and 231). **Resolved by the algorithm definition.**

2. **Redmean scaling.** The requirements (FUNC-DSP-005) write the distance formula with `R_mean / 256` as integer division, which produces coefficients of 2 for all inputs. The tech spec proposes the scaled version `(512 + R_mean)` to preserve the perceptual weighting. The Ada spec should implement the scaled version; the distance values are only compared against each other (never against an absolute threshold), so scaling does not change the result selection, only the magnitudes. **Decision: use scaled formula.**

3. **`Downsample_True_To_16` for (255, 0, 0).** The requirements say the expected result is 9 (Bright Red). Let us verify: distance to index 1 (170, 0, 0): `R_mean = (255+170)/2 = 212`. Scaled: `(512+212)*(255-170)^2 + 1024*0 + (512+43)*0 = 724 * 7225 = 5,230,900`. Distance to index 9 (255, 85, 85): `R_mean = (255+255)/2 = 255`. Scaled: `(512+255)*0 + 1024*85^2 + (512+0)*85^2 = 0 + 1024*7225 + 512*7225 = 7,398,400 + 3,699,200 = 11,097,600`. So index 1 (Red) has distance 5,230,900, while index 9 (Bright Red) has distance 11,097,600. The nearest is index 1 (Red), not 9 (Bright Red). **This contradicts the expected test vector in FUNC-DSP-012. The Ada spec phase should confirm the expected value and update the test vector if needed.**

4. **Package visibility of conversion primitives.** Should `Downsample_True_To_256`, `Downsample_True_To_16`, and `Downsample_256_To_16` be public (in the spec) or private (in the body)? Making them public enables direct testing and allows advanced callers to skip the dispatch overhead. Making them private reduces the API surface. **Recommendation: public.** The requirements define them as independent functions with specific signatures, and FUNC-DSP-012 requires independent testing.

---

## Related Documents

- **Requirements:** `docs/requirements/color-downsampling.sdoc` (FUNC-DSP-001 through FUNC-DSP-012)
- **ADR-0009:** `docs/adr/0009-downsampling-return-type.md` (Downsampled_Color representation decision)
- **Building Blocks:** `docs/architecture/03-building-blocks.md` (package hierarchy)
- **Runtime View:** `docs/architecture/04-runtime-view.md` (detection flow context)
- **Global Synthesis:** `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` (section 3.3: degradation strategies)
- **Tech Spec F3:** `docs/tech-specs/f3-color-level-detection.md` (color level detection)
