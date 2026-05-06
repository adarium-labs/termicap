# API Reference: `Termicap.Wcwidth`

Package providing wcwidth() probing for fine-grained Unicode version detection. Calls the POSIX C library `wcwidth()` function on three sentinel codepoints to determine the Unicode version supported by the terminal's C runtime locale, then integrates the result with the environment-variable-based `Unicode_Level` from `Termicap.Unicode`.

**Files:**
- `src/termicap-wcwidth.ads`
- `src/posix/termicap-wcwidth.adb` (POSIX)
- `src/windows/termicap-wcwidth.adb` (Windows stub)
- `src/c/termicap_wcwidth.c` (C helper: portable `LC_CTYPE` value)

**SPARK_Mode:** On (spec); Off (both bodies)
**License:** Apache-2.0

---

## Overview

The WCWIDTH feature refines the coarser `Unicode_Level` result produced by `Termicap.Unicode.Detect_Unicode_Level` (which distinguishes only `None`, `Basic`, and `Extended`) by directly measuring the C runtime locale's Unicode character width table coverage. It does this by calling `wcwidth()` on three sentinel codepoints, each introduced in a specific Unicode version.

The probe tests sentinels in descending Unicode version order for early exit:

| Constant | Codepoint | Unicode Version | Block |
|----------|-----------|-----------------|-------|
| `WCW_SENTINEL_UNI16` | U+1CD00 | 16.0 | Symbols for Legacy Computing Supplement |
| `WCW_SENTINEL_UNI13` | U+1FB38 | 13.0 | Symbols for Legacy Computing |
| `WCW_SENTINEL_UNI3`  | U+28FF  | 3.0  | Braille Patterns |

A `wcwidth()` return value >= 1 for a sentinel indicates that the locale's character width tables include at least that Unicode version.

The result is expressed as a `Wcwidth_Level` enumeration (`Unknown`, `Unicode_3`, `Unicode_13`, `Unicode_16`) and is combined with the env-var-based `Unicode_Level` via `Refine_Unicode_Level`, which applies an upgrade-only rule: the probe may raise but never lower the result established by `Detect_Unicode_Level`.

**Key distinction from active-probing packages:** `Probe_Wcwidth_Level` does not use a `Probe_Session`, does not open `/dev/tty`, and requires no TTY. It reads C locale state — a process-global property independent of terminal connectivity.

**Locale precondition:** `setlocale(LC_CTYPE, "")` (or `setlocale(LC_ALL, "")`) must have been called by the application before `Probe_Wcwidth_Level`. The library does not call `setlocale()` itself; locale initialisation has process-global side effects incompatible with a detection library that claims no side effects. If the locale is "C" or "POSIX" at probe time, the function returns `Unknown` immediately without calling `wcwidth()`.

**Platform behaviour:**
- **POSIX (Linux, macOS, FreeBSD, OpenBSD):** Full probe with locale guard, descending sentinel tests, and per-process cache.
- **Windows:** `Probe_Wcwidth_Level` returns `Unknown` unconditionally. `wcwidth()` is not available on Windows without a POSIX compatibility layer. `Refine_Unicode_Level` then returns `Env_Level` unchanged; the Windows env-var heuristics in `Detect_Unicode_Level` (WT_SESSION, TERM_PROGRAM=vscode, TERMINAL_EMULATOR) are still applied.

The typical caller sequence is:

```ada
--  Phase 1: env-var cascade (pure, SPARK Silver)
Env_Level := Termicap.Unicode.Detect_Unicode_Level (Env);

--  Phase 2: wcwidth probe (FFI, may return Unknown)
Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

--  Phase 3: combine (pure, SPARK Silver)
Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);
--  Final_Level >= Env_Level always (upgrade-only)
```

---

## Types

### `Wcwidth_Level`

```ada
type Wcwidth_Level is
  (Unknown,     --  probe inconclusive or not performed
   Unicode_3,   --  locale supports at least Unicode 3.0
   Unicode_13,  --  locale supports at least Unicode 13.0
   Unicode_16); --  locale supports at least Unicode 16.0
```

Four-level enumeration representing the Unicode version supported by the terminal's C runtime locale character width tables, as determined by `wcwidth()` probing.

| Value | Meaning |
|-------|---------|
| `Unknown` | The probe was not performed or was inconclusive. Either the platform is Windows, the locale is "C"/"POSIX", `setlocale()` returned NULL, or all three sentinels returned a non-positive value from `wcwidth()`. When `Unknown`, `Refine_Unicode_Level` returns `Env_Level` unchanged. |
| `Unicode_3` | The locale's character width tables include at least Unicode 3.0. U+28FF (`WCW_SENTINEL_UNI3`) returned `wcwidth()` >= 1. Maps to at least `Termicap.Unicode.Basic` in `Refine_Unicode_Level`. |
| `Unicode_13` | The locale's character width tables include at least Unicode 13.0. U+1FB38 (`WCW_SENTINEL_UNI13`) returned `wcwidth()` >= 1. Maps to at least `Termicap.Unicode.Basic` in `Refine_Unicode_Level`. |
| `Unicode_16` | The locale's character width tables include at least Unicode 16.0. U+1CD00 (`WCW_SENTINEL_UNI16`) returned `wcwidth()` >= 1. Maps to at least `Termicap.Unicode.Extended` in `Refine_Unicode_Level`. |

Ordering: `Unknown` < `Unicode_3` < `Unicode_13` < `Unicode_16`. Callers may use `Wcwidth_Level'Max` for ceiling operations.

**Why a separate type from `Unicode_Level`:**
- The probe distinguishes three positive levels (`Unicode_3`, `Unicode_13`, `Unicode_16`) while `Unicode_Level` has only two (`Basic`, `Extended`). Collapsing immediately would lose information.
- `Unknown` is semantically distinct from `Unicode_Level.None`: `None` means "confirmed no Unicode support", `Unknown` means "probe not performed or inconclusive". Conflating them would incorrectly demote the env-var result on systems where `wcwidth()` is unavailable.
- Decoupling allows each feature to evolve independently.

**Requirements:** FUNC-WCW-004

---

### `Optional_Wcwidth_Level`

```ada
type Optional_Wcwidth_Level (Is_Set : Boolean := False) is record
   case Is_Set is
      when True  => Level : Wcwidth_Level;
      when False => null;
   end case;
end record;
```

Discriminated record wrapping an optional `Wcwidth_Level` value. Used by the POSIX body to implement the per-process result cache. Declared in the SPARK-visible spec so GNATprove can see its shape when analysing callers.

| Field | Description |
|-------|-------------|
| `Is_Set` | `False` until the first call to `Probe_Wcwidth_Level` completes. `True` on all subsequent calls. |
| `Level` | Present only when `Is_Set = True`. Holds the cached probe result. |

**Requirements:** FUNC-WCW-010

---

## Constants

### `WCW_SENTINEL_UNI3`

```ada
WCW_SENTINEL_UNI3 : constant := 16#28FF#;
```

Unicode codepoint U+28FF BRAILLE PATTERN DOTS-12345678, introduced in Unicode 3.0 (Braille Patterns block, U+2800–U+28FF). A `wcwidth()` return value >= 1 for this codepoint confirms that the locale's character width tables include at least Unicode 3.0.

**Requirements:** FUNC-WCW-002

---

### `WCW_SENTINEL_UNI13`

```ada
WCW_SENTINEL_UNI13 : constant := 16#1FB38#;
```

Unicode codepoint U+1FB38 UPPER LEFT BLOCK SEXTANT-2 AND 5 AND 6, introduced in Unicode 13.0 (Symbols for Legacy Computing block, U+1FB00–U+1FBFF). A `wcwidth()` return value >= 1 for this codepoint confirms that the locale's character width tables include at least Unicode 13.0.

**Requirements:** FUNC-WCW-002

---

### `WCW_SENTINEL_UNI16`

```ada
WCW_SENTINEL_UNI16 : constant := 16#1CD00#;
```

Unicode codepoint U+1CD00 (Symbols for Legacy Computing Supplement block), introduced in Unicode 16.0. A `wcwidth()` return value >= 1 for this codepoint confirms that the locale's character width tables include at least Unicode 16.0.

**Requirements:** FUNC-WCW-002

---

## Functions

### `Probe_Wcwidth_Level`

```ada
function Probe_Wcwidth_Level return Wcwidth_Level;
```

Probe the locale's `wcwidth()` support to determine the Unicode version level of the C runtime character width tables.

**Returns:** The detected `Wcwidth_Level`, or `Unknown` on any failure or inconclusive result.

**Algorithm:** Sentinels are tested in descending Unicode version order for early exit (FUNC-WCW-003):

1. Cache check — if the result has been cached from a prior call, return it immediately (< 1 µs).
2. Locale guard — call `setlocale(LC_CTYPE, NULL)`; if the result is NULL, `"C"`, or `"POSIX"`, cache `Unknown` and return `Unknown` without calling `wcwidth()`.
3. Probe U+1CD00 (`WCW_SENTINEL_UNI16`, Unicode 16): `wcwidth()` >= 1 → cache and return `Unicode_16`.
4. Probe U+1FB38 (`WCW_SENTINEL_UNI13`, Unicode 13): `wcwidth()` >= 1 → cache and return `Unicode_13`.
5. Probe U+28FF (`WCW_SENTINEL_UNI3`, Unicode 3): `wcwidth()` >= 1 → cache and return `Unicode_3`.
6. All probes non-positive → cache and return `Unknown`.

**Returns `Unknown` when:**
- The current LC_CTYPE locale is `"C"` or `"POSIX"` (locale guard, FUNC-WCW-006).
- `setlocale()` returns NULL (locale not initialised).
- All three sentinel codepoints return <= 0 from `wcwidth()` (FUNC-WCW-007, FUNC-WCW-011).
- The platform is Windows (no POSIX `wcwidth()` available, FUNC-WCW-011).

**Precondition (not enforceable at compile time):**
`setlocale(LC_CTYPE, "")` (or equivalent) must have been called by the application before this function (FUNC-WCW-006). The library does not call `setlocale()` itself.

**Thread safety (FUNC-WCW-009):**
Safe to call from multiple threads provided no thread is changing the locale (`setlocale()`) concurrently. The protected-object cache (`Wcwidth_Cache`) makes first-call initialisation safe against concurrent callers; the `wcwidth()` and `setlocale()` FFI calls are outside the protected region. Recommended usage: call once at process startup, before spawning application threads.

**Caching (FUNC-WCW-010):**
The result is cached after the first call. Subsequent calls return the cached value immediately without additional `wcwidth()` calls. The cache is never invalidated; if `setlocale()` is changed after the first probe, the cached value is stale. The recommended usage (probe at startup before locale changes) avoids this issue.

**SPARK boundary (FUNC-WCW-008):**
The function specification is SPARK-visible (`SPARK_Mode => On`) so callers with SPARK contracts can call it and reason about its `Wcwidth_Level` return type. The body is `SPARK_Mode => Off` (C FFI bindings and protected object). GNATprove treats the Off body as an opaque black box.

**Requirements:** FUNC-WCW-003, FUNC-WCW-006, FUNC-WCW-007, FUNC-WCW-010, FUNC-WCW-011, FUNC-WCW-012

---

### `Refine_Unicode_Level`

```ada
function Refine_Unicode_Level
  (Env_Level : Termicap.Unicode.Unicode_Level;
   Wcw_Level : Wcwidth_Level)
   return Termicap.Unicode.Unicode_Level
with Global => null;
```

Combine the env-var-based `Unicode_Level` result with the wcwidth probe result to produce a final refined `Unicode_Level`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env_Level` | in | The Unicode level inferred from environment variables. Typically the result of `Termicap.Unicode.Detect_Unicode_Level (Env)`. |
| `Wcw_Level` | in | The Unicode version level determined by `wcwidth()` probing. Typically the result of `Probe_Wcwidth_Level`. |

**Returns:** The refined `Unicode_Level`: the maximum of `Env_Level` and the `Unicode_Level` mapped from `Wcw_Level`. Always >= `Env_Level` (upgrade-only rule).

**Combination rules (FUNC-WCW-004 mapping):**

| `Wcw_Level` | Effect on result |
|-------------|-----------------|
| `Unknown` | Return `Env_Level` unchanged. The probe contributes nothing when inconclusive. |
| `Unicode_3` | Return `Unicode_Level'Max (Env_Level, Basic)`. At least `Basic`; never demotes `Extended`. |
| `Unicode_13` | Return `Unicode_Level'Max (Env_Level, Basic)`. At least `Basic`; never demotes `Extended`. |
| `Unicode_16` | Return `Unicode_Level'Max (Env_Level, Extended)`. At least `Extended`. |

**Properties:**
- `Result >= Env_Level` for all inputs (upgrade-only rule — the probe never demotes the env-var result).
- If `Wcw_Level = Unknown`, then `Result = Env_Level`.
- If `Wcw_Level = Unicode_16`, then `Result >= Extended`.
- Pure function: no side effects, no global state (`Global => null`). GNATprove Silver-provable.

**Requirements:** FUNC-WCW-005, FUNC-WCW-012

---

## Usage Patterns

### Pattern 1: Full three-phase Unicode detection

The recommended call sequence for complete Unicode detection with wcwidth refinement:

```ada
with Termicap.Environment.Capture;
with Termicap.Unicode;
with Termicap.Wcwidth;

declare
   Env         : Termicap.Environment.Environment;
   Env_Level   : Termicap.Unicode.Unicode_Level;
   Wcw_Level   : Termicap.Wcwidth.Wcwidth_Level;
   Final_Level : Termicap.Unicode.Unicode_Level;
begin
   --  Phase 1: capture environment and run env-var cascade
   Termicap.Environment.Capture.Capture_Current (Env);
   Env_Level := Termicap.Unicode.Detect_Unicode_Level (Env);

   --  Phase 2: wcwidth probe (FFI, may return Unknown)
   --  Precondition: setlocale(LC_CTYPE, "") has been called earlier.
   Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

   --  Phase 3: combine (pure, SPARK Silver)
   Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);

   --  Final_Level >= Env_Level always (upgrade-only)
   case Final_Level is
      when Termicap.Unicode.None     => -- no Unicode rendering
      when Termicap.Unicode.Basic    => -- basic Unicode (emoji, box-drawing)
      when Termicap.Unicode.Extended => -- extended Unicode (sextants, octants)
   end case;
end;
```

### Pattern 2: Standalone wcwidth level (raw probe result)

When the application needs the raw `Wcwidth_Level` without env-var context:

```ada
declare
   Level : Termicap.Wcwidth.Wcwidth_Level;
begin
   Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

   case Level is
      when Termicap.Wcwidth.Unknown    =>
         --  Probe inconclusive; rely on other detection signals
      when Termicap.Wcwidth.Unicode_3  =>
         --  Locale supports at least Unicode 3.0 (Braille, box-drawing)
      when Termicap.Wcwidth.Unicode_13 =>
         --  Locale supports at least Unicode 13.0 (sextant blocks)
      when Termicap.Wcwidth.Unicode_16 =>
         --  Locale supports at least Unicode 16.0 (octant blocks, SignWriting)
   end case;
end;
```

### Pattern 3: Testing Refine_Unicode_Level with known inputs

`Refine_Unicode_Level` is a pure function — it can be tested without any OS or locale interaction:

```ada
--  Verify upgrade-only property for all 12 combinations
declare
   use Termicap.Unicode;
   use Termicap.Wcwidth;
   Result : Unicode_Level;
begin
   --  Unknown: no change
   Result := Refine_Unicode_Level (None, Unknown);
   pragma Assert (Result = None);
   Result := Refine_Unicode_Level (Extended, Unknown);
   pragma Assert (Result = Extended);

   --  Unicode_16: upgrade to at least Extended
   Result := Refine_Unicode_Level (None, Unicode_16);
   pragma Assert (Result = Extended);
   Result := Refine_Unicode_Level (Extended, Unicode_16);
   pragma Assert (Result = Extended);

   --  Unicode_3 / Unicode_13: upgrade to at least Basic
   Result := Refine_Unicode_Level (None, Unicode_3);
   pragma Assert (Result = Basic);
   Result := Refine_Unicode_Level (Extended, Unicode_3);
   pragma Assert (Result = Extended);  -- no downgrade from Extended
end;
```

---

## Preconditions and Constraints

### Locale initialisation (FUNC-WCW-006)

`Probe_Wcwidth_Level` depends on the C runtime locale for meaningful results. The process locale must be initialised before calling this function:

```c
/* In C application startup (before calling into Ada/Termicap): */
setlocale(LC_CTYPE, "");  /* or setlocale(LC_ALL, ""); */
```

Without this call, the "C" locale is active and `wcwidth()` returns -1 for all non-ASCII codepoints, causing the probe to return `Unknown`. The locale guard in `Probe_Wcwidth_Level` detects this condition and returns `Unknown` gracefully rather than a misleading result.

Termicap does not call `setlocale()` itself because doing so would change process-global state — a side effect incompatible with a detection library.

### Thread safety (FUNC-WCW-009)

`Probe_Wcwidth_Level` is safe to call from multiple threads **provided no thread is changing the locale (`setlocale()`) concurrently**. This is because `wcwidth()` reads locale data through a process-global pointer that is not protected against concurrent `setlocale()` calls on glibc or macOS.

Recommended usage:
1. Call `setlocale(LC_CTYPE, "")` at process startup.
2. Call `Probe_Wcwidth_Level` once, before spawning application threads.
3. Use the cached result (via repeated `Probe_Wcwidth_Level` calls, which return instantly) throughout the process lifetime.

---

## Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-WCW-002 | `WCW_SENTINEL_UNI3`, `WCW_SENTINEL_UNI13`, `WCW_SENTINEL_UNI16` constants | Silver (spec) |
| FUNC-WCW-003 | `Probe_Wcwidth_Level` (probing algorithm, descending order) | Spec: Silver, Body: Off |
| FUNC-WCW-004 | `Wcwidth_Level` enumeration | Silver (spec) |
| FUNC-WCW-005 | `Refine_Unicode_Level` function | Silver (spec and body) |
| FUNC-WCW-006 | Locale guard in `Probe_Wcwidth_Level` (documented; not enforceable at compile time) | Off (body only) |
| FUNC-WCW-007 | Graceful handling of `wcwidth()` returning <= 0 | Off (body only) |
| FUNC-WCW-008 | SPARK boundary: spec On, body Off | Silver (spec) / Off (body) |
| FUNC-WCW-009 | Thread safety constraints (documented in spec) | Silver (spec) |
| FUNC-WCW-010 | `Optional_Wcwidth_Level` type; result cache in `Probe_Wcwidth_Level` | Silver (type in spec); Off (cache in body) |
| FUNC-WCW-011 | `Unknown` returned on Windows, C/POSIX locale, all sentinels negative | Off (body) |
| FUNC-WCW-012 | Public API: `Wcwidth_Level`, `Probe_Wcwidth_Level`, `Refine_Unicode_Level` | Silver (spec) |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Wcwidth` entry
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 31: wcwidth probing runtime sequence
- **API Reference: Termicap.Unicode** — `Unicode_Level` type, `Detect_Unicode_Level` function (env-var cascade)
- **Tech Spec WCWIDTH** (`docs/tech-specs/wcwidth.md`) — full design rationale, framework survey, algorithm design, testing strategy
- **ADR-0032** (`docs/adr/0032-wcwidth-package-placement.md`) — package placement rationale (sibling vs. child of `Termicap.Unicode`)
- **ADR-0007** (`docs/adr/0007-unicode-level-three-value-enum.md`) — three-value `Unicode_Level` enumeration rationale
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — platform dispatch via GPR `Source_Dirs`
