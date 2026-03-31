# API Reference: `Termicap.Environment`

Package providing an immutable snapshot of environment variable bindings with SPARK-provable query operations.

**File:** `src/termicap-environment.ads`
**SPARK_Mode:** On (spec and body)
**License:** Apache-2.0

---

## Overview

`Termicap.Environment` stores a snapshot of environment variable bindings as a plain Ada record value. Once populated (either via `Termicap.Environment.Capture.Capture_Current` or programmatically with `Insert`), the snapshot is logically immutable and all query operations have `Global => null` contracts — making them fully SPARK Silver provable.

Keys are **case-normalized** (lowercased) at insertion time. All lookups are therefore case-insensitive. Values are stored **verbatim**.

The presence/value distinction critical for NO_COLOR compliance is preserved: a variable set to the empty string has an entry in the map, whereas an absent variable has no entry. Use `Contains` (not `Value /= ""`) to check for presence.

---

## Types

### `Environment`

```ada
type Environment is private;
```

An opaque record containing a hash map from normalized (lowercase) variable names to their values. Represents either a captured OS environment snapshot or a programmatically constructed test environment.

**Requirement:** FUNC-ENV-001

---

### `String_Vector`

```ada
package String_Vectors is new
  SPARK.Containers.Formal.Unbounded_Vectors
    (Index_Type   => Positive,
     Element_Type => String);

subtype String_Vector is String_Vectors.Vector;
```

A SPARK-compatible, variable-length vector of `String` values. Used as the `Candidates` parameter of `Value_Matches`. With Ada 2022 aggregate syntax, callers can write inline vectors:

```ada
Value_Matches (Env, "TERM", ["xterm", "rxvt", "linux"])
```

**Requirement:** FUNC-ENV-008

---

## Constants

### `EMPTY_ENVIRONMENT`

```ada
EMPTY_ENVIRONMENT : constant Environment;
```

An environment snapshot containing no variables. Use as the starting point for programmatic construction in tests or other contexts where OS interaction is undesirable.

```ada
Env : Environment := EMPTY_ENVIRONMENT;
Insert (Env, "TERM", "xterm-256color");
```

**Requirement:** FUNC-ENV-005

---

## Functions

### `Contains`

```ada
function Contains (Env : Environment; Name : String) return Boolean
  with Global => null;
```

Check whether an environment variable is present in a snapshot.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | The environment snapshot to query. |
| `Name` | in | Variable name; case-insensitive (normalized to lowercase before lookup). |

**Returns:** `True` if the variable is present in the snapshot, even if its value is the empty string. `False` if the variable is absent.

**SPARK contract:** `Global => null` — no hidden state dependency; GNATprove-verifiable.

**NO_COLOR usage pattern:**

```ada
--  Correct: variable is present (possibly with empty value)
if Contains (Env, "NO_COLOR") then
   Disable_Color;
end if;
```

**Requirement:** FUNC-ENV-002

---

### `Value`

```ada
function Value (Env : Environment; Name : String) return String
  with Global => null;
```

Retrieve the value of an environment variable.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | The environment snapshot to query. |
| `Name` | in | Variable name; case-insensitive. |

**Returns:** The variable's value as stored (verbatim), or `""` if the variable is not present.

**SPARK contract:** `Global => null`.

**Note:** Both an absent variable and a variable explicitly set to `""` return `""` from `Value`. Use `Contains` first when the distinction matters.

```ada
if Contains (Env, "TERM") then
   declare
      T : constant String := Value (Env, "TERM");
   begin
      --  T is the actual TERM value, guaranteed non-absent
   end;
end if;
```

**Requirement:** FUNC-ENV-003

---

### `Equal_Case_Insensitive`

```ada
function Equal_Case_Insensitive (Left : String; Right : String) return Boolean
  with Global => null;
```

Case-insensitive equality comparison for environment variable values.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Left` | in | First string operand. |
| `Right` | in | Second string operand. |

**Returns:** `True` if `Left` and `Right` are equal when both are lowercased.

**SPARK contract:** `Global => null`.

```ada
Equal_Case_Insensitive ("truecolor", "TrueColor")  --  True
Equal_Case_Insensitive ("truecolor", "24bit")       --  False
Equal_Case_Insensitive ("", "")                     --  True
```

Useful for comparing `COLORTERM` or `TERM` values against known identifiers without caring about the casing used by the terminal emulator.

**Requirement:** FUNC-ENV-006

---

### `Value_Matches`

```ada
function Value_Matches
  (Env        : Environment;
   Name       : String;
   Candidates : String_Vector) return Boolean
  with Global => null;
```

Check whether an environment variable's value matches any of a set of candidate strings, using case-insensitive comparison.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | The environment snapshot. |
| `Name` | in | Variable name; case-insensitive. |
| `Candidates` | in | Vector of candidate values to match against. |

**Returns:** `True` if the variable is present in `Env` and its value case-insensitively matches at least one element of `Candidates`. `False` if the variable is absent, or if no candidate matches.

**SPARK contract:** `Global => null`.

```ada
--  Ada 2022 aggregate syntax
if Value_Matches (Env, "COLORTERM", ["truecolor", "24bit"]) then
   --  Terminal claims true-color support
end if;

if Value_Matches (Env, "TERM_PROGRAM", ["iTerm.app", "WezTerm", "vscode"]) then
   --  Known true-color terminal emulator
end if;
```

**Requirement:** FUNC-ENV-008

---

## Procedures

### `Insert`

```ada
procedure Insert (Env : in out Environment; Name : String; Value : String)
  with Global => null;
```

Add or replace a variable binding in an environment snapshot.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in out | The environment snapshot to modify. |
| `Name` | in | Variable name. Normalized to lowercase before storage. |
| `Value` | in | Variable value. Stored verbatim. |

If a binding for `Name` already exists (under case-insensitive comparison), it is replaced with the new `Value`.

**SPARK contract:** `Global => null`.

**Testing pattern:**

```ada
declare
   Env : Environment := EMPTY_ENVIRONMENT;
begin
   Insert (Env, "NO_COLOR", "");            --  set, empty value
   Insert (Env, "TERM",     "xterm-256color");
   Insert (Env, "COLORTERM", "truecolor");

   pragma Assert (Contains (Env, "NO_COLOR"));           --  True
   pragma Assert (Value (Env, "TERM") = "xterm-256color");
end;
```

**Requirement:** FUNC-ENV-005

---

## Child Package: `Termicap.Environment.Capture`

**File:** `src/termicap-environment-capture.ads`
**SPARK_Mode:** Off

The sole OS interaction point for environment variable access. Reads the live process environment via `Ada.Environment_Variables` and produces an immutable `Environment` snapshot. All downstream detection logic operates on the captured snapshot, which is fully SPARK-provable.

### `Capture_Current`

```ada
procedure Capture_Current (Env : out Environment);
```

Capture the current process environment into a snapshot.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | out | Receives the populated snapshot. Any previous content is discarded. |

Iterates over all variables in the current process environment via `Ada.Environment_Variables.Iterate` and calls `Insert` for each. The resulting snapshot is complete and independent of subsequent OS environment changes.

**No SPARK contract** — this procedure is in a `SPARK_Mode => Off` package because it performs OS calls that GNATprove cannot verify.

**Typical usage:**

```ada
with Termicap.Environment;         use Termicap.Environment;
with Termicap.Environment.Capture; use Termicap.Environment.Capture;

procedure Main is
   Env : Environment;
begin
   Capture_Current (Env);
   --  Env now contains a snapshot of the process environment.
   --  Pass Env to detection functions as needed.
   if Contains (Env, "NO_COLOR") then
      --  ...
   end if;
end Main;
```

**Requirement:** FUNC-ENV-004

---

## Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-ENV-001 | `Environment` type | Silver |
| FUNC-ENV-002 | `Contains` | Silver |
| FUNC-ENV-003 | `Value` | Silver |
| FUNC-ENV-004 | `Capture_Current` | Off |
| FUNC-ENV-005 | `EMPTY_ENVIRONMENT`, `Insert` | Silver |
| FUNC-ENV-006 | `Equal_Case_Insensitive` | Silver |
| FUNC-ENV-007 | `Global => null` contracts on all query functions | Silver |
| FUNC-ENV-008 | `Value_Matches`, `String_Vector` | Silver |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy and SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — capture flow, query flow, testability pattern
- **ADR-0001** (`docs/adr/0001-environment-snapshot-storage-strategy.md`) — container choice rationale
- **ADR-0002** (`docs/adr/0002-multi-candidate-matching-spark-boundary.md`) — `Value_Matches` design decision
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`) — full design rationale
