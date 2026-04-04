# API Reference: `Termicap.Capabilities`

Package providing the primary integration point for complete terminal capability detection.

**Files:** `src/termicap-capabilities.ads`, `src/termicap-capabilities.adb`
**SPARK_Mode:** On (spec and `Assemble` function); Off (protected cache object, `Detect` and `Get` bodies)
**License:** Apache-2.0

---

## Overview

`Termicap.Capabilities` aggregates all sub-detector results into a single `Terminal_Capabilities` record, providing cached (`Get`) and fresh (`Detect`) detection entry points. Applications that need the full capability picture in a single call use this package rather than invoking each sub-detector independently.

The package provides:

- A `Terminal_Capabilities` record type with eight fields covering TTY status (three streams), color level, terminal size, Unicode support level, terminal identity, and a derived downsampling flag.
- `Assemble` — a SPARK Silver-provable pure function that constructs a `Terminal_Capabilities` record from pre-computed sub-detector results; primarily used by tests and by `Detect` internally.
- `Detect` — performs a full, uncached detection run; use after `SIGWINCH` or after calling `Set_Override`.
- `Get` — returns a cached result for the given stream, populating the cache on the first call; safe to call from multiple Ada tasks concurrently.

Override state installed via `Termicap.Override.Set_Override` is automatically reflected in the `TTY_*` fields and the `Color` field of both `Detect` and `Get` results, because the underlying sub-detectors (`Is_TTY`, `Query_All`, and `Detect_Color_Level`) all perform an override check as their first step.

**Requirements:** FUNC-CAP-001 through FUNC-CAP-014

---

## Types

### `Terminal_Capabilities`

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

Aggregated terminal capability snapshot. Assignment produces an independent copy with value semantics — no access types, no mutable discriminants, no aliasing (FUNC-CAP-009). All fields reflect detection results at the moment `Get` or `Detect` was called.

| Field | Type | Description |
|-------|------|-------------|
| `TTY_Stdin` | `Boolean` | `True` when stdin is connected to an interactive terminal (or an override forces color on). |
| `TTY_Stdout` | `Boolean` | `True` when stdout is connected to an interactive terminal (or an override forces color on). |
| `TTY_Stderr` | `Boolean` | `True` when stderr is connected to an interactive terminal (or an override forces color on). |
| `Color` | `Termicap.Color.Color_Level` | Color depth supported by the terminal: `None`, `Basic_16`, `Extended_256`, or `True_Color`. Reflects the active override when one is set. |
| `Size` | `Termicap.Dimensions.Terminal_Size` | Terminal dimensions from ioctl, `COLUMNS`/`LINES` env vars, or the 80×24 default. Always derived from the stdout stream. |
| `Unicode` | `Termicap.Unicode.Unicode_Level` | Unicode rendering capability: `None`, `Basic`, or `Extended`. Derived from locale and terminal-emulator heuristics. |
| `Identity` | `Termicap.Terminal_Id.Terminal_Identity` | Passively identified terminal emulator or multiplexer. `Kind = Unknown` when no recognisable signal is found. |
| `Downsampling_Available` | `Boolean` | `True` when `Color >= Extended_256`. Derived by `Assemble`; GNATprove-verifiable postcondition confirms the relationship. |

**Requirements:** FUNC-CAP-001, FUNC-CAP-009

---

## Subprograms

### `Assemble`

```ada
function Assemble
  (TTY_Stdin  : Boolean;
   TTY_Stdout : Boolean;
   TTY_Stderr : Boolean;
   Color      : Termicap.Color.Color_Level;
   Size       : Termicap.Dimensions.Terminal_Size;
   Unicode    : Termicap.Unicode.Unicode_Level;
   Identity   : Termicap.Terminal_Id.Terminal_Identity)
   return Terminal_Capabilities
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    Assemble'Result.Downsampling_Available
    = (Assemble'Result.Color >= Termicap.Color.Extended_256);
```

Pure function that constructs a `Terminal_Capabilities` record from pre-computed sub-detector results. `Downsampling_Available` is derived as `Color >= Extended_256`; the postcondition is GNATprove-verifiable at Silver level. `Assemble` reads no global state and performs no OS calls.

`Detect` calls `Assemble` internally as its final step. Test code may call `Assemble` directly with known inputs to verify the assembly logic without invoking any sub-detector or OS call (FUNC-CAP-013).

**SPARK contract:** `Global => null` — no side effects, no global reads.

**Requirements:** FUNC-CAP-012, FUNC-CAP-013

---

### `Detect`

```ada
function Detect
  (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
   return Terminal_Capabilities;
```

Perform a complete, uncached detection for the given stream. Captures a fresh environment snapshot, invokes all sub-detectors in dependency order, and assembles the result via `Assemble`. Does not read or write the cache used by `Get`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Stream` | in | The stream for which `Color` and TTY status are computed. `Size` is always derived from stdout. Default: `Stdout`. |

**Returns:** A `Terminal_Capabilities` record reflecting terminal state at the moment of the call.

**When to use:** Use `Detect` when up-to-date capability information is required — for example, after `SIGWINCH` (to pick up new dimensions) or after calling `Set_Override` / `Reset_Override` (to reflect the new override state immediately). Every call performs a full detection run regardless of cache state (FUNC-CAP-004, FUNC-CAP-014).

**Thread safety:** Safe to call from multiple Ada tasks concurrently — `Detect` holds no shared mutable state of its own; all sub-detectors are either pure functions or thread-safe protected calls.

**Requirements:** FUNC-CAP-004, FUNC-CAP-005, FUNC-CAP-006, FUNC-CAP-007, FUNC-CAP-010, FUNC-CAP-011, FUNC-CAP-014

---

### `Get`

```ada
function Get
  (Stream : Termicap.TTY.Stream_Kind := Termicap.TTY.Stdout)
   return Terminal_Capabilities;
```

Return a cached `Terminal_Capabilities` value for the given stream. On the first call for a given `Stream`, invokes `Detect` and stores the result in a thread-safe protected object. Subsequent calls for the same `Stream` return a copy of the cached value without re-running any sub-detector.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Stream` | in | The stream for which capabilities are requested. Each of the three `Stream_Kind` values has its own independent cache slot. Default: `Stdout`. |

**Returns:** A `Terminal_Capabilities` record; a value copy of the cached result.

**Caching behaviour:** The cache is populated lazily — `Detect` is only called when a stream's cache slot has not yet been filled. Invalidation is not automatic: a cached result reflects the override state and environment at the time the slot was first populated. Call `Detect` directly when fresh results are needed after an override change (FUNC-CAP-003, FUNC-CAP-006).

**Thread safety:** The per-stream cache is a protected object. Concurrent calls from multiple Ada tasks for the same or different streams are safe; the protected barrier guarantees that `Detect` is called at most once per stream slot (FUNC-CAP-008).

**Requirements:** FUNC-CAP-003, FUNC-CAP-005, FUNC-CAP-008, FUNC-CAP-009

---

## SPARK Contracts Summary

| Subprogram | `Global` aspect | Provability |
|-----------|----------------|-------------|
| `Assemble` | `null` | Silver (spec and body carry `SPARK_Mode => On`; postcondition GNATprove-verifiable) |
| `Detect` | *(no Global contract)* | Spec: SPARK annotation only; body: Off (delegates to OS-calling sub-detectors) |
| `Get` | *(no Global contract)* | Spec: SPARK annotation only; body: Off (protected cache + Detect delegation) |

`Detect` and `Get` are not given `Global` contracts because they call sub-detectors that read `Termicap.Override.Override_State` and perform OS calls — both of which place them outside the SPARK provable zone. The `Assemble` function remains pure: it receives all inputs as parameters and performs no IO.

---

## Usage Examples

### Simplest use — single cached call

```ada
with Termicap.Capabilities; use Termicap.Capabilities;

declare
   Caps : constant Terminal_Capabilities := Get;
   --  Stream => Stdout (default)
begin
   if Caps.Color >= Termicap.Color.Extended_256 then
      --  Safe to emit 256-color SGR escape codes
      null;
   end if;

   if Caps.Downsampling_Available then
      --  Caps.Color >= Extended_256 is guaranteed by Assemble's postcondition
      null;
   end if;
end;
```

### Fresh detection after SIGWINCH

```ada
--  After receiving a resize notification:
declare
   Caps : constant Terminal_Capabilities := Detect;
   --  Full detection run; new Size.Columns / Size.Rows reflect the resize
begin
   Redraw (Cols => Caps.Size.Columns, Rows => Caps.Size.Rows);
end;
```

### Testability — Assemble with known inputs

```ada
with Termicap.Capabilities; use Termicap.Capabilities;
with Termicap.Color;         use Termicap.Color;
with Termicap.Dimensions;
with Termicap.Unicode;
with Termicap.Terminal_Id;

declare
   Default_Size : constant Termicap.Dimensions.Terminal_Size :=
     (Columns => 80, Rows => 24, Pixel_Width => 0, Pixel_Height => 0);

   Id : constant Termicap.Terminal_Id.Terminal_Identity :=
     (Kind => Termicap.Terminal_Id.Unknown, Is_Multiplexer => False,
      Program_Name | Program_Version | Term_Value =>
        Ada.Strings.Unbounded.Null_Unbounded_String);

   Caps : constant Terminal_Capabilities :=
     Assemble
       (TTY_Stdin  => False,
        TTY_Stdout => True,
        TTY_Stderr => True,
        Color      => Extended_256,
        Size       => Default_Size,
        Unicode    => Termicap.Unicode.Extended,
        Identity   => Id);
begin
   --  Postcondition: Downsampling_Available = (Color >= Extended_256)
   pragma Assert (Caps.Downsampling_Available);
   pragma Assert (Caps.Color = Extended_256);
end;
```

---

## Thread Safety Notes

- `Get` is safe to call concurrently from multiple Ada tasks. The protected object enforces mutual exclusion on cache reads and writes. The first-population call to `Detect` occurs inside the protected barrier, so `Detect` is invoked at most once per stream slot.
- `Detect` is safe to call concurrently from multiple Ada tasks. It holds no shared state; each call operates on its own stack-allocated local environment snapshot and result record.
- `Assemble` is a pure function with `Global => null`. It is safe to call from any context including interrupt handlers.

---

## Related Documents

- **Tech Spec** (`docs/tech-specs/capability-record.md`): Full design rationale, SPARK strategy, sub-detector ordering, and cache design
- **ADR-0011** (`docs/adr/0011-capability-record-package-placement.md`): Rationale for placing the aggregation package as a top-level child of `Termicap`
- **ADR-0012** (`docs/adr/0012-capability-cache-design.md`): Rationale for the per-stream protected cache design
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`): Rationale for the SPARK/Ada split (`Assemble` pure vs. `Detect`/`Get` Ada-only)
- **Runtime View** (`docs/architecture/04-runtime-view.md`): Scenario 17 — Get/Detect flow sequence diagrams
- **Building Blocks** (`docs/architecture/03-building-blocks.md`): `Termicap.Capabilities` in the package hierarchy and SPARK boundary diagram
- **Requirements** (`docs/requirements/capability_record.sdoc`): FUNC-CAP-001 through FUNC-CAP-014
