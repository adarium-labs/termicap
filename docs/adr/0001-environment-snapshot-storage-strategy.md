# Use sparklib Unbounded_Hashed_Maps for environment snapshot storage

* Status: Approved
* Deciders: Heziode
* Date: 2026-03-29

## Context and Problem Statement

The `Termicap.Environment` package needs an internal container to store environment variable bindings (name-value pairs) as an immutable snapshot. The container choice must balance SPARK Silver provability, performance, memory efficiency, and support for indefinite string types.

How should we store environment variable key-value pairs in the `Environment` snapshot type?

## Decision Drivers

* SPARK Silver target: the container must be usable in SPARK-annotated code, with contracts sufficient for Silver-level proofs
* Performance: environment queries happen during detection cascades with many lookups; O(1) average is preferred over O(n)
* Memory: environment sizes vary (typically 30-200 variables); the container should not waste memory on small environments or truncate on large ones
* String support: both keys and values are standard Ada `String` (indefinite type)
* Case-insensitive keys: the container must support custom hash and equality functions for case-normalized keys
* Available in project dependencies: sparklib is already a dependency

## Considered Options

* **Option A**: `SPARK.Containers.Formal.Unbounded_Hashed_Maps` (sparklib)
* **Option B**: `SPARK.Containers.Formal.Hashed_Maps` (sparklib, bounded)
* **Option C**: `Ada.Containers.Indefinite_Hashed_Maps` (standard library)
* **Option D**: Sorted array of records with binary search

## Decision Outcome

Chosen option: **Option A -- `SPARK.Containers.Formal.Unbounded_Hashed_Maps`**, because it is the only option that satisfies all four decision drivers simultaneously: SPARK Silver provability, O(1) lookup performance, dynamic sizing, and availability in existing project dependencies.

If during implementation it turns out that sparklib's unbounded maps cannot accept `String` as an indefinite key/element type, the fallback is a hybrid approach: keep the `Environment` spec SPARK-annotated (the type is private, so the prover does not need to see the completion), and use `Ada.Containers.Indefinite_Hashed_Maps` in the body with `SPARK_Mode => Off` on the body only. This preserves SPARK contracts on all public query functions while using a proven standard library container internally.

### Positive Consequences

* SPARK Silver proofs on all query functions (`Contains`, `Value`, `Equal_Case_Insensitive`)
* O(1) average lookup time for environment variable queries
* No arbitrary capacity limits; adapts to any environment size
* Custom hash/equality functions enable case-insensitive key lookup
* No new dependencies needed (sparklib is already in the project)

### Negative Consequences

* sparklib's unbounded containers may use dynamic memory allocation internally, which is acceptable for a desktop/server library but would be a concern for embedded targets
* If sparklib does not support indefinite types in the unbounded variant, the fallback hybrid approach reduces SPARK coverage of the body (but not the spec)

## Pros and Cons of the Options

### Option A: SPARK.Containers.Formal.Unbounded_Hashed_Maps

sparklib provides SPARK-annotated unbounded hashed maps with functional models for proof.

* Good, because SPARK Silver provable with functional contracts
* Good, because O(1) average lookup
* Good, because no capacity limit
* Good, because supports custom Hash and Equivalent_Keys functions
* Good, because already a project dependency
* Bad, because may not support indefinite key/element types (to be verified)
* Bad, because internal dynamic allocation is not suitable for embedded/high-integrity

### Option B: SPARK.Containers.Formal.Hashed_Maps (bounded)

sparklib provides bounded hashed maps with a fixed capacity set at object creation.

* Good, because SPARK Silver provable
* Good, because O(1) average lookup
* Good, because no dynamic allocation after creation
* Bad, because requires choosing a capacity constant (too small truncates, too large wastes memory)
* Bad, because bounded formal maps require definite key/element types (String is indefinite)
* Bad, because capacity errors must be handled (Insert can fail)

### Option C: Ada.Containers.Indefinite_Hashed_Maps

Standard library container that natively handles indefinite types.

* Good, because natively supports String keys and elements
* Good, because O(1) average lookup
* Good, because well-tested, standard library implementation
* Good, because no capacity limits
* Bad, because NOT SPARK-compatible (would require SPARK_Mode => Off on entire body)
* Bad, because loses SPARK proofs on internal operations

### Option D: Sorted array with binary search

A simple array of (Name, Value) records, sorted by name, with binary search for lookup.

* Good, because fully SPARK-provable (arrays are native SPARK types)
* Good, because no dependency on any container library
* Good, because simple implementation
* Bad, because O(log n) lookup instead of O(1)
* Bad, because requires a maximum capacity constant (same problem as bounded maps)
* Bad, because insertion requires shifting elements (O(n))
* Bad, because indefinite String elements require bounded-length wrappers

## Links

* Relates to: [F1 Tech Spec](../tech-specs/f1-environment-variable-abstraction.md)
* Requirements: FUNC-ENV-001, FUNC-ENV-005, FUNC-ENV-007
