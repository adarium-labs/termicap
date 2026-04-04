# Termicap.Capabilities child package for capability record assembly

* Status: proposed
* Deciders: Heziode
* Date: 2026-04-03

## Context and Problem Statement

The Capability Record Assembly feature needs a home for the `Terminal_Capabilities` record type, the `Detect` function, the `Get` function, and the internal cache. Three placements are possible: the root `Termicap` package, a `Termicap.Capabilities` child, or a `Termicap.Detect` child. The choice affects call-site ergonomics, circular dependency risk, and SPARK annotation boundaries.

## Decision Drivers

* Call-site ergonomics: `Termicap.Get` (root) vs. `Termicap.Capabilities.Get` (child)
* Circular dependency avoidance: the assembly layer must `with` all sub-detector child packages (`Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, etc.); those children already `with Termicap` implicitly as their parent
* SPARK annotation control: the root `termicap.ads` is currently a plain namespace package with no `SPARK_Mode` annotation; adding types and functions would introduce constraints on all child packages
* Consistency with existing architecture: the root package has no types or subprograms (documented in arc42 section 5)

## Considered Options

* **Option A: Root package (`Termicap`)** -- add `Terminal_Capabilities`, `Detect`, `Get` directly to `termicap.ads`
* **Option B: `Termicap.Capabilities` child package** -- new child package dedicated to assembly
* **Option C: `Termicap.Detect` child package** -- new child named `Detect`

## Decision Outcome

Chosen option: **Option B (`Termicap.Capabilities`)**, because it avoids circular dependency risk, preserves the root package as a clean namespace, and provides clear naming that describes the package's purpose.

### Positive Consequences

* Zero risk of circular `with`: `Termicap.Capabilities` can `with` all sub-detector children freely, since none of them need to `with Termicap.Capabilities` back
* Root package remains an empty namespace, consistent with the existing architecture and all eleven existing child packages
* The package name `Capabilities` clearly describes its content (the aggregated capability record) rather than an action (detect)
* Call-site ergonomics are good with a `use` clause: `use Termicap.Capabilities; Caps := Get;`
* SPARK annotations on the root package are unaffected; the new package controls its own `SPARK_Mode` independently

### Negative Consequences

* Slightly longer qualified name (`Termicap.Capabilities.Get`) compared to `Termicap.Get`
* One additional package in the hierarchy (but the library already has eleven child packages)

## Pros and Cons of the Options

### Option A: Root package

* Good, because `Termicap.Get` is the most ergonomic call site
* Bad, because `termicap.ads` would need to `with Termicap.Color`, `Termicap.TTY`, etc., but those packages already `with Termicap` implicitly as children -- this creates a circular `with` chain that the Ada compiler rejects
* Bad, because adding `SPARK_Mode` to the root package would constrain all child packages
* Bad, because it breaks the architectural convention that the root is namespace-only

### Option B: Termicap.Capabilities

* Good, because no circular dependency risk
* Good, because the name describes the content (capability record)
* Good, because SPARK annotations are self-contained
* Bad, because slightly longer qualified name

### Option C: Termicap.Detect

* Good, because `Termicap.Detect.Get` is reasonably short
* Bad, because `Detect` names an action, creating ambiguity: `Termicap.Detect.Detect` (the function within the package) reads poorly
* Bad, because the package also contains the record type and cache, not just detection logic
* Bad, because the name conflicts with the `Detect` function name, requiring callers to use the fully qualified `Termicap.Detect.Detect` for the fresh detection path

## Links

* Relates to: FUNC-CAP-001 (Terminal_Capabilities type), FUNC-CAP-003 (Get), FUNC-CAP-004 (Detect)
* Informed by: termwiz `caps` module (separate from root), termenv `output.go` (detection on a dedicated Output type)
* Informs: [ADR-0013](0013-spark-annotation-split-capabilities.md) (SPARK boundary depends on package placement)
