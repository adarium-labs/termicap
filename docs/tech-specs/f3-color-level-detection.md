# F3: Color Level Detection

**Feature:** Color Level Detection
**Requirements:** FUNC-CLR-001 through FUNC-CLR-015
**Status:** Approved
**Date:** 2026-04-02

---

## A. Framework Survey

### How reference libraries detect color level

#### supports-color (JavaScript) -- The canonical cascade

supports-color (`index.js`, ~120 lines) is the most widely depended-upon color detection library (115,000+ npm dependents). Its algorithm is a single function `_supportsColor(haveStream, {streamIsTTY})` that returns an integer level 0-3:

```
Phase 1 -- FORCE_COLOR override:
  Parse FORCE_COLOR as integer (0-3). "true" -> 1, "false" -> 0, "" -> 1.
  If level is 0, return 0 immediately.
  Otherwise, store as floor (min).

Phase 2 -- CI pre-TTY:
  Azure DevOps (TF_BUILD + AGENT_NAME) -> 1.

Phase 3 -- TTY gate:
  If stream exists, is not a TTY, and no forceColor -> return 0.
  min = forceColor || 0.

Phase 4 -- TERM=dumb:
  return min.

Phase 5 -- Platform (Windows):
  Build number thresholds -> 2 or 3.

Phase 6 -- CI detection:
  GITHUB_ACTIONS, GITEA_ACTIONS, CIRCLECI -> 3.
  TRAVIS, APPVEYOR, GITLAB_CI, BUILDKITE, DRONE -> 1.
  Generic CI present but no specific match -> min.

Phase 7 -- COLORTERM / TERM / TERM_PROGRAM heuristics:
  COLORTERM="truecolor" -> 3.
  TERM=xterm-kitty|xterm-ghostty|wezterm -> 3.
  TERM_PROGRAM=iTerm.app (version >= 3) -> 3.
  TERM_PROGRAM=Apple_Terminal -> 2.
  TERM ends with -256color/-256 -> 2.
  TERM matches screen|xterm|vt100|vt220|rxvt|color|ansi|cygwin|linux -> 1.
  COLORTERM present (any value) -> 1.

Phase 8 -- Default:
  return min.
```

**Key patterns adopted by Termicap:**
- FORCE_COLOR parsed as a floor (min_level) that later stages can only raise, never lower.
- TTY gate returns 0 only when no force override is active.
- CI detection is positioned before some heuristics (COLORTERM/TERM) in supports-color, but the spec for Termicap (FUNC-CLR-015) places CI before the TTY gate.
- TERM=dumb is handled after the TTY gate in supports-color but before it in Termicap's requirements. Termicap follows its own priority order (FUNC-CLR-015).

**Weaknesses Termicap improves upon:**
- supports-color checks `'NO_COLOR' in env` but does not distinguish empty from absent (JavaScript's `in` operator handles this correctly, but the code also checks `env.FORCE_COLOR === ''`, treating empty FORCE_COLOR as level 1 rather than checking presence vs. value). Termicap uses `Contains` for presence and `Value` for content, following the no-color.org spec strictly.
- supports-color mutates global state (`flagForceColor`). Termicap's pure-function design avoids this.
- No CLICOLOR_FORCE or CLICOLOR support in supports-color. Termicap implements both (FUNC-CLR-005, FUNC-CLR-012).

#### termenv (Go) -- Environment-injectable detection

termenv structures detection differently from supports-color. It has two layers:

1. **`ColorProfile()`** (in `termenv_unix.go`): The raw heuristic cascade, gated by `o.isTTY()`. Checks GOOGLE_CLOUD_SHELL, COLORTERM (with screen multiplexer cap), known TERM values (alacritty, contour, rio, wezterm, xterm-ghostty, xterm-kitty), TERM "256color"/"color"/"ansi" substrings. Returns `Ascii` if nothing matches.

2. **`EnvColorProfile()`** (in `termenv.go`): Wraps `ColorProfile()` with NO_COLOR and CLICOLOR_FORCE logic. If `EnvNoColor()` returns true, returns `Ascii`. If CLICOLOR_FORCE is set and the raw profile is `Ascii`, upgrades to `ANSI`.

**Key patterns adopted by Termicap:**
- Injectable `Environ` interface for testability. Termicap's `Environment` snapshot type serves the same purpose but as a concrete SPARK-provable value type.
- Screen multiplexer awareness: when TERM starts with "screen" and TERM_PROGRAM is not "tmux", cap at ANSI256 even if COLORTERM says truecolor. Termicap adopts this (FUNC-CLR-013).
- termenv's `Profile` enum uses reverse ordering (TrueColor=0, Ascii=3), which makes "higher is better" comparisons awkward. Termicap uses the more natural `None < Basic_16 < Extended_256 < True_Color` ordering.

**Weaknesses Termicap improves upon:**
- No FORCE_COLOR support at all. Termicap implements the full FORCE_COLOR spec (FUNC-CLR-004).
- `EnvNoColor()` requires `NO_COLOR != ""` (non-empty), deviating from the no-color.org spec which says presence alone is sufficient. Termicap follows the spec: `Contains("NO_COLOR")` triggers disable.
- No CI environment detection. Termicap adds CI detection (FUNC-CLR-011).

#### chalk/supports-color (Rust) -- rust-supports-color

The Rust crate `supports-color` is a port of the JavaScript `supports-color`. It follows the same algorithm but wraps the result in a Rust struct with `has_basic`, `has_256`, `has_16m` fields. It uses `std::env::var()` directly (no environment injection), making it difficult to test. Termicap's snapshot-based approach is superior for testability and SPARK provability.

### What Termicap should adopt

| Pattern | Source | Adoption |
|---------|--------|----------|
| 4-level color model (None/16/256/TrueColor) | All frameworks | Direct adoption as `Color_Level` enum |
| FORCE_COLOR as floor (min_level) | supports-color JS | Direct adoption with extended value parsing (FUNC-CLR-004) |
| Screen multiplexer cap at 256 | termenv | Direct adoption (FUNC-CLR-013) |
| Environment injection for testability | termenv | Already implemented as `Termicap.Environment` snapshot |
| CI detection before TTY gate | supports-color JS | Adopted per FUNC-CLR-015 priority order |
| Strict NO_COLOR compliance (presence, not value) | Improvement over all | Termicap-specific: uses `Contains` for presence check |
| CLICOLOR/CLICOLOR_FORCE support | termenv (partial) | Full support per FUNC-CLR-005, FUNC-CLR-012 |
| Pure function with explicit parameters | Termicap-specific | `Detect_Color_Level(Env, Is_TTY)` with `Global => null` |

---

## B. Package Design

### Package hierarchy

```
Termicap                              (root namespace -- no types or subprograms)
+-- Termicap.Environment              [SPARK Silver] -- environment snapshot (F1)
|   +-- Termicap.Environment.Capture  [SPARK_Mode => Off] -- OS FFI boundary
+-- Termicap.TTY                      [spec: SPARK, body: Off] -- TTY detection (F2)
+-- Termicap.Color                    [SPARK Silver] -- color level detection (F3, new)
```

### SPARK boundaries

| Package | SPARK_Mode (spec) | SPARK_Mode (body) | Rationale |
|---------|------------------|------------------|-----------|
| `Termicap.Color` | On | On | All logic is pure: enum comparisons, string matching via Environment API, no FFI. Fully provable. |

### Why a single package

`Termicap.Color` contains:
- The `Color_Level` enumeration type (FUNC-CLR-001).
- The `Detect_Color_Level` function (FUNC-CLR-002).
- Internal helper functions for each detection phase.

No child package is needed because:
1. There is no FFI boundary -- all OS interaction happened upstream (Environment capture, TTY detection).
2. All logic operates on the `Environment` snapshot and a `Boolean` parameter.
3. The entire package is SPARK-provable.

This is unlike `Termicap.Environment` (which needs a non-SPARK `Capture` child) and unlike `Termicap.TTY` (which needs `SPARK_Mode => Off` in the body for the `isatty()` FFI call).

### Relationship to other packages

`Termicap.Color` depends on `Termicap.Environment` for:
- `Environment` type (passed as parameter)
- `Contains` function (presence checks for NO_COLOR, FORCE_COLOR, etc.)
- `Value` function (value retrieval for TERM, COLORTERM, etc.)
- `Equal_Case_Insensitive` function (case-insensitive value comparison)

`Termicap.Color` does **not** depend on `Termicap.TTY`. The TTY status is passed as a `Boolean` parameter, preserving the SPARK boundary. The caller captures TTY status once in an Ada-only region and passes it in.

---

## C. Type Design

### Color_Level enumeration (FUNC-CLR-001)

```ada
type Color_Level is (None, Basic_16, Extended_256, True_Color);
```

The four values represent the terminal color capability tiers defined by the ECMA-48 / ANSI standard and universally adopted by modern terminal libraries:

| Value | Colors | SGR Format | Description |
|-------|--------|-----------|-------------|
| `None` | 0 | No escape sequences | Dumb terminal, NO_COLOR active, or non-TTY |
| `Basic_16` | 16 | `ESC[31m` etc. | 8 standard + 8 bright ANSI colors |
| `Extended_256` | 256 | `ESC[38;5;Nm` | 256-color palette |
| `True_Color` | 16,777,216 | `ESC[38;2;R;G;Bm` | 24-bit RGB |

**Ordering property:** Ada enumerations have a natural ordering based on declaration order. `None < Basic_16 < Extended_256 < True_Color` is guaranteed by the language. This enables:

```ada
--  Floor mechanism: can only go up
Level := Color_Level'Max (Level, Extended_256);

--  Comparison: check if at least 256-color capable
if Level >= Extended_256 then ...
```

The `Color_Level'Max` function is the key primitive for the "floor" mechanism used throughout the detection algorithm. It is a built-in attribute of Ada enumeration types, requires no custom implementation, and is SPARK-provable.

### No additional types needed

The detection function uses only:
- `Color_Level` (the result type)
- `Environment` (from `Termicap.Environment`, the env snapshot parameter)
- `Boolean` (the `Is_TTY` parameter)
- `String` (for intermediate value retrieval from the environment)

No helper types, discriminated records, or access types are required. The design is deliberately minimal.

---

## D. Function Design

### Primary function: Detect_Color_Level (FUNC-CLR-002, FUNC-CLR-014)

```ada
--  @summary Detect the color level supported by the terminal.
--  @param Env    An immutable environment variable snapshot.
--  @param Is_TTY Whether the target output stream is connected to a TTY.
--  @return The detected color level.
--  @relation(FUNC-CLR-002): Pure detection function
--  @relation(FUNC-CLR-014): SPARK Silver provability
--  @relation(FUNC-CLR-015): Priority order cascade
function Detect_Color_Level
   (Env    : Environment;
    Is_TTY : Boolean) return Color_Level
   with Global => null;
```

**SPARK contracts:**
- `Global => null` -- confirms no hidden state dependencies. All inputs are explicit parameters.
- No `Pre` condition is needed -- the function is total (defined for all inputs).
- A `Post` condition could assert `Detect_Color_Level'Result >= None`, but this is trivially true for all enumeration values and adds no verification value.

### Internal helper functions

The body of `Detect_Color_Level` delegates to helper functions for each detection phase. These are declared in the package body (not visible in the spec) and share the same SPARK provability.

See [ADR-0004](../adr/0004-color-detection-decomposed-helpers.md) for the rationale on decomposed helpers vs. a monolithic function.

```ada
--  Phase 1: Parse FORCE_COLOR and return the floor level.
--  Returns None if FORCE_COLOR is absent or "0"/"false".
function Parse_Force_Color (Env : Environment) return Color_Level
   with Global => null;

--  Phase 2: Check CLICOLOR_FORCE and return the floor level.
--  Returns None if CLICOLOR_FORCE is absent or "0".
function Parse_Clicolor_Force (Env : Environment) return Color_Level
   with Global => null;

--  Phase 3: Check NO_COLOR presence (FUNC-CLR-003).
--  Returns True if NO_COLOR is present (any value, including empty).
function Has_No_Color (Env : Environment) return Boolean
   with Global => null;

--  Phase 4: Check TERM=dumb (FUNC-CLR-006).
function Is_Dumb_Terminal (Env : Environment) return Boolean
   with Global => null;

--  Phase 5: Detect CI environment and return color level (FUNC-CLR-011).
function Detect_CI_Color (Env : Environment) return Color_Level
   with Global => null;

--  Phase 7: Detect from COLORTERM (FUNC-CLR-008).
--  Applies multiplexer cap (FUNC-CLR-013).
function Detect_Colorterm (Env : Environment) return Color_Level
   with Global => null;

--  Phase 8: Detect from TERM_PROGRAM (FUNC-CLR-010).
function Detect_Term_Program (Env : Environment) return Color_Level
   with Global => null;

--  Phase 9: Detect from TERM suffix/pattern (FUNC-CLR-009).
function Detect_Term_Pattern (Env : Environment) return Color_Level
   with Global => null;

--  Phase 10: Check CLICOLOR (FUNC-CLR-012).
function Has_Clicolor (Env : Environment) return Boolean
   with Global => null;
```

Each helper is a pure function with `Global => null`. They return either a `Color_Level` (for phases that can establish a level) or a `Boolean` (for phases that are yes/no gates).

### String suffix matching helper

For TERM suffix detection ("-256color", "-256"), a local helper function performs suffix matching on Ada strings:

```ada
function Ends_With (Source : String; Suffix : String) return Boolean
   with Global => null;
```

Implementation:

```ada
function Ends_With (Source : String; Suffix : String) return Boolean is
begin
   if Source'Length < Suffix'Length then
      return False;
   end if;
   return Equal_Case_Insensitive
      (Source (Source'Last - Suffix'Length + 1 .. Source'Last), Suffix);
end Ends_With;
```

This uses `Equal_Case_Insensitive` from `Termicap.Environment` for consistency with the rest of the detection logic.

### String substring matching helper

For TERM pattern detection (contains "color", "ansi", etc.), a local helper performs substring matching:

```ada
function Contains_Substring (Source : String; Pattern : String) return Boolean
   with Global => null;
```

Implementation uses a simple sliding window:

```ada
function Contains_Substring (Source : String; Pattern : String) return Boolean is
begin
   if Pattern'Length = 0 then
      return True;
   end if;
   if Source'Length < Pattern'Length then
      return False;
   end if;
   for I in Source'First .. Source'Last - Pattern'Length + 1 loop
      if Equal_Case_Insensitive
         (Source (I .. I + Pattern'Length - 1), Pattern)
      then
         return True;
      end if;
   end loop;
   return False;
end Contains_Substring;
```

Both `Ends_With` and `Contains_Substring` are bounded loops over string indices, which the SPARK prover can discharge without manual lemmas.

---

## E. Algorithm Design

### The 11-step priority cascade (FUNC-CLR-015)

The `Detect_Color_Level` body implements the priority cascade as a linear sequence of checks. A local variable `Floor` tracks the minimum color level established by force overrides (steps 1-2). A separate local variable `Level` accumulates the detected level from heuristic phases (steps 5-10).

```ada
function Detect_Color_Level
   (Env    : Environment;
    Is_TTY : Boolean) return Color_Level
is
   Floor       : Color_Level := None;
   Force_Set   : Boolean := False;
   CI_Level    : Color_Level;
   Heuristic   : Color_Level := None;
begin
   --  Step 1: FORCE_COLOR (FUNC-CLR-004)
   if Contains (Env, "FORCE_COLOR") then
      Floor := Parse_Force_Color (Env);
      Force_Set := Floor > None;
      --  FORCE_COLOR=0/"false" means Floor stays None and Force_Set stays False,
      --  but we still skip the NO_COLOR and dumb checks below because
      --  FORCE_COLOR was explicitly set.
      if Contains (Env, "FORCE_COLOR") and then
         (Equal_Case_Insensitive (Value (Env, "FORCE_COLOR"), "0") or
          Equal_Case_Insensitive (Value (Env, "FORCE_COLOR"), "false"))
      then
         return None;  -- FORCE_COLOR=0 explicitly disables
      end if;
   end if;

   --  Step 2: CLICOLOR_FORCE (FUNC-CLR-005)
   if not Force_Set then
      Floor := Color_Level'Max (Floor, Parse_Clicolor_Force (Env));
      Force_Set := Floor > None;
   end if;

   --  Step 3: NO_COLOR (FUNC-CLR-003)
   if not Force_Set and then Has_No_Color (Env) then
      return None;
   end if;

   --  Step 4: TERM=dumb (FUNC-CLR-006)
   if Is_Dumb_Terminal (Env) then
      return Floor;  -- Floor is None unless steps 1-2 set it
   end if;

   --  Step 5: CI environment (FUNC-CLR-011)
   CI_Level := Detect_CI_Color (Env);
   if CI_Level > None then
      Heuristic := Color_Level'Max (Heuristic, CI_Level);
   end if;

   --  Step 6: TTY gate (FUNC-CLR-007)
   if not Is_TTY and Floor = None and Heuristic = None then
      return None;
   end if;

   --  Step 7: COLORTERM (FUNC-CLR-008)
   Heuristic := Color_Level'Max (Heuristic, Detect_Colorterm (Env));

   --  Step 8: TERM_PROGRAM (FUNC-CLR-010)
   Heuristic := Color_Level'Max (Heuristic, Detect_Term_Program (Env));

   --  Step 9: TERM suffix/pattern (FUNC-CLR-009)
   Heuristic := Color_Level'Max (Heuristic, Detect_Term_Pattern (Env));

   --  Step 10: CLICOLOR (FUNC-CLR-012)
   if Has_Clicolor (Env) then
      Heuristic := Color_Level'Max (Heuristic, Basic_16);
   end if;

   --  Step 11: Default (FUNC-CLR-015)
   return Color_Level'Max (Floor, Heuristic);
end Detect_Color_Level;
```

### The floor mechanism

The "floor" is a `Color_Level` variable that can only go up, never down. It is established by FORCE_COLOR (step 1) or CLICOLOR_FORCE (step 2). The final return value is `Color_Level'Max(Floor, Heuristic)`, ensuring that the floor is never undercut by heuristic detection.

The `Force_Set` Boolean tracks whether a non-zero floor was established. When `Force_Set` is True:
- NO_COLOR is ignored (step 3 is skipped).
- The TTY gate is bypassed (step 6 checks `Floor = None`).
- TERM=dumb still returns `Floor` (not `None`).

When `Force_Set` is False and `Floor` is `None`, the function behaves as if no override is active, and NO_COLOR / TTY gate can return `None`.

### FORCE_COLOR value parsing (FUNC-CLR-004)

See [ADR-0005](../adr/0005-force-color-value-parsing-strategy.md) for the design decision on string-to-enum mapping.

Since Ada `case` requires discrete types, we first classify the raw string into
a local enumeration and then dispatch with a clean `case` statement:

```ada
type Force_Color_Token is
   (FC_Zero, FC_False, FC_One, FC_True, FC_Empty,
    FC_Two, FC_Three, FC_Other);

function Classify_Force_Color (Val : String) return Force_Color_Token
   with Global => null;

function Classify_Force_Color (Val : String) return Force_Color_Token is
begin
   if Val'Length = 0                          then return FC_Empty;
   elsif Equal_Case_Insensitive (Val, "0")    then return FC_Zero;
   elsif Equal_Case_Insensitive (Val, "false") then return FC_False;
   elsif Equal_Case_Insensitive (Val, "1")    then return FC_One;
   elsif Equal_Case_Insensitive (Val, "true") then return FC_True;
   elsif Equal_Case_Insensitive (Val, "2")    then return FC_Two;
   elsif Equal_Case_Insensitive (Val, "3")    then return FC_Three;
   else                                            return FC_Other;
   end if;
end Classify_Force_Color;

function Parse_Force_Color (Env : Environment) return Color_Level is
   Token : constant Force_Color_Token :=
      Classify_Force_Color (Value (Env, "FORCE_COLOR"));
begin
   case Token is
      when FC_Zero | FC_False      => return None;
      when FC_Three                => return True_Color;
      when FC_Two                  => return Extended_256;
      when FC_One | FC_True
         | FC_Empty | FC_Other     => return Basic_16;
   end case;
end Parse_Force_Color;
```

The classify-then-case pattern separates string matching from decision logic, making the mapping immediately visible. The `case` statement is exhaustive by construction — the compiler enforces coverage of all `Force_Color_Token` values. The mapping is:

| FORCE_COLOR value | Result |
|-------------------|--------|
| `"3"` | `True_Color` |
| `"2"` | `Extended_256` |
| `"1"` | `Basic_16` |
| `"true"` | `Basic_16` |
| `""` (empty) | `Basic_16` |
| `"0"` | `None` |
| `"false"` | `None` |
| Any other value | `Basic_16` |

### COLORTERM detection with multiplexer cap (FUNC-CLR-008, FUNC-CLR-013)

```ada
function Detect_Colorterm (Env : Environment) return Color_Level is
   CT   : constant String := Value (Env, "COLORTERM");
   Term : constant String := Value (Env, "TERM");
begin
   if not Contains (Env, "COLORTERM") then
      return None;
   end if;

   if Equal_Case_Insensitive (CT, "truecolor") or
      Equal_Case_Insensitive (CT, "24bit")
   then
      --  Multiplexer cap (FUNC-CLR-013): screen cannot pass TrueColor
      if Ends_With_Screen_Prefix (Term) and then
         not Equal_Case_Insensitive (Value (Env, "TERM_PROGRAM"), "tmux")
      then
         return Extended_256;
      end if;
      return True_Color;
   end if;

   --  Any other non-empty COLORTERM value -> at least Basic_16
   return Basic_16;
end Detect_Colorterm;
```

Where `Ends_With_Screen_Prefix` is a helper that checks if TERM starts with "screen" (case-insensitive). This directly implements the multiplexer awareness from FUNC-CLR-013.

### TERM suffix matching (FUNC-CLR-009)

```ada
function Detect_Term_Pattern (Env : Environment) return Color_Level is
   Term : constant String := Value (Env, "TERM");
begin
   if Term'Length = 0 then
      return None;
   end if;

   --  256-color detection: TERM ends with "-256color" or "-256"
   if Ends_With (Term, "-256color") or Ends_With (Term, "-256") then
      return Extended_256;
   end if;

   --  Basic color detection: known terminal type identifiers
   if Contains_Substring (Term, "xterm") or
      Contains_Substring (Term, "screen") or
      Contains_Substring (Term, "vt100") or
      Contains_Substring (Term, "vt220") or
      Contains_Substring (Term, "rxvt") or
      Contains_Substring (Term, "color") or
      Contains_Substring (Term, "ansi") or
      Contains_Substring (Term, "cygwin") or
      Contains_Substring (Term, "linux")
   then
      return Basic_16;
   end if;

   return None;
end Detect_Term_Pattern;
```

### TERM_PROGRAM detection with version gating (FUNC-CLR-010)

Same classify-then-case pattern as `Parse_Force_Color`:

```ada
type Term_Program_Token is
   (TP_ITerm, TP_Apple_Terminal, TP_VSCode, TP_Other);

function Classify_Term_Program (TP : String) return Term_Program_Token
   with Global => null;

function Classify_Term_Program (TP : String) return Term_Program_Token is
begin
   if Equal_Case_Insensitive (TP, "iTerm.app")      then return TP_ITerm;
   elsif Equal_Case_Insensitive (TP, "Apple_Terminal") then return TP_Apple_Terminal;
   elsif Equal_Case_Insensitive (TP, "vscode")       then return TP_VSCode;
   else                                                    return TP_Other;
   end if;
end Classify_Term_Program;

function Detect_Term_Program (Env : Environment) return Color_Level is
   TP : constant String := Value (Env, "TERM_PROGRAM");
begin
   if not Contains (Env, "TERM_PROGRAM") then
      return None;
   end if;

   case Classify_Term_Program (TP) is
      when TP_ITerm =>
         --  Version-gated: iTerm.app v3+ supports TrueColor
         declare
            Ver : constant String := Value (Env, "TERM_PROGRAM_VERSION");
         begin
            if Ver'Length > 0 and then Ver (Ver'First) >= '3' then
               return True_Color;
            end if;
         end;
         return Extended_256;  -- iTerm.app < v3 or version absent

      when TP_Apple_Terminal | TP_VSCode =>
         return Extended_256;

      when TP_Other =>
         return None;
   end case;
end Detect_Term_Program;
```

The version check for iTerm.app uses a simple first-character comparison (`>= '3'`). This is sufficient because TERM_PROGRAM_VERSION for iTerm is formatted as "3.x.y", and the first character being '3' or higher indicates version 3+. This avoids full version string parsing and keeps the function SPARK-provable with no integer conversion.

### CI environment detection (FUNC-CLR-011)

```ada
function Detect_CI_Color (Env : Environment) return Color_Level is
begin
   --  Specific CI environments with TrueColor support
   if (Contains (Env, "GITHUB_ACTIONS") and then
       Equal_Case_Insensitive (Value (Env, "GITHUB_ACTIONS"), "true")) or
      Contains (Env, "GITEA_ACTIONS") or
      Contains (Env, "CIRCLECI")
   then
      return True_Color;
   end if;

   --  Specific CI environments with Basic color support
   if Contains (Env, "TRAVIS") or
      Contains (Env, "APPVEYOR") or
      Contains (Env, "GITLAB_CI") or
      Contains (Env, "BUILDKITE") or
      Contains (Env, "DRONE")
   then
      return Basic_16;
   end if;

   --  Generic CI fallback
   if Contains (Env, "CI") then
      return Basic_16;
   end if;

   return None;
end Detect_CI_Color;
```

---

## F. SPARK Strategy

### SPARK_Mode placement

```ada
package Termicap.Color
   with SPARK_Mode
is
   --  All declarations are SPARK-visible and provable.
end Termicap.Color;

package body Termicap.Color
   with SPARK_Mode
is
   --  All implementations are SPARK-provable.
   --  No SPARK_Mode => Off region is needed.
end Termicap.Color;
```

This is a fully SPARK package -- both spec and body. No FFI boundary exists because:
- Environment data arrives as an `Environment` parameter (already captured).
- TTY status arrives as a `Boolean` parameter (already queried).
- All logic is pure string comparison and enumeration operations.

### Global contracts

All functions have `Global => null`:

```ada
function Detect_Color_Level
   (Env : Environment; Is_TTY : Boolean) return Color_Level
   with Global => null;
```

The internal helpers also have `Global => null`. Since the helpers are body-local, their contracts are not visible in the spec, but they are still verified by GNATprove.

### Inlining of helpers

All body-local helper functions (classifiers and detection-phase helpers) shall be
annotated with `pragma Inline`:

```ada
pragma Inline (Classify_Force_Color);
pragma Inline (Parse_Force_Color);
pragma Inline (Parse_Clicolor_Force);
pragma Inline (Has_No_Color);
pragma Inline (Is_Dumb_Terminal);
pragma Inline (Detect_CI_Color);
pragma Inline (Classify_Term_Program);
pragma Inline (Detect_Term_Program);
pragma Inline (Detect_Colorterm);
pragma Inline (Detect_Term_Pattern);
pragma Inline (Has_Clicolor);
pragma Inline (Ends_With);
pragma Inline (Contains_Substring);
```

These helpers are small, called once each from the cascade, and their call overhead
would otherwise dominate the actual string comparison work. `pragma Inline` gives
the compiler a strong hint to eliminate the call overhead. Note that `pragma Inline`
is a recommendation, not a mandate — GNAT will honour it when the body is visible
in the same compilation unit (which it is, since all helpers are body-local).

### Proof obligations and discharge strategy

The SPARK prover must discharge the following obligations:

| Obligation | Source | Discharge Strategy |
|-----------|--------|-------------------|
| Range checks on String indexing | `Ends_With`, `Contains_Substring`, version check | Guard with `'Length` checks before indexing |
| Loop termination | `Contains_Substring` loop | Bounded by `Source'Last - Pattern'Length + 1` |
| No overflow in index arithmetic | `Source'Last - Suffix'Length + 1` | Precluded by `Source'Length >= Suffix'Length` guard |
| Global => null compliance | All functions | No global variables referenced; all data flows through parameters |
| Absence of runtime exceptions | All functions | No dynamic allocation, no unbounded loops, no division |

The design avoids:
- Dynamic memory allocation (no `new`, no unbounded containers).
- Unbounded loops (all loops iterate over string indices with known bounds).
- Integer arithmetic that could overflow (all indices are `Natural`/`Positive`, and guards prevent underflow).
- Access types (no pointers).
- Exception handlers (total functions, no failure cases).

### No abstract state

Like `Termicap.Environment`, this package does not use abstract state. All data flows through explicit parameters. This is the simplest and most verifiable approach.

---

## G. Dependencies

### From `Termicap.Environment`

- `Environment` type -- parameter to `Detect_Color_Level`
- `Contains` function -- presence checks for env vars
- `Value` function -- value retrieval for env vars
- `Equal_Case_Insensitive` function -- case-insensitive string comparison

### From `Termicap.TTY`

**None.** The TTY status is passed as a `Boolean` parameter. This decoupling is deliberate:
- It preserves the SPARK boundary (TTY detection is FFI-based).
- It allows testing with mock TTY status.
- It follows the same pattern used in `Termicap.TTY`'s own tech spec (Section D, "How downstream packages use Is_TTY").

### From `functional` crate

Nothing. This package does not use Result types. All functions are total with well-defined return values for all inputs.

### From `sparklib` crate

Nothing directly. `Termicap.Color` uses `Termicap.Environment`'s API, which internally uses sparklib containers, but there is no direct dependency.

### From the Ada standard library

Nothing beyond what `Termicap.Environment` already provides. No additional imports are needed.

### New dependencies

None required.

---

## H. Error Handling

### Analysis: Is error handling needed?

No. The detection function is a total function:

- Every combination of `Environment` and `Is_TTY` produces a valid `Color_Level`.
- There is no "error case" -- an empty environment with `Is_TTY = False` simply returns `None`.
- Invalid or unrecognized FORCE_COLOR values default to `Basic_16` (FUNC-CLR-004), not an error.
- Missing environment variables are handled gracefully by `Contains` returning `False` and `Value` returning `""`.

This mirrors the approach taken by all reference frameworks: color detection functions always return a valid level, never an error.

---

## I. File Layout

| File | SPARK | Description |
|------|-------|-------------|
| `src/termicap-color.ads` | Yes | `Color_Level` type, `Detect_Color_Level` function |
| `src/termicap-color.adb` | Yes | Implementation of detection algorithm and all helpers |

### File naming rationale

File names follow the Ada convention of lowercase with dashes matching the package hierarchy:
- `Termicap.Color` maps to `termicap-color.ads` / `.adb`

No changes to `termicap.gpr` are needed since all files are in the existing `src/` source directory.

---

## J. Testing Strategy

### How to test with mock environments

The snapshot-based design inherited from F1 makes testing straightforward. Tests construct `Environment` values programmatically and pass them to `Detect_Color_Level` with a known `Is_TTY` value:

```ada
declare
   Env : Environment := EMPTY_ENVIRONMENT;
begin
   Insert (Env, "COLORTERM", "truecolor");
   pragma Assert (Detect_Color_Level (Env, Is_TTY => True) = True_Color);
end;
```

No mocking framework needed. No process environment touched. Tests are parallelizable and deterministic.

### Key test scenarios

#### FUNC-CLR-001: Color_Level enumeration properties

```ada
pragma Assert (Color_Level'First = None);
pragma Assert (Color_Level'Last  = True_Color);
pragma Assert (None < Basic_16);
pragma Assert (Basic_16 < Extended_256);
pragma Assert (Extended_256 < True_Color);
pragma Assert (Color_Level'Max (Basic_16, Extended_256) = Extended_256);
```

#### FUNC-CLR-002: Pure function, no side effects

- Call `Detect_Color_Level` twice with same inputs; verify same result.
- Verify the function compiles with `Global => null` (SPARK contract).

#### FUNC-CLR-003: NO_COLOR compliance

- `NO_COLOR=""` (empty) present, no FORCE_COLOR -> `None`.
- `NO_COLOR="1"` present, no FORCE_COLOR -> `None`.
- `NO_COLOR` absent -> detection proceeds normally.
- `NO_COLOR` present but `FORCE_COLOR="1"` -> `Basic_16` (FORCE_COLOR overrides).

#### FUNC-CLR-004: FORCE_COLOR override

- `FORCE_COLOR="3"` -> `True_Color` regardless of other vars.
- `FORCE_COLOR="2"` -> `Extended_256` regardless of other vars.
- `FORCE_COLOR="1"` -> at least `Basic_16`.
- `FORCE_COLOR="0"` -> `None` even with COLORTERM=truecolor.
- `FORCE_COLOR="false"` -> `None`.
- `FORCE_COLOR="true"` -> `Basic_16`.
- `FORCE_COLOR=""` (empty) -> `Basic_16`.
- `FORCE_COLOR="xyz"` (unknown) -> `Basic_16`.
- `FORCE_COLOR="3"` with `TERM=dumb` -> `True_Color` (overrides dumb).
- `FORCE_COLOR="2"` with `Is_TTY=False` -> `Extended_256` (overrides TTY gate).

#### FUNC-CLR-005: CLICOLOR_FORCE

- `CLICOLOR_FORCE="1"`, `Is_TTY=False` -> at least `Basic_16`.
- `CLICOLOR_FORCE="0"` -> no effect (treated as not set).
- `CLICOLOR_FORCE="1"` with `FORCE_COLOR="3"` -> `True_Color` (FORCE_COLOR supersedes).
- `CLICOLOR_FORCE="1"` with `NO_COLOR` present -> `Basic_16` (CLICOLOR_FORCE overrides NO_COLOR).

#### FUNC-CLR-006: TERM=dumb

- `TERM="dumb"`, no force override -> `None`.
- `TERM="dumb"`, `FORCE_COLOR="1"` -> `Basic_16`.
- `TERM="DUMB"` (uppercase) -> `None` (case-insensitive).

#### FUNC-CLR-007: TTY gate

- `Is_TTY=False`, no force override, no CI -> `None`.
- `Is_TTY=True`, no env vars -> `None` (no positive signal).
- `Is_TTY=False`, `FORCE_COLOR="1"` -> `Basic_16` (force overrides gate).

#### FUNC-CLR-008: COLORTERM detection

- `COLORTERM="truecolor"` -> `True_Color`.
- `COLORTERM="24bit"` -> `True_Color`.
- `COLORTERM="TrueColor"` (mixed case) -> `True_Color`.
- `COLORTERM="yes"` -> `Basic_16`.
- `COLORTERM=""` absent -> no effect.

#### FUNC-CLR-009: TERM-based detection

- `TERM="xterm-256color"` -> `Extended_256`.
- `TERM="screen-256color"` -> `Extended_256`.
- `TERM="xterm"` -> `Basic_16`.
- `TERM="linux"` -> `Basic_16`.
- `TERM="rxvt-unicode"` -> `Basic_16` (contains "rxvt").
- `TERM="unknown-terminal"` -> `None`.

#### FUNC-CLR-010: TERM_PROGRAM detection

- `TERM_PROGRAM="iTerm.app"`, `TERM_PROGRAM_VERSION="3.4.0"` -> `True_Color`.
- `TERM_PROGRAM="iTerm.app"`, `TERM_PROGRAM_VERSION="2.1.0"` -> `Extended_256`.
- `TERM_PROGRAM="iTerm.app"`, no version -> `Extended_256`.
- `TERM_PROGRAM="Apple_Terminal"` -> `Extended_256`.
- `TERM_PROGRAM="vscode"` -> `Extended_256`.

#### FUNC-CLR-011: CI environment detection

- `CI="true"`, `GITHUB_ACTIONS="true"` -> `True_Color`.
- `CI="true"`, `TRAVIS` present -> `Basic_16`.
- `CI="true"`, no specific CI var -> `Basic_16`.
- `CI` absent -> no CI detection.
- CI detection with `Is_TTY=False` -> still returns color (CI before TTY gate).

#### FUNC-CLR-012: CLICOLOR

- `CLICOLOR="1"`, `Is_TTY=True`, no other signals -> `Basic_16`.
- `CLICOLOR="0"` -> no effect.
- `CLICOLOR="1"`, `Is_TTY=False` -> `None` (CLICOLOR is post-TTY gate).

#### FUNC-CLR-013: Multiplexer awareness

- `TERM="screen"`, `COLORTERM="truecolor"` -> `Extended_256` (screen caps at 256).
- `TERM="screen-256color"`, `COLORTERM="truecolor"`, `TERM_PROGRAM="tmux"` -> `True_Color` (tmux exception).
- `TERM="tmux-256color"`, `COLORTERM="truecolor"` -> `True_Color`.
- `FORCE_COLOR="3"`, `TERM="screen"` -> `True_Color` (force override not subject to cap).

#### FUNC-CLR-014: SPARK provability

- Verify with `alr exec -- gnatprove -P termicap.gpr` that all proof obligations are discharged.
- Confirm `Global => null` on `Detect_Color_Level`.

#### FUNC-CLR-015: Priority order

- Combined scenario: `FORCE_COLOR="2"`, `NO_COLOR` present, `COLORTERM="truecolor"` -> `Extended_256` (FORCE_COLOR=2 is the floor; NO_COLOR is ignored because floor is non-zero; COLORTERM would give True_Color but the function returns max(Floor=Extended_256, Heuristic=True_Color) = True_Color).
  Wait -- this needs careful analysis. FORCE_COLOR="2" sets Floor=Extended_256 and Force_Set=True. Step 3 (NO_COLOR) is skipped. Steps 7+ detect COLORTERM=truecolor -> Heuristic=True_Color. Final result = max(Extended_256, True_Color) = True_Color.
  This is correct: FORCE_COLOR="2" establishes a *floor* of 256, and COLORTERM can raise it to TrueColor. The floor mechanism only prevents going *below* the floor.

### Test file location

| File | Description |
|------|-------------|
| `tests/src/test_color.adb` | Unit tests for Color_Level type and Detect_Color_Level function |

---

## Appendix: API Signatures

### Complete spec sketch

```ada
-------------------------------------------------------------------------------
--  Termicap.Color - Color Level Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects the color output capability of a terminal from environment
--  variable heuristics.
--
--  @description
--  Provides a pure, SPARK-provable function that determines the terminal's
--  color level (None, 16, 256, or TrueColor) from an immutable environment
--  snapshot and a TTY status flag.  The function performs no OS calls and
--  reads no global state.
--
--  The detection algorithm implements an 11-step priority cascade defined
--  by FUNC-CLR-015, supporting NO_COLOR, FORCE_COLOR, CLICOLOR_FORCE,
--  CLICOLOR, COLORTERM, TERM, TERM_PROGRAM, and CI environment detection.
--
--  Requirements Coverage:
--    - @relation(FUNC-CLR-001): Color_Level enumeration type
--    - @relation(FUNC-CLR-002): Pure detection function signature
--    - @relation(FUNC-CLR-003): NO_COLOR compliance
--    - @relation(FUNC-CLR-004): FORCE_COLOR override
--    - @relation(FUNC-CLR-005): CLICOLOR_FORCE support
--    - @relation(FUNC-CLR-006): TERM=dumb handling
--    - @relation(FUNC-CLR-007): TTY gate
--    - @relation(FUNC-CLR-008): COLORTERM detection
--    - @relation(FUNC-CLR-009): TERM-based color detection
--    - @relation(FUNC-CLR-010): TERM_PROGRAM detection
--    - @relation(FUNC-CLR-011): CI environment detection
--    - @relation(FUNC-CLR-012): CLICOLOR support
--    - @relation(FUNC-CLR-013): Multiplexer awareness
--    - @relation(FUNC-CLR-014): SPARK Silver provability
--    - @relation(FUNC-CLR-015): Detection priority order

with Termicap.Environment; use Termicap.Environment;

package Termicap.Color
   with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-CLR-001)
   ---------------------------------------------------------------------------

   --  @summary Terminal color capability level.
   --  @description Ordered enumeration: None < Basic_16 < Extended_256 < True_Color.
   --  Supports Color_Level'Max for floor operations.
   --  @relation(FUNC-CLR-001): Four-valued ordered enumeration
   type Color_Level is (None, Basic_16, Extended_256, True_Color);

   ---------------------------------------------------------------------------
   --  Detection (FUNC-CLR-002 through FUNC-CLR-015)
   ---------------------------------------------------------------------------

   --  @summary Detect the color level supported by the terminal.
   --  @param Env    An immutable environment variable snapshot.
   --  @param Is_TTY Whether the target output stream is connected to a TTY.
   --  @return The detected color level based on the 11-step priority cascade.
   --  @relation(FUNC-CLR-002): Pure detection function
   --  @relation(FUNC-CLR-014): SPARK Silver provability
   --  @relation(FUNC-CLR-015): Detection priority order
   function Detect_Color_Level
      (Env    : Environment;
       Is_TTY : Boolean) return Color_Level
      with Global => null;

end Termicap.Color;
```

---

## Appendix: Requirements Traceability

| Requirement | API Element | SPARK | Notes |
|-------------|-------------|-------|-------|
| FUNC-CLR-001 | `Color_Level` enumeration type | Silver | Four ordered values: None, Basic_16, Extended_256, True_Color |
| FUNC-CLR-002 | `Detect_Color_Level` function signature | Silver | `Global => null`, pure function |
| FUNC-CLR-003 | `Has_No_Color` helper, step 3 of cascade | Silver | `Contains(Env, "NO_COLOR")` -- presence check, not value check |
| FUNC-CLR-004 | `Classify_Force_Color` + `Parse_Force_Color` helpers, step 1 of cascade | Silver | Classify-then-case pattern: string → `Force_Color_Token` → `Color_Level` |
| FUNC-CLR-005 | `Parse_Clicolor_Force` helper, step 2 of cascade | Silver | Presence + value != "0" check |
| FUNC-CLR-006 | `Is_Dumb_Terminal` helper, step 4 of cascade | Silver | Case-insensitive TERM="dumb" check |
| FUNC-CLR-007 | TTY gate, step 6 of cascade | Silver | `not Is_TTY and Floor = None and Heuristic = None` |
| FUNC-CLR-008 | `Detect_Colorterm` helper, step 7 of cascade | Silver | COLORTERM "truecolor"/"24bit" with multiplexer cap |
| FUNC-CLR-009 | `Detect_Term_Pattern` helper, step 9 of cascade | Silver | Suffix "-256color"/"-256" and substring matching |
| FUNC-CLR-010 | `Classify_Term_Program` + `Detect_Term_Program` helpers, step 8 of cascade | Silver | Classify-then-case pattern: string → `Term_Program_Token` → version-gated level |
| FUNC-CLR-011 | `Detect_CI_Color` helper, step 5 of cascade | Silver | CI variable presence checks |
| FUNC-CLR-012 | `Has_Clicolor` helper, step 10 of cascade | Silver | CLICOLOR presence + value != "0" |
| FUNC-CLR-013 | Multiplexer cap in `Detect_Colorterm` | Silver | TERM starts with "screen" and TERM_PROGRAM != "tmux" -> cap at Extended_256 |
| FUNC-CLR-014 | `Global => null` on `Detect_Color_Level`, fully SPARK body | Silver | No dynamic allocation, no unbounded loops |
| FUNC-CLR-015 | 11-step priority cascade in `Detect_Color_Level` body | Silver | Steps 1-11 implemented as linear control flow |
