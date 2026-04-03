# Technical Specification: Global Enable/Disable Override

**Requirements:** FUNC-OVR-001 through FUNC-OVR-014
**Date:** 2026-04-03
**Status:** Draft

---

## 1. Overview

The global override feature allows CLI applications to bypass Termicap's automatic terminal
detection and force a specific color level (or disable color entirely) for the remainder of
the process. This is the mechanism behind `--color=always`, `--color=never`, and
`--color=auto` flags.

The feature provides:

- A five-literal `Override_Mode` enumeration (`Auto`, `Force_None`, `Force_Basic`,
  `Force_256`, `Force_True_Color`)
- A process-wide protected object holding the current mode, with `Set_Override` /
  `Get_Override` / `Reset_Override`
- A `Scoped_Override` controlled type for RAII-style temporary overrides
- A pure `Parse_Color_Flag` function mapping CLI flag strings to `Override_Mode` values

The feature has zero FFI dependencies, is fully cross-platform, and uses Ada's protected
object for thread safety. The detection packages (`Termicap.Color`, `Termicap.TTY`) will
gain a top-of-function override check that short-circuits their normal logic.

---

## 2. Affected Packages

### New packages

| Package | SPARK Level | Responsibility |
|---------|-------------|----------------|
| `Termicap.Override` | Spec: SPARK On, Body: mixed (see section 5) | `Override_Mode` type, `Parse_Color_Flag`, protected state, `Scoped_Override` |

A single new package is sufficient. Splitting into multiple child packages would add
hierarchy complexity without benefit, since the type, state, and parser are tightly coupled
and small.

### Modified packages

| Package | Change |
|---------|--------|
| `Termicap.Color` | Add override check as the first step in `Detect_Color_Level`. When the override is not `Auto`, return the mapped `Color_Level` immediately without executing the 11-step cascade. |
| `Termicap.TTY` | Add override check as the first step in `Is_TTY`. When the override forces color on, return `True`; when it forces `Force_None`, return `False`; when `Auto`, proceed to `isatty()`. |

The current pure-function signatures of `Detect_Color_Level` and `Is_TTY` will gain a
`Global` aspect referencing the override state (see section 5 for the SPARK modelling).

---

## 3. Type Design

### Override_Mode enumeration (FUNC-OVR-001)

```ada
type Override_Mode is (Auto, Force_None, Force_Basic, Force_256, Force_True_Color);
```

Five literals, declared with `SPARK_Mode => On`. Ada's closed enumeration model guarantees
no other values are representable. The `Auto` literal means "no override active; use normal
detection." The four `Force_*` literals map directly to `Color_Level` values.

**Design rationale:** The requirements (FUNC-OVR-001) mandate exactly five literals. A
three-state model (`Force_On`/`Force_Off`/`Auto`) would conflate "force on" with "at what
level." A discriminated record (`Is_Active : Boolean; Level : Color_Level`) would add
complexity without benefit, since the five-literal enum is exhaustively analyzable by SPARK
case statements. See ADR-0010 for the full decision record.

### Override-to-Color mapping (FUNC-OVR-004)

```ada
--  Conceptual mapping (will be a case expression in the body):
--    Force_None       => None
--    Force_Basic      => Basic_16
--    Force_256        => Extended_256
--    Force_True_Color => True_Color
```

### Scoped_Override controlled type (FUNC-OVR-007, FUNC-OVR-008)

```ada
type Scoped_Override (Mode : Override_Mode) is
   new Ada.Finalization.Limited_Controlled with private;
```

Private fields:

| Field | Type | Purpose |
|-------|------|---------|
| `Mode` | `Override_Mode` (discriminant) | The override to install on initialization |
| `Saved` | `Override_Mode` | The mode captured from `Get_Override` before installation |

- `Initialize`: calls `Get_Override` to save the current mode, then calls
  `Set_Override (Mode)`.
- `Finalize`: calls `Set_Override (Saved)`. Suppresses any exception for defense in depth
  (FUNC-OVR-008).
- `Limited_Controlled` (not `Controlled`) prevents copy, which would cause double-restore.

---

## 4. Interface Design

### Package spec outline

```ada
with Ada.Finalization;
with Termicap.Color;

package Termicap.Override
   with SPARK_Mode
is
   -----------------------------------------------------------------------
   --  Types (FUNC-OVR-001)
   -----------------------------------------------------------------------

   type Override_Mode is
      (Auto, Force_None, Force_Basic, Force_256, Force_True_Color);

   -----------------------------------------------------------------------
   --  Global State Access (FUNC-OVR-002, FUNC-OVR-003, FUNC-OVR-011)
   -----------------------------------------------------------------------

   procedure Set_Override (Mode : Override_Mode)
      with Global => (In_Out => Override_State);

   function Get_Override return Override_Mode
      with Global => (Input => Override_State);

   procedure Reset_Override
      with Global => (In_Out => Override_State),
           Post   => Get_Override = Auto;

   -----------------------------------------------------------------------
   --  Mapping (FUNC-OVR-004)
   -----------------------------------------------------------------------

   function To_Color_Level (Mode : Override_Mode)
      return Termicap.Color.Color_Level
      with Global => null,
           Pre    => Mode /= Auto;

   -----------------------------------------------------------------------
   --  CLI Flag Parsing (FUNC-OVR-013)
   -----------------------------------------------------------------------

   function Parse_Color_Flag (Value : String) return Override_Mode
      with Global => null;

   -----------------------------------------------------------------------
   --  Scoped Override (FUNC-OVR-007, FUNC-OVR-008)
   -----------------------------------------------------------------------

   type Scoped_Override (Mode : Override_Mode) is
      new Ada.Finalization.Limited_Controlled with private;

private

   type Scoped_Override (Mode : Override_Mode) is
      new Ada.Finalization.Limited_Controlled with record
         Saved : Override_Mode := Auto;
      end record;

   overriding procedure Initialize (Self : in out Scoped_Override);
   overriding procedure Finalize   (Self : in out Scoped_Override);

end Termicap.Override;
```

### Key signatures

- **`Set_Override`** and **`Get_Override`** delegate to a protected object in the package
  body. The `Global` aspect references an abstract state `Override_State` that models the
  protected object for SPARK.
- **`Reset_Override`** is a thin wrapper: `Set_Override (Auto)`. Its postcondition is
  trivially dischargeable.
- **`To_Color_Level`** is a pure mapping function with a precondition excluding `Auto`
  (callers should check `Get_Override /= Auto` first). This keeps the override check and
  the level translation separate, which is easier to test and prove.
- **`Parse_Color_Flag`** is a pure function (no global reads/writes) that maps strings to
  `Override_Mode`. Unrecognized values return `Auto` (FUNC-OVR-013).

---

## 5. SPARK Strategy

### SPARK boundary map

| Element | SPARK_Mode | Rationale |
|---------|-----------|-----------|
| Package spec (types, function specs) | On | All types and contracts are SPARK-expressible. |
| `Parse_Color_Flag` body | On | Pure string comparison; provable at Gold level. |
| `To_Color_Level` body | On | Pure case expression; provable at Gold level. |
| Protected object declaration | Off | Ada protected types are outside the SPARK 2014 subset. |
| `Set_Override` / `Get_Override` body (delegation to protected object) | Off | Calls into protected operations. |
| `Scoped_Override` (Initialize/Finalize) | Off | `Ada.Finalization.Limited_Controlled` is outside SPARK. |

### Abstract state modelling

```ada
package Termicap.Override
   with SPARK_Mode,
        Abstract_State => (Override_State with External => Async_Readers,
                                                Async_Writers)
is ...
```

The `External` property with `Async_Readers` and `Async_Writers` tells GNATprove that the
state may be read/written concurrently (by the protected object's reader-writer semantics).
This allows SPARK-annotated callers (e.g., the color detection function) to reference
`Override_State` in their `Global` aspects without the prover needing to reason about
tasking.

### Modified detection functions

`Detect_Color_Level` in `Termicap.Color` gains a `Global` aspect:

```ada
function Detect_Color_Level
   (Env    : Termicap.Environment.Environment;
    Is_TTY : Boolean) return Color_Level
   with Global => (Input => Termicap.Override.Override_State);
```

The body adds an override check before the existing cascade:

```ada
--  Step 0: Global override (FUNC-OVR-004)
declare
   Mode : constant Termicap.Override.Override_Mode :=
      Termicap.Override.Get_Override;
begin
   if Mode /= Termicap.Override.Auto then
      return Termicap.Override.To_Color_Level (Mode);
   end if;
end;
--  Steps 1-11: existing cascade follows unchanged...
```

Similarly, `Is_TTY` in `Termicap.TTY` gains an override check at the top:

```ada
--  Override check (FUNC-OVR-005)
declare
   Mode : constant Termicap.Override.Override_Mode :=
      Termicap.Override.Get_Override;
begin
   case Mode is
      when Termicap.Override.Force_Basic
         | Termicap.Override.Force_256
         | Termicap.Override.Force_True_Color => return True;
      when Termicap.Override.Force_None       => return False;
      when Termicap.Override.Auto             => null;  --  fall through
   end case;
end;
```

### SPARK provability targets

| Proof obligation | Level | Mechanism |
|-----------------|-------|-----------|
| `Parse_Color_Flag` returns valid `Override_Mode` for all inputs | Gold | Exhaustive string matching with `Auto` default. No arithmetic, no dynamic allocation. |
| `To_Color_Level` covers all non-Auto modes | Gold | Four-literal case expression; SPARK exhaustiveness analysis. |
| No runtime errors in any SPARK-annotated subprogram | Silver | No arithmetic operations, no array indexing beyond string bounds (handled by `Parse_Color_Flag`'s bounded comparisons). |
| `Reset_Override` postcondition | Silver | Trivially discharged: `Set_Override (Auto)` establishes `Get_Override = Auto`. |

---

## 6. Dependencies

### New dependencies for `Termicap.Override`

| Dependency | Used For |
|-----------|----------|
| `Ada.Finalization` | `Limited_Controlled` base type for `Scoped_Override` |
| `Termicap.Color` | `Color_Level` type for `To_Color_Level` mapping |

No FFI, no `sparklib` containers, no OS calls (FUNC-OVR-009).

### Packages that gain a dependency on `Termicap.Override`

| Package | New Dependency | Change |
|---------|---------------|--------|
| `Termicap.Color` | `with Termicap.Override;` | Override check added to `Detect_Color_Level` |
| `Termicap.TTY` | `with Termicap.Override;` | Override check added to `Is_TTY` |

This introduces a new edge in the dependency graph. Currently `Termicap.Color` depends on
`Termicap.Environment` only. After this feature it also depends on `Termicap.Override`.
The `Termicap.Override` package itself has no dependency on `Termicap.Environment` or
`Termicap.TTY`, so no cycles are introduced.

---

## 7. Error Handling

### Parse_Color_Flag: unknown strings

Unrecognized input strings return `Auto` (FUNC-OVR-013). This is a safe default: the
caller's `Set_Override (Parse_Color_Flag (Unknown))` effectively installs "no override,"
which is the same as never calling `Set_Override` at all.

No exception is raised. The function is total over all possible `String` inputs.

### Scoped_Override.Finalize: exception suppression

`Finalize` calls `Set_Override (Saved)`, which delegates to a protected procedure. Protected
procedure calls cannot raise exceptions in normal operation (the protected object has no
entries and no barriers). As a defense-in-depth measure, `Finalize` wraps the call in a
block with a `when others => null` handler (FUNC-OVR-008).

```ada
overriding procedure Finalize (Self : in out Scoped_Override) is
begin
   Set_Override (Self.Saved);
exception
   when others => null;  --  FUNC-OVR-008: suppress for stack unwinding safety
end Finalize;
```

This complies with the Ada rule that exceptions propagated out of `Finalize` during stack
unwinding cause `Program_Error`.

---

## 8. Risks and Open Questions

| Risk / Question | Mitigation |
|----------------|-----------|
| **`Global` aspect change on `Detect_Color_Level` is a breaking API change for SPARK callers.** Any SPARK-annotated caller that currently declares `Global => null` for `Detect_Color_Level` will need to add `Termicap.Override.Override_State` to its own `Global` aspect. | This is an unavoidable consequence of introducing global state. The change is made once and is straightforward. Document in release notes. |
| **`Scoped_Override` is not task-safe for nested guards across tasks.** Two tasks creating overlapping `Scoped_Override` objects will interleave their save/restore sequences. | This is inherent to process-wide global state. The requirements specify a process-wide mode, not a per-task mode. Document the single-task usage recommendation for `Scoped_Override`. |
| **`Parse_Color_Flag` string comparison may need extension** for future flag values. | The function is pure and self-contained. Adding new recognized strings is a localized, backward-compatible change. |

---

## 9. Framework Survey

### How reference frameworks handle override / force-color

| Framework | Language | Override Model | Scoped Override | Flag Parsing | Thread Safety |
|-----------|----------|---------------|----------------|-------------|---------------|
| **owo-colors** | Rust | `AtomicU8` with 2-bit encoding (force mask + enable bit). `set_override(bool)` / `unset_override()`. | `with_override(bool, closure)` -- saves previous `AtomicU8` value, restores via `Drop` guard. | Boolean only (on/off), no level granularity. | `AtomicU8` with `SeqCst` ordering. |
| **chalk** | JS | `chalk.level` property (0-3) on instances. `new Chalk({level: N})` for per-instance override. | None -- instance-based model avoids global mutation. | Level is a raw integer 0-3. | Single-threaded (Node.js). |
| **termenv** | Go | `WithProfile(profile)` option on `Output` constructor. Global `SetDefaultOutput()`. | None -- override is per-`Output` instance or global singleton swap. | No string-to-profile parser; caller supplies the `Profile` value. | `sync.Once` for lazy detection. No mutex on global `output` variable. |
| **supports-color** | Rust | `FORCE_COLOR` env var parsed at detection time. No programmatic override API. | None. `on_cached()` uses `OnceLock` -- result is immutable after first call. | `FORCE_COLOR` values: `0`, `1`/`true`, `2`, `3`. | `OnceLock` per stream. |
| **rich** | Python | `Console(force_terminal=True, color_system="truecolor")` constructor args. | None -- per-`Console` instance. | Constructor string arg: `"standard"`, `"256"`, `"truecolor"`, or `None`. | Not thread-safe (Python GIL provides some protection). |
| **blessed** | Python | `Terminal(force_styling=True)` constructor arg. | None -- per-`Terminal` instance. | Boolean only. | Not thread-safe. |

### Key takeaways for Ada/SPARK

1. **owo-colors is the closest precedent** for the Ada design: a process-wide atomic state
   with a scoped-restore guard. The Ada protected object replaces the `AtomicU8`, and
   `Scoped_Override` via `Limited_Controlled` replaces the Rust `Drop` guard.

2. **Five-level granularity is richer than most frameworks.** owo-colors and blessed use
   boolean (on/off). chalk uses 0-3 integers. Termicap's five-literal enum matches
   chalk's granularity while using Ada's type system to make values self-documenting.

3. **`Parse_Color_Flag` is unique to Termicap.** Most frameworks either parse `FORCE_COLOR`
   at detection time (supports-color) or accept a raw integer/boolean from the caller
   (chalk, owo-colors). Providing a centralized string-to-enum parser avoids duplication
   across applications.

4. **Instance-based vs. global state.** Go and JS frameworks use per-instance override
   (each `Output` or `Chalk` object has its own level). Termicap uses process-wide global
   state because Ada CLI applications typically have a single output context, and the
   requirements (FUNC-OVR-002) specify process-wide semantics. The `Scoped_Override` type
   provides the temporary-override capability that instance-based models get for free.

---

## 10. Traceability

| Requirement | Design Element |
|-------------|---------------|
| FUNC-OVR-001 | `Override_Mode` enum with five literals in `Termicap.Override` spec, `SPARK_Mode => On` |
| FUNC-OVR-002 | `Set_Override` procedure delegating to protected object; initial value `Auto` |
| FUNC-OVR-003 | `Get_Override` function delegating to protected function; no exceptions |
| FUNC-OVR-004 | `To_Color_Level` mapping + override check at top of `Detect_Color_Level` |
| FUNC-OVR-005 | Override check at top of `Is_TTY` with three-way case on `Override_Mode` |
| FUNC-OVR-006 | Protected object `State` in `Termicap.Override` body with no entries/tasks |
| FUNC-OVR-007 | `Scoped_Override` type derived from `Limited_Controlled`, discriminant `Mode` |
| FUNC-OVR-008 | `Finalize` suppresses exceptions; `Limited_Controlled` prevents copy |
| FUNC-OVR-009 | No `pragma Import`, no `Linker_Options` in `Termicap.Override` |
| FUNC-OVR-010 | SPARK Silver on spec/pure functions; `SPARK_Mode => Off` on protected body and finalization |
| FUNC-OVR-011 | `Reset_Override` wrapper with `Post => Get_Override = Auto` |
| FUNC-OVR-012 | All behaviors testable via `Set_Override` / `Get_Override` / detection function calls |
| FUNC-OVR-013 | `Parse_Color_Flag` pure function, case-insensitive, `Auto` for unknowns |
| FUNC-OVR-014 | No `Ada.Command_Line` access anywhere in `Termicap.Override` |
