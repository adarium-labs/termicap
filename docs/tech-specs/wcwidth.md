# WCWIDTH: wcwidth() Probing for Unicode Level

**Feature:** wcwidth() probing for fine-grained Unicode version detection (Tier 4)
**Requirements:** FUNC-WCW-001 through FUNC-WCW-013 (`docs/requirements/wcwidth.sdoc`)
**Parent Requirements:** UNI (REQ-UNI), CAP (REQ-CAP)
**Status:** Proposed
**Date:** 2026-05-06

---

## 1. Overview

The WCWIDTH feature calls the POSIX C library function `wcwidth()` on a set of
sentinel codepoints to determine the Unicode version supported by the terminal's
C runtime locale. This provides a finer-grained measurement than the
environment-variable-based detection in `Termicap.Unicode` (which only
distinguishes None, Basic, and Extended).

The probe tests three sentinel codepoints in descending Unicode version order:

| Sentinel | Codepoint | Unicode Version | Block |
|----------|-----------|-----------------|-------|
| `WCW_SENTINEL_UNI16` | U+1CD00 | 16.0 | Symbols for Legacy Computing Supplement |
| `WCW_SENTINEL_UNI13` | U+1FB38 | 13.0 | Symbols for Legacy Computing |
| `WCW_SENTINEL_UNI3`  | U+28FF  | 3.0  | Braille Patterns |

A `wcwidth()` return value >= 1 for a sentinel indicates the locale's character
width tables include at least that Unicode version. The result is expressed as a
`Wcwidth_Level` enumeration (`Unknown`, `Unicode_3`, `Unicode_13`, `Unicode_16`)
that is then integrated with the env-var-based `Unicode_Level` via a pure
`Refine_Unicode_Level` function. The wcwidth probe may upgrade but never
downgrade the env-var result.

The probe body is SPARK_Mode => Off (C FFI); the result type, sentinel
constants, and integration function are SPARK_Mode => On and Silver-provable.

---

## 2. Framework Survey

### notcurses (C) -- The canonical wcwidth probing strategy

notcurses is the primary reference for this feature. In
`reference-frameworks/notcurses/src/lib/termdesc.c` (lines 1064--1075), the
terminal description setup probes three codepoints using `wcwidth()`:

```c
// run a wcwidth() to guarantee libc Unicode 3 support
if(wcwidth(L'\u28FF') < 0){
    ti->caps.braille = false;
}
// run a wcwidth() to guarantee libc Unicode 13 support
if(wcwidth(L'\U0001FB38') < 0){
    ti->caps.sextants = false;
}
// run a wcwidth() to guarantee libc Unicode 16 support
if(wcwidth(L'\U0001CD00') < 0){
    ti->caps.octants = false;
}
```

Key observations:

- **Sentinel selection**: notcurses chose codepoints from blocks that were
  introduced in exactly the target Unicode version, ensuring that a positive
  wcwidth result confirms that version's character tables are loaded.
- **Per-capability flags**: notcurses stores the result as three independent
  Boolean flags (`braille`, `sextants`, `octants`), each controlling a specific
  blitter mode. Termicap collapses these into an ordered enumeration because it
  does not need per-blitter granularity.
- **Descending vs. ascending**: notcurses tests in ascending order (3, 13, 16)
  because it wants to disable individual capabilities. Termicap tests in
  descending order (16, 13, 3) because it wants the highest supported level with
  the fewest FFI calls.
- **Locale dependency**: notcurses assumes `setlocale()` has already been called
  (it calls it during `notcurses_init()`). Termicap follows the same pattern but
  documents the requirement rather than calling `setlocale()` itself.
- **Terminal heuristics**: notcurses also sets `sextants`/`octants` based on
  known terminal identifiers (kitty, foot, VTE, WezTerm) as a supplementary
  signal. Termicap separates this concern: terminal identification lives in
  `Termicap.Terminal_Id`, and wcwidth probing is an independent additive signal.

### is-unicode-supported (JavaScript) -- No wcwidth equivalent

is-unicode-supported returns a Boolean from environment heuristics only. It has
no concept of wcwidth probing or Unicode version levels. Its simplicity is its
strength for web/Node environments but it cannot distinguish between a locale
with Unicode 3 tables and one with Unicode 16 tables.

### tcell (Go) -- Locale-only, no wcwidth

tcell detects Unicode support from locale variables (LC_ALL, LC_CTYPE, LANG) but
does not probe wcwidth. Its charset detection is authoritative for "is UTF-8
active?" but cannot determine the Unicode version of the C library's width
tables.

### rich (Python) -- Internal width tables, no system probing

rich ships its own Unicode width tables indexed by `UNICODE_VERSION` environment
variable. It never calls the system `wcwidth()`. This approach gives complete
control over width calculations but requires table updates with each new Unicode
release.

### What Termicap borrows and adapts

| Aspect | Source | Termicap Adaptation |
|--------|--------|---------------------|
| Three sentinel codepoints | notcurses | Adopted verbatim (U+28FF, U+1FB38, U+1CD00) |
| wcwidth as Unicode level probe | notcurses | Adapted to an ordered enumeration instead of per-capability Booleans |
| Descending probe order | (novel) | Termicap probes 16 -> 13 -> 3 for early exit on modern systems |
| Locale guard before probe | notcurses (implicit) | Termicap adds an explicit "C"/"POSIX" locale guard with fallback to Unknown |
| Separate type from env-var result | (novel) | `Wcwidth_Level` is distinct from `Unicode_Level` to preserve version granularity |
| Upgrade-only integration | (novel) | `Refine_Unicode_Level` uses `'Max` to ensure the probe never demotes the env-var result |

---

## 3. Package Design

### Package hierarchy

```
Termicap
+-- Termicap.Unicode           [SPARK Silver] -- Unicode_Level type, env-var cascade
+-- Termicap.Wcwidth           [spec: SPARK On, body: SPARK Off] -- wcwidth probing (NEW)
```

`Termicap.Wcwidth` is a sibling of `Termicap.Unicode`, not a child. This
follows the flat naming convention used by all other Termicap feature packages
(`Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, etc.) and avoids
creating a hierarchical dependency that would be misleading -- the wcwidth
probe is an independent detection mechanism that supplements, rather than
extends, the env-var cascade.

See **ADR-0032** (`docs/adr/0032-wcwidth-package-placement.md`) for the
rationale.

### File layout

| File | SPARK | Description |
|------|-------|-------------|
| `src/termicap-wcwidth.ads` | On | Package spec: `Wcwidth_Level`, sentinel constants, `Probe_Wcwidth_Level` spec, `Refine_Unicode_Level` |
| `src/posix/termicap-wcwidth.adb` | Off | POSIX body: C FFI bindings, locale check, probe algorithm, caching |
| `src/windows/termicap-wcwidth.adb` | Off | Windows body: stub returning Unknown (no POSIX wcwidth available) |

The platform-split follows the same `Source_Dirs` dispatch pattern documented
in ADR-0018. The spec lives in `src/` (shared across all platforms); bodies
live in `src/posix/` and `src/windows/`.

### Dependencies

| Package | Relationship |
|---------|-------------|
| `Termicap.Unicode` | Uses `Unicode_Level` type in `Refine_Unicode_Level` |
| `Interfaces.C` | Used in POSIX body for `wchar_t`, `int`, and `Strings.chars_ptr` |

No dependency on `Termicap.Environment` (the wcwidth probe reads C locale
state, not the environment snapshot). No dependency on `Termicap.TTY` (the
probe does not require a TTY).

---

## 4. Type Definitions

### Wcwidth_Level enumeration (FUNC-WCW-004)

```ada
type Wcwidth_Level is
   (Unknown,     -- probe inconclusive or not performed
    Unicode_3,   -- locale supports at least Unicode 3.0
    Unicode_13,  -- locale supports at least Unicode 13.0
    Unicode_16); -- locale supports at least Unicode 16.0
```

Values are ordered: `Unknown < Unicode_3 < Unicode_13 < Unicode_16`. This
enables `Wcwidth_Level'Max` for comparison operations.

**Why a separate type from `Unicode_Level`**: See the requirements comment on
FUNC-WCW-004 and ADR-0032. In summary: (a) `Wcwidth_Level` has three positive
levels vs. `Unicode_Level`'s two, so information would be lost by immediate
collapse; (b) `Unknown` is semantically distinct from `None` -- Unknown means
"probe not performed" while None means "confirmed no Unicode"; (c) decoupling
allows each feature to evolve independently.

### Optional_Wcwidth_Level for caching (FUNC-WCW-010)

```ada
type Optional_Wcwidth_Level (Is_Set : Boolean := False) is record
   case Is_Set is
      when True  => Level : Wcwidth_Level;
      when False => null;
   end case;
end record;
```

This type is declared in the package spec (SPARK visible) but is used only in
the body for the cache variable. The `Is_Set` discriminant avoids a separate
Boolean flag.

### Sentinel constants (FUNC-WCW-002)

```ada
WCW_SENTINEL_UNI3  : constant := 16#28FF#;
--  U+28FF  BRAILLE PATTERN DOTS-12345678  (Unicode 3.0)

WCW_SENTINEL_UNI13 : constant := 16#1FB38#;
--  U+1FB38  UPPER LEFT BLOCK SEXTANT-2 AND 5 AND 6  (Unicode 13.0)

WCW_SENTINEL_UNI16 : constant := 16#1CD00#;
--  U+1CD00  (Symbols for Legacy Computing Supplement)  (Unicode 16.0)
```

These are universal integer constants (no type association), declared in the
SPARK-visible spec. They can be converted to `Interfaces.C.wchar_t` in the
body when passed to `C_Wcwidth`.

---

## 5. Algorithm Design

### Probing algorithm (FUNC-WCW-003)

The probe function tests sentinels in descending Unicode version order for
early exit:

```
function Probe_Wcwidth_Level return Wcwidth_Level:

   -- Step 0: Check cache (FUNC-WCW-010)
   if Cache.Is_Set then
      return Cache.Level
   end if

   -- Step 1: Locale guard (FUNC-WCW-006)
   Current_Locale := C_Setlocale (LC_CTYPE, Null_Ptr)
   if Current_Locale is null
      or else Current_Locale = "C"
      or else Current_Locale = "POSIX" then
      Cache := (Is_Set => True, Level => Unknown)
      return Unknown
   end if

   -- Step 2: Probe Unicode 16 (FUNC-WCW-003)
   if C_Wcwidth (wchar_t (WCW_SENTINEL_UNI16)) >= 1 then
      Cache := (Is_Set => True, Level => Unicode_16)
      return Unicode_16
   end if

   -- Step 3: Probe Unicode 13
   if C_Wcwidth (wchar_t (WCW_SENTINEL_UNI13)) >= 1 then
      Cache := (Is_Set => True, Level => Unicode_13)
      return Unicode_13
   end if

   -- Step 4: Probe Unicode 3
   if C_Wcwidth (wchar_t (WCW_SENTINEL_UNI3)) >= 1 then
      Cache := (Is_Set => True, Level => Unicode_3)
      return Unicode_3
   end if

   -- Step 5: All probes failed
   Cache := (Is_Set => True, Level => Unknown)
   return Unknown
```

### Refine_Unicode_Level (FUNC-WCW-005)

This is a pure function with `Global => null`, SPARK Silver provable:

```ada
function Refine_Unicode_Level
   (Env_Level : Termicap.Unicode.Unicode_Level;
    Wcw_Level : Wcwidth_Level)
    return Termicap.Unicode.Unicode_Level
is
begin
   case Wcw_Level is
      when Unknown =>
         return Env_Level;
      when Unicode_3 | Unicode_13 =>
         return Termicap.Unicode.Unicode_Level'Max (Env_Level, Termicap.Unicode.Basic);
      when Unicode_16 =>
         return Termicap.Unicode.Unicode_Level'Max (Env_Level, Termicap.Unicode.Extended);
   end case;
end Refine_Unicode_Level;
```

The mapping follows FUNC-WCW-004:
- `Unknown` -> no change (transparent fallback)
- `Unicode_3`, `Unicode_13` -> at least `Basic`
- `Unicode_16` -> at least `Extended`

The `'Max` operation ensures the probe never downgrades the env-var result.

### Caching strategy (FUNC-WCW-010)

The cache is a package-body-level variable of type `Optional_Wcwidth_Level`,
initialized to `(Is_Set => False)`. On the first call to
`Probe_Wcwidth_Level`, the probe is performed and the result is stored. On
subsequent calls, the cached value is returned immediately.

The cache is implemented using a protected object to make the first-call
initialization safe against concurrent callers:

```ada
protected Wcwidth_Cache is
   procedure Store (Level : Wcwidth_Level);
   function Get return Optional_Wcwidth_Level;
private
   Value : Optional_Wcwidth_Level := (Is_Set => False);
end Wcwidth_Cache;
```

The cache is never invalidated. This is acceptable because:
1. The recommended usage is to probe at startup, before locale changes.
2. Termicap does not call `setlocale()` itself.
3. The three `wcwidth()` calls are individually cheap (~microseconds).

---

## 6. FFI Boundary

### C binding: wcwidth (FUNC-WCW-001)

```ada
function C_Wcwidth (Wc : Interfaces.C.wchar_t) return Interfaces.C.int;
pragma Import (C, C_Wcwidth, "wcwidth");
```

This binding is declared in the POSIX body (`src/posix/termicap-wcwidth.adb`)
with `SPARK_Mode => Off`. It uses `Interfaces.C.wchar_t` and
`Interfaces.C.int` for ABI compatibility. The `External_Name` is `"wcwidth"`
(all lowercase) matching the POSIX symbol.

### C binding: setlocale for locale check (FUNC-WCW-006)

```ada
function C_Setlocale
   (Category : Interfaces.C.int;
    Locale   : Interfaces.C.Strings.chars_ptr)
    return Interfaces.C.Strings.chars_ptr;
pragma Import (C, C_Setlocale, "setlocale");

LC_CTYPE : constant Interfaces.C.int := 0;
--  Platform-specific; 0 on Linux/glibc, may differ elsewhere.
--  Will need a C helper constant or platform-specific value.
```

The locale check calls `C_Setlocale (LC_CTYPE, Null_Ptr)` (the C equivalent
of `setlocale(LC_CTYPE, NULL)`) which returns the current locale string
without modifying it. The returned string is then compared against `"C"` and
`"POSIX"`.

**LC_CTYPE constant portability**: The numeric value of `LC_CTYPE` varies
across platforms (0 on Linux/glibc, 2 on macOS/FreeBSD). To handle this
portably, a tiny C helper function or constant should be provided:

```c
/* src/c/termicap_wcwidth.c */
#include <locale.h>
int termicap_lc_ctype(void) { return LC_CTYPE; }
```

Then in Ada:

```ada
function C_LC_CTYPE return Interfaces.C.int;
pragma Import (C, C_LC_CTYPE, "termicap_lc_ctype");
```

This follows the same C-helper pattern used by `termicap_ioctl.c` and
`termicap_osc.c` (ADR-0006).

### Platform split: POSIX vs. Windows

**POSIX body** (`src/posix/termicap-wcwidth.adb`):
- Contains C FFI bindings (`C_Wcwidth`, `C_Setlocale`, `C_LC_CTYPE`)
- Implements the full probe algorithm with locale guard and caching
- SPARK_Mode => Off on the entire body

**Windows body** (`src/windows/termicap-wcwidth.adb`):
- No C FFI bindings (wcwidth is not available on Windows without a POSIX
  compatibility layer)
- `Probe_Wcwidth_Level` returns `Unknown` unconditionally
- `Refine_Unicode_Level` implemented identically (pure function, could be
  shared but must be duplicated per the Source_Dirs pattern)
- SPARK_Mode => Off on the body (for consistency, though it contains no FFI)

**C helper** (`src/c/termicap_wcwidth.c`):
- Provides `termicap_lc_ctype()` returning the platform's `LC_CTYPE` value
- Included in POSIX builds only (same `case Host_OS` gating in the GPR)

---

## 7. Integration with Termicap.Unicode

### Caller sequence

The typical call sequence for full Unicode detection with wcwidth refinement:

```ada
--  Phase 1: env-var cascade (pure, SPARK Silver)
Env_Level := Termicap.Unicode.Detect_Unicode_Level (Env);

--  Phase 2: wcwidth probe (FFI, may return Unknown)
Wcw_Level := Termicap.Wcwidth.Probe_Wcwidth_Level;

--  Phase 3: combine (pure, SPARK Silver)
Final_Level := Termicap.Wcwidth.Refine_Unicode_Level (Env_Level, Wcw_Level);
```

### Capability Record integration

The `Terminal_Capabilities` record in `Termicap.Capabilities` currently has a
`Unicode` field of type `Termicap.Unicode.Unicode_Level`. The wcwidth result
does **not** require a new field in the record; instead, the
`Detect_All`/`Build` function in `Termicap.Capabilities` should call
`Probe_Wcwidth_Level` and `Refine_Unicode_Level` to produce the final
`Unicode_Level` value that is stored in the existing `Unicode` field.

Integration into `Terminal_Capabilities` may be deferred, following the
pattern established by ADR-0021 (keyboard), ADR-0026 (mouse), and ADR-0031
(clipboard). If deferred, the `Wcwidth_Level` result is available as a
standalone API for callers who need the raw probe result.

### Wcwidth_Level as a new Capability Record field (optional)

If callers need access to the raw `Wcwidth_Level` (not just the refined
`Unicode_Level`), a new field could be added:

```ada
type Terminal_Capabilities is record
   ...
   Unicode        : Termicap.Unicode.Unicode_Level;
   Wcwidth        : Termicap.Wcwidth.Wcwidth_Level;   -- raw probe result
   ...
end record;
```

This is a "Could" requirement and can be added later without breaking changes.

---

## 8. Thread Safety

### Documented constraints (FUNC-WCW-009)

The wcwidth probe's threading model is documented in the package spec:

1. **Not thread-safe if locale is changing**: `Probe_Wcwidth_Level` reads the
   process-global locale via `setlocale(LC_CTYPE, NULL)` and then calls
   `wcwidth()`, which reads locale data through a process-global pointer.
   Concurrent `setlocale()` calls from another thread create a data race.

2. **Recommended usage**: Call `Probe_Wcwidth_Level` once at process startup,
   before spawning application threads. This is safe because the locale is
   stable during single-threaded initialization.

3. **No internal locks on the FFI call path**: The protected object
   `Wcwidth_Cache` guards only the cache read/write. The `wcwidth()` and
   `setlocale()` calls themselves are outside the protected region because
   (a) POSIX does not require them to be serialized, and (b) holding a lock
   during a C library call would create an unnecessary serialization point.

4. **uselocale() improvement** (optional, FUNC-WCW-009 point 4): A future
   quality-of-implementation improvement could use `newlocale()` /
   `uselocale()` to apply a thread-local locale for the probe, eliminating
   the race condition entirely. This is not implemented in the base version.

### Protected object design

```ada
protected Wcwidth_Cache is
   procedure Store (Level : Wcwidth_Level);
   function Get return Optional_Wcwidth_Level;
private
   Value : Optional_Wcwidth_Level := (Is_Set => False);
end Wcwidth_Cache;

protected body Wcwidth_Cache is
   procedure Store (Level : Wcwidth_Level) is
   begin
      Value := (Is_Set => True, Level => Level);
   end Store;

   function Get return Optional_Wcwidth_Level is
   begin
      return Value;
   end Get;
end Wcwidth_Cache;
```

The `Probe_Wcwidth_Level` function checks `Wcwidth_Cache.Get` first. If
`Is_Set` is `True`, it returns the cached level immediately. Otherwise, it
performs the probe and stores the result via `Wcwidth_Cache.Store`.

---

## 9. Error Handling

### Failure modes and their mapping (FUNC-WCW-007, FUNC-WCW-011)

All failure modes map to `Wcwidth_Level => Unknown`, which causes
`Refine_Unicode_Level` to return `Env_Level` unchanged. No exception is ever
raised.

| Failure mode | Detection | Result |
|-------------|-----------|--------|
| Windows platform (no wcwidth) | Compile-time (Source_Dirs) | Unknown |
| Locale is "C" or "POSIX" | `C_Setlocale(LC_CTYPE, NULL)` returns "C"/"POSIX" | Unknown |
| `setlocale()` returns NULL | Null pointer check before string comparison | Unknown |
| All sentinels return -1 | Normal algorithm flow; no sentinel >= 1 | Unknown |
| `wcwidth()` returns 0 | Treated same as -1 (zero-width is not a positive detection) | Unknown |
| `wcwidth()` returns unexpected negative | Any value < 1 is non-detection | Unknown |
| `Interfaces.C.int` overflow | Impossible in practice (C int and Ada Integer are both >= 32 bits on all supported platforms); defensive `< 1` comparison avoids the issue | Unknown |

### No-exception guarantee

- The probe function body is `SPARK_Mode => Off` and uses only C imports and
  enumeration assignments. No `Constraint_Error` path exists because:
  - `Interfaces.C.wchar_t` conversion from a universal integer constant
    cannot overflow (all sentinels fit in 32 bits).
  - The `< 1` comparison on `Interfaces.C.int` is defined for all values.
- `Refine_Unicode_Level` is a pure case statement on two enumerations.
  No exceptions are possible.

---

## 10. Testing Strategy

### Unit tests for Refine_Unicode_Level (FUNC-WCW-013 scenario 3)

All 12 combinations of `Unicode_Level` (None, Basic, Extended) x
`Wcwidth_Level` (Unknown, Unicode_3, Unicode_13, Unicode_16):

| Env_Level | Wcw_Level | Expected Result | Rationale |
|-----------|-----------|-----------------|-----------|
| None | Unknown | None | No upgrade |
| None | Unicode_3 | Basic | 3->Basic upgrades None |
| None | Unicode_13 | Basic | 13->Basic upgrades None |
| None | Unicode_16 | Extended | 16->Extended upgrades None |
| Basic | Unknown | Basic | No upgrade |
| Basic | Unicode_3 | Basic | 3->Basic = Basic (no change) |
| Basic | Unicode_13 | Basic | 13->Basic = Basic (no change) |
| Basic | Unicode_16 | Extended | 16->Extended upgrades Basic |
| Extended | Unknown | Extended | No upgrade |
| Extended | Unicode_3 | Extended | 3->Basic < Extended (no downgrade) |
| Extended | Unicode_13 | Extended | 13->Basic < Extended (no downgrade) |
| Extended | Unicode_16 | Extended | 16->Extended = Extended (no change) |

Properties verified for all combinations:
- `Result >= Env_Level` (probe never downgrades)
- If `Wcw_Level = Unknown`, then `Result = Env_Level`
- If `Wcw_Level = Unicode_16`, then `Result >= Extended`

### Sentinel constant sanity test (FUNC-WCW-013 scenario 4)

```ada
pragma Assert (WCW_SENTINEL_UNI3  = 16#28FF#);
pragma Assert (WCW_SENTINEL_UNI13 = 16#1FB38#);
pragma Assert (WCW_SENTINEL_UNI16 = 16#1CD00#);
```

### Integration tests -- locale-dependent (FUNC-WCW-013 scenarios 1, 2)

These tests are environment-dependent and should be tagged for conditional
execution:

1. **UTF-8 locale test**: Set `LC_CTYPE` to a UTF-8 locale (e.g.,
   "en_US.UTF-8") on a system with glibc >= 2.31. Verify
   `Probe_Wcwidth_Level >= Unicode_13`. Skip if locale is not installed.

2. **"C" locale test**: Set locale to "C" or "POSIX". Verify
   `Probe_Wcwidth_Level = Unknown`. This tests the locale guard (FUNC-WCW-006).

### Caching test (FUNC-WCW-013 scenario 5)

Call `Probe_Wcwidth_Level` twice in succession. Verify both calls return the
same value. If mock injection is supported, verify that `C_Wcwidth` is called
at most three times total (for the first invocation only).

### Mock strategy for FFI layer

The POSIX body contains the C FFI calls, making direct mocking difficult
without dependency injection. Two strategies are available:

1. **Subprocess testing**: Run the test binary in a subprocess with controlled
   locale settings. This is the most realistic approach for integration tests.

2. **Compile-time mock body**: Create a `tests/mock/termicap-wcwidth.adb` that
   overrides the production body via Source_Dirs precedence. The mock body
   records call counts and returns configurable values. This enables the
   caching test (scenario 5) and the full 12-combination unit test without
   requiring a real locale.

---

## 11. Requirements Traceability

| UID | Priority | Summary | Design element / location |
|-----|----------|---------|----------------------------|
| FUNC-WCW-001 | Must | C wcwidth() FFI binding | S.6; POSIX body FFI section |
| FUNC-WCW-002 | Must | Sentinel codepoint constants | S.4; spec constants |
| FUNC-WCW-003 | Must | Sentinel probing algorithm | S.5; probe algorithm |
| FUNC-WCW-004 | Must | Wcwidth_Level enumeration | S.4; type definition |
| FUNC-WCW-005 | Must | Refine_Unicode_Level function | S.5; integration function |
| FUNC-WCW-006 | Must | Locale initialisation requirement | S.5, S.6; locale guard |
| FUNC-WCW-007 | Must | Graceful handling of wcwidth -1 | S.9; error handling |
| FUNC-WCW-008 | Must | SPARK boundary | S.3, S.6; package design |
| FUNC-WCW-009 | Must | Thread safety constraints | S.8; threading model |
| FUNC-WCW-010 | Should | Cached probe result | S.5, S.8; caching strategy |
| FUNC-WCW-011 | Must | Fallback when probe fails | S.9; failure mode table |
| FUNC-WCW-012 | Must | Public API specification | S.3, S.4; package spec |
| FUNC-WCW-013 | Should | Integration tests | S.10; testing strategy |

---

## 12. SPARK Contract Summary

| Element | SPARK Mode | Provable? | Notes |
|---------|-----------|-----------|-------|
| `Wcwidth_Level` type | On | N/A (type) | Plain enumeration, no proof needed |
| `Optional_Wcwidth_Level` type | On | N/A (type) | Discriminated record |
| Sentinel constants | On | N/A (constants) | Universal integer literals |
| `Probe_Wcwidth_Level` spec | On | Spec only | Body is SPARK Off (FFI) |
| `Probe_Wcwidth_Level` body | Off | No | Contains C imports and protected object |
| `Refine_Unicode_Level` | On | Silver | `Global => null`, pure case statement |
| `Wcwidth_Cache` protected object | Off | No | In SPARK Off body |

---

## 13. Files to Create/Modify

### Files to create

| File | Description |
|------|-------------|
| `src/termicap-wcwidth.ads` | Package spec: types, constants, function specs |
| `src/posix/termicap-wcwidth.adb` | POSIX body: FFI bindings, probe algorithm, cache |
| `src/windows/termicap-wcwidth.adb` | Windows stub: returns Unknown |
| `src/c/termicap_wcwidth.c` | C helper: `termicap_lc_ctype()` returning platform LC_CTYPE value |
| `tests/src/termicap-wcwidth-tests.ads` | Test package spec |
| `tests/src/termicap-wcwidth-tests.adb` | Test cases: 12-combination unit test, sentinel sanity, locale integration |
| `docs/adr/0032-wcwidth-package-placement.md` | ADR: Termicap.Wcwidth as sibling vs. child of Termicap.Unicode |

### Files to modify

| File | Modification |
|------|-------------|
| `termicap.gpr` | No change needed if `src/` is auto-discovered; C helper added to `src/c/` |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Wcwidth` to package overview and SPARK boundary diagram |
| `docs/architecture/04-runtime-view.md` | Add wcwidth probe flow to the Unicode detection scenario |
| `docs/adr/README.md` | Add ADR-0032 entry to the index |

---

## 14. ADR

**ADR-0032** (`docs/adr/0032-wcwidth-package-placement.md`): Documents the
decision to place wcwidth probing in `Termicap.Wcwidth` (a sibling package)
rather than `Termicap.Unicode.Wcwidth` (a child package).

---

## Related Documents

- **Requirements:** `docs/requirements/wcwidth.sdoc` (FUNC-WCW-001 through FUNC-WCW-013)
- **ADR-0007:** `docs/adr/0007-unicode-level-three-value-enum.md` (three-level Unicode_Level enum)
- **ADR-0018:** `docs/adr/0018-platform-dispatch-via-source-dirs.md` (Source_Dirs pattern)
- **ADR-0032:** `docs/adr/0032-wcwidth-package-placement.md` (package placement)
- **Tech Spec F5:** `docs/tech-specs/unicode-support.md` (env-var Unicode detection)
- **Architecture:** `docs/architecture/03-building-blocks.md` (package structure)
- **Global Synthesis:** `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` (section 2.10, Method 3)
- **notcurses:** `reference-frameworks/notcurses/src/lib/termdesc.c` (lines 1064--1075)
