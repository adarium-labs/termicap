# Technical Specification: Capability Record Assembly

**Requirements:** FUNC-CAP-001 through FUNC-CAP-015
**Date:** 2026-04-03
**Status:** Draft

---

## 1. Overview

The Capability Record Assembly feature provides a single integration point for applications
that need all terminal capability information in one call. Rather than invoking each
sub-detector independently, an application calls `Get` (cached) or `Detect` (fresh) and
receives an immutable `Terminal_Capabilities` record containing TTY status, color level,
terminal dimensions, Unicode support, terminal identity, and a downsampling-availability
flag.

The feature provides:

- An immutable `Terminal_Capabilities` record type aggregating all sub-detector results
- A `Detect` function that performs fresh, stateless detection (SPARK-friendly)
- A `Get` function with lazy per-stream caching (three slots: Stdout, Stderr, Stdin)
- A pure `Assemble` helper that combines pre-computed sub-detector outputs into the record
  with a `Global => null` contract and a SPARK-provable postcondition on
  `Downsampling_Available`

The assembly layer contains no FFI calls. All OS interaction is delegated to existing
sub-detector packages. The cache uses an Ada protected object for thread safety, with
`SPARK_Mode => Off` confined to the cache boundary.

---

## 2. Requirements Coverage

| Requirement | Title | Design Decision |
|-------------|-------|-----------------|
| FUNC-CAP-001 | Terminal_Capabilities Record Type | Plain record in `Termicap.Capabilities` (section 4.2) |
| FUNC-CAP-002 | Stream Selection | `Stream` parameter on `Detect` and `Get`, default `Stdout` |
| FUNC-CAP-003 | Get Function (Cached) | `Get` delegates to protected object with per-stream lazy init (section 4.4) |
| FUNC-CAP-004 | Detect Function (Fresh) | `Detect` calls all sub-detectors, no cache read/write (section 4.3) |
| FUNC-CAP-005 | Default Stream Aliases | Default parameter `Stream => Stdout` on both functions |
| FUNC-CAP-006 | Override Applied to Color | Delegated to `Detect_Color_Level` which already consults `Override_State` |
| FUNC-CAP-007 | TTY Fields Reflect Override | Delegated to `TTY.Is_TTY` / `TTY.Query_All` which already consult `Override_State` |
| FUNC-CAP-008 | Thread-Safe Cache Init | Protected object `Cache` with entry guard (section 4.5) |
| FUNC-CAP-009 | Immutability of Returned Record | Plain Ada record, value semantics, no access types |
| FUNC-CAP-010 | Sub-Detector Invocation Order | Enforced in `Detect` body (section 6.1) |
| FUNC-CAP-011 | Environment Snapshot Consistency | Single `Capture_Current` call at start of each `Detect` invocation |
| FUNC-CAP-012 | SPARK Silver for Pure Assembly | `Assemble` function with `Global => null` and postcondition (section 4.6) |
| FUNC-CAP-013 | No FFI in Assembly | Assembly layer calls only existing Ada sub-detector functions |
| FUNC-CAP-014 | Re-Detection on Detect Call | `Detect` never reads cache; `Get` never calls sub-detectors after init |
| FUNC-CAP-015 | Unit Testability | `Detect` accepts environment snapshot indirectly via `Capture`; tests use `EMPTY_ENVIRONMENT` + `Insert` |

---

## 3. Framework Survey

### termenv (Go)

termenv's `Output` struct is the closest analogue. It wraps an `io.Writer` and lazily
detects `ColorProfile()`, `HasDarkBackground()`, etc. Detection results are cached on the
`Output` instance. A global `output` variable is provided for stdout convenience. Key
observations:

- **Per-stream model**: each `Output` wraps one stream; there is no multi-stream record.
  Termicap differs by aggregating all three TTY statuses into one record, with the `Color`
  field reflecting a caller-selected stream.
- **Lazy caching**: `ColorProfile()` computes on first call, caches thereafter. Termicap's
  `Get` follows this pattern at the per-stream level.
- **No separate `Detect` path**: termenv has no explicit "fresh re-detection" function.
  Termicap provides `Detect` as the escape hatch from the cache.

### wezterm/termwiz (Rust)

termwiz's `Capabilities` struct holds `color_level`, `hyperlinks`, `sixel`, `iterm2_image`,
`bce`, `bracketed_paste`, `mouse_reporting`, and a `terminfo_db`. It is constructed via
`Capabilities::new_with_hints(hints)` where `ProbeHints` is a builder that can override
individual fields. Key observations:

- **Builder pattern**: `ProbeHints` allows callers to inject overrides before detection.
  Termicap's override mechanism is a separate global state (`Termicap.Override`) rather than
  a per-call builder, which is simpler but less flexible.
- **Flat record**: all fields are independent scalars or booleans. Termicap follows this
  pattern -- no capability tree or inheritance.
- **No caching**: `Capabilities` is constructed once by the caller and stored; termwiz does
  not provide a library-level cache. Termicap adds caching via a protected object because
  Ada library elaboration makes an eager "construct once" approach fragile.

### supports-color (JavaScript)

supports-color returns a `{ level, hasBasic, has256, has16m }` object per stream (stdout,
stderr). The `createSupportsColor()` function performs detection; the module exports
cached results. Key observations:

- **Per-stream exports**: `supportsColor.stdout` and `supportsColor.stderr` are computed
  separately. Termicap's `Get(Stream)` follows this pattern.
- **Derived Boolean fields**: `hasBasic`, `has256`, `has16m` are derived from `level` via
  `>=` comparisons. Termicap's `Downsampling_Available` follows the same "derived
  convenience flag" pattern.
- **No re-detection API**: once the module is loaded, results are fixed. Termicap's
  `Detect` function fills this gap.

---

## 4. Package Design

### 4.1 Package Hierarchy and Placement

**Decision: `Termicap.Capabilities` child package** (Option b)

See [ADR-0011](../adr/0011-capability-record-package-placement.md) for the full rationale.

The record type, `Detect`, `Get`, and the internal cache all live in a new child package
`Termicap.Capabilities`. This avoids circular dependencies (the root `termicap.ads`
remains an empty namespace) and keeps the SPARK annotation boundary clean.

**Call-site ergonomics** remain good with a `use` clause or renaming:

```ada
with Termicap.Capabilities;

Caps : constant Termicap.Capabilities.Terminal_Capabilities
     := Termicap.Capabilities.Get;

--  Or with a use clause:
use Termicap.Capabilities;
Caps : constant Terminal_Capabilities := Get;
```

**File mapping:**

| File | Content |
|------|---------|
| `src/termicap-capabilities.ads` | Spec: record type, `Detect`, `Get`, `Assemble` |
| `src/termicap-capabilities.adb` | Body: `Detect` orchestration, `Get` cache, protected object |

### 4.2 Terminal_Capabilities Record Type

```ada
type Terminal_Capabilities is record
   TTY_Stdin              : Boolean;
   TTY_Stdout             : Boolean;
   TTY_Stderr             : Boolean;
   Color                  : Termicap.Color.Color_Level;
   Size                   : Termicap.Dimensions.Terminal_Size;
   Unicode                : Termicap.Unicode.Unicode_Level;
   Identity               : Termicap.Terminal_Id.Terminal_Identity;
   Downsampling_Available : Boolean;
end record;
```

All fields are plain values. No access types, no tagged types, no discriminants with
mutable defaults. Assignment produces an independent copy (FUNC-CAP-009).

### 4.3 Detect Function (Signature and Contract)

```ada
function Detect
   (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
    return Terminal_Capabilities
with Global => (Input => Termicap.Override.Override_State);
```

`Detect` is declared with `SPARK_Mode => On` in the spec, but its body requires
`SPARK_Mode => Off` because it calls `Capture_Current` (OS FFI) and `Query_All` (isatty
FFI). The `Global` aspect references `Override_State` because `Detect_Color_Level` and
`Is_TTY` both read it.

`Detect` is stateless with respect to the cache. It performs a full detection run on every
call (FUNC-CAP-014).

### 4.4 Get Function (Signature and Cache)

```ada
function Get
   (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
    return Terminal_Capabilities;
```

`Get` is declared without a SPARK `Global` aspect because it reads and writes to the
internal protected object (cache), which is not expressible in SPARK. Its body is compiled
with `SPARK_Mode => Off`.

On the first call for a given `Stream`, `Get` invokes `Detect(Stream)` and stores the
result. Subsequent calls return the cached value (FUNC-CAP-003).

### 4.5 Cache Implementation (Protected Object Design)

**Decision: Protected record with an array indexed by `Stream_Kind`** (Option a)

See [ADR-0012](../adr/0012-capability-cache-design.md) for the full rationale.

```ada
--  In the package body (SPARK_Mode => Off region):

type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Terminal_Capabilities;
end record;

type Cache_Array is array (Termicap.TTY.Stream_Kind) of Cache_Slot;

protected Cache is
   function Get_Cached (Stream : Termicap.TTY.Stream_Kind) return Cache_Slot;
   procedure Set_Cached (Stream : Termicap.TTY.Stream_Kind;
                         Caps   : Terminal_Capabilities);
private
   Slots : Cache_Array;
end Cache;
```

The `Get` function body follows this pattern:

```ada
function Get (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
   return Terminal_Capabilities
is
   Slot : constant Cache_Slot := Cache.Get_Cached (Stream);
begin
   if Slot.Initialized then
      return Slot.Value;
   end if;

   declare
      Result : constant Terminal_Capabilities := Detect (Stream);
   begin
      Cache.Set_Cached (Stream, Result);
      return Result;
   end;
end Get;
```

Note: there is a benign race where two tasks both see `Initialized = False` and both run
`Detect`. The second `Set_Cached` call overwrites the first, but both produce identical
results (same environment, same TTY state). This avoids the complexity of a protected
entry with a barrier, which would risk deadlock if `Get` is called during elaboration.
The protected object ensures no task sees a partially written record (FUNC-CAP-008).

### 4.6 SPARK Annotation Split

**Decision: Spec `SPARK_Mode => On`, body mixed** (see
[ADR-0013](../adr/0013-spark-annotation-split-capabilities.md))

| Region | SPARK_Mode | Reason |
|--------|-----------|--------|
| Package spec | On | Record type, `Assemble`, `Detect`, `Get` signatures visible to SPARK callers |
| `Assemble` body | On | Pure function, `Global => null`, provable postcondition |
| `Detect` body | Off | Calls `Capture_Current` (OS FFI), `Query_All` (isatty FFI) |
| `Get` body | Off | Reads/writes protected object (tasking, outside SPARK subset) |
| Protected object `Cache` | Off | Protected types are outside the SPARK 2014 subset |

The `Assemble` function is the SPARK-provable core:

```ada
function Assemble
   (TTY    : Termicap.TTY.TTY_Status;
    Color  : Termicap.Color.Color_Level;
    Size   : Termicap.Dimensions.Terminal_Size;
    Unicode : Termicap.Unicode.Unicode_Level;
    Identity : Termicap.Terminal_Id.Terminal_Identity)
    return Terminal_Capabilities
with
   Global => null,
   Post   =>
      Assemble'Result.Downsampling_Available =
         (Assemble'Result.Color >= Termicap.Color.Extended_256)
      and then Assemble'Result.Color = Color
      and then Assemble'Result.Unicode = Unicode
      and then Assemble'Result.TTY_Stdin = TTY.Stdin
      and then Assemble'Result.TTY_Stdout = TTY.Stdout
      and then Assemble'Result.TTY_Stderr = TTY.Stderr;
```

This function receives all sub-detector outputs as parameters and constructs the record.
The `Global => null` contract ensures SPARK can verify it without reasoning about global
state. The postcondition on `Downsampling_Available` is the representative Silver-level
obligation (FUNC-CAP-012).

`Detect` calls `Assemble` internally but is itself `SPARK_Mode => Off` because it performs
the FFI calls that produce the inputs to `Assemble`.

---

## 5. Design Decisions (ADR References)

| Decision | ADR | Choice | Summary |
|----------|-----|--------|---------|
| Package placement | [ADR-0011](../adr/0011-capability-record-package-placement.md) | `Termicap.Capabilities` child package | Avoids circular with; keeps root package empty; good ergonomics with `use` clause |
| Cache design | [ADR-0012](../adr/0012-capability-cache-design.md) | Protected record + `Cache_Array` indexed by `Stream_Kind` | Single protected object, natural array indexing, minimal code |
| SPARK annotation split | [ADR-0013](../adr/0013-spark-annotation-split-capabilities.md) | Spec On, body mixed with `Assemble` provable | Maximizes SPARK coverage; isolates unavoidable Off regions to FFI and tasking |
| `Downsampling_Available` | Inline (section 4.2/4.6) | Field set during assembly, not a computed function | Enables SPARK postcondition proof; value is frozen at detection time, consistent with the cached snapshot |

### Downsampling_Available: Field vs. Function

Option (a) -- a field set during assembly -- is chosen over option (b) -- a computed
function. Rationale:

- A field allows the SPARK postcondition `Result.Downsampling_Available = (Result.Color >= Extended_256)` to be proven by the SPARK prover as a simple record field equality. A function would require the prover to inline the function body, adding complexity.
- The field is frozen at detection time, which is consistent with the snapshot semantics of the entire record. A computed function could theoretically return a different value if the Color field were somehow modified (impossible with value semantics, but the field approach makes this structurally clear).
- The redundant storage cost is one Boolean (1 byte), negligible.

---

## 6. Implementation Notes

### 6.1 Sub-Detector Call Sequence

The `Detect` function body implements the ordering from FUNC-CAP-010:

```ada
function Detect
   (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
    return Terminal_Capabilities
is
   --  Step 1: Capture environment snapshot
   Env : Termicap.Environment.Environment;

   --  Step 2: Terminal identity
   Id : Termicap.Terminal_Id.Terminal_Identity;

   --  Step 3: TTY status for all streams
   TTY : Termicap.TTY.TTY_Status;

   --  Step 4: Color level for the selected stream
   Is_TTY_For_Stream : Boolean;
   Color : Termicap.Color.Color_Level;

   --  Step 5: Terminal dimensions
   Size : Termicap.Dimensions.Terminal_Size;

   --  Step 6: Unicode level
   Uni : Termicap.Unicode.Unicode_Level;
begin
   --  Step 1
   Termicap.Environment.Capture.Capture_Current (Env);

   --  Step 2
   Id := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);

   --  Step 3
   TTY := Termicap.TTY.Query_All;

   --  Step 4: Select the TTY flag for the requested stream
   Is_TTY_For_Stream := (case Stream is
      when Termicap.TTY.Stdin  => TTY.Stdin,
      when Termicap.TTY.Stdout => TTY.Stdout,
      when Termicap.TTY.Stderr => TTY.Stderr);
   Color := Termicap.Color.Detect_Color_Level (Env, Is_TTY_For_Stream);

   --  Step 5
   Size := Termicap.Dimensions.Get_Size (Env, TTY.Stdout);

   --  Step 6
   Uni := Termicap.Unicode.Detect_Unicode_Level (Env);

   --  Steps 7 + 8: Assemble (derives Downsampling_Available internally)
   return Assemble (TTY    => TTY,
                    Color  => Color,
                    Size   => Size,
                    Unicode => Uni,
                    Identity => Id);
end Detect;
```

### 6.2 Override Integration

No special override handling is needed in the assembly layer. The override is already
integrated at the sub-detector level:

- `Termicap.Color.Detect_Color_Level` checks `Override_State` as the first step of its
  11-step cascade (FUNC-OVR-004). When the override is non-Auto, it returns the mapped
  `Color_Level` immediately.
- `Termicap.TTY.Is_TTY` checks `Override_State` before calling `isatty()` (FUNC-OVR-005).
  When the override forces color on, all streams return True; when Force_None, all return
  False.

The `Detect` function simply calls these sub-detectors and passes their results to
`Assemble`. The override is invisible to the assembly layer, exactly as required by
FUNC-CAP-013 (no FFI or global state reading in the assembly function itself).

### 6.3 Testing Approach

Tests exercise the assembly layer without a live terminal by:

1. **Using `EMPTY_ENVIRONMENT` + `Insert`** to construct deterministic environment snapshots
   (FUNC-ENV-005).
2. **Calling `Detect`** after setting up the environment via `Scoped_Override` for override
   tests, or with a controlled snapshot for detection tests.
3. **Calling `Assemble` directly** with known sub-detector outputs to verify the pure
   assembly logic and the `Downsampling_Available` derivation.

Test cases from FUNC-CAP-015:

| Category | Input | Expected |
|----------|-------|----------|
| Basic detection | TERM=xterm-256color, Is_TTY=True | Color = Extended_256, Downsampling_Available = True |
| NO_COLOR | NO_COLOR present, Is_TTY=True | Color = None, Downsampling_Available = False |
| Non-TTY | Is_TTY=False, no override | Color = None |
| Override Force_True_Color | Set_Override(Force_True_Color) | Color = True_Color, all TTY = True |
| Override Force_None | Set_Override(Force_None) | Color = None, all TTY = False |
| Downsampling True_Color | Color = True_Color | Downsampling_Available = True |
| Downsampling Extended_256 | Color = Extended_256 | Downsampling_Available = True |
| Downsampling Basic_16 | Color = Basic_16 | Downsampling_Available = False |
| Downsampling None | Color = None | Downsampling_Available = False |
| Stream selection | Detect(Stderr) with differing TTY status | Color reflects Stderr TTY |
| Immutability | Modify local copy of Get result | Subsequent Get returns original |

---

## 7. Files to Create/Modify

### New files

| File | Description |
|------|-------------|
| `src/termicap-capabilities.ads` | Package spec: `Terminal_Capabilities` record, `Assemble`, `Detect`, `Get` |
| `src/termicap-capabilities.adb` | Package body: `Detect` orchestration, `Get` cache, protected object |
| `tests/src/termicap-capabilities-tests.ads` | Test spec |
| `tests/src/termicap-capabilities-tests.adb` | Test cases per FUNC-CAP-015 |
| `docs/adr/0011-capability-record-package-placement.md` | ADR for package placement |
| `docs/adr/0012-capability-cache-design.md` | ADR for cache design |
| `docs/adr/0013-spark-annotation-split-capabilities.md` | ADR for SPARK split strategy |

### Modified files

| File | Change |
|------|--------|
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Capabilities` to package tree and Level 2 descriptions |
| `docs/architecture/04-runtime-view.md` | Add Scenario: Capability Record Assembly flow |
| `termicap.gpr` | Add new source file to project (if not auto-discovered) |
| `tests/alire.toml` | Add dependency on `Termicap.Capabilities` test sources if needed |
