# Batched Single-Sentinel DECRPM Session for Mouse Probing

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The MOUSE feature (FUNC-MSE-001..018) probes six DEC private modes — `1000`, `1002`, `1003`, `1015`, `1006`, `1016` — via DECRPM (CSI ? Ps $ p). The existing `Termicap.DECRPM.IO` package exposes two convenience functions for this:

- `Detect_Mode (Mode, Timeout_Ms)` — opens a fresh `Probe_Session`, sends one DECRPM query + DA1 sentinel, reads until the DA1 response, parses one frame, closes.
- `Detect_Modes (Modes, Count, Timeout_Ms)` — opens **one** `Probe_Session` then issues `Sentinel_Query` per mode (one DA1 sentinel per mode), reusing the session.

The first option implies six full session lifecycles (six `tcgetattr` + `tcsetattr` cycles, six DA1 sentinels echoed into the terminal); the second implies one session lifecycle but six DA1 sentinels and six per-mode read loops.

**A third option** is structurally distinct: open **one** `Probe_Session`, send all six DECRPM queries via `Write_Query`, then issue **one** `Sentinel_Query` with an empty `Query` argument so it writes only the DA1 sentinel and reads until the DA1 response — terminating the entire batch in a single sentinel. Which approach does Termicap's MOUSE feature adopt?

## Decision Drivers

* **Round-trip latency.** Six independent sessions (option 1) cost six SSH round-trips minimum. Six per-mode `Sentinel_Query` calls in one session (option 2) cost six round-trips but no extra termios cycles. The batched-single-sentinel pattern (option 3) costs **one** round-trip.
* **Sentinel echo visibility.** Each DA1 sentinel sent during a probe is bytes that the terminal **may** echo back as terminal output during raw-mode misconfiguration or buggy multiplexer passthrough. Six sentinels are six potential echo windows; one sentinel is one.
* **Termios churn.** Each `Probe_Session.Open`/`Close` cycle calls `tcgetattr` + `tcsetattr` + `tcsetattr` (raw entry + restore). Six cycles is six pairs of system calls; one cycle is one.
* **Parser complexity.** Option 1 lets each per-mode session apply `Parse_DECRPM_Response` to its own dedicated buffer (single frame, simple). Option 2 has the same property. Option 3 receives a buffer that may contain up to six interleaved DECRPM frames, requiring a multi-frame scanning parser.
* **Partial-result handling.** With option 1 or option 2, a per-mode timeout naturally degrades that one mode to `Status => Not_Recognized` while preserving the others. With option 3, the **single** timeout governs the entire batch — early modes that responded cleanly are still recoverable, but the boundary between "clean partial" and "garbled tail" is in the parser, not the I/O layer.
* **OSC-INFRA stability.** Adding a new entry point to `Termicap.OSC` (e.g., `Sentinel_Read_Only`) for the third option's "send only the DA1 sentinel and read" semantics would be a Tier 3 spec amendment requiring its own ADR. Reusing `Sentinel_Query (Query => Empty_Byte_Array, ...)` avoids any OSC-INFRA change.
* **Reference-framework precedent.** tcell and notcurses both probe at terminal-init by sending all queries up front and waiting for responses (no per-query DA1). blessed sends per-mode queries with first-timeout-kills-all; this is closer to option 2 with a fast-fail short-circuit.

## Considered Options

* **Option A**: **Batched single-sentinel session**. Open one `Probe_Session`; for each of the six modes, call `Write_Query` with the DECRPM query bytes; then call `Sentinel_Query` once with an empty `Query` argument so it writes only the DA1 sentinel and reads until DA1 termination. The accumulated buffer is parsed for up to six interleaved DECRPM frames.
* **Option B**: **Single session, per-mode sentinel queries**. Open one `Probe_Session`; loop six times calling `Sentinel_Query (Query => DECRPM_Query (Modes (I)), ...)`. Each iteration writes one query + DA1 sentinel and reads until DA1.
* **Option C**: **Six independent sessions**. Loop six times, each iteration opening and closing its own `Probe_Session` via `Termicap.DECRPM.IO.Detect_Mode (Modes (I), Timeout_Ms)`.
* **Option D**: **Extend OSC-INFRA**. Add a new `Termicap.OSC.Sentinel_Read_Only` entry point that takes no `Query` argument and only writes the DA1 sentinel + reads. Use it after six `Write_Query` calls.

## Decision Outcome

Chosen option: **Option A** (batched single-sentinel session via `Write_Query × 6 + Sentinel_Query (empty,...)`), because it minimises round-trip latency to a single sentinel cycle, avoids any OSC-INFRA spec amendment, and the parser-complexity cost is bounded (the multi-frame scan is `O (Resp_Length)` over a 4 KiB buffer — microseconds).

Calling `Sentinel_Query` with a zero-length `Byte_Array` as the `Query` argument is a **legal use** of the existing API (FUNC-OSC-006 does not forbid empty queries; the procedure simply writes whatever bytes are passed, then writes the DA1 sentinel, then reads until DA1). No change to `Termicap.OSC` is needed. This composition is documented in the MOUSE tech spec §G.3 as "phase 1: write all six queries; phase 2: write empty-then-sentinel and read".

The interleaved-response parser (`Parse_All_Responses` body-private helper in `Termicap.Mouse.IO`) scans the response buffer linearly looking for `ESC [ ? <digits>+ ; <digit> $ y` frames and applies each frame's `Mode` and `Status` to the corresponding `Supports_*` Boolean in `Mouse_Capabilities`. Frames may arrive in any order; the parser matches by `Ps`, not by position (FUNC-MSE-004 final paragraph). Stray or garbled bytes are skipped.

### Positive Consequences

* **Single round-trip.** On a 200 ms-RTT SSH link, the difference between option A (200 ms wall clock) and option C (1.2 s) is significant for an interactive cold-start.
* **One DA1 sentinel.** A single sentinel is a single echo target; six is six. This matters when interleaved input arrives during the probe.
* **One termios cycle.** `tcgetattr`/`tcsetattr` are fast but not free; a single cycle keeps the cost to its minimum.
* **No OSC-INFRA change.** `Termicap.OSC.Sentinel_Query`, `Write_Query`, and `Probe_Session` are reused unchanged. The MOUSE feature ships without a Tier 3 amendment ADR.
* **Aligns with tcell / notcurses startup pattern.** Both reference frameworks send their full probe set in one flush before reading responses. Validates the design.
* **Partial results preserved on timeout.** If the DA1 sentinel arrives after only three of six DECRPM responses, the parser populates three `Supports_*` flags and leaves the rest False — exactly what FUNC-MSE-013 asks for.

### Negative Consequences

* **Interleaved-response parser required.** ~30 lines of new code in `Parse_All_Responses` to scan multiple frames from one buffer. Tested via §Q.1 combined-batch vectors.
* **Single timeout governs all six modes.** A slow terminal that responds for the first three modes within 1000 ms but is interrupted before responding for the last three returns "first three known, last three False (i.e., not-supported)". This is the desired interpretation per FUNC-MSE-013, but it means we cannot distinguish "terminal responded with `Not_Recognized` for mode X" from "terminal did not respond for mode X within the timeout". For mouse capability detection this is acceptable (both yield `Supports_X = False`).
* **`Sentinel_Query` semantics rely on empty-query-is-legal.** If a future `Termicap.OSC` revision adds a precondition `Query'Length > 0`, this design breaks. Mitigation: a comment in the MOUSE body documents the dependency, and a future OSC-INFRA change would have to migrate this call site.
* **Worst-case latency is bounded by the slowest mode's response.** Same as option B, just inverted: option B gives each mode 1/6 of the budget; option A gives the batch the full budget.

## Pros and Cons of the Options

### Option A: Batched single-sentinel session (chosen)

`Write_Query × 6` followed by `Sentinel_Query (Query => Empty_Byte_Array, ..., Timeout_Ms => 1000)`.

* Good, because single round-trip; minimum SSH-friendly latency.
* Good, because zero termios churn beyond the single open/close cycle (RAII via `Probe_Session`).
* Good, because no OSC-INFRA spec change needed; reuses existing API.
* Good, because matches tcell/notcurses startup-probe pattern (validated cross-language).
* Bad, because requires a multi-frame interleaved-response parser (~30 LOC, fully testable in CI without I/O).
* Bad, because depends on the tacit OSC-INFRA contract that empty queries are legal.

### Option B: Single session, per-mode sentinel queries

`Sentinel_Query × 6` inside one `Probe_Session`, each writing `DECRPM_Query (Modes (I))` + DA1 sentinel.

* Good, because per-mode parsing is trivial (one frame per buffer).
* Good, because per-mode timeouts are independent: mode 1015's timeout does not affect mode 1006.
* Good, because `Termicap.DECRPM.IO.Detect_Modes` already implements this pattern; we could reuse it directly.
* Bad, because six round-trips instead of one — visible latency on SSH.
* Bad, because six DA1 sentinels echoed into the terminal — six potential echo windows.
* Bad, because per-mode budgeting (1000 / 6 = 167 ms per mode) is less generous than the single 1000 ms cap, and if any one mode times out the others suffer correspondingly.

### Option C: Six independent sessions

Six successive calls to `Termicap.DECRPM.IO.Detect_Mode (Modes (I), 1000)`.

* Good, because the simplest possible code (one-line loop body).
* Good, because per-mode results are perfectly isolated.
* Bad, because **six** termios cycles (six `tcgetattr` + six `tcsetattr` + six `tcsetattr`) — eighteen system calls for what could be three.
* Bad, because six round-trips (same as option B).
* Bad, because six `Probe_Session` lifecycles each acquire the single-concurrent-session guard (FUNC-OSC-012), which serialises any concurrent feature probing.
* Bad, because every iteration drains stale input (`FUNC-OSC-011`); cumulative cost adds up.

### Option D: Extend OSC-INFRA with `Sentinel_Read_Only`

Add a new procedure to `Termicap.OSC` that does only the sentinel-write + read; six `Write_Query` calls then one `Sentinel_Read_Only`.

* Good, because makes the "send only the sentinel" intent explicit at the API level.
* Good, because no longer relies on the empty-query-is-legal tacit contract.
* Bad, because requires an OSC-INFRA spec amendment, an ADR (this one would not suffice), updates to FUNC-OSC-* requirements, and tests in `tests/src/test_osc.adb`.
* Bad, because turns a mouse-feature change into a cross-cutting infrastructure change.
* Bad, because the new entry point would be used only by MOUSE, increasing API surface for a single client.

## Links

* Related ADR: [ADR-0015](0015-probe-session-limited-controlled.md) — `Probe_Session` `Limited_Controlled` semantics (foundation for RAII termios restore)
* Related ADR: [ADR-0017](0017-da1-timeout-only-read-loop.md) — DA1 query uses `Timeout_Query` instead of `Sentinel_Query`; contrast with this ADR's reuse of `Sentinel_Query`
* Tech Spec: [`docs/tech-specs/mouse-protocol.md`](../tech-specs/mouse-protocol.md) §G.3 — Detection algorithm (batched probe)
* Tech Spec: [`docs/tech-specs/decrpm.md`](../tech-specs/decrpm.md) §7.3 — Detect_Modes batch design (option B reference)
* Tech Spec: [`docs/tech-specs/osc-query-infra.md`](../tech-specs/osc-query-infra.md) — Sentinel_Query specification
* Requirements: FUNC-MSE-004, FUNC-MSE-005, FUNC-MSE-013
* Reference framework: `reference-frameworks/tcell/tscreen.go` lines 1230–1238 — sends all queries followed by `requestPrimaryDA` (DA1) sentinel; identical pattern
* Reference framework: `reference-frameworks/notcurses/src/lib/termdesc.c` — startup probe sequence with single DA1 wait
