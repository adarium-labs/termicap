# F1: Environment Variable Abstraction

**Feature:** Environment Variable Abstraction Layer
**Requirements:** FUNC-ENV-001 through FUNC-ENV-008
**Status:** Approved
**Date:** 2026-03-29

---

## A. Framework Survey

### How reference libraries handle env var access for testability

#### termenv (Go) -- Environ interface

termenv defines a minimal `Environ` interface:

```go
type Environ interface {
    Environ() []string
    Getenv(string) string
}
```

This interface is stored in the `Output` struct and defaults to an `osEnviron` implementation that wraps `os.Environ()` / `os.Getenv()`. During testing or SSH-forwarded environments, callers inject an alternative implementation via `WithEnvironment(environ Environ)`. All detection logic (`ColorProfile()`, `EnvNoColor()`, `isTTY()`) reads exclusively through `o.environ.Getenv(key)`, never calling `os.Getenv` directly.

**Strengths:**
- Clean separation between detection logic and OS access.
- Testing with mock environments is trivial.
- SSH session environments can be injected directly.
- Detection functions become testable without modifying process state.

**Weaknesses:**
- Go interface dispatch is incompatible with SPARK verification.
- `Getenv` returns `""` for both "not set" and "set to empty", losing the presence/value distinction. termenv works around this by only checking `!= ""`, which deviates from the NO_COLOR spec.
- `Environ() []string` returns the full `KEY=VALUE` list, which is never used by detection logic.

#### supports-color (JavaScript) -- Direct env access

supports-color accesses `process.env` directly (a global object in Node.js):

```javascript
const {env} = process;
// ...
if ('NO_COLOR' in env) { ... }
if (env.TERM === 'dumb') { ... }
```

It uses JavaScript's `in` operator to distinguish "key exists" from "key has a value", which correctly handles the NO_COLOR case. However, the global `process.env` access makes the function impossible to unit test without mutating global state.

**Strengths:**
- Simple, direct access with no abstraction overhead.
- JavaScript's `in` operator handles presence vs. value correctly.

**Weaknesses:**
- Tests must set/unset real process env vars (fragile, non-parallelizable).
- No way to inject mock environments.

#### rust-supports-color -- std::env::var

Rust's `std::env::var()` returns `Result<String, VarError>`, where `VarError::NotPresent` distinguishes missing from empty. The Rust crate accesses `std::env::var` directly in its detection logic.

**Strengths:**
- Rust's `Result` type correctly models presence vs. value.

**Weaknesses:**
- Same testability problem as supports-color: global process state.

### What Termicap should adopt and why

Termicap should adopt **termenv's snapshot pattern with Ada-specific improvements**:

1. **Snapshot-based approach** (like termenv's `Environ` but as a value type, not an interface): Capture the environment once into an immutable snapshot, then pass the snapshot to all detection functions as a parameter. This maps directly to SPARK's `Global => null` contracts.

2. **Preserve presence/value distinction** (improving on termenv): termenv loses this distinction because `Getenv` returns `""` for both missing and empty. Termicap must track which keys are present, since NO_COLOR with an empty value is different from NO_COLOR absent (per the no-color.org spec, FUNC-ENV-002).

3. **Concrete type, not interface/tagged type**: SPARK Silver verification requires concrete types with deterministic behavior. A discriminated or record type with a SPARK-compatible container avoids the proof complications of dynamic dispatch.

4. **Case-insensitive key lookup**: Environment variable names are case-sensitive on POSIX but case-insensitive on Windows. For maximum portability and to support the common pattern of comparing against known names, the abstraction should store keys in a normalized (lowercased) form.

See [ADR-0001](../adr/0001-environment-snapshot-storage-strategy.md) for the container choice rationale.

---

## B. Package Design

### Package hierarchy

```
Termicap                          -- Root package (existing)
   Termicap.Environment           -- SPARK Silver: snapshot type, queries, builder
   Termicap.Environment.Capture   -- Ada only (SPARK_Mode => Off): OS env capture via FFI
```

### SPARK boundaries

| Package | SPARK_Mode | Rationale |
|---------|-----------|-----------|
| `Termicap.Environment` (spec) | On | Snapshot type, Contains, Value, builder API -- all pure |
| `Termicap.Environment` (body) | On | All operations are pure map lookups |
| `Termicap.Environment.Capture` (spec) | Off | Imports Ada.Environment_Variables (FFI boundary) |
| `Termicap.Environment.Capture` (body) | Off | Calls Ada.Environment_Variables.Iterate, .Value |

### Relationship to root package

`Termicap.Environment` is a child package of `Termicap`. It has no dependency on any other `Termicap` child package and serves as a foundational building block. All downstream detection packages (`Termicap.Detection`, `Termicap.Standards`, etc.) will depend on it.

The root `Termicap` package remains a namespace-only package with no types or subprograms.

---

## C. Type Design

### Environment snapshot type

The `Environment` type is a record containing a map from normalized (lowercased) variable names to their values. The map stores keys that are present in the environment; absent keys have no entry.

```ada
type Environment is private;
```

The private completion uses `SPARK.Containers.Formal.Unbounded_Hashed_Maps` from sparklib, instantiated with `String` key and `String` element types.

#### Why Unbounded_Hashed_Maps from sparklib

See [ADR-0001](../adr/0001-environment-snapshot-storage-strategy.md) for the full decision rationale. In summary:

- **SPARK Silver compatible**: sparklib's formal containers are designed for SPARK verification and come with functional models for proof.
- **Unbounded**: The number of environment variables varies between systems (typically 30-200). A bounded container would require an arbitrary capacity constant, wasting memory on small environments or truncating on large ones. The unbounded variant uses dynamic allocation internally but exposes a SPARK-provable interface.
- **Hashed**: O(1) average lookup is ideal for the query pattern (many lookups during detection).
- **String keys and elements**: Both env var names and values are standard Ada `String`. The hash function and equality operate on the lowercased normalized form.

The alternative of `Ada.Containers.Indefinite_Hashed_Maps` was rejected because it is not SPARK-compatible.

### Presence vs. empty-value distinction (FUNC-ENV-002)

This is critical for NO_COLOR compliance. The design handles it as follows:

- **Key present with value `""`**: The map contains an entry with the key mapped to `""`. `Contains` returns `True`. `Value` returns `""`.
- **Key absent**: The map has no entry for the key. `Contains` returns `False`. `Value` returns `""` (safe default per FUNC-ENV-003).

The distinction is made solely by `Contains`. Callers checking NO_COLOR must use `Contains`, not `Value /= ""`.

Example usage pattern:
```ada
if Env.Contains ("NO_COLOR") then
   --  NO_COLOR is set (even if empty) -- disable colors
end if;
```

### Case-insensitive comparison approach

All keys are normalized to lowercase at insertion time using `Ada.Characters.Handling.To_Lower`. This means:

- `Insert (Env, "NO_COLOR", "1")` stores the key as `"no_color"`.
- `Contains (Env, "NO_COLOR")`, `Contains (Env, "no_color")`, and `Contains (Env, "No_Color")` all return `True`.
- `Value (Env, "TERM")` and `Value (Env, "term")` return the same result.

The hash function hashes the lowercased form. The equality function compares lowercased forms.

This approach is simple, consistent, and SPARK-provable. It correctly handles the Windows case-insensitivity requirement and is harmless on POSIX (where env var names are conventionally uppercase).

Note: Only keys are case-normalized. Values are stored verbatim, preserving original casing. This is important because values like `"truecolor"` vs `"TrueColor"` need case-insensitive comparison at the detection layer, not at the storage layer. The `Value_Matches` utility (FUNC-ENV-006) handles value comparison separately.

---

## D. SPARK Strategy

### SPARK_Mode placement

```ada
package Termicap.Environment
   with SPARK_Mode
is
   --  All declarations here are SPARK-visible
end Termicap.Environment;

package body Termicap.Environment
   with SPARK_Mode
is
   --  All implementations here are SPARK-proved
end Termicap.Environment;
```

```ada
package Termicap.Environment.Capture
   with SPARK_Mode => Off
is
   --  OS interaction -- outside SPARK boundary
end Termicap.Environment.Capture;
```

### Global contracts

All query functions on `Environment` receive the snapshot as a parameter and have `Global => null`:

```ada
function Contains (Env : Environment; Name : String) return Boolean
   with Global => null;

function Value (Env : Environment; Name : String) return String
   with Global => null;
```

The builder procedures (`Insert`, `Empty`) also have `Global => null` since they operate only on the `Environment` parameter.

The `Capture` procedure in `Termicap.Environment.Capture` does NOT have `Global => null` because it reads the process environment. Since it is in a `SPARK_Mode => Off` package, no SPARK contract is needed.

### Abstract state considerations

Unlike the synthesis report's suggestion of an `Environment_State` abstract state, this design **does not use abstract state**. The environment is passed as an explicit parameter, eliminating hidden state dependencies entirely. This is a deliberate improvement over the abstract state pattern:

- No need for `Volatile_Function` or `External` state.
- All query functions are genuinely pure.
- The `Capture` operation is isolated in a non-SPARK child package.
- Downstream detection functions can take `Environment` as a parameter with `Global => null`.

---

## E. API Signatures

### Core query functions (SPARK Silver)

```ada
-------------------------------------------------------------------------------
--  Termicap.Environment - Environment Variable Snapshot
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

package Termicap.Environment
   with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types
   ---------------------------------------------------------------------------

   type Environment is private;

   EMPTY_ENVIRONMENT : constant Environment;

   ---------------------------------------------------------------------------
   --  Query Operations (FUNC-ENV-002, FUNC-ENV-003, FUNC-ENV-007)
   ---------------------------------------------------------------------------

   --  @summary Check whether an environment variable is present.
   --  @param Env  The environment snapshot to query.
   --  @param Name The variable name (case-insensitive).
   --  @return True if the variable is present, even if its value is empty.
   --  @relation(FUNC-ENV-002): Presence check for NO_COLOR compliance
   function Contains (Env : Environment; Name : String) return Boolean
      with Global => null;

   --  @summary Retrieve the value of an environment variable.
   --  @param Env  The environment snapshot to query.
   --  @param Name The variable name (case-insensitive).
   --  @return The variable's value, or "" if not present.
   --  @relation(FUNC-ENV-003): Value retrieval with empty default
   function Value (Env : Environment; Name : String) return String
      with Global => null;

   ---------------------------------------------------------------------------
   --  Builder Operations (FUNC-ENV-005)
   ---------------------------------------------------------------------------

   --  @summary Add or replace a variable binding in an environment snapshot.
   --  @param Env   The environment snapshot to modify.
   --  @param Name  The variable name (will be case-normalized).
   --  @param Value The variable value (stored verbatim).
   --  @relation(FUNC-ENV-005): Programmatic construction for testing
   procedure Insert
      (Env   : in out Environment;
       Name  :        String;
       Value :        String)
      with Global => null;

   ---------------------------------------------------------------------------
   --  Comparison Utilities (FUNC-ENV-006)
   ---------------------------------------------------------------------------

   --  @summary Case-insensitive equality comparison for env var values.
   --  @param Left  First string.
   --  @param Right Second string.
   --  @return True if Left and Right are equal ignoring case.
   --  @relation(FUNC-ENV-006): Case-insensitive value comparison
   function Equal_Case_Insensitive
      (Left  : String;
       Right : String) return Boolean
      with Global => null;

   ---------------------------------------------------------------------------
   --  Multi-Candidate Matching (FUNC-ENV-008)
   ---------------------------------------------------------------------------

   --  String_Vectors provides a SPARK-compatible container for passing
   --  variable-length lists of String values. sparklib's Unbounded_Vectors
   --  accepts indefinite element types and is fully SPARK-provable.
   --  With Ada 2022 aggregate syntax, callers can write:
   --    Value_Matches (Env, "TERM", ["xterm", "rxvt", "linux"])

   package String_Vectors is new
      SPARK.Containers.Formal.Unbounded_Vectors
        (Index_Type   => Positive,
         Element_Type => String);

   subtype String_Vector is String_Vectors.Vector;

   --  @summary Check if an env var's value matches any candidate (case-insensitive).
   --  @param Env        The environment snapshot.
   --  @param Name       The variable name (case-insensitive).
   --  @param Candidates Vector of candidate values to match against.
   --  @return True if the variable is present and its value case-insensitively
   --          matches any element of Candidates.
   --  @relation(FUNC-ENV-008): Multi-candidate value matching
   function Value_Matches
      (Env        : Environment;
       Name       : String;
       Candidates : String_Vector) return Boolean
      with Global => null;

private
   --  Private completion using sparklib formal container
   --  (see implementation notes below)

end Termicap.Environment;
```

**Note on `Value_Matches` and `String_Vector`:** The `SPARK.Containers.Formal.Unbounded_Vectors` package from sparklib accepts indefinite element types (like `String`) and is fully SPARK-provable. This avoids the need for access types or `SPARK_Mode => Off` regions.

With Ada 2022 container aggregate syntax, callers can write concise expressions:
```ada
if Value_Matches (Env, "TERM_PROGRAM", ["iTerm.app", "WezTerm", "vscode"]) then ...
```

This approach was chosen over two alternatives:
- **Access-type array** (`access constant String`): Not SPARK-compatible — anonymous access types cannot be stored in composite types in SPARK. Additionally, `pragma SPARK_Mode (Off)` cannot be toggled back to `On` within the same package section.
- **Fixed-parameter overloads** (`C1, C2, C3 : String := ""`): SPARK-provable but artificially limits the candidate count and requires sentinel handling for defaulted parameters.

See [ADR-0002](../adr/0002-multi-candidate-matching-spark-boundary.md) for the updated decision rationale.

### Capture procedure (Ada-only)

```ada
-------------------------------------------------------------------------------
--  Termicap.Environment.Capture - OS Environment Capture
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Captures the current process environment into an Environment snapshot.
--
--  @description
--  This package contains the sole OS interaction point for environment
--  variable access. It reads the live process environment via
--  Ada.Environment_Variables and produces an immutable snapshot.
--
--  Requirements Coverage:
--    - @relation(FUNC-ENV-004): Capture current process environment

package Termicap.Environment.Capture
   with SPARK_Mode => Off
is

   --  @summary Capture the current process environment.
   --  @param Env  The environment snapshot to populate.
   --  @relation(FUNC-ENV-004): Capture current process environment
   procedure Capture_Current (Env : out Environment);

end Termicap.Environment.Capture;
```

The body will use `Ada.Environment_Variables.Iterate` to enumerate all variables and call `Insert` for each.

---

## F. Error Handling

### Analysis: Is error handling needed?

Environment variable queries are inherently safe operations:

- `Contains` always returns a valid `Boolean`.
- `Value` always returns a valid `String` (empty string for missing keys -- FUNC-ENV-003).
- `Insert` always succeeds (may replace existing value).
- `Capture_Current` reads the OS environment, which is always available. Even in degenerate cases (empty environment), the result is simply an empty snapshot.

**Conclusion: No error handling is needed for this package.** The `functional` crate's `Result` types are not required here. All operations are total functions with well-defined behavior for all inputs.

The only conceivable failure mode is memory exhaustion during `Insert` (from the underlying container allocation), which would raise `Storage_Error` -- a language-defined exception that cannot be prevented at the application level and should not be caught.

### Why not use Result types here

- `Contains` and `Value` have natural return types (`Boolean`, `String`).
- There is no "error case" to represent -- a missing key is a normal condition, not an error.
- Wrapping these returns in `Result` types would add complexity and verbosity for zero benefit.
- Downstream detection packages *may* use `Result` types for their own operations (e.g., parsing FORCE_COLOR values), but the environment abstraction itself does not need them.

---

## G. Dependencies

### From `functional` crate

Nothing. This package does not use Result types (see Section F).

### From `sparklib` crate

- `SPARK.Containers.Formal.Unbounded_Hashed_Maps` -- used for the internal storage of the `Environment` type.
- `SPARK.Containers.Types` -- for `Count_Type` used by the map.

### From the Ada standard library

- `Ada.Characters.Handling` -- for `To_Lower` (key normalization).
- `Ada.Strings.Hash` -- for the hash function (applied to lowercased keys).
- `Ada.Environment_Variables` -- only in `Termicap.Environment.Capture` (SPARK_Mode => Off).

### New dependencies

None required.

---

## H. File Layout

| File | SPARK | Description |
|------|-------|-------------|
| `src/termicap-environment.ads` | Yes | Environment type, query API, builder API, comparison utilities |
| `src/termicap-environment.adb` | Yes | Implementation of all pure operations |
| `src/termicap-environment-capture.ads` | No | Capture_Current procedure spec |
| `src/termicap-environment-capture.adb` | No | Implementation using Ada.Environment_Variables |

### File naming rationale

File names follow the Ada convention of lowercase with dashes matching the package hierarchy:
- `Termicap.Environment` maps to `termicap-environment.ads` / `.adb`
- `Termicap.Environment.Capture` maps to `termicap-environment-capture.ads` / `.adb`

No changes to `termicap.gpr` are needed since all files are in the existing `src/` source directory.

---

## I. Testing Strategy

### How to test with mock environments

The snapshot-based design makes testing straightforward. Tests construct `Environment` values programmatically using `Insert`, with no OS interaction:

```ada
declare
   Env : Environment := EMPTY_ENVIRONMENT;
begin
   Insert (Env, "NO_COLOR", "");
   Insert (Env, "TERM", "xterm-256color");
   Insert (Env, "COLORTERM", "truecolor");

   pragma Assert (Contains (Env, "NO_COLOR"));
   pragma Assert (Value (Env, "TERM") = "xterm-256color");
end;
```

No mocking framework is needed. No process environment is touched. Tests are parallelizable and deterministic.

### Key test scenarios

#### 1. Empty environment
- `EMPTY_ENVIRONMENT` contains no variables.
- `Contains` returns `False` for any name.
- `Value` returns `""` for any name.

#### 2. Single variable
- Insert `"TERM" => "xterm"`.
- `Contains ("TERM")` returns `True`.
- `Value ("TERM")` returns `"xterm"`.
- `Contains ("OTHER")` returns `False`.

#### 3. NO_COLOR edge cases (FUNC-ENV-002)
- `NO_COLOR` set to `""` (empty): `Contains` returns `True`, `Value` returns `""`.
- `NO_COLOR` set to `"1"`: `Contains` returns `True`, `Value` returns `"1"`.
- `NO_COLOR` absent: `Contains` returns `False`.
- This is the critical distinction: presence with empty value is different from absence.

#### 4. Case insensitivity (FUNC-ENV-006)
- Insert `"NO_COLOR" => "1"`.
- `Contains ("no_color")` returns `True`.
- `Contains ("No_Color")` returns `True`.
- `Value ("NO_COLOR")` equals `Value ("no_color")`.

#### 5. Value overwrite
- Insert `"TERM" => "xterm"`, then insert `"TERM" => "xterm-256color"`.
- `Value ("TERM")` returns `"xterm-256color"`.

#### 6. Case-insensitive value comparison (FUNC-ENV-006)
- `Equal_Case_Insensitive ("truecolor", "TrueColor")` returns `True`.
- `Equal_Case_Insensitive ("truecolor", "24bit")` returns `False`.
- `Equal_Case_Insensitive ("", "")` returns `True`.

#### 7. Multi-candidate matching (FUNC-ENV-008)
- Insert `"COLORTERM" => "truecolor"`.
- `Value_Matches ("COLORTERM", ["truecolor", "24bit"])` returns `True`.
- `Value_Matches ("COLORTERM", ["ansi", "256color"])` returns `False`.
- `Value_Matches ("MISSING", ["truecolor"])` returns `False` (key absent).

#### 8. Capture round-trip
- Set a known env var in the process environment.
- Call `Capture_Current`.
- Verify the captured snapshot contains the variable with the correct value.
- This test lives in a non-SPARK test file.

### Test file location

Tests will live in `tests/src/` following the project convention. Suggested files:

| File | Description |
|------|-------------|
| `tests/src/test_environment.adb` | Unit tests for Environment type (SPARK-compatible scenarios) |
| `tests/src/test_environment_capture.adb` | Integration tests for Capture_Current |

---

## Appendix: Implementation Notes

### Private type completion

The `Environment` private type completion will look approximately like:

```ada
private

   package Env_Maps is new SPARK.Containers.Formal.Unbounded_Hashed_Maps
      (Key_Type        => String,
       Element_Type    => String,
       Hash            => Case_Insensitive_Hash,
       Equivalent_Keys => Case_Insensitive_Equal);

   type Environment is record
      Map : Env_Maps.Map;
   end record;

   EMPTY_ENVIRONMENT : constant Environment := (Map => Env_Maps.Empty_Map);

end Termicap.Environment;
```

Where `Case_Insensitive_Hash` and `Case_Insensitive_Equal` are local helper functions that normalize to lowercase before hashing/comparing.

### Capture implementation sketch

```ada
with Ada.Environment_Variables;

package body Termicap.Environment.Capture is

   procedure Capture_Current (Env : out Environment) is

      procedure Process_Variable (Name, Value : in String) is
      begin
         Insert (Env, Name, Value);
      end Process_Variable;

   begin
      Env := EMPTY_ENVIRONMENT;
      Ada.Environment_Variables.Iterate (Process_Variable'Access);
   end Capture_Current;

end Termicap.Environment.Capture;
```

### Sparklib instantiation considerations

The `SPARK.Containers.Formal.Unbounded_Hashed_Maps` generic requires:
- `Key_Type` with `=` and a hash function
- `Element_Type` with `=`
- Both must be definite types in the formal parameter

Since `String` is an indefinite type, the unbounded variant is specifically designed to handle this. If the sparklib unbounded maps do not accept indefinite types directly, an alternative approach would be to use a bounded-length string wrapper:

```ada
MAX_ENV_NAME_LENGTH  : constant := 256;
MAX_ENV_VALUE_LENGTH : constant := 4096;

subtype Env_Name  is String (1 .. MAX_ENV_NAME_LENGTH);
subtype Env_Value is String (1 .. MAX_ENV_VALUE_LENGTH);
```

However, this would waste significant memory and require length tracking. The preferred approach is to verify that sparklib's unbounded maps support indefinite types. If they do not, the fallback is to use `Ada.Containers.Indefinite_Hashed_Maps` in the body with `SPARK_Mode => Off` on the body, while keeping the spec SPARK-compatible with the private type completion hidden from the prover.

This decision will be finalized during implementation when the actual sparklib API is tested. See [ADR-0001](../adr/0001-environment-snapshot-storage-strategy.md) for the decision framework.

---

## Appendix: Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-ENV-001 | `Environment` type, immutability after capture | Silver |
| FUNC-ENV-002 | `Contains` function | Silver |
| FUNC-ENV-003 | `Value` function | Silver |
| FUNC-ENV-004 | `Capture_Current` procedure | Off |
| FUNC-ENV-005 | `EMPTY_ENVIRONMENT` constant, `Insert` procedure | Silver |
| FUNC-ENV-006 | `Equal_Case_Insensitive` function | Silver |
| FUNC-ENV-007 | `Global => null` on query functions | Silver |
| FUNC-ENV-008 | `Value_Matches` function with `String_Vector` | Silver |
