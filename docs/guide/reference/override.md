# API Reference: `Termicap.Override`

Package providing process-wide color output override for `--color` flag support.

**File:** `src/termicap-override.ads`
**SPARK_Mode:** On (spec and pure functions); Off (protected object body, `Set_Override`/`Get_Override` bodies, `Initialize`/`Finalize`)
**License:** Apache-2.0

---

## Overview

`Termicap.Override` allows CLI applications to bypass automatic terminal detection and force a specific color level (or disable color entirely) for the lifetime of the process. It is the mechanism behind `--color=always`, `--color=never`, `--color=256`, and equivalent flags.

The package provides:

- A five-literal `Override_Mode` enumeration covering `Auto` (no override) and four forced levels.
- `Set_Override` / `Get_Override` / `Reset_Override` — thread-safe access to the process-wide state.
- `Parse_Color_Flag` — a pure, case-insensitive function that maps CLI flag strings to `Override_Mode` values.
- `Scoped_Override` — an RAII guard that installs an override for the duration of a lexical scope and restores the previous mode on exit.

Once an override is installed, `Termicap.Color.Detect_Color_Level` and `Termicap.TTY.Is_TTY` both check it as their first step and return immediately, skipping all environment-variable heuristics and OS calls.

No FFI, no OS calls, no `Ada.Command_Line` access.

**Requirements:** FUNC-OVR-001 through FUNC-OVR-014

---

## Types

### `Override_Mode`

```ada
type Override_Mode is
  (Auto, Force_None, Force_Basic, Force_256, Force_True_Color);
```

Five-literal flat enumeration. `Auto` means no override is active and all detection functions execute their normal logic. The four `Force_*` literals map directly onto `Termicap.Color.Color_Level` values and short-circuit detection.

| Literal | `Color_Level` equivalent | Typical CLI flag(s) |
|---------|--------------------------|---------------------|
| `Auto` | *(no override)* | `--color=auto` |
| `Force_None` | `None` | `--color=never`, `--color=false`, `--color=off`, `--color=0` |
| `Force_Basic` | `Basic_16` | `--color=true`, `--color=1`, `--color=16` |
| `Force_256` | `Extended_256` | `--color=256`, `--color=2` |
| `Force_True_Color` | `True_Color` | `--color=always`, `--color=truecolor`, `--color=16m`, `--color=3` |

**SPARK note:** The type is declared with `SPARK_Mode => On`. Ada's closed enumeration model guarantees no other values are representable. See ADR-0010 for the rationale for choosing five literals over a discriminated record or boolean.

**Requirement:** FUNC-OVR-001

---

### `Scoped_Override`

```ada
type Scoped_Override (Mode : Override_Mode) is
  new Ada.Finalization.Limited_Controlled with private;
```

RAII guard for temporarily installing an override within a lexical scope.

| Field | Kind | Description |
|-------|------|-------------|
| `Mode` | Discriminant | The override to install when the object is declared. |
| `Saved` | Private record field | The mode captured from `Get_Override` at declaration time; restored on scope exit. |

**Lifecycle:**

1. **Declaration (`Initialize`):** Calls `Get_Override` to capture the current mode into `Saved`, then calls `Set_Override (Mode)`.
2. **Block body executes** with `Mode` active.
3. **Scope exit (`Finalize`):** Calls `Set_Override (Saved)`. Any exception raised during finalization is suppressed.

**Exception safety:** `Finalize` wraps its body in a `when others => null` handler. This is required because Ada raises `Program_Error` when an exception propagates out of `Finalize` during stack unwinding (FUNC-OVR-008).

**Copy prevention:** The type is `Limited_Controlled` (not `Controlled`). Copying would create two objects sharing the same `Saved` value, causing a double-restore when both finalize (FUNC-OVR-008).

**Requirements:** FUNC-OVR-007, FUNC-OVR-008

---

## Subprograms

### `Set_Override`

```ada
procedure Set_Override (Mode : Override_Mode)
  with Global => (In_Out => Override_State);
```

Set the process-wide color override.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Mode` | in | The override to install. Pass `Auto` to remove any previously installed override and restore normal detection. |

**Thread safety:** Delegates to a protected procedure. Safe to call from multiple Ada tasks concurrently.

**Initial state:** The protected object is initialized to `Auto`. If `Set_Override` is never called, `Get_Override` returns `Auto` and all detection functions operate normally.

**Requirement:** FUNC-OVR-002

---

### `Get_Override`

```ada
function Get_Override return Override_Mode
  with Global => (Input => Override_State);
```

Retrieve the current process-wide color override.

**Returns:** The `Override_Mode` most recently passed to `Set_Override`, or `Auto` if `Set_Override` has never been called.

**Thread safety:** Delegates to a protected function. Safe to call from multiple Ada tasks concurrently. Never raises an exception.

**Requirement:** FUNC-OVR-003

---

### `Reset_Override`

```ada
procedure Reset_Override
  with Global => (In_Out => Override_State),
       Post   => Get_Override = Auto;
```

Remove any previously installed override, restoring `Auto`.

Semantically equivalent to `Set_Override (Auto)`. Provided as a self-documenting convenience for the common "clear override" case. The postcondition `Get_Override = Auto` is GNATprove-verifiable at Silver level.

**Thread safety:** Same as `Set_Override`.

**Requirement:** FUNC-OVR-011

---

### `Parse_Color_Flag`

```ada
function Parse_Color_Flag (Value : String) return Override_Mode
  with Global => null;
```

Parse a `--color` flag value string into an `Override_Mode`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Value` | in | The raw flag value string, e.g. `"always"`, `"256"`, `"never"`. |

**Returns:** The `Override_Mode` corresponding to `Value`, or `Auto` for any unrecognised string.

**Alias table** (case-insensitive matching):

| Input string(s) | Result |
|-----------------|--------|
| `"never"`, `"false"`, `"off"`, `"0"` | `Force_None` |
| `"true"`, `"1"`, `"16"` | `Force_Basic` |
| `"2"`, `"256"` | `Force_256` |
| `"always"`, `"truecolor"`, `"16m"`, `"3"` | `Force_True_Color` |
| `"auto"` or any other string | `Auto` |

**Behavior on unknown input:** Returns `Auto`. This means `Set_Override (Parse_Color_Flag (unknown))` is equivalent to calling `Reset_Override` — a safe, non-raising default. No exception is raised for any input.

**SPARK contract:** `Global => null` — no side effects, no global reads. Provable at Gold level (pure string comparison, no arithmetic, no dynamic allocation). The function is total over all `String` inputs.

**Requirement:** FUNC-OVR-013

---

## SPARK Contracts Summary

| Subprogram | `Global` aspect | Provability |
|-----------|----------------|-------------|
| `Set_Override` | `(In_Out => Override_State)` | Spec: Silver; body: Off (protected procedure) |
| `Get_Override` | `(Input => Override_State)` | Spec: Silver; body: Off (protected function) |
| `Reset_Override` | `(In_Out => Override_State)`, `Post => Get_Override = Auto` | Silver (postcondition trivially discharged) |
| `Parse_Color_Flag` | `null` | Gold (pure string comparison) |

The `Abstract_State` annotation on the package spec:

```ada
package Termicap.Override
  with
    SPARK_Mode,
    Abstract_State =>
      (Override_State with External => (Async_Readers, Async_Writers))
```

The `External` property with `Async_Readers` and `Async_Writers` tells GNATprove that `Override_State` may be read and written concurrently (by the protected object's reader-writer semantics). SPARK-annotated callers — including `Termicap.Color.Detect_Color_Level` and `Termicap.TTY.Is_TTY` — reference `Override_State` in their own `Global` aspects. This means any SPARK caller of those functions must also include `Termicap.Override.Override_State` in its `Global` aspect.

---

## Usage Examples

### Setting an override from a CLI flag

```ada
with Termicap.Override; use Termicap.Override;

--  Parse --color=always from argv and install the override
Set_Override (Parse_Color_Flag ("always"));
--  Get_Override = Force_True_Color

--  All subsequent detection calls short-circuit:
--    Detect_Color_Level (Env, Is_TTY => False) → True_Color
--    Is_TTY (Stdout) → True
```

### Resetting the override

```ada
Reset_Override;
--  Get_Override = Auto; normal detection resumes
```

### Scoped override

```ada
declare
   Guard : Scoped_Override (Mode => Force_None);
   --  Initialize: captures current mode, installs Force_None
begin
   --  Detect_Color_Level returns None regardless of environment
   Level := Detect_Color_Level (Env, Is_TTY => True);
   pragma Assert (Level = None);
end;
--  Finalize: previous mode restored automatically (even on exception)
```

### Testability — no OS interaction required

```ada
--  Test that Force_True_Color short-circuits the 11-step cascade
Set_Override (Force_True_Color);
declare
   Env : constant Environment := EMPTY_ENVIRONMENT;
   --  No environment variables set; would normally return None
   Level : constant Color_Level :=
     Detect_Color_Level (Env, Is_TTY => False);
begin
   pragma Assert (Level = True_Color);
end;
Reset_Override;
```

---

## Thread Safety Notes

- `Set_Override`, `Get_Override`, and `Reset_Override` are safe to call concurrently from multiple Ada tasks.
- `Scoped_Override` is **not** safe for nested guards across tasks. Two tasks creating overlapping `Scoped_Override` objects will interleave their save/restore sequences. The recommended usage is single-task scope guards, typically at application startup before spawning tasks.

---

## Related Documents

- **Tech Spec** (`docs/tech-specs/override.md`): Full design rationale, SPARK strategy, and framework survey
- **ADR-0010** (`docs/adr/0010-override-mode-flat-enum.md`): Rationale for the five-literal flat enumeration
- **Runtime View** (`docs/architecture/04-runtime-view.md`): Scenario 16 — override flow sequence diagrams
- **Building Blocks** (`docs/architecture/03-building-blocks.md`): `Termicap.Override` in the package hierarchy and SPARK boundary diagram
- **Requirements** (`docs/requirements/func-override.sdoc`): FUNC-OVR-001 through FUNC-OVR-014
