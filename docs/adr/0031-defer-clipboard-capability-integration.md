# Defer Clipboard_Capabilities Integration into Terminal_Capabilities

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-05-06

## Context and Problem Statement

The OSC 52 Clipboard Detection feature (FUNC-C52-001 through FUNC-C52-019) introduces a `Clipboard_Capabilities` record type in `Termicap.Clipboard` and a `Detect_Clipboard` entry point in `Termicap.Clipboard.IO`. FUNC-C52-019 specifies that `Terminal_Capabilities` (FUNC-CAP-001) should eventually include a `Clipboard : Clipboard_Capabilities` field, but explicitly marks this integration as **out of scope** with Could priority and deferred status.

Should the `Clipboard_Capabilities` field be added to `Terminal_Capabilities` as part of the OSC52 feature implementation, or should it be deferred to a separate work item?

## Decision Drivers

* **Consistency with Tier 4 feature precedents.** Keyboard (ADR-0021), Mouse (ADR-0026), and Graphics (FUNC-SXL-019) all deferred their integration into `Terminal_Capabilities`. The clipboard feature should follow the same pattern for predictable project evolution.
* **Minimal blast radius.** Adding a field to `Terminal_Capabilities` requires modifying `Termicap.Capabilities` (spec and body), updating `Assemble` function signature and postcondition, updating `Detect` to call `Detect_Clipboard`, and adjusting all existing tests that construct `Terminal_Capabilities` values. This cross-cutting change is better batched with other Tier 4 integrations.
* **Standalone usability.** `Detect_Clipboard` is a fully functional standalone API. Applications can call it directly without any dependency on `Terminal_Capabilities`. The deferred integration does not reduce functionality.
* **FUNC-C52-019 explicit text.** The requirement itself states: "Integration into Terminal_Capabilities is OUT OF SCOPE for this feature specification and is deferred as an explicit non-goal."

## Considered Options

* **Option A**: Defer integration (standalone `Detect_Clipboard` API only).
* **Option B**: Integrate immediately (add `Clipboard` field to `Terminal_Capabilities` as part of this feature).

## Decision Outcome

Chosen option: **Option A (defer integration)**, because it follows the established Tier 4 precedent, minimises blast radius, and aligns with the explicit deferral in FUNC-C52-019.

### Positive Consequences

* **Zero modifications to `Termicap.Capabilities`.** The capability record, its `Assemble` function, and all existing tests remain unchanged.
* **Independent feature validation.** The clipboard feature can be implemented, tested, and validated without entangling it with the capability record's type evolution.
* **Batched Tier 4 integration.** When all Tier 4 features (Keyboard, Mouse, Graphics, Clipboard) are stable, a single coordinated update to `Terminal_Capabilities` adds all four fields at once, with a single test update pass.

### Negative Consequences

* **Two-step adoption for callers.** Callers who use `Termicap.Capabilities.Get` do not see clipboard capabilities until the integration is completed. They must call `Detect_Clipboard` separately in the interim.
* **Temporary API asymmetry.** `Terminal_Capabilities` includes DA1 (Tier 3) but not Clipboard (Tier 4) despite Clipboard depending on DA1. This asymmetry is cosmetic and resolved by the batched integration.

## Pros and Cons of the Options

### Option A: Defer integration (chosen)

* Good, because it follows the Tier 4 precedent (ADR-0021, ADR-0026, FUNC-SXL-019).
* Good, because it avoids cross-cutting changes to `Termicap.Capabilities` and its tests.
* Good, because `Detect_Clipboard` is fully functional as a standalone API.
* Good, because it aligns with the explicit deferral language in FUNC-C52-019.
* Bad, because callers of `Termicap.Capabilities.Get` must call `Detect_Clipboard` separately.

### Option B: Integrate immediately

* Good, because callers of `Get`/`Detect` would see clipboard capabilities automatically.
* Bad, because it requires modifying `Termicap.Capabilities` (spec, body, Assemble signature).
* Bad, because it diverges from the established Tier 4 deferral pattern.
* Bad, because it requires updating all existing tests that construct `Terminal_Capabilities`.
* Bad, because it contradicts the explicit FUNC-C52-019 deferral language.

## Links

* Supersedes: none
* Related: [ADR-0021](0021-defer-keyboard-capability-integration.md) (keyboard deferral)
* Related: [ADR-0026](0026-defer-mouse-capability-integration.md) (mouse deferral)
* Related: FUNC-SXL-019 (graphics deferral, no separate ADR)
* Related: [ADR-0011](0011-capability-record-package-placement.md) (capability record structure)
