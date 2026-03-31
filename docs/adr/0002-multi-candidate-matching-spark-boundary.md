# Use sparklib Unbounded_Vectors for multi-candidate matching

* Status: Approved
* Deciders: Heziode
* Date: 2026-03-31 (updated from 2026-03-29)

## Context and Problem Statement

FUNC-ENV-008 requires a function to check whether an environment variable's value matches any entry in a set of candidate strings. The natural Ada API would use an array of strings, but arrays of indefinite types (like `String`) require access types. SPARK does not allow anonymous access types stored in composite types (arrays, records), so a direct `array of access constant String` approach is not SPARK-compatible.

How should the `Value_Matches` function accept a variable-length list of String candidates while remaining SPARK-provable?

## Decision Drivers

* SPARK Silver target for ALL public functions, including `Value_Matches` (FUNC-ENV-007)
* Usability: callers need a convenient multi-candidate matching API
* Ada arrays cannot have unconstrained element types without access types
* SPARK does not allow anonymous access types in composite types
* `pragma SPARK_Mode (Off)` cannot be toggled back to `On` within the same package section — so carving out a non-SPARK region in the visible part is not viable
* sparklib provides `Unbounded_Vectors` that accept indefinite element types and are SPARK-provable

## Considered Options

* **Option A**: Use `SPARK.Containers.Formal.Unbounded_Vectors` instantiated with `String`
* **Option B**: Use a fixed-parameter overloaded function (up to N candidates)
* **Option C**: Place `Value_Matches` in a separate child package with `SPARK_Mode => Off`
* **Option D**: Use `access constant String` array in a `SPARK_Mode => Off` region (original proposal — rejected)

## Decision Outcome

Chosen option: **Option A — `SPARK.Containers.Formal.Unbounded_Vectors` of `String`**, because it keeps the entire `Termicap.Environment` package under `SPARK_Mode`, provides a natural variable-length API, and leverages sparklib's formal containers that are already a project dependency.

The package instantiates `String_Vectors` in its visible part and defines `Value_Matches` with a `String_Vector` parameter. With Ada 2022 container aggregate syntax, callers can write:

```ada
if Value_Matches (Env, "TERM_PROGRAM", ["iTerm.app", "WezTerm", "vscode"]) then ...
```

### Positive Consequences

* `Value_Matches` is fully SPARK Silver provable — no exceptions to the SPARK boundary
* No artificial limit on candidate count
* Natural Ada 2022 aggregate syntax at call sites
* No access types anywhere in the public API
* sparklib is already a project dependency (zero new dependencies)

### Negative Consequences

* Slightly heavier type than a plain array (vector with internal heap allocation via Holders)
* Callers without Ada 2022 must build the vector manually with `Append` calls
* Exposes a `String_Vectors` package instantiation in the public API

## Pros and Cons of the Options

### Option A: Unbounded_Vectors of String (chosen)

Instantiate `SPARK.Containers.Formal.Unbounded_Vectors` with `String` as the element type.

* Good, because fully SPARK Silver provable
* Good, because no limit on number of candidates
* Good, because Ada 2022 aggregate syntax `["a", "b", "c"]`
* Good, because uses existing sparklib dependency
* Bad, because heavier than a plain array
* Bad, because requires Ada 2022 for cleanest syntax

### Option B: Fixed-parameter overloaded function

```ada
function Value_Matches_Any
   (Env : Environment; Name : String;
    C1, C2, C3, C4, C5 : String := "") return Boolean;
```

* Good, because zero dependencies beyond `String`
* Good, because fully SPARK-provable
* Good, because clean call sites for small sets
* Bad, because arbitrary limit on candidate count
* Bad, because empty-string default conflicts with matching against `""` as a candidate
* Bad, because verbose signature that doesn't scale

### Option C: Separate child package with SPARK_Mode => Off

```ada
package Termicap.Environment.Matching with SPARK_Mode => Off is ...
```

* Good, because keeps main package fully SPARK
* Good, because natural access-type array syntax
* Bad, because `Value_Matches` itself is not formally verified
* Bad, because requires a separate child package (extra files)
* Bad, because access types need careful handling at call sites

### Option D: SPARK_Mode Off/On toggle in same package (rejected)

The original proposal toggled `pragma SPARK_Mode (Off)` then `pragma SPARK_Mode (On)` within the visible spec. **This is illegal in SPARK** — once SPARK_Mode is turned Off in a section, it cannot be turned back On in the same or subsequent sections of that unit.

* Bad, because violates SPARK rules (will not compile)
* Superseded by Option A

## Links

* Relates to: [F1 Tech Spec](../tech-specs/f1-environment-variable-abstraction.md)
* Relates to: [ADR-0001](0001-environment-snapshot-storage-strategy.md)
* Requirements: FUNC-ENV-008
