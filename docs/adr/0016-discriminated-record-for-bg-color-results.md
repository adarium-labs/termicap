# Discriminated record for BG-COLOR result types instead of functional Result type

* Status: accepted
* Deciders: Heziode, Claude
* Date: 2026-04-05

## Context and Problem Statement

The BG-COLOR requirements (FUNC-BGC-007, FUNC-BGC-009, FUNC-BGC-013, FUNC-BGC-014) specify several functions that return either a success value or a failure indication. The requirements reference a `Result_RGB` type from the `functional` dependency for the high-level detect functions. However, the `functional` crate (providing generic Result types) is not present in the Termicap project's dependency list, and adding it solely for this feature would introduce a new external dependency for a pattern that Ada can express natively.

How should the BG-COLOR feature represent fallible return values?

## Decision Drivers

* The `functional` dependency is not in the project and would need to be added to `alire.toml`
* Ada discriminated records provide compile-time enforcement: accessing the success payload when the discriminant is False is a Constraint_Error, preventing misuse
* SPARK can reason about discriminated records natively without requiring special support for a generic Result type
* Consistency with existing patterns in the codebase (e.g., `DA1_Params` uses Count = 0 as the failure sentinel)
* Minimizing external dependencies is a project-wide design principle

## Considered Options

* **Option 1:** Add the `functional` crate and use its generic `Result` type
* **Option 2:** Use Ada discriminated records with a Boolean Success discriminant
* **Option 3:** Use out parameters with a Boolean Success flag

## Decision Outcome

Chosen option: "Option 2: Ada discriminated records", because it provides compile-time safety (discriminant check prevents accessing success-only fields on failure), is SPARK-provable without additional dependency, and keeps the project dependency footprint minimal.

### Positive Consequences

* No new external dependency required
* SPARK prover can reason about discriminant constraints natively and discharge postconditions about the success payload
* Callers must check the Success discriminant before accessing the Color/Value field, enforced by the language runtime (Constraint_Error) and verifiable by SPARK
* Pattern is consistent and can be reused by future features without adding dependencies

### Negative Consequences

* Less ergonomic than a monadic Result type with map/and_then combinators
* Each feature defines its own result record rather than reusing a single generic type (minor duplication)
* If the `functional` crate is later added for other reasons, there would be two patterns in the codebase (discriminated records and generic Result)

## Pros and Cons of the Options

### Option 1: functional crate Result type

* Good, because it provides a generic, reusable Result type with monadic combinators
* Good, because it matches the pattern described in the requirements document
* Bad, because it introduces a new external dependency for a simple pattern
* Bad, because SPARK support for the generic Result type would need verification
* Bad, because the `functional` crate may have its own SPARK_Mode constraints that conflict with BG_Query's Silver target

### Option 2: Ada discriminated records

* Good, because no external dependency needed
* Good, because SPARK natively supports discriminated records and can verify postconditions
* Good, because compile-time discriminant checking prevents misuse
* Bad, because each result type must be defined separately (no generic reuse)

### Option 3: Out parameters with Boolean flag

* Good, because it is the simplest approach
* Bad, because nothing prevents the caller from reading the out parameter when Success is False
* Bad, because SPARK cannot enforce the "only valid when Success" invariant

## Links

* Related to: `docs/tech-specs/bg-color-query.md` (BG-COLOR technical specification)
* Related to: `docs/requirements/bg-color-query.sdoc` (FUNC-BGC-007, FUNC-BGC-013)
