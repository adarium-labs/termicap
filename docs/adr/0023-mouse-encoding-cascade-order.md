# Mouse Encoding Cascade Order: SGR_Pixels > SGR > URXVT > X10 > None

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The MOUSE feature exposes a `Mouse_Encoding` enum (FUNC-MSE-001) with five practical values: `None`, `X10`, `URXVT`, `SGR`, `SGR_Pixels`. The pure SPARK function `Resolve_Best_Encoding` (FUNC-MSE-008) collapses the per-mode `Supports_*` Boolean flags in `Mouse_Capabilities` into a single `Best_Encoding` value via a preference cascade. Which order should the cascade evaluate the candidates in?

Multiple orderings are plausible. The choice has runtime consequences: a terminal that supports both `1006` (SGR) and `1015` (URXVT) will be reported as `SGR` under one cascade and `URXVT` under another. Applications that follow `Best_Encoding`'s recommendation will then send a different DECSET sequence and parse a different wire format.

## Decision Drivers

* **Information richness.** SGR-Pixels (1016) returns pixel-precision coordinates; SGR (1006) returns cell coordinates with explicit press/release distinction (`M`/`m` terminator); URXVT (1015) returns cell coordinates without press/release distinction; X10 (1000) returns 3-byte raw-byte coordinates with a 222-cell ceiling and breaks on `\xff`-class bytes.
* **Wire-format byte safety.** X10's raw-byte encoding is the only mouse encoding that may emit bytes outside the printable-ASCII / ESC/CSI range. On terminals with character-set switching or non-UTF-8 locales, this is a known footgun.
* **Cross-language consensus.** blessed (`tests/test_mouse.py` line 38) and notcurses both prefer SGR-Pixels over SGR. wezterm's `MouseEncoding` enum places `SgrPixels` last (highest), `SGR` second-highest, then `Utf8`/`X10`. tcell's reference design (`tscreen.go` `enableMouse`) prefers `SGR` if `haveMouseSgr`, otherwise warns via comment about reduced behaviour.
* **Caller predictability.** A cascade that returns the most expressive encoding minimises caller-side fallback logic: the caller can take `Best_Encoding`'s recommendation at face value and trust that a less-rich encoding will not silently substitute.
* **URXVT vs X10 ordering.** URXVT (1015) is mode-numbered between X10 and SGR (1015 sits between 1003 and 1016 in DEC-mode numbering). However, **functionally** URXVT is closer to SGR than to X10: it has unlimited coordinate range (X10 does not) but lacks press/release distinction (SGR has it). Should URXVT be placed above X10 (functional ordering) or below SGR (mode-number ordering)?
* **User-override hook.** Some applications may want to force X10 for legacy compatibility (e.g., a TUI that targets pre-modern terminals). Should the cascade support a user override? FUNC-MSE-008 does not specify one.

## Considered Options

* **Option A**: **Expressive-power-descending** — `SGR_Pixels > SGR > URXVT > X10 > None`. Pixel-precision first, then cell + press/release, then cell-only, then legacy, then nothing.
* **Option B**: **Mode-number-ascending** — `X10 > URXVT > SGR > SGR_Pixels > None`. Numerical order; legacy first.
* **Option C**: **Mode-number-descending** — `SGR_Pixels > URXVT > SGR > X10 > None`. SGR-Pixels first (correct), but URXVT (1015) above SGR (1006) by mode number — functionally wrong because SGR has press/release distinction.
* **Option D**: **Expressive with X10 promoted** — `SGR_Pixels > SGR > X10 > URXVT > None`. Same as A but X10 above URXVT, on the grounds that X10 is more universally supported.
* **Option E**: **User-overridable cascade** — public function `Resolve_Best_Encoding (Caps, Override : Mouse_Encoding := Unknown)` that returns `Override` when it is non-Unknown and supported, else falls back to option A.

## Decision Outcome

Chosen option: **Option A** (`SGR_Pixels > SGR > URXVT > X10 > None`), because it (1) returns the most information-rich encoding the terminal advertises, (2) matches blessed's published preference order and notcurses's effective preference, (3) places URXVT above X10 on functional grounds (unlimited coordinate range strictly dominates X10's 222-cell ceiling), and (4) keeps `Resolve_Best_Encoding` a pure parameterless function with a deterministic, easily-unit-testable mapping.

The cascade is implemented as a five-arm if-elsif chain in `Resolve_Best_Encoding` (MOUSE tech spec §H.1). Per FUNC-MSE-008, the cascade is evaluated only when `Probed = True`; otherwise it returns `Unknown` regardless of which `Supports_*` flags are set.

**No user override in v1.** Applications that need a different policy (e.g., force X10 for legacy compatibility) can ignore `Best_Encoding` and inspect the `Supports_*` Booleans directly:

```ada
Caps := Termicap.Mouse.IO.Detect_Mouse_Protocols;
if Want_Legacy and then Caps.Supports_X10 then
   Use_Encoding (X10);
else
   Use_Encoding (Caps.Best_Encoding);
end if;
```

This composition pattern matches Termicap's general philosophy: the library reports observed capability, the caller decides policy.

### Positive Consequences

* **Maximum information by default.** Callers who use `Best_Encoding` without further analysis get the richest available mouse data.
* **Pure SPARK function.** No I/O, no globals, deterministic; trivially unit-testable. SPARK Silver provable.
* **Matches blessed test expectations** (`tests/test_mouse.py` line 38: "When both 1006 and 1016 are enabled, 1016 (SGR-Pixels) is preferred"). Cross-validated.
* **URXVT above X10 reflects real-world terminal capability.** Most modern terminals that support URXVT also support X10; the cascade picking URXVT means callers get unlimited coordinates instead of being capped at 222.
* **No API surface for overrides** — keeps the v1 API minimal. Override capability can be added in a future version without breaking `Resolve_Best_Encoding`'s signature (add a default-valued parameter).

### Negative Consequences

* **No way to force a less-rich encoding via Best_Encoding alone.** Callers who want X10 for a specific reason (e.g., debugging, legacy emulator) must inspect `Supports_*` directly. Documented in the User Guide.
* **Cascade is opinionated.** The library imposes a preference order. Applications with unusual requirements (e.g., a Sixel renderer that needs pixel coords but is willing to fall back to cell coords if SGR-Pixels is "too new" for the surrounding ecosystem) must implement their own cascade.
* **URXVT placement is debatable.** Some readers may expect URXVT (mode 1015) above X10 (1000) because it is numerically lower than SGR (1006) but greater than X10 (1000). The ordering chosen here trumps the numerical intuition with a functional argument; reasonable people may disagree.

## Pros and Cons of the Options

### Option A: Expressive-power-descending — SGR_Pixels > SGR > URXVT > X10 > None (chosen)

* Good, because returns the most information-rich encoding the terminal supports.
* Good, because matches blessed and notcurses preferences (cross-validated).
* Good, because URXVT above X10 favours unlimited coordinates over byte-limited.
* Good, because pure SPARK function with deterministic mapping; trivially unit-testable.
* Bad, because cascade is opinionated; callers wanting unusual policies must read `Supports_*` directly.

### Option B: Mode-number-ascending — X10 > URXVT > SGR > SGR_Pixels > None

* Good, because matches DEC private-mode number ordering — easy mnemonic.
* Bad, because returns the **least** rich encoding by default — the opposite of what callers usually want.
* Bad, because no reference framework uses this order; cross-language inconsistency.
* Bad, because callers would always need to override the default to get usable behaviour, defeating the purpose of having a `Best_Encoding` field.

### Option C: Mode-number-descending — SGR_Pixels > URXVT > SGR > X10 > None

* Good, because places SGR-Pixels first (correct).
* Bad, because URXVT above SGR is functionally wrong: SGR has press/release distinction (`M`/`m`), URXVT does not. A caller picking URXVT over SGR loses information unnecessarily.
* Bad, because no reference framework uses this; surprises Python/Go porters who expect option A.

### Option D: Expressive with X10 promoted — SGR_Pixels > SGR > X10 > URXVT > None

* Good, because X10 is the most universally-deployed legacy encoding; promoting it serves caller compatibility.
* Bad, because URXVT below X10 forces callers on URXVT-supporting terminals (foot, urxvt-derived) to lose unlimited coordinate range.
* Bad, because functionally inverts the "richer encoding wins" property — URXVT supports >222-column terminals while X10 does not.
* Bad, because no reference framework uses this order.

### Option E: User-overridable cascade — `Resolve_Best_Encoding (Caps, Override)`

* Good, because lets callers force a specific encoding without re-implementing the cascade.
* Good, because forward-compatible: can be added in v2 without breaking v1's signature.
* Bad, because adds API surface for a niche need; v1 callers who want overrides can inspect `Supports_*` directly.
* Bad, because the override semantics are ambiguous: should the override return the requested encoding even if `Supports_X = False`? Or fall back to the cascade? Both behaviours have arguments, and picking one in v1 forecloses the other.
* Bad, because the override would shift the override semantics from caller-controlled (the recommended pattern) into a library-policy decision.

## Links

* Related ADR: [ADR-0022](0022-batched-single-sentinel-decrpm-mouse-probe.md) — Batched probe session that produces the `Supports_*` flags this cascade consumes
* Related ADR: [ADR-0025](0025-mouse-capability-record-shape.md) — Why `Mouse_Capabilities` exposes orthogonal `Supports_*` Booleans (consumed by the cascade)
* Tech Spec: [`docs/tech-specs/mouse-protocol.md`](../tech-specs/mouse-protocol.md) §H — Cascade resolution, truth table, postconditions
* Requirements: FUNC-MSE-001, FUNC-MSE-008
* Reference framework: `reference-frameworks/blessed/tests/test_mouse.py` lines 38, 82 — `"When both 1006 and 1016 are enabled, 1016 (SGR-Pixels) is preferred"`
* Reference framework: `reference-frameworks/wezterm/term/src/terminalstate/mod.rs` lines 57–63 — `MouseEncoding` enum ordering (X10, Utf8, SGR, SgrPixels)
* Reference framework: `reference-frameworks/notcurses/src/lib/termdesc.c` — startup probe + cascade pattern
* Cross-language synthesis: `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` §2.6 — mouse encoding ladder
