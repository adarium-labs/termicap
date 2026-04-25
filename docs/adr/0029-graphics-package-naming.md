# Package Name `Termicap.Graphics` (Over `Sixel` / `Graphics_Protocol`)

* Status: proposed
* Deciders: Termicap Contributors
* Date: 2026-04-25

## Context and Problem Statement

The SIXEL feature (FUNC-SXL-001..019) detects two distinct graphics
protocols: Sixel (DEC bitmap encoding, FUNC-SXL-005..008) and the Kitty
graphics protocol (APC-based image rendering, FUNC-SXL-009..010). The
result is a single `Graphics_Capabilities` record that aggregates both
sets of flags.

The package name must be chosen carefully:

- It needs to accommodate **both** protocols without implying that one
  is hierarchically subordinate to the other.
- It needs to be future-extensible: if iTerm2 image protocol or a new
  graphics protocol joins the ecosystem, the package should host it
  without renaming.
- It needs to be discoverable: a developer searching for "how do I detect
  Sixel" or "how do I detect Kitty graphics" should find this package.
- It needs to follow the established `Termicap.<Capability>` naming
  pattern (`Termicap.Color`, `Termicap.Mouse`, `Termicap.Keyboard`,
  `Termicap.Unicode`, etc.).

FUNC-SXL-018 commentary mentions the choice but does not record the
alternatives evaluated. This ADR fills that gap so that future maintainers
understand the constraints.

## Decision Drivers

* **Plurality.** Two protocols today; potentially more tomorrow.
* **Discoverability.** Developers may search by protocol name (Sixel,
  Kitty) or by capability (graphics, image, bitmap).
* **Future extensibility.** Adding iTerm2's inline-image protocol or any
  new bitmap encoding should not require a package rename or a new
  package.
* **Consistency.** `Termicap` already has `Termicap.Mouse` (a generic
  capability name covering X10/SGR/SGR-Pixels/URXVT — multiple encodings)
  and `Termicap.Keyboard` (covering Kitty keyboard + modifyOtherKeys —
  multiple protocols). Capability-level naming is the established pattern.
* **Brand-neutrality.** Naming after a specific vendor's protocol
  (`Termicap.Kitty`, `Termicap.WezTerm`) anchors the package to one
  ecosystem. A generic name is more durable.
* **Conciseness.** Long compound names (`Termicap.Graphics_Protocol`)
  are tolerated but break the existing single-word capability convention
  (`Termicap.Mouse`, not `Termicap.Mouse_Protocol`).

## Considered Options

* **Option A**: **`Termicap.Graphics`**. Generic capability name covering
  both Sixel and Kitty graphics. Single-word; matches the existing pattern.
* **Option B**: **`Termicap.Sixel`**. Names the older / more widespread
  protocol. Kitty graphics is a "secondary feature" of the same package.
* **Option C**: **`Termicap.Graphics_Protocol`**. Explicit "protocol"
  suffix; verbose but unambiguous.
* **Option D**: **`Termicap.Image`**. Reflects the user-facing concept
  (the application wants to render an image; the package answers "is
  that possible?").
* **Option E**: **`Termicap.Bitmap`**. Narrower than Image; specifically
  raster graphics.
* **Option F**: **Two sibling packages**: `Termicap.Sixel` and
  `Termicap.Kitty_Graphics`, each with its own detection and types.
  Aggregated by a higher-level `Termicap.Graphics` if needed.

## Decision Outcome

Chosen option: **Option A (`Termicap.Graphics`)**, because:

1. It is **generic**: covers Sixel, Kitty, and any future graphics
   protocol without renaming.
2. It is **brand-neutral**: no vendor-specific name embedded in the
   import path.
3. It is **concise**: single word, matches `Termicap.Mouse` /
   `Termicap.Keyboard` / `Termicap.Color` / `Termicap.Unicode` etc.
4. It is **discoverable**: any developer searching for graphics
   capabilities will find it.
5. It is **forward-compatible**: adding iTerm2 image protocol becomes a
   `Termicap.Graphics.iTerm2_*` field addition — no architectural change.
6. The result-record naming (`Graphics_Capabilities`) flows naturally
   from the package name and matches the existing
   `Mouse_Capabilities` / `Keyboard_Capability` / `DA1_Capabilities`
   patterns.

The alternative names are useful as **constants and field names within**
`Termicap.Graphics`:

```ada
package Termicap.Graphics is
   --  ...
   TERM_PROGRAM_WEZTERM   : constant String := "WezTerm";
   ENV_KITTY_WINDOW_ID    : constant String := "KITTY_WINDOW_ID";
   XTVERSION_NAME_KITTY   : constant String := "kitty";
   XTVERSION_NAME_WEZTERM : constant String := "WezTerm";
   --  ...
   type Graphics_Capabilities is record
      Sixel_Supported          : Boolean := False;
      Kitty_Graphics_Supported : Boolean := False;
      Sixel_Via_DA1            : Boolean := False;
      Kitty_Via_Active_Probe   : Boolean := False;
      --  ...
   end record;
end Termicap.Graphics;
```

The protocol names appear inside the package as field/constant names where
the specificity is appropriate, while the package itself stays generic.

### Positive Consequences

* **One package, many protocols.** Future iTerm2 image protocol detection
  (or any new graphics encoding) is a one-field addition to
  `Graphics_Capabilities` plus a passive heuristic — no renaming, no new
  package.
* **Consistent with established pattern.** `Termicap.Mouse` covers six
  encoding modes; `Termicap.Keyboard` covers Kitty + modifyOtherKeys;
  `Termicap.Graphics` covers Sixel + Kitty graphics. Mental model is
  uniform.
* **Brand-neutral.** Application code reads
  `Termicap.Graphics.Detect_Graphics` — neutral about which protocol
  fired.
* **Future maintainability.** A future contributor adding Sixel-only
  (or Kitty-only) functionality places it in `Termicap.Graphics` with
  appropriate field/constant names; no architectural decision needed.

### Negative Consequences

* **Slightly less discoverable for "Kitty graphics" searches.** A
  developer typing `Termicap.Kitty<TAB>` in their IDE will not find this
  package. Mitigated by:
  - The package's `XTVERSION_NAME_KITTY` constant is searchable.
  - The `Kitty_Graphics_Supported` field is discoverable from
    `Graphics_Capabilities`.
  - The user-guide section title and tutorial pages explicitly mention
    "Kitty graphics protocol".
* **Generic name implies more scope than v1 delivers.** "Graphics" might
  suggest a richer feature set (e.g., image encoding, decoding, clipping,
  scaling). v1 is purely *detection*. Mitigated by the package summary
  comment: "graphics *protocol* detection".

## Pros and Cons of the Options

### Option A: `Termicap.Graphics` (chosen)

* Good, because generic and brand-neutral.
* Good, because matches `Termicap.Mouse` / `Termicap.Keyboard` /
  `Termicap.Color` pattern (single-word capability names).
* Good, because forward-compatible with future graphics protocols.
* Good, because the result type `Graphics_Capabilities` flows naturally.
* Bad, because slightly less searchable for protocol-specific queries
  (mitigated by field/constant names and documentation).
* Bad, because "graphics" is a broad term; might over-promise scope.

### Option B: `Termicap.Sixel`

* Good, because matches the historically older protocol.
* Good, because explicitly searchable for "Sixel".
* Bad, because **excludes Kitty graphics** in the name; either Kitty
  becomes a misleading sub-feature, or we need a sibling
  `Termicap.Kitty_Graphics` package (Option F).
* Bad, because future iTerm2 / new-protocol additions become awkward
  ("here's iTerm2 detection; it's in `Termicap.Sixel`").
* Bad, because the result type would have to be `Sixel_Capabilities`,
  which then awkwardly contains `Kitty_Graphics_Supported`.

### Option C: `Termicap.Graphics_Protocol`

* Good, because explicit about scope ("protocol detection").
* Good, because brand-neutral and future-extensible.
* Bad, because verbose; breaks the single-word convention used by every
  other capability package.
* Bad, because awkward in qualified names:
  `Termicap.Graphics_Protocol.Graphics_Capabilities`.
* Bad, because the suffix `_Protocol` is not used elsewhere
  (`Termicap.Mouse` is mouse *protocol* detection but is not named
  `Mouse_Protocol`).

### Option D: `Termicap.Image`

* Good, because user-centric naming (applications want to render
  *images*).
* Good, because brand-neutral.
* Bad, because Image suggests image *manipulation* / *encoding*, not
  *detection*. Over-promises scope.
* Bad, because future readers of `Termicap.Image.Detect_Image` may
  expect this function to return an image, not a capability record.
* Bad, because Sixel and Kitty graphics also encode non-image bitmaps
  (vector primitives, sparse data).

### Option E: `Termicap.Bitmap`

* Good, because narrower and more accurate than Image.
* Good, because brand-neutral.
* Bad, because excludes Kitty graphics's PNG/RGBA payloads (which are
  not bitmaps in the traditional pixel-array sense).
* Bad, because uncommon term in modern terminal contexts.

### Option F: Two sibling packages

* Good, because each protocol gets a focused namespace.
* Good, because individually optimisable / removable.
* Bad, because **doubles the surface area** of the feature: two specs,
  two bodies, two test files, two cache instances, two ADRs for naming.
* Bad, because the `Graphics_Capabilities` aggregate record cannot live
  in either sibling without a circular dependency. We would need a third
  aggregator package (`Termicap.Graphics`) anyway.
* Bad, because callers who want both protocols' status need to call two
  separate `Detect_*` functions and combine the results manually.
* Bad, because cross-protocol cross-cutting (e.g., the WezTerm TERM_PROGRAM
  signal which is relevant to both Sixel and Kitty graphics) duplicates
  state across two packages.

## Links

* Tech Spec: [`docs/tech-specs/sixel-graphics.md`](../tech-specs/sixel-graphics.md) §E — Package structure
* Tech Spec: [`docs/tech-specs/sixel-graphics.md`](../tech-specs/sixel-graphics.md) "Why `Termicap.Graphics`?" subsection
* Requirements: FUNC-SXL-018 (commentary)
* Related: `Termicap.Mouse` (six encodings, one capability) — naming
  precedent
* Related: `Termicap.Keyboard` (two protocols: Kitty + modifyOtherKeys)
  — naming precedent
* Related: `Termicap.Color` (multiple modes: 16/256/Truecolor) — naming
  precedent
