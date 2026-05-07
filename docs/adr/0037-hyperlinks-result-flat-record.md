# Hyperlinks_Result as a flat record instead of a discriminated record

* Status: proposed
* Deciders: Heziode, Claude
* Date: 2026-05-07

## Context and Problem Statement

FUNC-HYP-002 requires a `Hyperlinks_Result` carrying three pieces of information:

* `Support` : `Hyperlinks_Support` (one of `Unsupported / Likely_Supported / Supported / Unknown`)
* `Provenance` : `Hyperlinks_Provenance` (one of seven values describing how `Support` was determined)
* `Terminal_Version_Known` : `Boolean`

Two prior Termicap result types use distinctly different shapes:

* `XTVERSION_Result` and `BG_Color_Result` are **discriminated records** (variant per `Status` / `Success`), enforcing at compile time that name/version (or color) fields are accessible only on the success variant. This pattern is recorded in [ADR-0016](0016-discriminated-record-for-bg-color-results.md).
* `Graphics_Capabilities` is a **flat record** with multiple Booleans (`Sixel_Supported`, `Sixel_Via_DA1`, etc.). All fields are unconditionally accessible.

Which shape fits `Hyperlinks_Result`?

## Decision Drivers

* **Compile-time safety** — does any field of `Hyperlinks_Result` only make sense for some values of `Support` (or `Provenance`)? If yes, a discriminated record offers real protection. If no, a discriminated record is overhead.
* **SPARK provability** — flat records with no discriminants are simpler for SPARK to reason about. Discriminated records add a discriminant-check obligation on every field access.
* **Caller ergonomics** — discriminated records require either case statements or a defensive discriminant check before reading the variant fields. Flat records read like any other record.
* **Pattern consistency with sibling Tier 4 features** — Sixel, Mouse, Keyboard, Clipboard all use flat records with provenance Booleans / enums.
* **Default value** — both shapes can express the canonical default (`Support = Unknown, Provenance = Default, Terminal_Version_Known = False`), but a flat record's default is a one-line aggregate; a discriminated record requires picking a default discriminant.

## Considered Options

* **Option A: Flat record** — three fields, all unconditionally accessible. One default constant.
* **Option B: Discriminated by `Hyperlinks_Support`** — variant per `Support` value, with `Terminal_Version_Known` only on certain variants.
* **Option C: Discriminated by `Hyperlinks_Provenance`** — variant per `Provenance` value, with `Terminal_Version_Known` and even `Support` placed in different variants.

## Decision Outcome

Chosen option: **Option A — flat record**, because:

1. **All three fields are always meaningful** regardless of `Support` value.
   * `Provenance` is meaningful for every `Support`: even `Unsupported` distinguishes `Env_Excluded` (legacy `TERM`) from `XTVERSION_Rejected` (known-too-old version).
   * `Terminal_Version_Known` is meaningful for every `Support`: it is `True` whenever the XTVERSION refinement matched a name in the known-good table, even if the version was unparseable (which keeps `Support = Likely_Supported`).
   No field "doesn't apply" to any variant, so no discriminant check has anything to protect.

2. **Pattern consistency**. Every Tier 4 capability record in Termicap (Sixel, Mouse, Keyboard, Clipboard) is a flat record with provenance fields. Adopting the same shape minimises cognitive load for consumers and tests.

3. **SPARK simplicity**. `Classify_Hyperlinks_Support` (FUNC-HYP-007) targets SPARK Silver. Building a flat record at the end of each branch is a single aggregate; building a discriminated record requires per-variant aggregates and the prover must verify the discriminant choice matches the field set in each branch.

4. **Default value clarity**. `DEFAULT_HYPERLINKS_RESULT : constant Hyperlinks_Result := (Support => Unknown, Provenance => Default, Terminal_Version_Known => False);` is a one-line, self-documenting constant that doubles as the cache initial value.

5. **The XTVERSION precedent (ADR-0016) does not apply here.** ADR-0016 selected a discriminated record for `BG_Color_Result` because the success variant carries an actual RGB payload that **does not exist** in the failure variant — the discriminant prevents reading uninitialised fields. `Hyperlinks_Result` has no such per-variant payload: every field is populated in every variant.

### Positive Consequences

* Simple aggregate construction in every branch of `Classify_Hyperlinks_Support` and `Refine_With_XTVERSION`.
* Test code can pattern-match on any field directly without unpacking a discriminant.
* Consistent with sibling Tier 4 records — readers familiar with `Graphics_Capabilities` can immediately read `Hyperlinks_Result`.
* SPARK Silver proof obligations are a strict subset of what a discriminated record would need.

### Negative Consequences

* No compile-time check prevents a buggy implementation from setting `Support = Unsupported` with `Provenance = XTVERSION_Confirmed`. Mitigated: this is a unit-test obligation (FUNC-HYP-012 state-transition table coverage), and the body has only ~6 explicit return points so manual review is straightforward.
* If a future requirement adds a variant-specific payload (e.g., a parsed-version field on `XTVERSION_Confirmed` only), we may need to revisit. Mitigated: the field would naturally extend the flat record at the cost of one default-zero value on other variants — no code break.

## Pros and Cons of the Options

### Option A: Flat record (chosen)

* Good, because all fields are unconditionally meaningful.
* Good, because pattern matches Tier 4 sibling records.
* Good, because SPARK Silver-friendly.
* Good, because default-constant is a one-line aggregate.
* Bad, because no compile-time enforcement of (Support, Provenance) consistency. Manual review and unit tests close the gap.

### Option B: Discriminated by Hyperlinks_Support

* Good, because consumers writing `case R.Support is` exhaustively are forced to handle each variant.
* Bad, because `Provenance` and `Terminal_Version_Known` apply to every variant, so they end up duplicated in every variant.
* Bad, because requires choosing a default discriminant; defaulting to `Unknown` is fine but adds visual noise.
* Bad, because asymmetric with sibling Tier 4 records.

### Option C: Discriminated by Hyperlinks_Provenance

* Good, because `Provenance` is the most fine-grained discriminant.
* Bad, because seven variants with no per-variant payload differences is the highest possible boilerplate-to-information ratio.
* Bad, because the variant set is intrinsically tied to detection logic; adding a `Provenance` value in a future requirement (e.g., `Override_Forced`) becomes a breaking change to the type.

## Links

* Tech Spec: [`docs/tech-specs/hyperlink.md`](../tech-specs/hyperlink.md) §5.2, §5.3
* Requirements: FUNC-HYP-001, FUNC-HYP-002, FUNC-HYP-003
* Sibling: [ADR-0016](0016-discriminated-record-for-bg-color-results.md) — discriminated record chosen for `BG_Color_Result` because of per-variant payload (RGB only on success). Counter-precedent to this ADR.
* Sibling pattern: `Graphics_Capabilities` (flat record with provenance Booleans), `Mouse_Capabilities` (flat record), `Keyboard_Capability` (flat record).
