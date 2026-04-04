# SPARK annotation split: spec On, body mixed with provable Assemble function

* Status: proposed
* Deciders: Heziode
* Date: 2026-04-03

## Context and Problem Statement

The Capability Record Assembly package contains three categories of code with different SPARK compatibility:

1. **Pure assembly logic** (`Assemble`): combines pre-computed sub-detector results into a record. No global state, no FFI, no tasking. Fully SPARK-provable.
2. **Detection orchestration** (`Detect`): calls `Capture_Current` (OS FFI via Ada.Environment_Variables), `Query_All` (isatty FFI), and other sub-detectors. Cannot be SPARK-verified.
3. **Cache management** (`Get`, protected object `Cache`): uses Ada protected types, which are outside the SPARK 2014 subset.

How should `SPARK_Mode` annotations be distributed across the spec and body?

## Decision Drivers

* SPARK Silver target for the pure assembly logic (FUNC-CAP-012)
* The `Terminal_Capabilities` record type must be visible to SPARK-annotated callers across the library
* The `Detect` function signature must be expressible in SPARK (with `Global` aspect referencing `Override_State`)
* The `Get` function cannot have a SPARK `Global` aspect because it reads/writes a protected object
* Minimize the `SPARK_Mode => Off` surface area

## Considered Options

* **Option A: Spec On, body mixed** -- package spec compiled with `SPARK_Mode => On`; body has `SPARK_Mode => Off` at the package level but uses `SPARK_Mode => On` for the `Assemble` function body
* **Option B: Separate SPARK and non-SPARK packages** -- put `Assemble` in `Termicap.Capabilities.Assembly` (SPARK On) and `Detect`/`Get` in `Termicap.Capabilities` (SPARK Off)
* **Option C: Entire package SPARK Off** -- give up SPARK verification for the assembly layer

## Decision Outcome

Chosen option: **Option A (spec On, body mixed)**, because it keeps all capability-related declarations in one package while maximizing SPARK coverage through selective annotation in the body.

### Positive Consequences

* The `Terminal_Capabilities` record type is visible to SPARK callers (other packages can reference it in contracts)
* The `Assemble` function is fully SPARK-provable with `Global => null` and a postcondition on `Downsampling_Available`
* `Detect` has a proper `Global` aspect in the spec, allowing SPARK callers to reason about its side effects even though the body is not verified
* Only two regions in the body are `SPARK_Mode => Off`: the `Detect` function body and the `Get`/Cache region
* The pattern is consistent with `Termicap.Override` (spec On, body mixed for protected object)

### Negative Consequences

* The body requires careful placement of `SPARK_Mode` pragmas to switch between On and Off regions
* `Get` cannot carry a `Global` aspect in the spec, so SPARK callers using `Get` must be in a `SPARK_Mode => Off` region themselves (acceptable: `Get` is intended for application-level code, not SPARK-verified library internals)

## Pros and Cons of the Options

### Option A: Spec On, body mixed

* Good, because record type visible to SPARK callers
* Good, because `Assemble` postcondition is machine-verified
* Good, because consistent with the Override package pattern
* Bad, because body needs pragma placement discipline

### Option B: Separate SPARK and non-SPARK packages

* Good, because clean SPARK boundary (entire `Assembly` package is SPARK)
* Bad, because introduces an extra package for one function
* Bad, because callers must `with` two packages to use the assembly layer
* Bad, because the `Terminal_Capabilities` type must be declared in a shared location, complicating the hierarchy

### Option C: Entire package SPARK Off

* Good, because simplest -- no SPARK_Mode pragmas at all
* Bad, because forfeits SPARK verification of the assembly logic entirely
* Bad, because the `Downsampling_Available` postcondition cannot be machine-verified
* Bad, because violates FUNC-CAP-012 (SPARK Silver target for pure assembly)

## Links

* Relates to: FUNC-CAP-012 (SPARK Silver for assembly), FUNC-CAP-013 (no FFI in assembly)
* Informed by: `Termicap.Override` (spec On, body Off for protected object), `Termicap.TTY` (spec SPARK, body Off for FFI)
* Depends on: [ADR-0011](0011-capability-record-package-placement.md) (package placement determines which spec gets SPARK_Mode)
