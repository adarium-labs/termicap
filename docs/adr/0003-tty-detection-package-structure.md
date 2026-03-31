# TTY detection as single package with SPARK spec / Ada body

* Status: Approved
* Deciders: Heziode
* Date: 2026-03-31

## Context and Problem Statement

Feature F2 (TTY Detection) needs to call the POSIX `isatty()` C function via FFI. How should the package be structured with respect to SPARK boundaries? Should it follow the `Termicap.Environment` / `Termicap.Environment.Capture` parent/child pattern, or use a simpler single-package approach?

## Decision Drivers

* SPARK Silver target for detection logic specs
* FFI call to `isatty()` cannot be verified by GNATprove
* TTY detection has no pure logic to prove in the body (unlike Environment, which has SPARK-provable map operations)
* Simplicity -- avoid unnecessary package proliferation
* Consistency with F1 patterns where they apply, divergence where they do not

## Considered Options

* **Option A**: Single package `Termicap.TTY` with SPARK spec and `SPARK_Mode => Off` body
* **Option B**: Parent/child split: `Termicap.TTY` (types only) + `Termicap.TTY.Binding` (FFI calls)
* **Option C**: Child of Environment: `Termicap.Environment.TTY`

## Decision Outcome

Chosen option: **Option A** (single package with SPARK spec / Ada body), because TTY detection has no pure body logic to prove, making a parent/child split unnecessary overhead.

### Positive Consequences

* Minimal package count -- one `.ads` and one `.adb` file
* Types (`Stream_Kind`, `TTY_Status`) and functions (`Is_TTY`, `Query_All`) live in one cohesive unit
* Clear SPARK boundary: spec is provable, body is explicitly not
* Downstream packages that need TTY status can capture it once as a `Boolean` and pass it into SPARK-provable detection functions

### Negative Consequences

* The entire body is `SPARK_Mode => Off`, meaning GNATprove cannot verify any body logic (but there is no meaningful pure logic to verify)
* If future TTY-related pure logic is added (e.g., TTY caching, TTY-dependent defaults), it would need to either live in the `SPARK_Mode => Off` body or require a separate SPARK-provable package

## Pros and Cons of the Options

### Option A: Single package (chosen)

* Good, because minimal file count (2 files)
* Good, because all TTY concerns in one package
* Good, because types and functions are co-located
* Bad, because body is entirely SPARK_Mode => Off

### Option B: Parent/child split

`Termicap.TTY` would declare types and have a SPARK body (containing only the `Query_All` aggregation logic), while `Termicap.TTY.Binding` would contain the `pragma Import` and raw `Is_TTY` call.

* Good, because `Query_All` aggregation could be SPARK-proved
* Bad, because `Query_All` is trivial (3-line record aggregate) -- proving it adds no confidence
* Bad, because 4 files for a simple feature
* Bad, because `Termicap.TTY.Is_TTY` would need to delegate to `Termicap.TTY.Binding.C_Isatty`, adding an indirection layer

### Option C: Child of Environment

`Termicap.Environment.TTY` would make TTY detection a child of Environment.

* Good, because could access Environment private types (unnecessary here)
* Bad, because TTY detection has no logical dependency on Environment
* Bad, because creates a false architectural coupling
* Bad, because contradicts the reference framework consensus (go-isatty, crossterm, and termwiz all treat TTY detection as independent from environment handling)

## Additional Decision: TTY_Status as record vs array

For the bulk query result (FUNC-TTY-006), a record with named Boolean fields was chosen over `array (Stream_Kind) of Boolean`:

* **Record**: `Status.Stdout` -- clear, self-documenting field access
* **Array**: `Status (Stdout)` -- slightly more concise but less readable in documentation

Both are fully SPARK-compatible. The record was chosen for readability at call sites and in assertions.

## Links

* [Tech Spec F2](../tech-specs/f2-tty-detection.md) -- Full technical specification
* [ADR-0001](0001-environment-snapshot-storage-strategy.md) -- Related: Environment storage strategy
