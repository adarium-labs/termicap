# Mouse Capability Record Shape: Orthogonal Booleans + Derived Best_Encoding

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-23

## Context and Problem Statement

The MOUSE feature returns a structured result type, `Mouse_Capabilities` (FUNC-MSE-002), that aggregates the outcome of detection. The result has two semantic dimensions:

1. **Per-mode support**: which DEC private modes (`1000`, `1002`, `1003`, `1015`, `1006`, `1016`) the terminal acknowledged via DECRPM.
2. **Encoding preference**: which of the four encoding families (`X10`, `URXVT`, `SGR`, `SGR_Pixels`) the caller should use, derived from the per-mode flags via the cascade in FUNC-MSE-008.

These two dimensions can be expressed in several record shapes. Which one does Termicap adopt?

## Decision Drivers

* **Caller ergonomics.** Most callers want a one-line answer: "what encoding should I use?". Some callers (e.g., a TUI library that supports drag selection) need to know whether mode `1002` (button-event) is available, separately from whether SGR encoding is. The record shape must serve both audiences.
* **SPARK provability.** Termicap's pure parser and cascade functions are SPARK Silver targets. Record shapes with discriminants, type invariants, or non-trivial predicates increase the proof burden. The simpler the record, the easier to prove.
* **Forward extensibility.** Future modes (e.g., `1004` focus events, hypothetical mouse extensions) should be addable without breaking the record's shape or the cascade's semantics. A flexible structure pays dividends as the protocol space evolves.
* **Test ergonomics.** Unit tests build `Mouse_Capabilities` aggregates by hand and check field-by-field equivalence. Sparse aggregates (mostly defaults, one or two fields set) should be easy to write.
* **Cross-language reference.** wezterm uses an opaque enum (`MouseEncoding`) without per-mode flags. tcell uses **per-flag Booleans** on its `tScreen` struct (`haveMouse`, `haveMouseSgr`). blessed uses per-mode `DecModeResponse` objects keyed by mode number. There is no single dominant idiom.
* **Internal consistency.** KKB's `Keyboard_Capability` (FUNC-KKB-003) is a flat record with `Protocol` enum + `Flags` record + `Probed` Boolean. Mouse should follow a similar shape for cognitive consistency unless there is a strong reason to diverge.

## Considered Options

* **Option A**: **Orthogonal Booleans + derived `Best_Encoding`**. Six per-mode `Supports_*` Booleans, two platform-specific Booleans (`Win32_Console_Mouse`, `GPM_Available`), one `Probed` flag, and a derived `Best_Encoding` enum field computed by `Resolve_Best_Encoding`. The record is "wide" but every field has clear semantics.
* **Option B**: **Opaque enum only** — `Mouse_Capabilities` is just `Mouse_Encoding`. Per-mode flags are not exposed; the cascade picks the encoding and that is the only output.
* **Option C**: **Discriminated record on `Mouse_Encoding`** — variant fields per encoding (e.g., `case Best_Encoding is when SGR_Pixels => null; when SGR => Supports_Button_Event : Boolean; when ...`).
* **Option D**: **Bitmask integer** — one `Supports_Mask : Interfaces.Unsigned_8` field encoding the six modes as bit positions; helper functions to query individual bits.
* **Option E**: **Set-of-modes** — `type Mode_Set is array (Mode_Id range MODE_MOUSE_X10 .. MODE_MOUSE_SGR_PIXELS) of Boolean`; `Mouse_Capabilities` includes a `Supported : Mode_Set` field.

## Decision Outcome

Chosen option: **Option A** (orthogonal Booleans + derived `Best_Encoding`), because it (1) serves both the "give me the best encoding" caller and the "tell me which tracking modes are available" caller without compromise, (2) is SPARK-friendly (flat record, no discriminant, no invariant), (3) extends cleanly (add a Boolean field per new mode, no other changes), and (4) follows KKB's flat-record-with-derived-summary pattern.

The record shape (MOUSE tech spec §F.2):

```ada
type Mouse_Capabilities is record
   Best_Encoding         : Mouse_Encoding := Unknown;  --  derived
   Supports_X10          : Boolean        := False;    --  mode 1000
   Supports_Button_Event : Boolean        := False;    --  mode 1002
   Supports_Any_Event    : Boolean        := False;    --  mode 1003
   Supports_URXVT        : Boolean        := False;    --  mode 1015
   Supports_SGR          : Boolean        := False;    --  mode 1006
   Supports_SGR_Pixels   : Boolean        := False;    --  mode 1016
   Win32_Console_Mouse   : Boolean        := False;    --  Win32 platform
   GPM_Available         : Boolean        := False;    --  Linux/GPM
   Probed                : Boolean        := False;
end record;
```

Internal consistency: the four implicit invariants `I1`–`I4` (MOUSE tech spec §F.2) are enforced by **construction** in body-private constructor helpers (`Make_Win32_Result`, `Make_GPM_Result`, `Make_Probed_Result`), not by `Type_Invariant` aspect. This avoids SPARK proof complexity at the boundary between `Termicap.Mouse` (SPARK On) and `Termicap.Mouse.IO` (SPARK Off) — see MOUSE tech spec §F.3 for the rejection rationale.

The `Best_Encoding` field is **derived** from the `Supports_*` flags at the moment the result is assembled (in `Make_Probed_Result`). It is not a dynamic computed property; once a `Mouse_Capabilities` value is materialised, `Best_Encoding` stays consistent with the `Supports_*` flags by construction. Callers who manually mutate the record (rare) are responsible for re-deriving via `Resolve_Best_Encoding`.

### Positive Consequences

* **Single result record satisfies both audiences.** The "give me the encoding" caller reads `Best_Encoding`; the "give me the tracking modes" caller reads `Supports_Button_Event` etc. No second API call needed.
* **SPARK-simple.** Flat record, no discriminant, no invariant aspect. The only SPARK contracts are on the parser and the cascade, both pure.
* **Forward-extensible.** Adding a new `Supports_Focus_Event : Boolean := False` field is a backward-compatible record extension. No callers break (default is False; absent in old data implies "not detected").
* **Trivially testable.** Test vectors construct sparse aggregates with `(Best_Encoding => SGR, Supports_SGR => True, others => False)` and compare equality.
* **Mirrors KKB.** `Keyboard_Capability` has the same flat-record shape with derived summary. Cognitive consistency for maintainers.
* **Honest about platform semantics.** The two platform Booleans (`Win32_Console_Mouse`, `GPM_Available`) are independent of the per-mode flags; mutual-exclusion is documented in the spec but not enforced by the type system, allowing the record to truthfully represent any future platform combination (e.g., a Cygwin/MSYS PTY where DECRPM works AND the user has GPM running on the X11 side — currently impossible but not provably so).

### Negative Consequences

* **Wide record.** Ten Boolean fields (six modes + two platform + Probed + Best_Encoding). Caller code that pattern-matches on every field is verbose; helper functions (`Is_Modern_Mouse (Caps)`, `Has_Drag_Support (Caps)`) are encouraged in caller-side application code, not the library.
* **Implicit invariants not type-enforced.** Constructing a `Mouse_Capabilities` literal that violates I1 (e.g., `Win32_Console_Mouse=True, Supports_X10=True`) does not cause a compile error. Mitigation: only the body-private constructors are used inside the library; external callers are unlikely to hand-construct invalid records (they get them from `Detect_Mouse_Protocols`). Documented as a non-enforced invariant.
* **`Best_Encoding` is denormalised.** It is derivable from the flags; storing it duplicates information. Trade-off: callers get a single-field answer without invoking `Resolve_Best_Encoding`. The denormalisation is set once at construction; no "stale `Best_Encoding`" risk under normal use.
* **No bitmask-style "any mouse mode supported" predicate.** Callers wanting "is any mouse mode supported?" check `Caps.Best_Encoding /= None and Caps.Best_Encoding /= Unknown`. Slightly more verbose than `Caps.Supports_Mask /= 0` (option D), but more explicit.

## Pros and Cons of the Options

### Option A: Orthogonal Booleans + derived Best_Encoding (chosen)

* Good, because serves both encoding-only callers and per-mode callers without separate APIs.
* Good, because SPARK-friendly (flat record, no discriminant, no invariant).
* Good, because extending with a new mode is a backward-compatible field addition.
* Good, because mirrors KKB pattern; consistency.
* Bad, because wide record (10 fields).
* Bad, because implicit invariants are not type-enforced (mitigated by body-private constructors).

### Option B: Opaque enum only

`type Mouse_Capabilities is new Mouse_Encoding;` (or a single-field record).

* Good, because minimal API surface; one field.
* Good, because trivial for "what encoding should I use?" callers.
* Bad, because callers needing per-mode information (e.g., does the terminal support drag tracking?) must call a separate API. Doubles the API surface.
* Bad, because `Probed` distinction is lost — callers cannot tell `Unknown` (didn't probe) from `None` (probed, found nothing).
* Bad, because diverges from KKB's record-with-Probed pattern.

### Option C: Discriminated record on Mouse_Encoding

```ada
type Mouse_Capabilities (Best_Encoding : Mouse_Encoding := Unknown) is record
   Probed : Boolean := False;
   case Best_Encoding is
      when SGR_Pixels | SGR => Supports_Button_Event : Boolean;
      when others           => null;
   end case;
end record;
```

* Good, because the type system enforces "you only have button-event info when Best_Encoding is SGR-derived".
* Bad, because the variant structure misrepresents reality: a terminal can support `1002` (button-event) without supporting `1006` (SGR encoding) — the two are independent. A discriminated record over `Best_Encoding` conflates the "encoding" axis and the "tracking mode" axis.
* Bad, because variant records with mutable discriminants are SPARK-hostile (FUNC-CAP-001 commentary explicitly discourages them).
* Bad, because record-aggregate updates require restating the discriminant; verbose at every constructor call site.

### Option D: Bitmask integer

```ada
type Mode_Mask is mod 64;
NO_MODES         : constant Mode_Mask := 0;
MASK_X10         : constant Mode_Mask := 1;
MASK_BUTTON_EVT  : constant Mode_Mask := 2;
... (six bits)

type Mouse_Capabilities is record
   Supported_Modes : Mode_Mask := 0;
   Best_Encoding   : Mouse_Encoding := Unknown;
   ... (Probed, Win32, GPM)
end record;

function Has_X10 (M : Mode_Mask) return Boolean is (M and MASK_X10) /= 0;
```

* Good, because compact (one byte for the modes field).
* Good, because "any mode supported" is a single comparison.
* Bad, because hides field semantics behind bit positions; readers need to consult constants to interpret a `Supported_Modes` value.
* Bad, because SPARK reasoning over modular bit operations requires more annotations than reasoning over boolean-record fields.
* Bad, because adding a new mode shifts existing bit values (or requires holes); brittle.
* Bad, because diverges from `Kitty_Flags`'s explicit-Boolean-field design (FUNC-KKB-002).

### Option E: Set-of-modes

```ada
type Mode_Set is array (Mode_Id range 1000 .. 1016) of Boolean;
type Mouse_Capabilities is record
   Supported : Mode_Set := (others => False);
   Best_Encoding : Mouse_Encoding := Unknown;
   ...
end record;
```

* Good, because the Boolean array indexed by mode number is direct semantically.
* Bad, because the array has 17 elements (indices 1000..1016) of which only 6 are used; sparse.
* Bad, because using a `Mode_Id` range as the index conflates `Mode_Id` (a `Natural` subtype with no upper bound) with a fixed enumeration; needs a separate `Tracked_Mode` enum, multiplying types.
* Bad, because no reference framework uses this shape; surprising for porters.

## Links

* Related ADR: [ADR-0023](0023-mouse-encoding-cascade-order.md) — How `Best_Encoding` is derived from the `Supports_*` flags
* Related ADR: [ADR-0013](0013-spark-annotation-split-capabilities.md) — Mixed SPARK_Mode pattern that allows the record to cross the SPARK boundary without invariant complications
* Tech Spec: [`docs/tech-specs/mouse-protocol.md`](../tech-specs/mouse-protocol.md) §F — Type design, predicate-rejection rationale, body-private constructors
* Requirements: FUNC-MSE-001 (encoding enum), FUNC-MSE-002 (record shape), FUNC-MSE-008 (cascade)
* Reference framework: `reference-frameworks/tcell/tscreen.go` lines 213–217 — `haveMouse` / `haveMouseSgr` per-flag Booleans on `tScreen`
* Reference framework: `reference-frameworks/wezterm/term/src/terminalstate/mod.rs` lines 57–63 — `MouseEncoding` enum (option B reference)
* Reference framework: `reference-frameworks/blessed/blessed/dec_modes.py` — per-mode `DecModeResponse` keyed by mode number (closer to option E)
* KKB analogue: `Termicap.Keyboard.Keyboard_Capability` in `src/termicap-keyboard.ads`
