# Use Unbounded_String with spec-On/body-Off SPARK boundary for Terminal_Identity

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-03

## Context and Problem Statement

The `Terminal_Identity` record (FUNC-TID-002) contains three string fields: `Program_Name`, `Program_Version`, and `Term_Value`. These store raw environment variable values whose lengths cannot be bounded at compile time. The requirement specifies `Ada.Strings.Unbounded.Unbounded_String` for these fields. However, `Unbounded_String` is a controlled type with hidden heap allocation, which is excluded from the SPARK language subset. FUNC-TID-007 requires the package to be SPARK Silver provable. How should the module handle this tension?

## Decision Drivers

* **Requirement compliance** -- FUNC-TID-002 explicitly specifies `Ada.Strings.Unbounded.Unbounded_String` for the string fields.
* **SPARK Silver target** -- FUNC-TID-007 requires SPARK Silver provability. The spec must have `SPARK_Mode => On` and the function must carry `Global => null`.
* **No truncation** -- Environment variable values have no guaranteed maximum length. WezTerm's `TERM_PROGRAM_VERSION` is already 25 characters (`"20231203-110809-5046fc22"`). A bounded string risks silent truncation.
* **Project consistency** -- The existing codebase has two SPARK boundary patterns: (1) spec + body both On (`Termicap.Color`, `Termicap.Unicode`), and (2) spec On, body Off (`Termicap.TTY`, `Termicap.Dimensions`).
* **Body purity** -- The function body contains no FFI, no global state access, and no side effects. The only non-SPARK element is `Unbounded_String` construction.

## Considered Options

* **Option A**: Bounded strings (`String (1 .. MAX_ENV_VALUE_LENGTH)`) for all fields, with the full package in `SPARK_Mode => On`.
* **Option B**: `Unbounded_String` fields with spec `SPARK_Mode => On` and body `SPARK_Mode => Off`.
* **Option C**: SPARK formal containers (`SPARK.Containers.Formal.Unbounded_Vectors` of `Character`) as a SPARK-compatible variable-length string.

## Decision Outcome

Chosen option: **Option B** (`Unbounded_String` with spec-On/body-Off boundary), because it satisfies the requirement (FUNC-TID-002), avoids truncation risk, and follows the established project pattern for packages where the body cannot be SPARK-verified.

The spec is compiled with `SPARK_Mode => On`, enabling GNATprove to verify:
- The `Global => null` contract (no global reads/writes visible through the interface).
- The postcondition expressions (FUNC-TID-005, FUNC-TID-006) are well-typed.
- Callers in SPARK packages can depend on the declared contracts.

The body is compiled with `SPARK_Mode => Off`, excluding it from GNATprove analysis. The body's correctness is ensured by:
- Unit tests covering every classification rule (FUNC-TID-012).
- The body's structural simplicity (if/elsif chain, no loops in the main function, no FFI, no allocation beyond `To_Unbounded_String` calls).

### Positive Consequences

* Requirement-compliant: `Unbounded_String` fields exactly as specified in FUNC-TID-002.
* No truncation risk: arbitrarily long environment variable values are stored without loss.
* Spec-level contracts are machine-verified by GNATprove, giving callers Silver-level guarantees.
* Consistent with the project's existing spec-On/body-Off pattern (`Termicap.TTY`, `Termicap.Dimensions`).
* The body is testable with programmatically constructed `Environment` snapshots, compensating for the lack of body-level SPARK proof.

### Negative Consequences

* The body is not SPARK-verified. A logic error in the classification cascade would not be caught by GNATprove. Mitigation: comprehensive unit tests (one per `Terminal_Kind` value, shadow-rule tests, case-insensitivity tests).
* Unlike `Termicap.Color` and `Termicap.Unicode` (both fully SPARK Silver), this module has a lower SPARK coverage ratio. Mitigation: the difference is solely due to `Unbounded_String` construction; the detection logic itself is structurally identical to the fully-proved modules.
* Future SPARK versions that support controlled types or bounded containers natively would make Option A viable. If that happens, the body could be upgraded to `SPARK_Mode => On` without changing the spec.

## Pros and Cons of the Options

### Option A: Bounded strings

```ada
MAX_ENV_VALUE_LENGTH : constant := 256;
subtype Env_Value_String is String (1 .. MAX_ENV_VALUE_LENGTH);

type Terminal_Identity is record
   Kind            : Terminal_Kind;
   Program_Name    : Env_Value_String;
   Name_Length     : Natural;
   -- ... similarly for other fields
end record;
```

* Good, because full SPARK Silver proof coverage (spec + body).
* Good, because no heap allocation.
* Bad, because deviates from FUNC-TID-002 (which specifies `Unbounded_String`).
* Bad, because requires choosing `MAX_ENV_VALUE_LENGTH`. Any choice risks either truncation (too small) or waste (too large).
* Bad, because API is more cumbersome: callers must use `Program_Name (1 .. Name_Length)` instead of `To_String (Program_Name)`.
* Bad, because each `Terminal_Identity` value consumes `3 * MAX_ENV_VALUE_LENGTH` bytes on the stack regardless of actual content length.

### Option B: Unbounded_String with spec-On/body-Off (chosen)

```ada
--  spec (SPARK_Mode => On):
type Terminal_Identity is record
   Kind            : Terminal_Kind;
   Program_Name    : Ada.Strings.Unbounded.Unbounded_String;
   -- ...
end record;

--  body (SPARK_Mode => Off):
--  Uses To_Unbounded_String to construct fields
```

* Good, because requirement-compliant.
* Good, because no truncation risk.
* Good, because clean API for callers.
* Good, because follows existing project patterns.
* Bad, because body is not SPARK-proved.
* Bad, because `Unbounded_String` involves hidden heap allocation (though only for record construction, not in the detection logic itself).

### Option C: SPARK formal containers

```ada
package Char_Vectors is new
   SPARK.Containers.Formal.Unbounded_Vectors
     (Index_Type   => Positive,
      Element_Type => Character);

type Terminal_Identity is record
   Kind         : Terminal_Kind;
   Program_Name : Char_Vectors.Vector;
   -- ...
end record;
```

* Good, because full SPARK Silver proof coverage.
* Good, because variable-length without truncation.
* Bad, because `Char_Vectors.Vector` is not the natural Ada representation of a string. Callers must convert to `String` for any standard string operations.
* Bad, because no precedent in the project -- all other string handling uses `String` or `Unbounded_String`.
* Bad, because adds a SPARK container dependency for a conceptually simple string field.
* Bad, because the conversion overhead (Vector -> String) at every caller site adds complexity without proportional benefit.

## Links

* [Tech Spec F6](../tech-specs/terminal-identification.md) -- Terminal Identification technical specification
* [FUNC-TID-002](../requirements/terminal-identification.sdoc) -- Terminal_Identity record type requirement
* [FUNC-TID-007](../requirements/terminal-identification.sdoc) -- SPARK Silver provability requirement
* [ADR-0007](0007-unicode-level-three-value-enum.md) -- Prior decision on type representation for detection modules
