# Decomposed helper functions for color level detection

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-02

## Context and Problem Statement

The `Detect_Color_Level` function in `Termicap.Color` implements an 11-step priority cascade (FUNC-CLR-015) that checks multiple environment variables, applies force overrides, and evaluates heuristic signals. Should this be implemented as a single monolithic function or decomposed into helper functions for each detection phase?

## Decision Drivers

* SPARK Silver provability -- all proof obligations must be dischargeable
* Readability -- the 11-step cascade is complex and must be auditable against the requirements
* Testability -- individual detection phases should be testable in isolation during development
* Code size -- the monolithic approach would produce a function body of 100+ lines
* Compilation and proof performance -- smaller functions prove faster in GNATprove

## Considered Options

* **Option A**: Single monolithic function with inline logic for all 11 steps
* **Option B**: Decomposed helpers -- one function per detection phase, composed in the main function

## Decision Outcome

Chosen option: **Option B** (decomposed helpers), because it improves readability, testability, and proof performance without sacrificing the SPARK verification target.

### Positive Consequences

* Each helper function is small (5-20 lines), making it easy to audit against the specific FUNC-CLR requirement it implements.
* GNATprove processes smaller functions faster, reducing proof time.
* During development, individual helpers can be unit-tested before the full cascade is assembled. Although the helpers are body-local (not visible in the spec), they can be tested indirectly through carefully constructed environment snapshots that exercise specific code paths.
* The main `Detect_Color_Level` body becomes a clear, linear sequence of calls that maps directly to the 11 steps in FUNC-CLR-015.
* Adding new detection phases (e.g., new CI environments, new terminal emulators) requires modifying only the relevant helper function.

### Negative Consequences

* Slightly more boilerplate (function declarations in the body).
* Helpers are body-local -- they cannot be called directly from test code. All testing must go through the public `Detect_Color_Level` function. This is acceptable because the function is pure and deterministic: specific inputs always produce specific outputs.
* String values like TERM and COLORTERM are retrieved from the Environment snapshot multiple times across helpers. This is a negligible performance concern given that Environment lookups are O(1) hash map operations. Additionally, all helpers are annotated with `pragma Inline`, allowing GNAT to eliminate call overhead entirely when the optimization level permits.

## Pros and Cons of the Options

### Option A: Monolithic function

A single function body with all 11 steps inlined.

* Good, because no helper function overhead
* Good, because all logic visible in one place without jumping between functions
* Bad, because the function body would exceed 100 lines, making it hard to audit
* Bad, because a single large function generates more complex proof obligations for GNATprove
* Bad, because modifying one detection phase risks breaking adjacent phases
* Bad, because difficult to map specific lines of code to specific FUNC-CLR requirements

### Option B: Decomposed helpers (chosen)

Body-local helper functions, one per detection phase, composed in the main function.

* Good, because each helper maps 1:1 to a FUNC-CLR requirement
* Good, because small functions are easier for GNATprove to process
* Good, because the main function body reads like a specification of the priority cascade
* Good, because helpers can be modified independently
* Bad, because helpers are not directly testable from outside the package
* Bad, because minor overhead from repeated Environment lookups (negligible)

## Links

* [Tech Spec F3](../tech-specs/f3-color-level-detection.md) -- Full technical specification
* [FUNC-CLR-015](../requirements/02-functional.sdoc) -- Detection priority order requirement
