# Termicap.Version as a top-level shared utility instead of a private helper

* Status: proposed
* Deciders: Heziode, Claude
* Date: 2026-05-07

## Context and Problem Statement

The HYPERLINK feature (FUNC-HYP-013) needs to compare dotted-numeric version strings (e.g., `0.50.0` vs `0.49.99`, `357` vs `380`, `3.1.0` vs `3.0.9`) to gate the XTVERSION-based promotion / demotion of OSC 8 support.

The same logic is also called out in FUNC-HYP-022 for the existing `Termicap.Graphics` feature, which has a `Kitty_Graphics_Version : Natural` field (FUNC-SXL-003) reserved for future kitty-version-gated logic (e.g., `kitty >= 0.20.0` for animation support, per the notcurses precedent cited in `docs/requirements/sixel-graphics.sdoc:166-170`).

Where should the version-comparison code live?

## Decision Drivers

* **DRY across features**. HYPERLINK and Graphics both need it; future features (e.g., DECSET-version-gated mouse extensions if they appear) may want it too.
* **SPARK Silver target**. Both consumers want this to be SPARK-provable. A single utility avoids duplicating SPARK contracts and proof obligations.
* **Avoid premature framework-itis**. We have only two consumers today; introducing a top-level package for a 130-LOC utility must be justified.
* **Test surface**. A shared utility has its own focused test suite; a private helper gets tested transitively through its caller, which weakens regression coverage for the parser corner cases.
* **Naming consistency**. `Termicap.Color`, `Termicap.Unicode`, `Termicap.DA1`, `Termicap.XTVERSION` — Termicap already follows a "one utility, one top-level child package" convention.
* **Cross-feature refactor scope** (FUNC-HYP-022). The Sixel refactor explicitly mandates that `Termicap.Graphics` consumes the same utility. A private helper cannot satisfy this requirement without duplication.

## Considered Options

* **Option A: `Termicap.Version` top-level shared utility** — single new package, withed by both `Termicap.Hyperlinks` and `Termicap.Graphics`.
* **Option B: Private helper in `Termicap.Hyperlinks` body** — version logic is internal to Hyperlinks; Graphics gets its own private copy if/when it needs version comparison.
* **Option C: Private helper in `Termicap.XTVERSION`** — version comparison is "about XTVERSION responses", co-locate it there.

## Decision Outcome

Chosen option: **Option A — `Termicap.Version` top-level shared utility**, because:

1. FUNC-HYP-022 makes Option B impossible without duplicating the utility into both packages.
2. The naming convention (`Termicap.<utility>`) is already established for similar concerns (Color, Unicode, DA1).
3. The utility is a pure SPARK function set with no platform variability; promoting it to a top-level package costs one `.ads` and one `.adb` file plus a `with` clause in two consumers.
4. A focused test suite (`tests/src/termicap-version-tests.adb`) gives the parser its own regression coverage, including bounds tests, malformed input, and shorter-is-less rule.
5. Future features (e.g., a hypothetical `Termicap.DA2` that gates on terminal-class version) can adopt the utility without disturbing existing code.

### Positive Consequences

* Single source of truth for version parsing and comparison.
* SPARK Silver verification done once, applies everywhere.
* Adding a new version-gated feature is a one-line `with`.
* Tests target the utility directly — the parser corner cases (empty string, leading dot, trailing dot, double dot, non-digit, overflow) are exercised in isolation, not through the consumer's lens.
* FUNC-HYP-022 refactor becomes a literal "swap private helper for `Termicap.Version` calls" — we never write a private helper in the first place.

### Negative Consequences

* One extra package in the public namespace. Mitigated: `Termicap.Version` is a useful exposed API; users who parse terminal-supplied version strings can reuse it.
* If a future version requirement emerges that conflicts with the current scheme (semver pre-release tags, build metadata, etc.), the shared utility may need extension. Mitigated: today's requirement (FUNC-HYP-013) is explicit about supporting only dotted non-negative integers, and any future extension can be additive (new `Parse_Semver` etc.).

## Pros and Cons of the Options

### Option A: Top-level shared utility (chosen)

* Good, because it satisfies FUNC-HYP-022 directly without duplication.
* Good, because SPARK Silver verification done once.
* Good, because one focused test suite for parser corner cases.
* Good, because pattern matches existing utilities (`Termicap.Color`, `Termicap.Unicode`, etc.).
* Bad, because adds one package to the public namespace.

### Option B: Private helper in `Termicap.Hyperlinks` body

* Good, because zero new public surface.
* Bad, because FUNC-HYP-022 mandates the same logic be reachable from `Termicap.Graphics`; either we duplicate (against FUNC-HYP-022 spirit) or we make the helper public (which is Option A by another name).
* Bad, because parser corner cases get tested only through the Hyperlinks consumer's lens.
* Bad, because adding a third consumer in the future requires another duplicate or a refactor to Option A.

### Option C: Private helper in `Termicap.XTVERSION`

* Good, because XTVERSION is the natural source of version strings.
* Bad, because version comparison is *not* about parsing XTVERSION responses — it is about comparing already-parsed dotted-numeric versions. Co-locating couples two concerns.
* Bad, because `Termicap.XTVERSION` is SPARK On but contains `Unbounded_String`; adding a SPARK-friendly version comparator there would force a careful split between the two SPARK-mode regions, which is harder than just creating a clean new package.
* Bad, because graphics consumers would need to `with Termicap.XTVERSION` solely for the version comparator, even when they have their own version source (e.g., a future DA2-version field).

## Links

* Tech Spec: [`docs/tech-specs/hyperlink.md`](../tech-specs/hyperlink.md) §4.3, §5.7, §10
* Requirements: FUNC-HYP-013, FUNC-HYP-022
* Related ADR: [ADR-0013](0013-spark-annotation-split-capabilities.md) — SPARK annotation split pattern reused here
* Related ADR: [ADR-0027](0027-da1-reuse-vs-fresh-probe.md) — sibling "consume existing infrastructure, do not duplicate" precedent
