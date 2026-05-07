# Active hyperlink refinement reuses the existing XTVERSION result instead of issuing a fresh probe

* Status: proposed
* Deciders: Heziode, Claude
* Date: 2026-05-07

## Context and Problem Statement

The HYPERLINK feature's Tier 2 active refinement (FUNC-HYP-009 / -010 / -011) needs the terminal name and version. The library already obtains this information once per `Detect_Full` invocation via `Termicap.XTVERSION.IO.Query_And_Identify`, which is Step 9 of the existing `Detect_Full` cascade (`src/posix/termicap-capabilities.adb` lines 252-253).

Two ways to satisfy the requirement:

* **A.** Consume the existing `XTV : XTVERSION_Result` value already computed in `Detect_Full` Step 9 and pass it through a pure value-to-value refinement function (`Refine_With_XTVERSION (Passive, XTV)`).
* **B.** Issue a fresh XTVERSION probe inside the hyperlinks I/O layer, opening its own `Probe_Session`, paying its own timeout budget.

ADR-0027 set a precedent for `Termicap.Graphics`: reuse `Termicap.DA1.IO.Detect_DA1` rather than duplicate the DA1 session lifecycle. This ADR documents the analogous decision for HYPERLINK and XTVERSION, which is structurally simpler (a value reuse, no session at all).

## Decision Drivers

* **Latency budget.** Each XTVERSION probe takes up to 1 s on a slow terminal (`GRAPHICS_PROBE_TIMEOUT_MS`). `Detect_Full` already runs one in Step 9 (`Query_And_Identify (Timeout_Ms => 1_000)`). Adding a second probe inside `Termicap.Hyperlinks.IO` doubles the worst-case XTVERSION latency for no information gain.
* **Multiplexer passthrough.** `Query_And_Identify` already handles tmux/screen passthrough (FUNC-XTV-012). A duplicate probe would have to redo the passthrough decision.
* **Failure semantics.** `XTVERSION_Result` already encodes `Success / Timeout / Parse_Error` (FUNC-XTV-001). The refinement function only needs to discriminate between `Success` (look up name + parse version) and "not Success" (return `XTVERSION_Unresolved`). No additional probe failure modes need handling.
* **SPARK boundary.** A pure value-to-value function does no I/O and needs only `SPARK_Mode Off` for the `Unbounded_String` access — the body is otherwise straight Ada with bounded behaviour. A fresh-probe variant would need to wire `Probe_Session`, raw mode, and timeout, all SPARK Off.
* **Consistency with the broader Termicap design.** `Detect_Full` is a single composition of pre-computed sub-detector outputs (compare `Assemble_Full` in `src/posix/termicap-capabilities.adb` line 175-200). Refinement is just one more parameter in that composition.

## Considered Options

* **Option A: Reuse `XTV` from `Detect_Full` Step 9.** `Refine_With_XTVERSION (Passive, XTV)` is a pure value-to-value transformation; `Detect_Full` calls it between Step 9 (XTV) and Step 10 (Graphics).
* **Option B: Fresh probe in a new `Termicap.Hyperlinks.IO` package.** Mirror the SIXEL `Termicap.Graphics.IO` pattern: a `.IO` child with its own session, its own cache, its own timeout.
* **Option C: Refine inline in `Detect_Full` body.** Skip `Refine_With_XTVERSION` and put the version-comparison logic directly in `Detect_Full` between Steps 9 and 10.

## Decision Outcome

Chosen option: **Option A — reuse the existing XTVERSION result via a pure value-to-value refinement function**, because:

1. **Zero new I/O.** No new probe sessions, no new cache, no new timeout budget. `Detect_Full` runs exactly one XTVERSION probe per call (already does), and HYPERLINK refinement is "free" on top of it.
2. **No new platform body required (FUNC-HYP-017).** The active refinement is platform-neutral; XTVERSION's platform split is already abstracted upstream. This is a stronger guarantee than ADR-0027 made for Graphics (which still has a platform body for the APC probe).
3. **Worst-case `Detect_Full` latency unchanged.** Adding HYPERLINK refinement adds zero milliseconds to the existing ~6 s worst-case (capabilities.ads line 267-269).
4. **Symmetry with the SIXEL/DA1 precedent (ADR-0027) but stronger.** ADR-0027 reuses an .IO convenience function (which still does I/O once per process). HYPERLINK reuses an already-computed *value*. The reuse is purer.
5. **Test ergonomics.** Tests for `Refine_With_XTVERSION` build synthetic `XTVERSION_Result` values directly. No probe stubbing, no I/O fixtures, no platform-specific test harness. One test per row of the FUNC-HYP-012 state-transition table.
6. **No new package surface.** Avoids creating a `Termicap.Hyperlinks.IO` child that would contain a single function calling another package's I/O. The HYPERLINK feature ships as a single mixed-SPARK package, mirroring `Termicap.DECRPM` rather than `Termicap.Graphics`.

The implementation is one expression in `Detect_Full`:

```ada
HL_Refined : constant Termicap.Hyperlinks.Hyperlinks_Result :=
   Termicap.Hyperlinks.Refine_With_XTVERSION
     (Passive => Base_Caps.Hyperlinks, XTV => XTV);
```

inserted between the existing `XTV` declaration and the `GFX` declaration.

### Positive Consequences

* **Zero added latency.** HYPERLINK Tier 2 contributes 0 ms to `Detect_Full`.
* **Zero added FFI / platform code.** All platform-specific I/O is upstream in `Termicap.XTVERSION.IO`.
* **Zero added cache state.** Existing `Full_Cache` already memoises the entire `Full_Terminal_Capabilities`.
* **Establishes a "value reuse" precedent for future Tier 4 features.** When a future feature needs an existing probe result, the default answer is "compose the value, do not reprobe".
* **One package, mixed-SPARK, simple.** No `.IO` child needed.

### Negative Consequences

* **HYPERLINK Tier 2 only refines when `Detect_Full` is called.** A caller using only `Detect` / `Get` (base capabilities) gets the passive Tier 1 result, which is precisely the FUNC-HYP-014 / FUNC-HYP-015 split — the consequence is intended.
* **Coupling to `XTVERSION_Result` shape.** If `XTVERSION_Result` adds new variants or fields, the refinement must adapt. Mitigated: `XTVERSION_Result` is a stable type backed by FUNC-XTV-001.
* **No standalone "refine hyperlinks now" entry point.** Callers wanting on-demand refinement must call `Detect_Full` (which runs every Tier 4 probe) or call `Refine_With_XTVERSION` themselves with a pre-computed XTVERSION result. The latter is exactly what tests do.

## Pros and Cons of the Options

### Option A: Reuse the XTVERSION value (chosen)

* Good, because zero new I/O.
* Good, because zero added latency.
* Good, because zero new platform body.
* Good, because tests are deterministic value-to-value (no probe stubs).
* Good, because precedent-setting: future "I need a probe result that already exists" answers are now standardised on value reuse.
* Bad, because Tier 2 is only available through `Detect_Full`. Acceptable per FUNC-HYP-014/015 design.

### Option B: Fresh probe in a new `Termicap.Hyperlinks.IO`

* Good, because HYPERLINK becomes self-contained (no upstream dependency on `Detect_Full`'s ordering).
* Good, because a standalone `Detect_Hyperlinks` entry point is possible.
* Bad, because doubles XTVERSION latency in `Detect_Full` (probe twice).
* Bad, because requires its own `Probe_Session`, raw mode, timeout, multiplexer-passthrough decision — all duplicated logic.
* Bad, because needs platform body files (POSIX + Windows) for what should be a pure logic feature.
* Bad, because adds a new cache to keep coherent with `Full_Cache`.
* Bad, because contradicts the FUNC-HYP-016 explicit statement "no platform-specific body files are required".

### Option C: Refine inline in `Detect_Full`

* Good, because no new package surface.
* Good, because zero new I/O (same as Option A).
* Bad, because the refinement logic is non-trivial (state-transition table, version parser, known-good table lookup) and would bloat `Detect_Full` by ~150 LOC.
* Bad, because tests would have to call `Detect_Full` end-to-end to exercise refinement state transitions, instead of unit-testing `Refine_With_XTVERSION` directly.
* Bad, because future XTVERSION-version-gated features would each need to inline their own logic in `Detect_Full`. Option A factors this once.

## Links

* Tech Spec: [`docs/tech-specs/hyperlink.md`](../tech-specs/hyperlink.md) §1, §4.2, §6.B, §9
* Requirements: FUNC-HYP-009, FUNC-HYP-010, FUNC-HYP-011, FUNC-HYP-015, FUNC-HYP-016, FUNC-HYP-017
* Precedent ADR: [ADR-0027](0027-da1-reuse-vs-fresh-probe.md) — "consume existing infrastructure, do not duplicate" (DA1 reuse for Sixel). This ADR strengthens the precedent: HYPERLINK reuses a *value*, not just an *.IO entry point*.
* Related ADR: [ADR-0028](0028-graphics-independent-probe-sessions.md) — Sixel uses *independent* sessions; HYPERLINK uses *no* new session at all.
* Source: `src/termicap-capabilities.ads` lines 252-269 (`Detect_Full` step ordering)
* Source: `src/termicap-xtversion-io.ads` (the `Query_And_Identify` function being reused)
