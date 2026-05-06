# Wcwidth probing as a sibling package (Termicap.Wcwidth) rather than a child of Termicap.Unicode

* Status: Proposed
* Deciders: Heziode
* Date: 2026-05-06

## Context and Problem Statement

The wcwidth() probing feature (FUNC-WCW-001 through FUNC-WCW-013) introduces a new package that detects the Unicode version supported by the terminal's C runtime locale. This package depends on `Termicap.Unicode` for the `Unicode_Level` type used by the `Refine_Unicode_Level` integration function. Where should this package be placed in the Termicap hierarchy?

Two natural options exist: `Termicap.Wcwidth` (a sibling of `Termicap.Unicode`) or `Termicap.Unicode.Wcwidth` (a child of `Termicap.Unicode`).

## Decision Drivers

* **Naming consistency**: All existing Termicap feature packages use flat sibling names (`Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, `Termicap.Unicode`, `Termicap.DA1`, `Termicap.OSC`, etc.). No feature package is currently a child of another feature package (only infrastructure children like `Termicap.DA1.IO`, `Termicap.OSC.Parsing` exist).
* **SPARK boundary independence**: The wcwidth probe has a SPARK Off body (C FFI) while `Termicap.Unicode` is fully SPARK Silver (no FFI). Making the probe a child would introduce a SPARK Off child under a fully SPARK-proved parent, which is architecturally misleading.
* **Dependency direction**: `Termicap.Wcwidth` depends on `Termicap.Unicode` (for the `Unicode_Level` type), but `Termicap.Unicode` does not depend on wcwidth probing. A child package creates a false impression of tight coupling.
* **Platform split**: The wcwidth body requires platform dispatch (POSIX vs. Windows via Source_Dirs), while `Termicap.Unicode` has a single body for all platforms. Mixing dispatch strategies in a parent-child relationship would complicate the GPR file.
* **Independent evolution**: The env-var cascade and the wcwidth probe are separate detection mechanisms that can be used independently. A sibling relationship communicates this separation more clearly.

## Considered Options

* **Option A**: `Termicap.Wcwidth` (sibling package)
* **Option B**: `Termicap.Unicode.Wcwidth` (child package)

## Decision Outcome

Chosen option: **Option A** (`Termicap.Wcwidth`), because it follows the established flat naming convention, keeps the SPARK boundary clean, and correctly represents the probe as an independent detection mechanism rather than an extension of the env-var cascade.

### Positive Consequences

* Consistent with all other Termicap feature packages (flat hierarchy).
* The SPARK annotation strategy is clear: `Termicap.Unicode` is fully SPARK Silver (no exceptions), `Termicap.Wcwidth` has a SPARK On spec with a SPARK Off body (same pattern as `Termicap.TTY`).
* Platform-specific body dispatch via Source_Dirs is self-contained within the wcwidth package, no interaction with the Unicode package's (non-dispatched) body.
* Callers who only need the env-var cascade can use `Termicap.Unicode` without any knowledge of `Termicap.Wcwidth`.

### Negative Consequences

* The semantic relationship between wcwidth probing and Unicode detection is less visible in the package name. Mitigation: the `Refine_Unicode_Level` function signature makes the relationship explicit, and the tech spec documents the integration pattern.
* Two separate `with` clauses are needed by callers who use both features. Mitigation: `Termicap.Capabilities` aggregates both results, so most callers interact with the capability record rather than individual packages.

## Pros and Cons of the Options

### Option A: Termicap.Wcwidth (sibling) -- chosen

```
Termicap.Unicode         [SPARK Silver, no FFI]
Termicap.Wcwidth         [spec: SPARK On, body: SPARK Off]
```

* Good, because consistent with the flat naming convention used by all feature packages.
* Good, because the SPARK boundary is visually and structurally independent.
* Good, because `Termicap.Unicode` remains a "pure" package with no FFI ancestry.
* Good, because platform dispatch (POSIX/Windows body split) is isolated.
* Bad, because the name `Termicap.Wcwidth` does not immediately suggest a relationship to Unicode detection.

### Option B: Termicap.Unicode.Wcwidth (child)

```
Termicap.Unicode                [SPARK Silver, no FFI]
+-- Termicap.Unicode.Wcwidth    [spec: SPARK On, body: SPARK Off]
```

* Good, because the hierarchical name makes the relationship to Unicode detection explicit.
* Good, because child packages in Ada have visibility into the parent's private part (though not needed here).
* Bad, because no other Termicap feature uses child packages for feature modules (only for infrastructure like `.IO`, `.Parsing`).
* Bad, because a SPARK Off child under a fully SPARK Silver parent is architecturally misleading -- it suggests the parent is also partially unproved.
* Bad, because the child package would need platform dispatch while the parent does not, complicating the Source_Dirs layout.

## Links

* [Tech Spec: WCWIDTH](../tech-specs/wcwidth.md) -- wcwidth() probing technical specification
* [ADR-0007](0007-unicode-level-three-value-enum.md) -- Unicode_Level three-value enumeration
* [ADR-0018](0018-platform-dispatch-via-source-dirs.md) -- Platform dispatch via Source_Dirs
* [FUNC-WCW-012](../requirements/wcwidth.sdoc) -- Public API specification (tentative package name)
