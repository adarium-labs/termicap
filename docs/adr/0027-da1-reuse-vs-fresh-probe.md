# Reuse `Termicap.DA1.IO.Detect_DA1` Rather Than Issue a Private DA1 Probe

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-25

## Context and Problem Statement

The SIXEL feature (FUNC-SXL-001..019) needs the DA1 Ps=4 flag to detect Sixel
graphics support (FUNC-SXL-005). The DA1 protocol is already implemented by
the `Termicap.DA1` and `Termicap.DA1.IO` packages (FUNC-DA1-001..013):

- `Termicap.DA1.IO.Detect_DA1 (Timeout_Ms)` — opens a `Probe_Session`,
  sends `DA1_QUERY`, reads with `Timeout_Query` (timeout-only read loop,
  ADR-0017), parses, and returns a `DA1_Capabilities` record.
- `Termicap.DA1.IO.Query_DA1` — the lower-level entry point that returns
  raw response bytes for callers that want their own parsing.

FUNC-SXL-005 last paragraph says: *"if a DA1 result is already available
from a prior Termicap.DA1 detection call in the same process, the cached
DA1_Capabilities record shall be reused rather than issuing a new ESC [ c
query"*. The requirement specifies the behaviour but not the mechanism.
Three implementations satisfy the spec:

- **A.** Call `Termicap.DA1.IO.Detect_DA1` directly. Rely on whatever
  caching `Termicap.DA1.IO` provides internally (or accept an extra DA1
  round-trip if `Detect_DA1` does not cache).
- **B.** Maintain a private `DA1_Capabilities` cache inside
  `Termicap.Graphics.IO`. First call to `Detect_Graphics` issues a fresh
  `Detect_DA1` and stores the result; subsequent calls hit the Graphics
  cache (which already includes the derived `Sixel_Supported` flag, so the
  DA1 sub-cache is redundant).
- **C.** Duplicate the DA1 session lifecycle inside `Termicap.Graphics.IO`:
  open `Probe_Session`, write `DA1_QUERY`, run `Timeout_Query`, parse via
  `Termicap.OSC.Parsing.Parse_DA1_Response`, call
  `Termicap.DA1.Interpret_DA1`. Skip `Termicap.DA1.IO` entirely.

The decision affects: code duplication, coupling, the failure surface of
`Detect_Graphics`, and how XTSMGRAPHICS / future DA1-derived features
interact across the codebase.

## Decision Drivers

* **Code duplication.** Option C duplicates ~70 LOC of session lifecycle,
  multiplexer-passthrough decision, and parse orchestration. Options A and
  B share that code via `Detect_DA1`.
* **Coupling.** Option A couples `Termicap.Graphics` tightly to
  `Termicap.DA1.IO`. Option B keeps the coupling looser at the cost of
  redundant local state. Option C decouples completely at the cost of
  duplication.
* **Caching semantics.** The Graphics cache (FUNC-SXL-017) stores a
  `Graphics_Capabilities` record, which already records whether DA1 reported
  Sixel via `Sixel_Via_DA1`. A separate DA1-result cache would be
  semantically dominated.
* **Future feature reuse.** XTSMGRAPHICS, DA2, terminal-fingerprinting, and
  any other DA1-consumer will have the same question. Establishing a
  consistent answer now sets a precedent.
* **Testability.** Option A makes Graphics depend on the test posture of
  `Termicap.DA1.IO`. Option C lets Graphics tests stub DA1 directly. Option
  B is in between.
* **Failure isolation.** If `Detect_DA1` has a bug that makes it raise
  occasionally, the no-exception guarantee of `Detect_Graphics` (FUNC-SXL-016)
  must absorb it. Same for the multiplexer passthrough decision: if
  `Termicap.Terminal_Id.Detect_Terminal_Identity` raises, `Detect_DA1`
  catches it and returns Supported=False, but the failure mode must be
  understood by Graphics.

## Considered Options

* **Option A**: **Reuse `Termicap.DA1.IO.Detect_DA1` directly**. Call it
  with `GRAPHICS_PROBE_TIMEOUT_MS`. Wrap the result in an `exception when
  others => return zeroed DA1_Capabilities` block as a defence in depth.
  Rely on whatever caching `Detect_DA1` provides; if none, accept one
  fresh probe per `Detect_Graphics` call (which is itself cached).
* **Option B**: **Private DA1 sub-cache inside `Termicap.Graphics.IO`**.
  First call to `Detect_Graphics` runs `Detect_DA1` and stores the
  `DA1_Capabilities` in a private slot. Subsequent calls (which would in
  practice hit the Graphics cache before reaching this point) skip DA1.
* **Option C**: **Duplicate the DA1 session lifecycle**. Open `Probe_Session`
  manually, send `DA1_QUERY`, run `Timeout_Query`, parse with
  `Termicap.OSC.Parsing.Parse_DA1_Response`, interpret with
  `Termicap.DA1.Interpret_DA1`. Reuses only the SPARK On building blocks.

## Decision Outcome

Chosen option: **Option A** (reuse `Termicap.DA1.IO.Detect_DA1` directly),
because:

1. It minimises code duplication: zero LOC of session lifecycle inside
   `Termicap.Graphics.IO`.
2. The Graphics cache (FUNC-SXL-017) already provides the right caching
   granularity. A second DA1-result sub-cache is dominated and adds state
   without value.
3. The multiplexer-passthrough decision (FUNC-DA1-012) is a real,
   non-trivial consideration that should not be reimplemented per feature.
4. Future features (XTSMGRAPHICS, DA2 if added) can follow the same pattern,
   establishing a consistent "consume the .IO convenience function"
   precedent.
5. The no-exception guarantee is preserved by the outer `when others`
   handler in `Detect_Graphics` and an inner safety wrap around the
   `Detect_DA1` call.

The implementation is one expression:

```ada
declare
   DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
                Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
begin
   if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Sixel_Graphics) then
      Caps.Sixel_Supported := True;
      Caps.Sixel_Via_DA1   := True;
      Caps.Probed          := True;
   end if;
end;
```

If `Detect_DA1` adds caching in the future (or already has it via the
`Termicap.DA1.IO` body), Graphics inherits the benefit transparently. If
not, the per-process Graphics cache (FUNC-SXL-017) ensures `Detect_DA1` is
called at most once per process anyway.

### Positive Consequences

* **Zero new session-lifecycle code in Graphics.** All session management
  lives in `Termicap.OSC` and `Termicap.DA1.IO`; Graphics is a thin
  orchestration layer.
* **Multiplexer awareness for free.** `Detect_DA1` already wraps DA1_QUERY
  in tmux/screen passthrough envelopes when needed (FUNC-DA1-012); Graphics
  inherits this without a single line of code.
* **Consistent precedent for DA1-consumer features.** Future XTSMGRAPHICS,
  DA2, etc. all use `Termicap.<Foo>.IO.Detect_<Foo>` as the canonical entry.
* **Smaller test surface.** Graphics tests do not need to validate DA1
  session lifecycle; they assume `Detect_DA1` works (validated by its own
  test suite) and test only the orchestration glue.

### Negative Consequences

* **Tighter coupling to `Termicap.DA1.IO`.** A breaking change to
  `Detect_DA1`'s signature or semantics requires a Graphics update. Mitigated
  by `Detect_DA1` being a stable, low-churn API (FUNC-DA1-009).
* **Two-level caching is opaque.** The Graphics cache hits before
  `Detect_DA1` does, but a developer reading `Run_Cascade` for the first
  time may not realise that `Detect_DA1` is itself idempotent across
  process lifetime via the Graphics cache. Mitigated by the comment in
  §G.2 of the SIXEL tech spec.
* **`Detect_DA1` failures are outside Graphics's control.** If `Detect_DA1`
  has a bug that returns wrong results, Graphics inherits it. Mitigated by
  `Detect_DA1`'s own test suite and the FUNC-SXL-016 outer exception
  handler as a last-resort defence.

## Pros and Cons of the Options

### Option A: Reuse `Detect_DA1` directly (chosen)

* Good, because zero LOC of session lifecycle in Graphics.
* Good, because multiplexer-passthrough handled automatically.
* Good, because consistent with the established "convenience-function .IO
  packages" idiom (`Detect_XTVERSION`, `Detect_DA1`, `Detect_Mouse_Protocols`).
* Good, because future DA1-consumer features have a clear precedent.
* Bad, because tight coupling to `Termicap.DA1.IO` API stability.
* Bad, because two-level caching (DA1.IO's internal cache + Graphics's cache)
  is initially confusing.

### Option B: Private DA1 sub-cache

* Good, because makes the "DA1 result reused across calls" property
  explicit and locally inspectable.
* Good, because decouples Graphics from any future caching changes in
  `Termicap.DA1.IO`.
* Bad, because the Graphics cache already provides the same property at
  a higher granularity; the sub-cache is dominated.
* Bad, because adds a protected-object instance (or volatile state) for
  no observable behaviour change.
* Bad, because increases the failure surface of `Detect_Graphics` (a bug
  in the sub-cache is one more thing that can go wrong).

### Option C: Duplicate the DA1 session lifecycle

* Good, because Graphics has zero runtime dependency on `Termicap.DA1.IO`.
* Good, because Graphics tests can stub the OSC layer directly without
  going through `Detect_DA1`.
* Bad, because ~70 LOC of duplicated session lifecycle, multiplexer
  passthrough decision, and parse orchestration.
* Bad, because two-place bug surface: a fix in `Detect_DA1` does not
  propagate to Graphics.
* Bad, because sets a bad precedent: every DA1-consumer feature would be
  tempted to copy-paste this code.
* Bad, because Graphics would need to with `Termicap.OSC` and
  `Termicap.OSC.Parsing` and `Termicap.Terminal_Id` — a deeper dependency
  graph than option A.

## Links

* Related ADR: [ADR-0017](0017-da1-timeout-only-read-loop.md) — DA1 uses
  `Timeout_Query` instead of `Sentinel_Query`; the `Detect_DA1` body
  embodies this choice.
* Related ADR: [ADR-0028](0028-graphics-independent-probe-sessions.md) —
  Sibling decision: DA1 and APC are independent sessions; this ADR
  resolves *what* to do for DA1; ADR-0028 resolves *how* DA1 and APC
  relate session-wise.
* Tech Spec: [`docs/tech-specs/sixel-graphics.md`](../tech-specs/sixel-graphics.md) §G.2 — DA1 detection algorithm
* Tech Spec: [`docs/tech-specs/da1-response-parsing.md`](../tech-specs/da1-response-parsing.md) — `Detect_DA1` design
* Requirements: FUNC-SXL-005, FUNC-SXL-006
* Source: `src/termicap-da1.ads` (the `Sixel_Graphics` enum literal)
* Source: `src/termicap-da1-io.ads` / `.adb` (the `Detect_DA1` function)
