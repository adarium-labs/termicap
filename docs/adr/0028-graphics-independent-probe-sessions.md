# DA1 and APC Run as Independent Probe Sessions, Not Batched

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-25

## Context and Problem Statement

The SIXEL feature (FUNC-SXL-001..019) issues two distinct active probes:

- **DA1 probe** (FUNC-SXL-005, FUNC-SXL-006) — sends `ESC [ c`, reads until
  the DA1 response `CSI ? ... c`. The DA1 response *is* the data being
  sought (Sixel = Ps=4 in the response).
- **Kitty APC probe** (FUNC-SXL-010) — sends `ESC _ G i=1,a=q ESC \`,
  optionally followed by a DA1 sentinel for boundary detection. Reads
  until a kitty APC response (`ESC _ G ... ESC \` containing OK or
  EINVAL) or until the DA1 sentinel terminates the read.

FUNC-SXL-015 explicitly mandates: *"When the DA1 probe and APC probe are
both performed in the same detection call, they shall be performed as
separate sessions with independent timeouts, not as a single batched session."*

The MOUSE feature took the opposite design (ADR-0022): six DECRPM queries
are batched into a single session with one DA1 sentinel. This asymmetry
warrants explicit justification: why does SIXEL diverge?

The decision affects: latency, parser complexity, code reuse, and the
correctness of timeout semantics across two probes that have very different
response shapes.

## Decision Drivers

* **DA1 self-sentinelling property.** The DA1 query's *own response* is
  CSI-shaped (`CSI ? ... c`). When `Termicap.DA1.IO.Detect_DA1` runs, it
  uses `Termicap.OSC.Timeout_Query` (not `Sentinel_Query`) because there
  is no separate sentinel — the response *is* the boundary (ADR-0017).
* **APC sentinel-bounded read.** The APC response (`ESC _ G ... ESC \`)
  is not predictable in length; the read needs an explicit DA1 sentinel
  appended after the APC query to terminate the read on terminals that
  ignore the APC. This is what `Sentinel_Query` does.
* **Response-shape ambiguity if batched.** If DA1 and APC are batched in
  one session, the response stream contains:
  - A possible APC response: `ESC _ G ... ESC \`
  - A DA1 response: `ESC [ ? ... c`
  And the read terminator is the DA1 response — but DA1 is *also* the
  data the DA1 probe is seeking. The parser cannot disambiguate "this
  CSI is the APC's terminating DA1 sentinel" from "this CSI is the DA1
  probe's data response" without semantic knowledge: they are byte-identical.
* **Code reuse via existing convenience functions.** `Termicap.DA1.IO.Detect_DA1`
  is a stable, tested entry point for DA1 probing (per ADR-0027). Mixing
  its behaviour with an APC probe would require re-implementing the DA1
  session lifecycle inside Graphics, undoing ADR-0027.
* **Latency cost of two sessions.** Two `tcgetattr`/`tcsetattr` cycles, two
  `/dev/tty` opens, two raw-mode entries. On a local PTY, total overhead is
  ~1 ms; on SSH, two 200 ms RTTs (~400 ms total) versus a hypothetical
  batched ~200 ms. For a one-time-per-process detection, this is acceptable.
* **Optionality of the APC probe.** FUNC-SXL-010 is Should-priority; an
  implementation that omits APC entirely still satisfies all MUST
  requirements via passive Kitty detection (FUNC-SXL-009). A batched
  design cannot honour this optionality cleanly: either both probes run
  or neither does, since they share the session.
* **MOUSE precedent.** MOUSE batches six queries because they all use
  the same DECRPM response shape (`CSI ? Ps ; Pm $ y`) which is
  structurally distinct from the DA1 sentinel. SIXEL has two queries with
  different response shapes and one of them shares the boundary marker
  with the other's data — fundamentally different.

## Considered Options

* **Option A**: **Independent sessions, sequential**. First call
  `Termicap.DA1.IO.Detect_DA1`, then call a local `Run_APC_Probe` that
  opens its own `Probe_Session` and runs `Sentinel_Query` for the APC.
  Two sessions; ~600 ms worst case on SSH (300 ms per session).
* **Option B**: **Batched single session, single sentinel**. Open one
  `Probe_Session`. Send the APC query first (`ESC _ G i=1,a=q ESC \`),
  followed by `ESC [ c` (DA1 sentinel-and-data combined). Read until
  `CSI ? ... c` is detected. Parse both APC and DA1 from the
  accumulated buffer. One session; ~300 ms worst case on SSH.
* **Option C**: **Independent sessions, parallel**. Open two
  `Probe_Sessions` simultaneously and read both responses concurrently.
  Faster than option A on SSH, but conflicts with FUNC-OSC-012
  (single-concurrent-session guard) — would require lifting that
  invariant.
* **Option D**: **Sequential, but only run APC when env-vars are
  ambiguous**. Skip the APC probe when KITTY_WINDOW_ID is set or
  TERM=xterm-kitty (FUNC-SXL-009 already implies this). When passive
  detection is conclusive, no APC is sent — saving ~300 ms in the common
  kitty/WezTerm case.

## Decision Outcome

Chosen option: **Option A** with the **Option D optimisation overlay**:

1. **Sessions are independent and sequential** (FUNC-SXL-015 mandates this).
2. **The APC probe is skipped when env-var Kitty detection has already
   confirmed Kitty graphics support** (per the spec's §G.1 cascade Step 5
   guard `if not Caps.Kitty_Graphics_Supported then`).

This is the right choice because:

1. **DA1's self-sentinelling property is non-negotiable.** Mixing DA1
   probing with any other query in the same session creates parser
   ambiguity that no clever encoding can resolve. The bytes
   `ESC [ ? ... c` are identical for "DA1 response data" and "DA1 sentinel
   marker"; only context separates them, and that context is the session
   semantics.
2. **`Termicap.DA1.IO.Detect_DA1` is the right caller for DA1 probing**
   (per ADR-0027). Re-implementing DA1 session orchestration inline to
   batch with APC would undo ADR-0027 and duplicate ~70 LOC.
3. **The APC probe's optionality is preserved.** When env-var Kitty
   detection succeeds (the common case for kitty and WezTerm), the APC
   probe is skipped entirely — zero round-trip cost for the modal path.
4. **The latency cost is acceptable.** In the worst case (terminal does
   not match any env-var, DA1 times out, APC times out), `Detect_Graphics`
   takes 2-3 seconds. In the common case (kitty/WezTerm with env vars set;
   xterm with DA1 fast-fail), it takes <500 ms. A one-time-per-process
   cost.

The APC sentinel boundary is `ESC [ c` (DA1) appended by `Sentinel_Query`.
This works because the APC probe runs in a separate session from DA1 — the
DA1 sentinel here is just a boundary marker, not data being sought.

### Positive Consequences

* **Parser simplicity.** `Parse_Kitty_APC_Response` looks for `ESC _ G`;
  `Termicap.DA1.IO.Detect_DA1` looks for `CSI ? ... c`. Each parser has
  one well-defined response shape and no risk of confusing the two.
* **Reuses existing convenience functions.** Zero new session-lifecycle
  code; `Detect_DA1` and `Run_APC_Probe` (a thin wrapper over
  `Sentinel_Query`) cover all I/O.
* **APC probe truly optional.** When env-vars resolve Kitty, APC is
  skipped → zero cost. An implementation that omits APC entirely (e.g.,
  for size optimisation) deletes one helper and remains correct.
* **Independent timeouts.** A slow APC response does not consume the DA1
  budget; a slow DA1 response does not consume the APC budget. Each
  probe has a clean 1000 ms ceiling.
* **Aligned with ADR-0017.** ADR-0017 forbids mixing DA1 with sentinel-bounded
  queries in the same session; this ADR upholds that decision in a
  compositional context.

### Negative Consequences

* **Two `tcgetattr`/`tcsetattr` cycles.** ~1 ms wasted on local PTYs;
  unmeasurable in practice.
* **Two `/dev/tty` opens.** Same negligible cost.
* **Worst-case latency is 2-3 s** when both probes time out and XTVERSION
  is also queried. Mitigated by the env-var fast paths and the
  one-probe-per-process cache.
* **Asymmetry with MOUSE (ADR-0022).** Maintainers reading both ADRs need
  to understand *why* SIXEL diverges. Documented in §J of the SIXEL tech
  spec and the "Decision Drivers" section above.

## Pros and Cons of the Options

### Option A: Independent sequential sessions (chosen)

* Good, because parser shapes are isolated; no DA1/APC ambiguity.
* Good, because reuses `Termicap.DA1.IO.Detect_DA1` (per ADR-0027).
* Good, because APC probe is genuinely optional (cleanly skippable).
* Good, because independent timeouts.
* Bad, because two `tcgetattr`/`tcsetattr` cycles (~1 ms cost; negligible).
* Bad, because asymmetric with MOUSE batching (ADR-0022); requires
  documentation.

### Option B: Batched single session, single sentinel

* Good, because half the round-trip cost on SSH (~200 ms vs ~400 ms).
* Good, because one termios cycle.
* Bad, because **fatal parser ambiguity**: the DA1 response and the DA1
  sentinel are byte-identical. The parser cannot tell apart "this CSI is
  the DA1-probe's data" from "this CSI is the APC-probe's terminating
  sentinel".
* Bad, because precludes reusing `Termicap.DA1.IO.Detect_DA1`; must
  re-implement DA1 session orchestration inline.
* Bad, because precludes APC optionality: the session is committed to
  both probes from the start.
* Bad, because conflicts with ADR-0017 (DA1 uses `Timeout_Query`, not
  `Sentinel_Query`).

### Option C: Independent parallel sessions

* Good, because halves the wall-clock latency on SSH.
* Bad, because **violates FUNC-OSC-012** (single concurrent session
  guard). Lifting that invariant is a Tier 3 change requiring its own
  ADR.
* Bad, because two simultaneous raw-mode terminals on the same /dev/tty
  is unusual and may have OS-level interactions (most POSIX systems
  serialise these via the kernel, but the behaviour is platform-specific).
* Bad, because complicates failure modes: which session's failure
  matters? Both?
* Bad, because no real-world reference framework does this — uncharted
  territory.

### Option D as standalone: Skip APC when env-vars are conclusive

* Good, because zero APC round-trip in the common kitty/WezTerm case.
* Good, because optimisation is purely local (one extra `if` in
  `Run_Cascade`).
* Bad, because alone is not enough: the question of *how* to run the
  probes when both are needed remains open. Hence we adopt Option A's
  structural separation **plus** Option D's optimisation overlay.

## Links

* Related ADR: [ADR-0017](0017-da1-timeout-only-read-loop.md) — DA1 uses
  `Timeout_Query` (not `Sentinel_Query`) because DA1's response *is* the
  data; this ADR depends on that distinction.
* Related ADR: [ADR-0022](0022-batched-single-sentinel-decrpm-mouse-probe.md)
  — MOUSE batches six DECRPM queries because they have a uniform response
  shape distinct from the DA1 sentinel; SIXEL cannot batch because DA1
  *is* its own response.
* Related ADR: [ADR-0027](0027-da1-reuse-vs-fresh-probe.md) — Reuse
  `Detect_DA1`; this ADR confirms that the reuse is structurally sound.
* Tech Spec: [`docs/tech-specs/sixel-graphics.md`](../tech-specs/sixel-graphics.md) §J — Two-session decision discussion
* Tech Spec: [`docs/tech-specs/sixel-graphics.md`](../tech-specs/sixel-graphics.md) §K — Timeout behaviour
* Tech Spec: [`docs/tech-specs/da1-response-parsing.md`](../tech-specs/da1-response-parsing.md) — `Timeout_Query` rationale
* Tech Spec: [`docs/tech-specs/osc-query-infra.md`](../tech-specs/osc-query-infra.md) — `Sentinel_Query` specification
* Requirements: FUNC-SXL-005, FUNC-SXL-010, FUNC-SXL-015
* Reference: notcurses `KITTYQUERY` (`reference-frameworks/notcurses/src/lib/termdesc.c:383`)
  — adopted byte sequence; notcurses bundles APC with DA1 in a single
  startup batch but performs different post-hoc parsing per response shape
