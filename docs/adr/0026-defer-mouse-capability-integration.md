# Defer Mouse_Capabilities integration into Terminal_Capabilities

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The MOUSE feature adds a `Mouse_Capabilities` record (FUNC-MSE-002) to the Termicap library, populated by `Termicap.Mouse.IO.Detect_Mouse_Protocols`. FUNC-MSE-018 (priority **Could**) states that `Terminal_Capabilities` "should be extended with a field `Mouse : Termicap.Mouse.Mouse_Capabilities`" populated by `Terminal_Capabilities.Detect` / `.Get`. Mouse protocol detection involves a single batched DECRPM probe with a 1000 ms worst-case timeout, on top of the existing 100 ms DA1 probe in `Terminal_Capabilities.Detect`.

Should the `Mouse` field be integrated into `Terminal_Capabilities` now, as part of the MOUSE feature, or should the integration be deferred to a follow-up milestone?

This ADR mirrors ADR-0021 ("Defer Keyboard_Capability integration into Terminal_Capabilities") for the analogous keyboard situation. The decision shape is identical; the magnitudes differ (mouse adds +1000 ms vs keyboard's +2000 ms).

## Decision Drivers

* FUNC-MSE-018 is **Could** priority — even weaker than KKB's **Should** for the equivalent keyboard integration. Deferral is explicitly contemplated by the requirement text and is the natural reading of a Could.
* `Terminal_Capabilities` is **Approved**, widely used in tests and examples, and its `Detect` latency is currently ~150 ms worst-case (driven mostly by the 100 ms DA1 probe). Raising it to **~1150 ms** would change the cost profile of every cold-start `Get` call.
* If both KITTY-KB integration (deferred per ADR-0021) and this MOUSE integration shipped together, the combined worst-case latency of `Terminal_Capabilities.Detect` would be ~3150 ms — a **21x** increase. Ada CLIs and TUIs typically tolerate <1 s startup; a 3-second probe blast at startup would be a serious regression.
* The decision between **eager probing** (call `Detect_Mouse_Protocols` from every `Capabilities.Detect`) and **lazy probing** (new opt-in function or subset selector) is the same architectural decision deferred for KKB. Resolving it once for both features in a single follow-up ADR is cleaner than reinventing the analysis here.
* The Ada field-addition is backward-compatible: adding `Mouse : Mouse_Capabilities := NO_MOUSE_CAPABILITIES` to `Terminal_Capabilities` does not break existing named-aggregate callers.
* MOUSE is Tier 4 (stretch goal). Most Termicap consumers care about color, TTY, and dimensions; mouse protocol detection is a niche capability used by interactive TUI libraries.

## Considered Options

* **Option A**: **Defer integration** to a follow-up milestone. Ship MOUSE with only the standalone `Detect_Mouse_Protocols` function. Open a follow-up ticket for the `Terminal_Capabilities.Mouse` field, to be informed by the same eager-vs-lazy ADR that will eventually unblock KITTY-KB integration.
* **Option B**: **Integrate eagerly now** — extend `Terminal_Capabilities`, call `Detect_Mouse_Protocols` from every `Capabilities.Detect` invocation.
* **Option C**: **Integrate lazily now** — add the field but do not populate it from `Capabilities.Detect`; provide a new `Capabilities.Detect_With_Mouse` (or similar) entry point.
* **Option D**: **Integrate together with KITTY-KB** as part of a single coordinated follow-up — make the eager/lazy decision once for both features.

## Decision Outcome

Chosen option: **Option A** (defer integration), because:

1. FUNC-MSE-018 is **Could** priority; deferring is explicitly permitted (and is the default reading of a Could).
2. The standalone `Detect_Mouse_Protocols` API is fully usable immediately without `Terminal_Capabilities` coupling; the caller invokes it when mouse information is needed.
3. The eager-vs-lazy question is the same architectural decision deferred for KITTY-KB (ADR-0021); resolving it once for both features (option D semantics, but executed asynchronously) is cleaner than two parallel reinventions.
4. Shipping the feature standalone first preserves `Terminal_Capabilities.Detect`'s ~150 ms latency profile, which is a load-bearing property of existing callers.
5. The integration path is documented (MOUSE tech spec §M) and is a non-breaking field addition when picked up.

The deferral is **explicit and tracked**: when the eager-vs-lazy follow-up ADR is written (presumably triggered by either KKB or MOUSE being promoted to In-Progress), it will cover both `Keyboard` and `Mouse` integrations together.

### Positive Consequences

* `Terminal_Capabilities.Detect` latency is unchanged (~150 ms), preserving the cost profile of existing consumers.
* Scope of the MOUSE feature remains focused: the 18 approved requirements all pass without cross-cutting `Termicap.Capabilities` edits.
* The eager-vs-lazy question can be decided with real-world data from the standalone APIs (both keyboard and mouse), rather than guessed up front.
* No cascading test-harness updates to `Termicap.Capabilities`, its cache, the examples, or the architecture doc in the same commit.
* Combined integration of mouse + keyboard later is more efficient than two sequential integration passes — both features add roughly the same cost, and a single follow-up can amortise the test-harness updates and architecture doc edits.

### Negative Consequences

* Callers that already obtain a `Terminal_Capabilities` record via `Capabilities.Get` must make additional calls (`Detect_Mouse_Protocols`, `Detect_Keyboard_Protocol`) to obtain mouse and keyboard information. Minor API inconvenience; documented in the User Guide.
* A future integration pass will need to coordinate edits across `Termicap.Capabilities`, the capability-record tech spec, the arc42 building-blocks doc, and multiple tests. This work is postponed rather than avoided.
* Some consumers who would have benefited from automatic population will not notice the feature until it is wired into `Terminal_Capabilities`. Acceptable cost for a stretch-goal Tier 4 feature.

## Pros and Cons of the Options

### Option A: Defer integration (chosen)

Ship `Termicap.Mouse` and `Termicap.Mouse.IO` as self-contained; add the `Terminal_Capabilities.Mouse` field in a follow-up feature.

* Good, because FUNC-MSE-018's Could priority explicitly allows deferral.
* Good, because preserves `Terminal_Capabilities.Detect` latency for existing users.
* Good, because separates two orthogonal decisions: "does the feature work" and "how is it wired into the aggregate capability record".
* Good, because the eager-vs-lazy decision can be made with hindsight from the standalone APIs.
* Good, because aligns with ADR-0021 for KKB; the two integrations should be made together (option D) but executed asynchronously from the standalone feature ships.
* Bad, because consumers using `Terminal_Capabilities` as their single source of truth must make multiple API calls until the integration ships.

### Option B: Integrate eagerly now

Extend `Terminal_Capabilities`, call `Detect_Mouse_Protocols` from `Detect` as a new sub-detector step.

* Good, because callers see all capabilities in a single call.
* Good, because cache semantics unified with existing per-stream cache.
* Bad, because raises `Capabilities.Detect` worst-case latency from ~150 ms to ~1150 ms — a 7.7x increase. The latency hits every cold-start `Get`.
* Bad, because if KKB is integrated separately later (or simultaneously), combined latency is ~3150 ms — a 21x increase.
* Bad, because forecloses the lazy-probing alternative without a dedicated ADR.
* Bad, because expands the scope of MOUSE to include edits to `Capabilities.Assemble`'s signature, the capability-record tech spec, the cache tests, and arc42 docs — substantial cross-cutting work.

### Option C: Integrate lazily now — new `Detect_With_Mouse` entry point

Add the field to `Terminal_Capabilities`; do not call `Detect_Mouse_Protocols` from `Detect`. Add a new `Detect_With_Mouse` function.

* Good, because preserves existing `Detect` latency.
* Good, because mouse info is a first-class field of the record.
* Bad, because double-API-surface: `Detect`, `Detect_With_Mouse`, `Get`, `Get_With_Mouse` — and the same explosion will repeat for KKB. Combinatorial explosion.
* Bad, because the `Mouse` field in `Terminal_Capabilities` is sometimes populated and sometimes not — stateful behaviour that is harder to reason about than a clean field-less record.
* Bad, because solves the problem with API proliferation that is harder to justify than option A's "use the standalone function for now".

### Option D: Integrate jointly with KITTY-KB

Coordinate the integrations of `Mouse` and `Keyboard` fields into `Terminal_Capabilities` as a single follow-up feature, with one ADR resolving the eager-vs-lazy question.

* Good, because amortises the cross-cutting work (one round of test-harness updates, architecture doc edits, capability-record spec extension) instead of two.
* Good, because the eager-vs-lazy ADR can be informed by both features' standalone usage data.
* Good, because a single coordinated integration is easier for users to reason about ("from version X, all advanced capabilities are populated by `Capabilities.Detect`") than staggered integrations.
* Bad, because requires waiting until both standalone features have been validated in the field; not a strict barrier (this is a deferral) but a coordination cost.

In effect, **option A is option D's standalone phase**. Option A defers the integration; option D commits to integrating both features together when the deferral is picked up. We choose option A as the immediate decision and **endorse option D as the recommended execution for the follow-up**.

## Links

* Mirror ADR: [ADR-0021](0021-defer-keyboard-capability-integration.md) — Defer KITTY-KB integration; this ADR mirrors its structure
* Parent requirement: FUNC-MSE-018 (priority Could)
* Tech Spec: [`docs/tech-specs/mouse-protocol.md`](../tech-specs/mouse-protocol.md) §M — Integration with `Terminal_Capabilities` (deferred)
* Tech Spec (KKB analogue): [`docs/tech-specs/kitty-keyboard.md`](../tech-specs/kitty-keyboard.md) §K — same shape
* Related ADR: [ADR-0011](0011-capability-record-package-placement.md) — `Terminal_Capabilities` package placement
* Related ADR: [ADR-0012](0012-capability-cache-design.md) — `Terminal_Capabilities` cache structure (would need extension for `Mouse` and `Keyboard`)
* Follow-up: a future ADR will decide eager-vs-lazy integration policy for both `Keyboard` and `Mouse` when FUNC-MSE-018 (and/or FUNC-KKB-019) is promoted to In Progress.
