# Defer Keyboard_Capability integration into Terminal_Capabilities

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The KITTY-KB feature adds a `Keyboard_Capability` record (Protocol, Flags, Probed) to the Termicap library, populated by `Termicap.Keyboard.IO.Detect_Keyboard_Protocol`. FUNC-KKB-019 (priority **Should**) states that `Terminal_Capabilities` "should be extended with a field `Keyboard : Termicap.Keyboard.Keyboard_Capability`" populated by `Terminal_Capabilities.Detect` / `.Get`. Keyboard protocol detection involves two sequential sentinel probes at 1000 ms each, giving a **2 second worst-case cold-start latency** on top of the existing DA1 probe (100 ms) in `Terminal_Capabilities.Detect`.

Should we integrate the keyboard field into `Terminal_Capabilities` now, as part of the KITTY-KB feature, or defer the integration to a follow-up milestone?

## Decision Drivers

* FUNC-KKB-019 is **Should**, not Must — deferral is explicitly contemplated by the requirement text and its own commentary.
* `Terminal_Capabilities` is **Approved**, widely used in tests and examples, and its `Detect` latency is currently ~150 ms worst-case (driven mostly by the 100 ms DA1 probe). Raising it to **~2150 ms** changes the cost profile of every `Get` cold start and every explicit `Detect` call.
* Many Termicap consumers care only about color and TTY detection; keyboard protocol detection is a niche capability used by interactive TUI libraries.
* The decision between **eager probing** (call `Detect_Keyboard_Protocol` from every `Capabilities.Detect`) and **lazy probing** (new opt-in function, e.g., `Capabilities.Detect_With_Keyboard`) is not trivial: eager is simple but slow for the common case; lazy preserves current behaviour but adds API surface.
* The no-exception contract (FUNC-KKB-014) and FUNC-OSC-012's single-concurrent-session enforcement have been independently validated by their individual features, but their composition inside `Capabilities.Detect` has not been exercised yet. Doing the integration alongside a 19-requirement feature increases scope creep risk.
* The Ada field-addition is backward-compatible: adding `Keyboard : Keyboard_Capability := NO_KEYBOARD_CAPABILITY` to `Terminal_Capabilities` does not break existing named-aggregate callers.

## Considered Options

* **Option A**: **Defer integration** to a follow-up milestone. Ship KITTY-KB with only the standalone `Detect_Keyboard_Protocol` function. Open a follow-up ticket for the `Terminal_Capabilities` integration, to be informed by a separate ADR on eager-vs-lazy probing.
* **Option B**: **Integrate eagerly now** — extend `Terminal_Capabilities`, call `Detect_Keyboard_Protocol` from every `Capabilities.Detect` invocation.
* **Option C**: **Integrate lazily now** — add the field but do not populate it from `Capabilities.Detect`; provide a new `Capabilities.Detect_With_Keyboard` entry point.
* **Option D**: **Integrate eagerly with opt-out flag** — add a `Capabilities.Set_Probe_Keyboard (Enable : Boolean)` global switch defaulted to True; users who care about latency can disable it.

## Decision Outcome

Chosen option: **Option A (defer integration)**, because:

1. FUNC-KKB-019 is **Should** priority; deferring is explicitly permitted.
2. The standalone `Detect_Keyboard_Protocol` API is fully usable immediately without `Terminal_Capabilities` coupling; the caller simply invokes it when keyboard information is needed.
3. The eager-vs-lazy question is a genuinely separate architectural decision that deserves its own ADR, informed by user feedback on the standalone API and by observed field data on probe-latency variance.
4. Shipping the feature standalone first preserves `Terminal_Capabilities.Detect`'s ~150 ms latency profile, which is a load-bearing property of existing callers.
5. The integration path is documented (tech-spec §K) and is a non-breaking field addition when picked up.

### Positive Consequences

* `Terminal_Capabilities.Detect` latency is unchanged (~150 ms), preserving the cost profile of existing consumers.
* Scope of the KITTY-KB feature remains focused: the 19 approved requirements all pass without cross-cutting `Termicap.Capabilities` edits.
* The eager-vs-lazy question can be decided with real-world data from the standalone API, rather than guessed up front.
* No cascading test-harness updates to `Termicap.Capabilities`, its cache, the examples, or the architecture doc in the same commit.

### Negative Consequences

* Callers that already obtain a `Terminal_Capabilities` record via `Capabilities.Get` must make an additional call to `Detect_Keyboard_Protocol` to obtain keyboard information. Minor API inconvenience; documented in the User Guide when KITTY-KB ships.
* A future integration pass will need to coordinate edits across `Termicap.Capabilities`, the capability-record tech spec, the arc42 building-blocks doc, and multiple tests. This work is postponed rather than avoided.
* Some consumers who would have benefited from automatic population will not notice the feature until it is wired into `Terminal_Capabilities`. Acceptable cost for a stretch-goal feature (Tier 4).

## Pros and Cons of the Options

### Option A: Defer integration (chosen)

Ship `Termicap.Keyboard` and `Termicap.Keyboard.IO` as self-contained; add the `Terminal_Capabilities.Keyboard` field in a follow-up feature.

* Good, because FUNC-KKB-019's Should priority explicitly allows deferral.
* Good, because preserves `Terminal_Capabilities.Detect` latency for existing users.
* Good, because separates two orthogonal decisions: "does the feature work" and "how is it wired into the aggregate capability record".
* Good, because the eager-vs-lazy decision can be made with hindsight from the standalone API.
* Bad, because consumers using `Terminal_Capabilities` as their single source of truth must make a second API call for keyboard info until the integration ships.

### Option B: Integrate eagerly now

Extend `Terminal_Capabilities`, call `Detect_Keyboard_Protocol` from `Detect` as a new sub-detector step.

* Good, because callers see all capabilities in a single call.
* Good, because cache semantics unified with existing per-stream cache.
* Bad, because raises `Capabilities.Detect` worst-case latency from ~150 ms to ~2150 ms — a 14x increase. The latency hits every cold-start `Get`.
* Bad, because forecloses the lazy-probing alternative without a dedicated ADR.
* Bad, because expands the scope of KITTY-KB to include edits to `Capabilities.Assemble`'s signature, the capability-record tech spec, the cache tests, and arc42 docs — substantial cross-cutting work.
* Bad, because a full ~2 s latency spike at startup would disproportionately affect CLI tools that call `Get` during their `main` and already tolerate only sub-second startup.

### Option C: Integrate lazily now — new `Detect_With_Keyboard` entry point

Add the field to `Terminal_Capabilities`; do not call `Detect_Keyboard_Protocol` from `Detect`. Add a new `Detect_With_Keyboard` function.

* Good, because preserves existing `Detect` latency.
* Good, because keyboard info is a first-class field of the record.
* Bad, because double-API-surface: `Detect`, `Detect_With_Keyboard`, `Get`, `Get_With_Keyboard` — combinatorial explosion.
* Bad, because the `Keyboard` field in `Terminal_Capabilities` is sometimes populated (if the caller used the new entry point) and sometimes not (if the legacy entry point was used). Stateful behaviour is harder to reason about than a clean field-less record.
* Bad, because solves the problem with an API proliferation that is harder to justify than Option A's "just use the standalone function for now".

### Option D: Integrate eagerly with opt-out flag

Integrate eagerly but provide `Capabilities.Set_Probe_Keyboard (Enable : Boolean := True)` to disable.

* Good, because defaults to full information.
* Good, because latency-sensitive callers can opt out.
* Bad, because introduces a global mutable flag — violates the project's preference for immutable config via environment or function arguments.
* Bad, because the flag must be thread-safe (another protected object) or be restricted to elaboration-time setting (reducing its usefulness).
* Bad, because most Ada consumers will not discover the flag in time; default behaviour leaks 2 s latency before the user knows to opt out.

## Links

* Parent requirement: FUNC-KKB-019 (priority Should)
* Tech Spec: [`docs/tech-specs/kitty-keyboard.md`](../tech-specs/kitty-keyboard.md) — see §K "Integration with Terminal_Capabilities"
* Related ADR: [ADR-0012](0012-capability-cache-design.md) — `Terminal_Capabilities` cache structure (would need extension for keyboard)
* Related ADR: [ADR-0011](0011-capability-record-package-placement.md) — `Terminal_Capabilities` package placement
* Follow-up: a future ADR will decide eager-vs-lazy integration policy if and when FUNC-KKB-019 is promoted to In Progress.
