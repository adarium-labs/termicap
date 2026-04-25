# SIXEL: Sixel / Kitty Graphics Detection

**Feature:** Sixel and Kitty graphics protocol detection (Tier 4 Stretch Goal)
**Requirements:** FUNC-SXL-001 through FUNC-SXL-019 (`docs/requirements/sixel-graphics.sdoc`)
**Parent Requirements:** OSC-INFRA (REQ-OSC), DA1 (REQ-DA1), XTVERSION (REQ-XTV), TTY (REQ-TTY), CYGWIN (REQ-CYG), TERM-ID (REQ-TID)
**Status:** Proposed
**Date:** 2026-04-25

---

## A. Overview

Modern TUIs and CLI applications increasingly want to render bitmap images inline:
sparklines from Plotly, plots from Matplotlib, image previews in file managers, video
frames in dashboards. Two protocols dominate: **Sixel** (DEC bitmap encoding,
1980s, recently revived by xterm/foot/WezTerm/mlterm) and the **Kitty graphics
protocol** (APC-framed PNG/RGBA, kitty 2017+, also implemented by WezTerm).
A Termicap consumer needs to know — before emitting any image bytes — whether
the controlling terminal will *render* the bytes or *spew them as visible
garbage onto the user's screen*. Sixel emitted into a non-Sixel terminal is
particularly destructive: the raw `?`/`@`/`A`-`~` payload appears as a long
string of question marks and at-signs across the user's session.

This feature adds a new package `Termicap.Graphics` (SPARK On spec, SPARK Off
body with locally-annotated pure parsers) and its platform-specific I/O child
`Termicap.Graphics.IO`. The public entry point `Detect_Graphics` returns a
`Graphics_Capabilities` record. It implements **passive env-var harvest →
DA1 reuse / probe → XTVERSION fallback → optional Kitty APC probe**, layered
on top of three existing pre-shipped infrastructure features:

- **DA1** — `Termicap.DA1` already provides `DA1_Capabilities`, the `Sixel_Graphics`
  enum literal of `DA1_Capability`, and `Has_Capability`. Sixel detection is a
  single Boolean test against an existing field.
- **XTVERSION** — `Termicap.XTVERSION` already provides `XTVERSION_Result` with
  `Terminal_Name`. Name-substring matching against "kitty" / "WezTerm" needs
  only a case-insensitive Unbounded_String compare.
- **OSC-INFRA** — `Termicap.OSC.Probe_Session` and `Sentinel_Query` already
  provide the raw-mode lifecycle and DA1-bounded read loop reused by the
  optional Kitty APC probe.

The feature therefore introduces no new C wrappers, no new system calls, no
new platform dispatch. The only genuinely new code is (a) a small
case-insensitive name-substring helper, (b) a SPARK Silver APC response parser
for the three-way `OK / EINVAL / Not_Present` result, and (c) the orchestration
glue that combines the existing DA1 / XTVERSION outputs and the new APC probe
into a single `Graphics_Capabilities` value. Caching, no-exception guarantees,
and termios safety follow the established patterns from MOUSE and KKB exactly.

Integration into `Terminal_Capabilities` (FUNC-SXL-019) is intentionally
deferred (mirroring ADR-0021 and ADR-0026); the standalone `Detect_Graphics`
function is the primary API.

---

## B. Requirements Traceability

| UID | Priority | Summary | Design element / location |
|-----|----------|---------|----------------------------|
| FUNC-SXL-001 | Must | `Graphics_Capabilities` record (Sixel + Kitty + provenance + Probed) | §F.2; spec of `Termicap.Graphics` |
| FUNC-SXL-002 | Should | `Sixel_Color_Registers : Natural` defaulted to 0 (XTSMGRAPHICS deferred) | §F.2 |
| FUNC-SXL-003 | Could | `Kitty_Graphics_Version : Natural` defaulted to 0 | §F.2 |
| FUNC-SXL-004 | Must | Named String constants for known terminals (TERM_*, TERM_PROGRAM_*, ENV_*, XTVERSION_NAME_*) | §F.3 |
| FUNC-SXL-005 | Must | Sixel detection via `Termicap.DA1.Has_Capability (DA1_Caps, Sixel_Graphics)`; reuse cached DA1 if available | §G.2; ADR-0027 |
| FUNC-SXL-006 | Must | DA1 probe session via OSC-INFRA when no cached DA1 result exists | §G.2 |
| FUNC-SXL-007 | Must | XTVERSION name-substring fallback (`kitty`, `WezTerm`, case-insensitive) | §G.3 |
| FUNC-SXL-008 | Must | Env-var heuristics for Sixel (TERM_PROGRAM=WezTerm, TERM in known set, xterm prefix) | §G.4 |
| FUNC-SXL-009 | Must | Env-var heuristics for Kitty (KITTY_WINDOW_ID, TERM=xterm-kitty, TERM_PROGRAM=WezTerm) | §G.5 |
| FUNC-SXL-010 | Should | Optional Kitty APC active probe (`ESC _ G i=1,a=q ESC \` + DA1 sentinel) | §G.6; ADR-0029 |
| FUNC-SXL-011 | Should | Pure SPARK `Parse_Kitty_APC_Response` returning `APC_Parse_Result` (`Not_Present`/`OK`/`Error`) | §F.4; spec of `Termicap.Graphics` |
| FUNC-SXL-012 | Must | Four pre-condition guards (TTY / foreground / /dev/tty / Win32) | §H |
| FUNC-SXL-013 | Must | No-TTY passive fallback: skip probes, run env-var heuristics only | §H.2 |
| FUNC-SXL-014 | Must | Termios restore on every exit path (inherited from `Probe_Session` RAII) | §M |
| FUNC-SXL-015 | Must | 1000 ms timeout per session; DA1 and APC are **independent sessions** | §K; ADR-0028 |
| FUNC-SXL-016 | Must | No-exception guarantee for `Detect_Graphics` | §L |
| FUNC-SXL-017 | Must | One-probe-per-process cache; `Detect_Graphics_Uncached` bypass (Should) | §N |
| FUNC-SXL-018 | Must | Package structure: `Termicap.Graphics` (SPARK On spec) + `Termicap.Graphics.IO` (Off); platform bodies | §E, §O |
| FUNC-SXL-019 | Could | **Deferred** — Terminal_Capabilities integration is out of scope for this feature | §P |

---

## C. Framework Survey

### notcurses (C) — startup-bundled queries; KITTYQUERY APC probe

`reference-frameworks/notcurses/src/lib/termdesc.c` lines 375-386 define the
canonical Kitty graphics query string used by every modern TUI library that
detects Kitty graphics:

```c
// query for kitty graphics. if they are supported, we'll get a response to
// this using the kitty response syntax. otherwise, we'll get nothing. we
// send this with the other identification queries, since APCs tend not to
// be consumed by certain terminal emulators (looking at you, Linux console)
// which can be identified directly, sans queries.
// we do not send this query on Windows because it is bled through ConHost,
// and echoed onto the standard output.
#ifndef __MINGW32__
#define KITTYQUERY "\x1b_Gi=1,a=q;\x1b\\"
#else
#define KITTYQUERY
#endif
```

The query is bundled into `DIRECTIVES` (lines 446-458) alongside `KKBDQUERY`
(kitty keyboard), `SUMQUERY` (synchronized update mode), `PIXELMOUSEQUERY`
(mouse 1016), `CREGSXTSM`/`GEOMXTSM` (XTSMGRAPHICS), and trailed by
`PRIDEVATTR` (DA1) as the boundary marker. **Notcurses fires every detection
query in one batched session and lets DA1 terminate the read.** This is
maximally efficient on the wire (one round-trip for everything) but ties
parser complexity to the union of all query response shapes.

For Sixel detection, notcurses uses two independent paths in
`reference-frameworks/notcurses/src/lib/termdesc.c`:

1. **DA1 Ps=4** — parsed from the DA1 response that terminates `DIRECTIVES`.
   The `tinfo.bitmap_supported` flag is set when DA1 reports Sixel.
2. **TERM heuristic** — `setup_sixel_bitmaps()` is called when the terminal
   identification (XTVERSION, env vars) names a known sixel-capable terminal
   even if DA1 was not received.

`reference-frameworks/notcurses/src/info/main.c` line 404-407 reports the
result:

```c
if(ti->sixel_maxy){
  ncplane_printf(n, "%smax sixel size: %dx%d colorregs: %u",
                indent, ti->sixel_maxy, ti->sixel_maxx, ti->color_registers);
}
```

XTSMGRAPHICS (`CSI ? 1 ; 1 ; 0 S` for max geometry, `CSI ? 2 ; 1 ; 0 S` for
color registers) populates `sixel_maxy`/`sixel_maxx`/`color_registers`.

**Lessons for Termicap.** The `\x1b_Gi=1,a=q;\x1b\\` byte sequence is the
canonical APC query — adopt verbatim. The rationale comment ("APCs tend not
to be consumed by certain terminal emulators") justifies our DA1-sentinel
boundary even for the APC probe: a terminal that ignores the APC will only
emit a DA1 response, which our parser correctly interprets as `Not_Present`.
The DA1 + XTVERSION + env-var triad for Sixel is the same triad we adopt.
We diverge from notcurses by **not** batching everything into one mega-session:
our `Termicap.OSC.Sentinel_Query` is per-feature; DA1 and Kitty-APC are
separate sessions with independent 1000 ms budgets (FUNC-SXL-015, ADR-0028).

### WezTerm (Rust) — emulator-side; both Sixel and Kitty graphics

WezTerm is on the *terminal* side of the wire (it answers DA1 with Ps=4 for
Sixel and accepts Kitty APC commands), but its source is instructive for
understanding what the detection target is supposed to be.

`reference-frameworks/wezterm/term/src/terminalstate/sixel.rs` implements the
Sixel decoder (line 10: `pub(crate) fn sixel(&mut self, sixel: Box<Sixel>)`).
`reference-frameworks/wezterm/term/src/terminalstate/kitty.rs` line 176 gates
Kitty graphics on the user's config:

```rust
if !self.config.enable_kitty_graphics() {
    // ignore the request
    return Ok(());
}
```

`reference-frameworks/wezterm/term/src/lib.rs` line 8 advertises both:

> sixel and iTerm2 image support, OSC 8 Hyperlinks and a wide range of...

WezTerm advertises Sixel via DA1 (Ps=4) and reports its name via XTVERSION
("WezTerm version"). Both are reliably detected by Termicap's DA1 path
(FUNC-SXL-005) and XTVERSION path (FUNC-SXL-007).

`reference-frameworks/wezterm/wezterm-escape-parser/src/apc.rs` implements
the full Kitty graphics protocol parser (line 1214 `fn kitty_payload`,
line 1242 example `Ga=f,x=119,y=384,s=17,v=32,i=7257421,X=1,r=1,q=2;AAAA=`).
The `i=` parameter (image ID) and `a=q` (action=query) are exactly what our
APC probe sends.

**Lessons for Termicap.** WezTerm validates the `\x1b_Gi=1,a=q\x1b\\` query
shape: WezTerm parses it and responds with its own APC. The parser shape
`Ga=f,x=...,i=...;` is the response payload format; our parser only needs
to find the `OK` or `EINVAL` substring within an APC envelope, not parse the
full Kitty grammar.

### kitty terminal (C/Python) — the originator

The kitty terminal is the originator of the Kitty graphics protocol; its
documentation at <https://sw.kovidgoyal.net/kitty/graphics-protocol/> is the
normative specification. Key facts established from the protocol doc and from
notcurses' `KITTYQUERY` definition:

- `kitty` always sets `KITTY_WINDOW_ID` for every window it manages, even
  when the user has overridden `TERM` (e.g., inside `tmux` reporting
  `TERM=screen-256color`, `KITTY_WINDOW_ID` survives).
- `kitty` sets `TERM=xterm-kitty` by default.
- `kitty` advertises its name via XTVERSION as `"kitty"` (lowercase, with the
  version following).
- `kitty` does **not** advertise Sixel via DA1 in current versions, but **does**
  decode Sixel graphics (the kitty author maintains parity with the broader
  ecosystem). In Termicap, kitty is detected as both Sixel-capable (via the
  XTVERSION name match) and Kitty-graphics-capable (via the env-var path).

**Lessons for Termicap.** `KITTY_WINDOW_ID` is the highest-confidence Kitty
indicator — even higher than `TERM=xterm-kitty`, because it survives multiplexer
TERM mangling. We make it the first step of FUNC-SXL-009.

### foot (C) — Wayland-native sixel terminal

`foot` advertises Sixel via DA1 Ps=4. Its `TERM` value is `foot` (or
`foot-extra` in extra-capabilities builds). It does **not** implement the
Kitty graphics protocol. foot does not set a custom `TERM_PROGRAM`. Our
detection: DA1 path catches Sixel; XTVERSION path is irrelevant; env-var
path catches `TERM=foot` / `foot-extra` (FUNC-SXL-008).

### supports-color (Rust) / termenv (Go) — no graphics detection

Both `reference-frameworks/supports-color` and `reference-frameworks/termenv`
focus on color-level detection. Neither implements Sixel or Kitty graphics
detection; their roles are orthogonal. They confirm that graphics detection
is a Tier 4 concern, not a Tier 1 baseline.

### Cross-language consensus & Termicap's choices

| Aspect | notcurses (C) | wezterm (emulator) | kitty (originator) | foot | Termicap (this feature) |
|--------|---------------|---------------------|---------------------|------|--------------------------|
| Sixel via DA1 | DA1 Ps=4 | advertises Ps=4 | does not advertise | advertises Ps=4 | **DA1 Ps=4 via `Has_Capability(DA1_Caps, Sixel_Graphics)`** |
| Sixel via TERM | xterm/foot/yaft heuristics | n/a | n/a | n/a | **TERM in known set + xterm prefix** |
| Sixel via XTVERSION | name match | n/a | n/a | n/a | **`kitty`/`WezTerm` substring (case-insensitive)** |
| Kitty graphics via env | not used | n/a | sets KITTY_WINDOW_ID | n/a | **KITTY_WINDOW_ID + TERM=xterm-kitty + TERM_PROGRAM=WezTerm** |
| Kitty graphics via APC | `\x1b_Gi=1,a=q;\x1b\\` | answers it | answers it | does not answer | **`\x1b_Gi=1,a=q\x1b\\` + DA1 sentinel** |
| Probe batching | one mega-session | n/a | n/a | n/a | **DA1 and APC are independent sessions (FUNC-SXL-015)** |
| Color register count | XTSMGRAPHICS | n/a | n/a | n/a | **Field present, default 0; XTSMGRAPHICS deferred** |

**What Termicap adopts:**

| Pattern | Borrowed from | Adaptation |
|---------|---------------|------------|
| Kitty APC query bytes `\x1b_Gi=1,a=q\x1b\\` | notcurses `KITTYQUERY` (termdesc.c:383) | Adopted verbatim; `\x1b\\` is `ESC \` (ST) |
| KITTY_WINDOW_ID as primary kitty indicator | kitty originator + notcurses term identification | Constant `ENV_KITTY_WINDOW_ID` |
| DA1 Ps=4 as authoritative Sixel signal | xterm spec + notcurses + foot | Reuse existing `Termicap.DA1` |
| TERM-prefix `xterm` for Sixel | notcurses heuristics | Documented as imprecise; DA1 path is the definitive answer |
| XTVERSION name substring match | notcurses term identification | Case-insensitive, exact pattern from FUNC-TID-010 |
| Per-feature DA1-sentinel boundary | Termicap OSC-INFRA | DA1 query is self-sentinelling (FUNC-SXL-006); APC probe appends DA1 sentinel (FUNC-SXL-010) |
| Three-way APC parse result (Not_Present/OK/Error) | xterm DECRPM tri-state precedent | Differentiates "no answer" from "answer = EINVAL" |

**Primary-source citations:**

- xterm `ctlseqs.ms` — *"DA1 Reply: CSI ? Pp; ... c. Pp = 4 ⇒ Sixel graphics"*.
  Authoritative for FUNC-SXL-005.
- Kitty graphics protocol §"Querying support and available transmission
  mediums" — *"To query for support, send the escape code `<ESC>_Gi=1,a=q;<ESC>\\`.
  If you receive a response with a status of OK, the protocol is supported.
  If you receive a response with a status of EINVAL or no response, the
  protocol is not supported"*. Authoritative for FUNC-SXL-010 / FUNC-SXL-011.
- notcurses `KITTYQUERY` macro (`reference-frameworks/notcurses/src/lib/termdesc.c:383`)
  — first canonical implementation of the query in a multi-language detection
  library. Validates the byte sequence Termicap adopts.

### Conclusion of survey

Termicap adopts **notcurses' triad** (DA1 / XTVERSION / env-var) for Sixel
and **kitty/notcurses' env-var-first + APC-probe-fallback** for Kitty graphics.
We diverge from notcurses by **not** batching every detection query into a
single session: DA1 and APC run as separate sessions per FUNC-SXL-015, mirroring
the per-feature isolation of MOUSE and KKB. The result type is
`Graphics_Capabilities` with orthogonal Booleans plus provenance flags
(`Sixel_Via_DA1`, `Kitty_Via_Active_Probe`, `Probed`), matching the
`Mouse_Capabilities` shape (FUNC-MSE-002, ADR-0025) and the `Keyboard_Capability`
shape (FUNC-KKB-003).

---

## D. Existing Infrastructure Used

This feature is the densest reuse of pre-existing Termicap infrastructure of
any Tier 4 stretch goal, exceeding even MOUSE: SIXEL is essentially a thin
orchestration layer over DA1, XTVERSION, OSC-INFRA, and Environment.

### `Termicap.DA1` — `src/termicap-da1.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `DA1_Capability` enum, literal `Sixel_Graphics` | The exact flag tested for Sixel support (Ps=4) | `Termicap.DA1.Has_Capability (DA1_Caps, Sixel_Graphics)` in `Run_Cascade` |
| `DA1_Capabilities` record | Aggregated DA1 result with `Supported`/`Level`/`Flags` | Local result of DA1 probe; passed to `Has_Capability` |
| `Has_Capability` function | Short-circuit `Caps.Supported and then Caps.Flags (Cap)` | Single call after DA1 probe |
| `DA1_QUERY` byte constant | The DA1 query bytes if a fresh DA1 probe is needed | Indirectly via `Termicap.DA1.IO.Detect_DA1` (or `Query_DA1`) |
| `Interpret_DA1` function | Transform DA1_Params into DA1_Capabilities | Indirectly via `Detect_DA1` |

### `Termicap.DA1.IO` — `src/termicap-da1-io.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Detect_DA1 (Timeout_Ms)` function | Convenience entry point: probe + parse + interpret in one call | Default DA1 probe path; called when no cached DA1 result available (ADR-0027 negative) |

We use `Termicap.DA1.IO.Detect_DA1` — not the lower-level `Query_DA1` — because
it already handles the OSC-INFRA session lifecycle (FUNC-DA1-008), the
multiplexer passthrough decision (FUNC-DA1-012), and the DA1 response parse.
Re-implementing this would duplicate ~70 lines of body code.

### `Termicap.XTVERSION` — `src/termicap-xtversion.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `XTVERSION_Result` discriminated record | XTVERSION outcome with `Terminal_Name`/`Terminal_Version` | Returned by `Detect_XTVERSION`; consumed by name-match helper |
| `XTVERSION_Status` enum | Three-way outcome (Success/Timeout/Parse_Error) | Discriminator check before reading `Terminal_Name` |
| `Ada.Strings.Unbounded.Unbounded_String` (re-exported) | Variable-length terminal name string | Compared case-insensitively against XTVERSION_NAME_KITTY/WEZTERM |

### `Termicap.XTVERSION.IO` — `src/termicap-xtversion-io.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Detect_XTVERSION (Timeout_Ms)` | Convenience entry: probe + parse | Used only when no cached XTVERSION result is available; passive heuristic skips probe entirely if cache is empty (FUNC-SXL-013) |

**Caching note.** This feature does **not** unconditionally call
`Detect_XTVERSION`. Per FUNC-SXL-013, the XTVERSION heuristic is skipped when
no cached XTVERSION result is available **in non-TTY mode**; in full-TTY mode
the cascade attempts a fresh XTVERSION probe only if the DA1 probe failed and
no other Sixel signal was found. This keeps the worst case bounded to
DA1 (1000 ms) + APC (1000 ms) + maybe XTVERSION (1000 ms) = 3 s, but in the
common case (DA1 succeeds with Ps=4) only DA1 is queried.

### `Termicap.OSC` — `src/termicap-osc.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Probe_Session` (controlled type) | RAII open/save/raw/restore/close lifecycle | Local declaration in APC probe orchestration |
| `Sentinel_Query` | DA1-sentinel-bounded read for the APC probe | Called once per APC probe with the APC query bytes; DA1 sentinel is appended automatically by `Sentinel_Query` |
| `Response_Buffer` (subtype) | 4096-byte response accumulator | Local buffer for APC probe |
| `Session_Status` enum | Open outcome | Discriminator for guard 3 fall-through |
| `Byte`, `Byte_Array` | Wire-level types | Converted to `Termicap.Graphics.Byte_Array` at the I/O boundary |

### `Termicap.TTY` — `src/termicap-tty.ads`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Is_TTY` | Stdout TTY guard (Guard 1) | First test before any active probe |
| `Stdout` (constant of `Stream_Kind`) | Stream selector | Argument to `Is_TTY` per FUNC-SXL-012 |

Note: FUNC-SXL-012 specifies `Termicap.TTY.Is_TTY (Stdout)` (not `Stdin`),
because graphics rendering writes to stdout — testing stdout's TTY-ness is
the relevant predicate for "should we probe and render". MOUSE uses
`Is_TTY (Stdin)` because mouse events are read from stdin.

### `Termicap.Environment` / `Termicap.Environment.Capture`

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Capture_Current` | Snapshot of process env | Called once at the top of `Run_Cascade` |
| `Value` | Read TERM, TERM_PROGRAM, KITTY_WINDOW_ID | Three reads per detection call |
| `Equal_Case_Insensitive` | Case-insensitive comparison helper | TERM/TERM_PROGRAM matching per FUNC-SXL-008/009 |
| `Has` (or equivalent presence predicate) | Test `KITTY_WINDOW_ID` presence | First step of FUNC-SXL-009 |

### `Termicap.Win32_VT` (Windows path only)

| Symbol | Used for | `Termicap.Graphics` callsite |
|--------|----------|-------------------------------|
| `Termicap.Win32_VT.Is_Valid_Handle` | Guard against `INVALID_HANDLE_VALUE` | Inside the Win32 gate (Windows body only) |
| `Win32.Wincon.GetConsoleMode` | TTY/console predicate | Win32 platform gate (FUNC-SXL-012 Guard 4) |

### What we do **not** reuse

- `Termicap.DECRPM` — Sixel and Kitty graphics are not DECRPM-discoverable.
  Sixel is announced via DA1; Kitty graphics has its own APC protocol.
- `Termicap.Mouse` / `Termicap.Keyboard` — sibling Tier 4 features; no
  dependency in either direction.
- `Termicap.Capabilities` — explicitly out of scope (FUNC-SXL-019 deferred).

---

## E. Package Structure

### Package hierarchy

```
Termicap.Graphics                  (src/termicap-graphics.ads: SPARK_Mode => On)
  |   Types:      Graphics_Capabilities, APC_Parse_Result
  |   Constants:  TERM_XTERM_KITTY, TERM_FOOT, TERM_FOOT_EXTRA, TERM_XTERM,
  |               TERM_MLTERM, TERM_YAFT,
  |               TERM_PROGRAM_WEZTERM, TERM_PROGRAM_ITERM2,
  |               ENV_KITTY_WINDOW_ID,
  |               XTVERSION_NAME_KITTY, XTVERSION_NAME_WEZTERM,
  |               GRAPHICS_PROBE_TIMEOUT_MS, NO_GRAPHICS_CAPABILITIES,
  |               KITTY_APC_QUERY  (constant byte_array for the APC probe)
  |   Parsers:    Parse_Kitty_APC_Response  (SPARK_Mode => On)
  |
  |-- Termicap.Graphics.IO         (src/termicap-graphics-io.ads: SPARK_Mode => Off)
  |     Public:   Detect_Graphics            : function return Graphics_Capabilities
  |               Detect_Graphics_Uncached   : function return Graphics_Capabilities
  |                                            (cache-bypass, FUNC-SXL-017 Should clause)
  |     Private:  Cache : protected object (FUNC-SXL-017)
  |               Run_Cascade : internal worker
  |               Helpers:  Has_Sixel_From_XTVERSION_Name,
  |                         Has_Sixel_From_Env,
  |                         Has_Kitty_Graphics_From_Env,
  |                         Run_APC_Probe
  |
  |     POSIX body:  src/posix/termicap-graphics-io.adb
  |         Cascade starts at TTY guard; no Win32 dependencies.
  |
  |     Windows body: src/windows/termicap-graphics-io.adb
  |         Cascade starts at Win32 gate (FUNC-SXL-012 Guard 4 evaluated first
  |         per requirement final paragraph); falls through to TTY/foreground
  |         guards for Cygwin/MSYS PTY.
```

### Why `Termicap.Graphics` (and not `Termicap.Sixel` / `Termicap.Graphics_Protocol`)?

**Decision: `Termicap.Graphics`.** Considered alternatives and rejected:

- `Termicap.Sixel` — too narrow. The package handles both Sixel and Kitty
  graphics; naming after one of the two would force a sibling package
  `Termicap.Kitty_Graphics` and create artificial coupling between two
  packages whose capabilities are reported in one record.
- `Termicap.Graphics_Protocol` — verbose and singular; "graphics protocol"
  suggests one protocol when there are two. The plural `Graphics_Protocols`
  would be ungrammatical in the parent path.
- `Termicap.Image` — Sixel and Kitty graphics encode images, but the
  capabilities reported here are about *protocol support*, not image
  manipulation. `Image` would over-promise (callers might expect image-loading
  helpers).
- `Termicap.Bitmap` — too narrow in the opposite direction; misses the
  semantic that Kitty graphics also handles PNG/RGBA payloads.

`Termicap.Graphics` is short, technically accurate, and aligns with FUNC-SXL-018
("The package name `Termicap.Graphics` is chosen over `Termicap.Sixel` to
accommodate both Sixel and Kitty graphics protocols without implying a
hierarchy between them"). Recorded as part of ADR-0027 (which also covers the
DA1-reuse vs. always-probe decision, since both are spec/structure decisions).

### Why two packages and not three?

Same reasoning as MOUSE (§E of mouse-protocol.md) and KKB (§D of
kitty-keyboard.md):

- **`Termicap.Graphics`** (SPARK On): pure types, named String constants,
  one pure parser (`Parse_Kitty_APC_Response`).
- **`Termicap.Graphics.IO`** (SPARK Off): `Detect_Graphics` and
  `Detect_Graphics_Uncached`; protected-object cache; per-platform body files.

There is exactly one parser. A separate `Termicap.Graphics.Parsing` package
would be 30 lines of namespace overhead for ~25 lines of parser body. We
follow the established symmetry with MOUSE (§E) and KKB (§D).

### File layout

| File | Purpose | SPARK_Mode | Approx LOC |
|------|---------|------------|------------|
| `src/termicap-graphics.ads` | Spec: types, constants, parser signature (SPARK On) | On | 220 |
| `src/termicap-graphics.adb` | Body: `Parse_Kitty_APC_Response` (locally SPARK On) | Off (package); On (local) | 100 |
| `src/termicap-graphics-io.ads` | Spec: `Detect_Graphics`, `Detect_Graphics_Uncached` | Off | 100 |
| `src/posix/termicap-graphics-io.adb` | POSIX body: cascade with TTY/foreground/probe | Off | 280 |
| `src/windows/termicap-graphics-io.adb` | Windows body: Win32 gate + Cygwin fall-through | Off | 200 |

Total new code: ~900 LOC. Test files and example are listed in §Q.

### Dependency graph

```
Termicap.Graphics.IO (POSIX body)
  |-- Termicap.Graphics              (types, parser, constants)
  |-- Termicap.OSC                   (Probe_Session, Sentinel_Query, Byte_Array,
  |                                   Response_Buffer, Session_Status)
  |-- Termicap.DA1                   (DA1_Capability, Has_Capability, Sixel_Graphics)
  |-- Termicap.DA1.IO                (Detect_DA1)
  |-- Termicap.XTVERSION             (XTVERSION_Result, XTVERSION_Status)
  |-- Termicap.XTVERSION.IO          (Detect_XTVERSION)
  |-- Termicap.TTY                   (Is_TTY, Stdout)
  |-- Termicap.Environment           (Value, Equal_Case_Insensitive)
  |-- Termicap.Environment.Capture   (Capture_Current)
  |-- Ada.Strings.Unbounded          (Unbounded_String compare)
  |-- Ada.Characters.Handling        (To_Lower for case-insensitive name match)

Termicap.Graphics.IO (Windows body)
  |-- everything from POSIX, plus:
  |-- Termicap.Win32_VT              (Is_Valid_Handle)
  |-- Win32                          (BOOL, FALSE, DWORD)
  |-- Win32.Winbase                  (GetStdHandle, STD_OUTPUT_HANDLE)
  |-- Win32.Wincon                   (GetConsoleMode)
  |-- Win32.Winnt                    (HANDLE)

Termicap.Graphics (spec; SPARK On)
  |-- Interfaces.C                   (unsigned_char)
  |-- Ada.Strings.Unbounded          (for the parser? No — the parser uses Byte_Array only)
                                      — strictly SPARK On dependencies only
```

The Windows body uses `STD_OUTPUT_HANDLE` (not `STD_INPUT_HANDLE` as MOUSE does)
because the graphics gate question is "can stdout render images" — symmetric
with the `Is_TTY (Stdout)` test in Guard 1.

---

## F. Type Design

All types in §F.1 through §F.4 are declared in `Termicap.Graphics`
(SPARK_Mode => On). The cache type in §F.5 is in `Termicap.Graphics.IO`
(SPARK_Mode => Off).

### F.1 `Byte` and `Byte_Array` (representation-compatible boundary)

```ada
subtype Byte is Interfaces.C.unsigned_char;
type Byte_Array is array (Positive range <>) of Byte;
```

Same pattern as `Termicap.Mouse`, `Termicap.Keyboard`, `Termicap.DECRPM`,
`Termicap.DA1`, `Termicap.XTVERSION`. The body converts between
`Termicap.OSC.Byte_Array` and `Termicap.Graphics.Byte_Array` via direct array
conversion (zero copy).

### F.2 `Graphics_Capabilities` record (FUNC-SXL-001, FUNC-SXL-002, FUNC-SXL-003)

```ada
--  @relation(FUNC-SXL-001)
--  @relation(FUNC-SXL-002)
--  @relation(FUNC-SXL-003)
type Graphics_Capabilities is record

   --  Sixel support (FUNC-SXL-001)
   Sixel_Supported          : Boolean := False;
   --     True when Sixel graphics are available, established by any of:
   --     DA1 active probe (FUNC-SXL-005), XTVERSION name match
   --     (FUNC-SXL-007), or env-var heuristic (FUNC-SXL-008).

   --  Kitty graphics protocol support (FUNC-SXL-001)
   Kitty_Graphics_Supported : Boolean := False;
   --     True when the Kitty graphics protocol is available, established by
   --     env-var heuristics (FUNC-SXL-009) or the optional APC active probe
   --     (FUNC-SXL-010).

   --  Detection provenance flags (informational, FUNC-SXL-001)
   Sixel_Via_DA1            : Boolean := False;
   --     True when Sixel_Supported was set via DA1 Ps=4. False when set
   --     via XTVERSION name or env-var heuristic, or when Sixel_Supported
   --     is False.
   Kitty_Via_Active_Probe   : Boolean := False;
   --     True when Kitty_Graphics_Supported was confirmed via the APC probe.
   --     False when set via env-var heuristics, or when
   --     Kitty_Graphics_Supported is False.

   --  Probe metadata (FUNC-SXL-001)
   Probed                   : Boolean := False;
   --     True when at least one active probe (DA1 or APC) was attempted.
   --     False when guards suppressed all probes (no TTY / not foreground /
   --     /dev/tty unopenable / Win32 Console).

   --  Optional sub-fields (FUNC-SXL-002, FUNC-SXL-003)
   Sixel_Color_Registers    : Natural := 0;
   --     Number of simultaneous colors available for sixel rendering, or 0
   --     when unknown. Defaults to 0 in v1; XTSMGRAPHICS probing is deferred.
   Kitty_Graphics_Version   : Natural := 0;
   --     Kitty graphics protocol version, or 0 when not determinable.
   --     Defaults to 0 in v1; XTVERSION-version-string parsing is deferred.
end record;

--  Canonical "no result" value
NO_GRAPHICS_CAPABILITIES : constant Graphics_Capabilities :=
  (Sixel_Supported          => False,
   Kitty_Graphics_Supported => False,
   Sixel_Via_DA1            => False,
   Kitty_Via_Active_Probe   => False,
   Probed                   => False,
   Sixel_Color_Registers    => 0,
   Kitty_Graphics_Version   => 0);
```

**Default-initialisation invariant**: a `Graphics_Capabilities` declared
without an explicit aggregate equals `NO_GRAPHICS_CAPABILITIES`.

**Implicit invariants** (enforced by construction in `Run_Cascade` body
helpers, not by `Type_Invariant`, per the rationale in MOUSE §F.3):

- *I1.* `Sixel_Via_DA1 = True` implies `Sixel_Supported = True` and
  `Probed = True`.
- *I2.* `Kitty_Via_Active_Probe = True` implies
  `Kitty_Graphics_Supported = True` and `Probed = True`.
- *I3.* `Probed = False` implies `Sixel_Via_DA1 = False` and
  `Kitty_Via_Active_Probe = False` (provenance flags are only set on
  successful active probes).
- *I4.* `Sixel_Color_Registers > 0` implies `Sixel_Supported = True`.
  (XTSMGRAPHICS is only meaningful when Sixel is supported.)

### F.3 Named String constants (FUNC-SXL-004)

```ada
--  TERM values (FUNC-SXL-004)
TERM_XTERM_KITTY      : constant String := "xterm-kitty";
TERM_FOOT             : constant String := "foot";
TERM_FOOT_EXTRA       : constant String := "foot-extra";
TERM_XTERM            : constant String := "xterm";
TERM_MLTERM           : constant String := "mlterm";
TERM_YAFT             : constant String := "yaft";

--  TERM_PROGRAM values
TERM_PROGRAM_WEZTERM  : constant String := "WezTerm";
TERM_PROGRAM_ITERM2   : constant String := "iTerm.app";

--  Environment variable names
ENV_KITTY_WINDOW_ID   : constant String := "KITTY_WINDOW_ID";

--  XTVERSION name-substring tokens (case-insensitive match)
XTVERSION_NAME_KITTY   : constant String := "kitty";
XTVERSION_NAME_WEZTERM : constant String := "WezTerm";

--  Probe timeout (FUNC-SXL-015)
GRAPHICS_PROBE_TIMEOUT_MS : constant Natural := 1_000;

--  Kitty APC query bytes (FUNC-SXL-010)
--  ESC _ G i=1,a=q ESC \  (12 bytes)
KITTY_APC_QUERY : constant Byte_Array :=
  [16#1B#,                  --  ESC
   16#5F#,                  --  _   (APC introducer)
   Character'Pos ('G'),
   Character'Pos ('i'),
   Character'Pos ('='),
   Character'Pos ('1'),
   Character'Pos (','),
   Character'Pos ('a'),
   Character'Pos ('='),
   Character'Pos ('q'),
   16#1B#,                  --  ESC
   16#5C#];                 --  \   (ST terminator)
```

All naming follows ALL_CAPS_WITH_UNDERSCORES per the project coding standard.

### F.4 `APC_Parse_Result` enumeration and parser (FUNC-SXL-011)

```ada
--  @relation(FUNC-SXL-011)
type APC_Parse_Result is (Not_Present, OK, Error);

--  @relation(FUNC-SXL-011)
function Parse_Kitty_APC_Response
  (Buffer : Byte_Array; Length : Natural)
   return APC_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length,
  Post       => True;
```

**Semantics:**

- The function scans `Buffer (Buffer'First .. Buffer'First + Length - 1)`
  for an APC envelope `ESC _ G <params> ESC \`.
- If `<params>` contains the substring `"OK"`, return `OK`.
- If `<params>` contains the substring `"EINVAL"`, return `Error`.
- If no APC envelope is found, return `Not_Present`.
- BEL (0x07) is also a legal APC terminator alongside `ESC \` (per the same
  rule as DCS); the parser handles both.
- The function never raises; out-of-range or stray bytes are skipped.

The parser is short (≤30 LOC) and is a pure SPARK Silver function with the
same posture as `Parse_Mouse_DECRPM_Response` (FUNC-MSE-007) and
`Parse_Kitty_Response` (FUNC-KKB-006).

### F.5 Cache type (FUNC-SXL-017) — body of `Termicap.Graphics.IO`

```ada
--  Internal: protected-object cache; identical shape to
--  Termicap.Mouse.IO.Cache (FUNC-MSE-016) and
--  Termicap.Keyboard.IO.Cache (FUNC-KKB-017).

type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Graphics_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_GRAPHICS_CAPABILITIES);
end Cache;
```

ADR-0012 (capability cache design) governs.

### F.6 Public spec contracts

```ada
--  In Termicap.Graphics (SPARK_Mode => On)

function Parse_Kitty_APC_Response
  (Buffer : Byte_Array; Length : Natural)
   return APC_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length;

--  In Termicap.Graphics.IO (SPARK_Mode => Off)

function Detect_Graphics return Graphics_Capabilities;
function Detect_Graphics_Uncached return Graphics_Capabilities;
```

`Detect_Graphics` and `Detect_Graphics_Uncached` carry no SPARK contracts:
both involve I/O and protected-object access. The no-exception guarantee
(FUNC-SXL-016) is encoded as a comment-level invariant enforced by an
outer `when others => return NO_GRAPHICS_CAPABILITIES` handler.

---

## G. Detection Algorithm

### G.1 Cascade overview

```
function Detect_Graphics return Graphics_Capabilities is
   if cache initialised then return cache.Value;
   Result := Run_Cascade;
   Cache.Set_Cached (Result);
   return Result;
exception
   when others => return NO_GRAPHICS_CAPABILITIES;     --  FUNC-SXL-016
end;

function Run_Cascade return Graphics_Capabilities is
   Caps : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
begin
   --  Step 0: Capture environment once for all subsequent passive checks.
   Capture_Current (Env);

   --  Step 1: Passive Kitty env-var harvest (FUNC-SXL-009).
   --  Independent of TTY status: KITTY_WINDOW_ID may be set even on a piped
   --  output (FUNC-SXL-013).
   if Has_Kitty_Graphics_From_Env (Env) then
      Caps.Kitty_Graphics_Supported := True;
   end if;

   --  Step 2: Passive Sixel env-var harvest (FUNC-SXL-008).
   --  Same TTY-independence as step 1.
   if Has_Sixel_From_Env (Env) then
      Caps.Sixel_Supported := True;
   end if;

   --  Guard 4 (Windows only): Win32 Console gate (FUNC-SXL-012).
   --  On Windows, Win32 is checked FIRST per FUNC-SXL-012 final paragraph.
   #if Platform = Windows then
      if Is_Win32_Console then
         --  Skip all active probes; Caps already has env-var results.
         return Caps;  --  Probed = False
      end if;
   #end if;

   --  Guards 1, 2, 3 (POSIX-first): TTY / foreground / /dev/tty.
   if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdout) then
      return Caps;  --  Probed = False; passive results preserved.
   end if;
   --  Guards 2 + 3 are composed inside Probe_Session.Open below.

   --  Step 3: DA1 probe for Sixel (FUNC-SXL-005, FUNC-SXL-006).
   --  Reuses cached DA1 result from Termicap.DA1.IO if available
   --  (ADR-0027). Otherwise initiates a fresh DA1 session via Detect_DA1.
   declare
      DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
                   Termicap.DA1.IO.Detect_DA1 (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
   begin
      if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Sixel_Graphics) then
         Caps.Sixel_Supported := True;
         Caps.Sixel_Via_DA1   := True;
         Caps.Probed          := True;
      elsif DA1_Caps.Supported then
         --  DA1 returned a valid response but no Ps=4: terminal explicitly
         --  reports no Sixel. Probed = True; Sixel_Supported stays as set
         --  by env-var harvest (which may still be True for xterm-prefix
         --  matches that DA1 has now contradicted — but per FUNC-SXL-008
         --  documentation, the env-var path is "best-effort" and DA1 is
         --  authoritative; do not override env-var True with DA1 False).
         Caps.Probed := True;
      else
         --  DA1 timed out. Caps.Probed stays False; passive paths win.
         null;
      end if;
   end;

   --  Step 4: XTVERSION name-substring fallback (FUNC-SXL-007).
   --  Skip if Sixel_Via_DA1 is already True (DA1 authoritative).
   if not Caps.Sixel_Via_DA1 then
      declare
         XTV : constant Termicap.XTVERSION.XTVERSION_Result :=
                 Termicap.XTVERSION.IO.Detect_XTVERSION
                   (Timeout_Ms => GRAPHICS_PROBE_TIMEOUT_MS);
      begin
         if XTV.Status = Termicap.XTVERSION.Success
            and then Has_Sixel_From_XTVERSION_Name (XTV.Terminal_Name)
         then
            Caps.Sixel_Supported := True;
            --  Sixel_Via_DA1 stays False (provenance is XTVERSION).
            Caps.Probed := True;
         end if;
      end;
   end if;

   --  Step 5: Optional Kitty APC active probe (FUNC-SXL-010).
   --  Skip if env-var harvest already established Kitty support.
   --  Probe is Should-priority; an implementation that omits it still
   --  satisfies all MUST requirements.
   if not Caps.Kitty_Graphics_Supported then
      declare
         APC_Result : APC_Parse_Result;
      begin
         APC_Result := Run_APC_Probe;
         if APC_Result = OK then
            Caps.Kitty_Graphics_Supported := True;
            Caps.Kitty_Via_Active_Probe   := True;
            Caps.Probed                   := True;
         end if;
      end;
   end if;

   return Caps;
end Run_Cascade;
```

The Windows body's `Run_Cascade` evaluates Guard 4 (Win32 gate) **first** per
FUNC-SXL-012's final paragraph; Guards 1-3 run only if `GetConsoleMode`
returns False (i.e., we are inside a Cygwin/MSYS PTY or a redirected pipe).

### G.2 Sixel via DA1 (FUNC-SXL-005, FUNC-SXL-006)

The DA1 probe is delegated to `Termicap.DA1.IO.Detect_DA1`, which is a
pre-existing, fully-validated function. It:

1. Captures environment, detects multiplexer, derives passthrough mode.
2. Wraps `DA1_QUERY` (`ESC [ c`) in tmux/screen passthrough envelope if needed.
3. Opens a `Probe_Session` (foreground guard + /dev/tty open + raw mode + drain).
4. Runs `Timeout_Query` (timeout-only read loop, ADR-0017) until DA1 response
   pattern is detected or timeout fires.
5. Returns `DA1_Capabilities` with `Supported` / `Level` / `Flags`.

`Termicap.DA1.IO.Detect_DA1` already implements **its own** caching: by reusing
its result we get free DA1 caching across all features that need it. ADR-0027
documents this explicitly.

The single line that matters for Sixel detection:

```ada
if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Sixel_Graphics) then
```

`Has_Capability` is an expression function: `Caps.Supported and then Caps.Flags (Cap)`.
The `Sixel_Graphics` enum literal is the `DA1_Capability` value mapped from
DA1 Ps=4 by `Interpret_DA1` (FUNC-DA1-004):

```
2 => Printer, 3 => ReGIS_Graphics, 4 => Sixel_Graphics, ...
```

The exact flag tested is therefore `Termicap.DA1.Sixel_Graphics` — already
defined in `src/termicap-da1.ads` line 79.

### G.3 Sixel via XTVERSION name (FUNC-SXL-007)

Helper function in the `.IO` body:

```ada
function Has_Sixel_From_XTVERSION_Name
  (Name : Ada.Strings.Unbounded.Unbounded_String) return Boolean
is
   use Ada.Strings.Unbounded;
   use Ada.Characters.Handling;
   Lower : constant String := To_Lower (To_String (Name));
begin
   --  Substring match (case-insensitive) for the two known names.
   --  Note: XTVERSION_NAME_WEZTERM is "WezTerm" → "wezterm" after To_Lower.
   return
     Ada.Strings.Fixed.Index (Lower, To_Lower (XTVERSION_NAME_KITTY))   > 0
     or else
     Ada.Strings.Fixed.Index (Lower, To_Lower (XTVERSION_NAME_WEZTERM)) > 0;
end Has_Sixel_From_XTVERSION_Name;
```

`Ada.Strings.Fixed.Index` returns the first index of the substring or 0
when not found. `Ada.Characters.Handling.To_Lower` is total and pure.

### G.4 Sixel via env vars (FUNC-SXL-008)

```ada
function Has_Sixel_From_Env
  (Env : Termicap.Environment.Environment) return Boolean
is
   T  : constant String := Termicap.Environment.Value (Env, "TERM");
   TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
begin
   --  Step 1: TERM_PROGRAM=WezTerm
   if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
      return True;
   end if;

   --  Step 2: TERM exact matches (case-insensitive)
   if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY)  or else
      Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT)         or else
      Termicap.Environment.Equal_Case_Insensitive (T, TERM_FOOT_EXTRA)   or else
      Termicap.Environment.Equal_Case_Insensitive (T, TERM_MLTERM)       or else
      Termicap.Environment.Equal_Case_Insensitive (T, TERM_YAFT)
   then
      return True;
   end if;

   --  Step 3: TERM prefix "xterm" (best-effort; DA1 is the definitive answer)
   if T'Length >= TERM_XTERM'Length
      and then Ada.Characters.Handling.To_Lower
                 (T (T'First .. T'First + TERM_XTERM'Length - 1)) = TERM_XTERM
   then
      return True;
   end if;

   return False;
end Has_Sixel_From_Env;
```

The xterm-prefix branch is intentionally imprecise (FUNC-SXL-008 last
paragraph). Cases like `TERM=xterm-mono` (no Sixel support compiled in)
would falsely return True; DA1 will correct this when active probing succeeds.

### G.5 Kitty graphics via env vars (FUNC-SXL-009)

```ada
function Has_Kitty_Graphics_From_Env
  (Env : Termicap.Environment.Environment) return Boolean
is
   KW : constant String := Termicap.Environment.Value (Env, ENV_KITTY_WINDOW_ID);
   T  : constant String := Termicap.Environment.Value (Env, "TERM");
   TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
begin
   --  Step 1: KITTY_WINDOW_ID present and non-empty
   if KW'Length > 0 then
      return True;
   end if;

   --  Step 2: TERM = xterm-kitty (exact)
   if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
      return True;
   end if;

   --  Step 3: TERM_PROGRAM = WezTerm (case-insensitive)
   if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
      return True;
   end if;

   return False;
end Has_Kitty_Graphics_From_Env;
```

Note: `Termicap.Environment.Value` returns the empty string (`""`) when the
variable is unset; `KW'Length > 0` correctly tests presence-and-non-empty as
a single condition.

### G.6 Kitty APC active probe (FUNC-SXL-010)

```ada
function Run_APC_Probe return APC_Parse_Result is
   use Termicap.OSC;
   Session     : Termicap.OSC.Probe_Session;
   Status      : Termicap.OSC.Session_Status;
   Resp_Buffer : Termicap.OSC.Response_Buffer;
   Resp_Length : Natural := 0;
   Timed_Out   : Boolean := False;
begin
   Termicap.OSC.Open (Session, Status);
   if Status /= Termicap.OSC.Session_OK then
      return Not_Present;
   end if;

   --  Sentinel_Query writes Query, then a DA1 sentinel, then reads until DA1.
   --  The terminal that supports Kitty graphics will emit:
   --    ESC _ G ... ; OK ESC \    (kitty / WezTerm)
   --    ESC _ G ... ; EINVAL ESC \  (terminal recognises APC but rejects)
   --  Or only a DA1 response (terminal does not understand APC).
   Termicap.OSC.Sentinel_Query
     (Session     => Session,
      Query       => Termicap.OSC.Byte_Array (KITTY_APC_QUERY),
      Response    => Resp_Buffer,
      Resp_Length => Resp_Length,
      Timeout_Ms  => GRAPHICS_PROBE_TIMEOUT_MS,
      Timed_Out   => Timed_Out,
      Retry       => False);

   --  Probe_Session goes out of scope on return; RAII Finalize unconditionally
   --  restores termios and closes /dev/tty (FUNC-SXL-014).

   if Resp_Length = 0 then
      return Not_Present;
   end if;

   declare
      Slice : constant Termicap.Graphics.Byte_Array :=
        Termicap.Graphics.Byte_Array
          (Resp_Buffer (Resp_Buffer'First .. Resp_Buffer'First + Resp_Length - 1));
   begin
      return Parse_Kitty_APC_Response (Slice, Resp_Length);
   end;
end Run_APC_Probe;
```

The exact byte sequence sent to the terminal:

```
ESC _ G i = 1 , a = q ESC \   (12 bytes; KITTY_APC_QUERY)
ESC [ c                       (3 bytes; DA1 sentinel, written by Sentinel_Query)
                              ─────
                              15 bytes total
```

Expected response patterns (exact bytes the parser handles):

```
Pattern 1 (kitty / WezTerm with graphics enabled):
   ESC _ G i = 1 ; OK ESC \    (APC response)
   ESC [ ? ... c                (DA1 sentinel response)
   → Parse_Kitty_APC_Response returns OK

Pattern 2 (terminal recognises APC but rejects):
   ESC _ G ... ; EINVAL ESC \
   ESC [ ? ... c
   → returns Error

Pattern 3 (terminal does not understand APC; only DA1 fires):
   ESC [ ? ... c
   → returns Not_Present
```

### G.7 Parsing the APC response (FUNC-SXL-011)

```ada
function Parse_Kitty_APC_Response
  (Buffer : Byte_Array; Length : Natural) return APC_Parse_Result
is
   pragma SPARK_Mode (On);
   I   : Positive := Buffer'First;
   Last : Natural := Buffer'First + Length - 1;
   --  APC envelope: ESC _ G ... ESC \  (or ESC _ G ... BEL)
begin
   --  Search for ESC _ (APC introducer). Allow leading bytes (DA1 may have
   --  arrived first and been mixed with APC in the buffer).
   while I <= Last - 2 loop
      if Buffer (I) = 16#1B# and then Buffer (I + 1) = 16#5F#
         and then Buffer (I + 2) = Character'Pos ('G')
      then
         --  Found APC G envelope. Find the terminator.
         declare
            J : Positive := I + 3;
         begin
            while J <= Last loop
               if Buffer (J) = 16#1B# and then J + 1 <= Last
                  and then Buffer (J + 1) = 16#5C#
               then
                  --  ESC \ terminator at J..J+1. Search OK / EINVAL in [I+3 .. J-1].
                  return Scan_OK_EINVAL (Buffer, I + 3, J - 1);
               elsif Buffer (J) = 16#07# then
                  --  BEL terminator at J. Search OK / EINVAL in [I+3 .. J-1].
                  return Scan_OK_EINVAL (Buffer, I + 3, J - 1);
               end if;
               J := J + 1;
            end loop;
            --  No terminator found in remaining buffer.
            exit;
         end;
      end if;
      I := I + 1;
   end loop;

   return Not_Present;
end Parse_Kitty_APC_Response;

--  Local helper: scan a payload range for "OK" or "EINVAL".
--  Order matters: "OK" check first (shortest match wins in ambiguous payloads,
--  though kitty payloads do not contain both substrings simultaneously).
function Scan_OK_EINVAL
  (Buffer : Byte_Array; First, Last : Natural) return APC_Parse_Result
is
begin
   --  Linear scan for "OK" (2 bytes).
   if Last >= First + 1 then
      for K in First .. Last - 1 loop
         if Buffer (K) = Character'Pos ('O')
            and then Buffer (K + 1) = Character'Pos ('K')
         then
            return OK;
         end if;
      end loop;
   end if;

   --  Linear scan for "EINVAL" (6 bytes).
   if Last >= First + 5 then
      for K in First .. Last - 5 loop
         if Buffer (K)     = Character'Pos ('E')
            and then Buffer (K + 1) = Character'Pos ('I')
            and then Buffer (K + 2) = Character'Pos ('N')
            and then Buffer (K + 3) = Character'Pos ('V')
            and then Buffer (K + 4) = Character'Pos ('A')
            and then Buffer (K + 5) = Character'Pos ('L')
         then
            return Error;
         end if;
      end loop;
   end if;

   --  APC envelope present but neither marker — treat as Error per FUNC-SXL-011
   --  ("treats both Not_Present and Error as not supported"). Choosing Error
   --  over Not_Present here records that an APC response *was* received.
   return Error;
end Scan_OK_EINVAL;
```

The parser is `O (Length)` worst-case (linear scan over the buffer for the
`ESC _ G` introducer; once found, linear scans for OK and EINVAL). All
bounds are checked; SPARK Silver provability is preserved. Both `OK` and
`Error` map to "not supported" for outer-cascade purposes (per FUNC-SXL-011),
so the distinction is preserved only for diagnostic value (test assertions,
debug logging).

### G.8 Detection priority cascade summary

For Sixel:

```
1. Active DA1 probe (TTY-only)        → Sixel_Via_DA1=True (authoritative)
2. XTVERSION name match (TTY-only)    → Sixel_Via_DA1=False (heuristic)
3. Env-var heuristics (always)        → Sixel_Via_DA1=False (heuristic)
```

For Kitty graphics:

```
1. Env-var heuristics (always)             → Kitty_Via_Active_Probe=False (passive)
2. Optional APC active probe (TTY-only)    → Kitty_Via_Active_Probe=True (active)
```

Note the inversion: Sixel is **active-probe-first** because DA1 is the
authoritative signal; Kitty graphics is **passive-first** because env-vars
(KITTY_WINDOW_ID specifically) are the authoritative signal for the kitty
terminal.

---

## H. Platform Gating and TTY Guards (FUNC-SXL-012)

### H.1 Guard sequence

| Guard | Test | Action on failure | POSIX order | Windows order |
|-------|------|-------------------|-------------|---------------|
| 1 | `Termicap.TTY.Is_TTY (Stdout)` | Skip active probes; passive only; `Probed := False` | 1 | 2 |
| 2 | `Is_Foreground_Process` (inside `Probe_Session.Open`) | Skip active probes; passive only; `Probed := False` | 2 | 3 |
| 3 | `Open_TTY` succeeds (inside `Probe_Session.Open`) | Skip active probes; passive only; `Probed := False` | 3 | 4 |
| 4 | (Windows only) `GetConsoleMode (STD_OUTPUT_HANDLE)` returns False (i.e., we are *not* a Win32 Console) | If True (genuine Win32 Console): skip active probes; passive only | n/a | **1** |

On POSIX, Guards 1-3 run as listed; Guard 4 is absent (compile-time, via
ADR-0018 platform-dispatch). On Windows, Guard 4 is evaluated **first** per
FUNC-SXL-012's final paragraph: "On Windows, Guard 4 is evaluated first." If
Guard 4 reports a genuine Win32 Console, no further probing happens (the
console cannot interpret VT escape sequences for Sixel/Kitty graphics);
passive heuristics still apply. If Guard 4 falls through (Cygwin/MSYS PTY
or pipe), Guards 1-3 are evaluated as on POSIX.

### H.2 No-TTY passive fallback (FUNC-SXL-013)

When Guard 1 (or any subsequent guard) fails, the cascade returns with:

- `Probed = False`
- `Sixel_Via_DA1 = False`
- `Kitty_Via_Active_Probe = False`
- `Sixel_Supported` and `Kitty_Graphics_Supported` set per env-var heuristics
  (which run **before** any guard check, so passive results are always
  preserved on guard fall-through).

Rationale: a Kitty terminal piping output to a file still has
`KITTY_WINDOW_ID` set — the caller can still infer Kitty graphics support and
choose to render images into the pipe (the rendering may or may not display,
but that decision belongs to the caller).

XTVERSION fallback (FUNC-SXL-007) is **skipped** in no-TTY mode unless a
cached XTVERSION result is available from a prior call in the same process.
v1 does not expose a cross-feature XTVERSION cache: the conservative
implementation skips FUNC-SXL-007 entirely when Guard 1 fails. This is
explicit in FUNC-SXL-013 ("Apply the XTVERSION passive heuristic if a cached
XTVERSION result is available from a prior call... otherwise skip
FUNC-SXL-007").

### H.3 Win32 Cygwin / MSYS2 fall-through

On Windows, when `GetConsoleMode (STD_OUTPUT_HANDLE)` returns False, stdout
is one of:

- A Cygwin/MSYS2 PTY (real PTY semantics; mintty supports VT escapes).
- A pipe or file (no terminal at all).

The Win32 gate falls through to POSIX-like Guards 1-3. Cygwin/MSYS2 PTYs
pass `Is_TTY (Stdout)` via the Cygwin branch (cygwin-pty.md), reach the
`Probe_Session.Open` call, and proceed to DA1 probing. Pipes and files fail
Guard 1 and exit with `Probed = False`.

This mirrors the MOUSE Windows body's Cygwin fall-through (mouse-protocol.md
§I.2) exactly.

---

## I. Multiplexer Behaviour

The DA1 probe is delegated to `Termicap.DA1.IO.Detect_DA1`, which already
handles the multiplexer-passthrough decision per FUNC-DA1-012:

- `tmux` → wrap DA1_QUERY in `DCS tmux; ... ST` envelope.
- `screen` → wrap in `DCS ; ... ST` envelope.
- Other multiplexers / no multiplexer → no wrapping.

The XTVERSION probe is similarly mux-aware (it is a separate feature with
its own multiplexer handling in `Termicap.XTVERSION.IO`).

The Kitty APC probe (Step 5) is **not** wrapped in multiplexer passthrough.
Rationale:

- `tmux` does not natively understand Kitty graphics passthrough except via
  its own DCS-encapsulated `passthrough` extension, which is not standardised
  across versions.
- `screen` does not implement Kitty graphics at all.
- Inside a multiplexer, KITTY_WINDOW_ID is typically already set (the kitty
  outer terminal sets it, and the variable is inherited into the multiplexer
  child). The env-var path (FUNC-SXL-009 step 1) catches this case without
  any active probing.
- An unsuccessful APC probe in a multiplexer is harmless: the APC sequence
  is silently swallowed (or echoed), the DA1 sentinel terminates the read,
  and `Parse_Kitty_APC_Response` returns `Not_Present`.

This matches the MOUSE multiplexer posture (FUNC-MSE-012, mouse-protocol.md
§J): probe regardless, accept partial results, document the caveat.

---

## J. Two-Session Decision: DA1 and APC Run Independently (FUNC-SXL-015)

FUNC-SXL-015 is explicit: "When the DA1 probe and APC probe are both performed
in the same detection call, they shall be performed as separate sessions
with independent timeouts, not as a single batched session."

This is the right call. **ADR-0028 documents the rationale.** Summary:

1. The DA1 probe uses `Termicap.OSC.Timeout_Query` (no DA1 sentinel — the
   DA1 *response* is the data, not a boundary). Adding a second query in the
   same session would require parsing two overlapping CSI responses.
2. The APC probe uses `Termicap.OSC.Sentinel_Query` (DA1 *is* the sentinel).
   Mixing it with a DA1 probe whose response is also CSI-shaped creates an
   ambiguity: is `ESC [ ? ... c` the APC's terminating DA1 sentinel or the
   DA1 probe's data response?
3. Both `Detect_DA1` and `Detect_XTVERSION` are pre-existing convenience
   functions that already manage their own session lifecycle. Using them
   means SIXEL has zero new I/O code — only orchestration.

The cost of two separate sessions is two `tcgetattr` + `tcsetattr` cycles
instead of one, and two DA1 round-trips on the wire. On a 200 ms-RTT SSH
link, two sessions take ~600 ms (300 ms each), versus a hypothetical batched
one-session ~300 ms. For a one-time-per-process detection, this is acceptable.

---

## K. Timeout Behaviour (FUNC-SXL-015)

### K.1 Per-session timeouts

| Session | Timeout | Pre-existing function | Rationale |
|---------|---------|------------------------|-----------|
| DA1 probe | `GRAPHICS_PROBE_TIMEOUT_MS` (1000 ms) | `Termicap.DA1.IO.Detect_DA1` | Matches FUNC-OSC-004 default; conservative for SSH |
| XTVERSION probe | `GRAPHICS_PROBE_TIMEOUT_MS` (1000 ms) | `Termicap.XTVERSION.IO.Detect_XTVERSION` | Same |
| APC probe | `GRAPHICS_PROBE_TIMEOUT_MS` (1000 ms) | `Termicap.OSC.Sentinel_Query` | Same |

Worst-case latency of `Detect_Graphics`: 1000 ms (DA1) + 1000 ms (XTVERSION)
+ 1000 ms (APC) = **3 seconds**. This worst case occurs only when:

- The terminal is a TTY (Guard 1 passes).
- DA1 probe times out completely (1000 ms).
- XTVERSION probe times out completely (1000 ms).
- Kitty env-vars are not set, so APC probe runs and times out (1000 ms).

In the common case (DA1 succeeds with Ps=4; or DA1 fails-fast on a non-Sixel
terminal in <100 ms), the latency is dominated by the DA1 round-trip and
the APC probe (if needed). KITTY_WINDOW_ID-set terminals skip the APC probe
entirely and complete in <DA1 latency.

### K.2 Per-session timeout handling

- **DA1 timeout**: `Detect_DA1` returns `DA1_Capabilities` with
  `Supported = False`. `Has_Capability` returns False. `Sixel_Via_DA1` stays
  False. Sixel may still be set by passive heuristics (FUNC-SXL-008).
- **XTVERSION timeout**: `Detect_XTVERSION` returns `XTVERSION_Result` with
  `Status = Timeout`. The name-match helper is not called. Sixel may still be
  set by env-var heuristics (FUNC-SXL-008).
- **APC timeout**: `Sentinel_Query` returns `Timed_Out = True`. If
  `Resp_Length = 0`, `Parse_Kitty_APC_Response` returns `Not_Present`.
  Kitty support stays as established by passive heuristics (FUNC-SXL-009).

### K.3 Implementation may shorten timeout (FUNC-SXL-015 third paragraph)

"Implementations may use a shorter timeout (minimum 100 milliseconds) on
platforms where round-trip latency to the terminal is known to be negligible
(local PTY)."

v1 ships with the conservative 1000 ms across all three sessions. A future
optimisation pass may detect "this is a local PTY" via heuristics (no SSH
ancestry, `getppid()` is sshd, etc.) and lower the budget to 100 ms.

---

## L. Error Handling (FUNC-SXL-016)

Per FUNC-SXL-016, every failure mode is silent: no exception escapes
`Detect_Graphics`. The catalogue:

| Failure mode | Catch location | `Graphics_Capabilities` returned |
|--------------|----------------|------------------------------------|
| `/dev/tty` unopenable in DA1 path | `Detect_DA1` returns Supported=False | DA1 contributes nothing; passive paths preserved |
| `tcgetattr`/`tcsetattr` fail in DA1 path | `Detect_DA1` returns Supported=False | Same |
| DA1 session times out | `Detect_DA1` returns Supported=False | Same |
| DA1 buffer cannot be parsed | `Detect_DA1` returns Supported=False (Count=0 in Parse_DA1_Response) | Same |
| XTVERSION session times out | `Detect_XTVERSION` returns Status=Timeout | Skip name-match; passive paths preserved |
| XTVERSION parse fails | `Detect_XTVERSION` returns Status=Parse_Error | Skip name-match |
| APC session fails to open | `Run_APC_Probe` returns Not_Present | Kitty stays as set by passive |
| APC `Write_Query` fails | `Sentinel_Query` sets Timed_Out=True, Resp_Length=0 | `Parse_Kitty_APC_Response` returns Not_Present |
| APC times out | Same | Same |
| APC response is garbled (no APC envelope, no `OK`/`EINVAL`) | `Parse_Kitty_APC_Response` returns Not_Present | Kitty stays passive |
| APC response present but neither OK nor EINVAL | Parser returns Error | Kitty stays passive (Error and Not_Present both map to "not supported") |
| Environment read raises | Wrapped in outer `when others` of `Run_Cascade` | Returns NO_GRAPHICS_CAPABILITIES |
| `GetConsoleMode` raises (Windows) | Outer `when others` | Same |
| `Restore_Termios` fails after probe | `Probe_Session.Close` swallows | No impact on result |
| Any unexpected exception | Outer `when others` in `Detect_Graphics` and `Detect_Graphics_Uncached` | Returns NO_GRAPHICS_CAPABILITIES |

### L.2 Outer exception handler

```ada
function Detect_Graphics return Graphics_Capabilities is
   ...
begin
   ...
   return Result;
exception
   when others =>
      return NO_GRAPHICS_CAPABILITIES;
end Detect_Graphics;

function Detect_Graphics_Uncached return Graphics_Capabilities is
begin
   return Run_Cascade;
exception
   when others =>
      return NO_GRAPHICS_CAPABILITIES;
end Detect_Graphics_Uncached;
```

This is the universal Termicap pattern (cf. FUNC-MSE-014, FUNC-KKB-014,
FUNC-DA1-009).

---

## M. Termios Safety (FUNC-SXL-014)

Owned by `Termicap.OSC.Probe_Session`'s RAII semantics. The DA1 probe
(via `Detect_DA1`), XTVERSION probe (via `Detect_XTVERSION`), and APC probe
(via local `Run_APC_Probe`) each declare a local `Probe_Session`; on every
return path the `Limited_Controlled.Finalize` operation runs and restores
termios + closes /dev/tty. This is identical to the guarantee MOUSE
(FUNC-MSE-015) and KKB (FUNC-KKB-015) inherit.

The SIXEL feature does **not** call `tcgetattr`, `tcsetattr`,
`Save_Termios`, `Restore_Termios`, `Set_Raw_Mode`, `Open_Terminal`, or
`Close_Terminal` directly. All termios manipulation is mediated through
either:

- `Termicap.DA1.IO.Detect_DA1` (which uses `Termicap.OSC.Probe_Session`).
- `Termicap.XTVERSION.IO.Detect_XTVERSION` (which uses `Probe_Session`).
- The local `Run_APC_Probe` (which declares a `Probe_Session` directly).

ADR-0015 (Probe_Session as Limited_Controlled) is the foundational decision;
this feature inherits it.

---

## N. Caching (FUNC-SXL-017)

### N.1 Cache shape

A single-slot protected object identical to MOUSE's and KKB's:

```ada
type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Graphics_Capabilities := NO_GRAPHICS_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Graphics_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_GRAPHICS_CAPABILITIES);
end Cache;
```

`Detect_Graphics` reads the cache first; on initialised, returns the cached
`Value`. On uninitialised, runs `Run_Cascade`, calls `Cache.Set_Cached
(Result)`, and returns. Race between two concurrent first callers: both run
the cascade, both write to the cache, last-writer wins. Both results are
semantically equivalent (the terminal does not change mid-cascade).

### N.2 Cache-bypass variant — `Detect_Graphics_Uncached`

The Should clause of FUNC-SXL-017 ("Detect_Graphics_Uncached function that
bypasses the cache") is satisfied by:

```ada
function Detect_Graphics_Uncached return Graphics_Capabilities;
```

Runs the full cascade every time, **does not** read or write the cache.
Intended for test harnesses and edge cases (e.g., terminal change mid-process).

### N.3 SIGWINCH not relevant

Per FUNC-SXL-017 final paragraph: graphics protocol support is a property of
the terminal emulator, not the terminal size. Cache is **not** invalidated
on SIGWINCH.

### N.4 Lazy initialisation

The protected object's `Slot` is default-initialised by Ada elaboration to
`(Initialized => False, Value => NO_GRAPHICS_CAPABILITIES)`. **No probe runs
at elaboration time.** The first call to `Detect_Graphics` triggers the
cascade.

### N.5 DA1/XTVERSION sub-caches

Note: when `Detect_Graphics` calls `Termicap.DA1.IO.Detect_DA1`, the DA1
result is **also** cached at the `Termicap.DA1` level (per the DA1 feature's
own caching, FUNC-DA1-009 if implemented as cached). This means:

- First call to `Detect_Graphics`: runs DA1 probe, caches DA1 + Graphics.
- A subsequent independent caller invoking `Termicap.DA1.IO.Detect_DA1`
  directly hits the DA1 cache (free).
- A subsequent `Detect_Graphics` call hits the Graphics cache (the inner
  DA1 cache is not consulted).

This is the desired property: DA1 is a low-level resource shared across
features. ADR-0027 documents the decision to delegate (rather than duplicate
or wrap) DA1 probing.

---

## O. SPARK Boundary

### O.1 Per-package SPARK_Mode summary

| Package / subprogram | SPARK_Mode | Target | Rationale |
|----------------------|------------|--------|-----------|
| `Termicap.Graphics` (spec) | On (package) | Silver | Pure types, named String constants, parser signature |
| `Termicap.Graphics` (body, package level) | Off | N/A | Body is mostly empty; only `Parse_Kitty_APC_Response` has a body |
| `Parse_Kitty_APC_Response` (body) | On (locally) | Silver | Pure scan; provable bounds; no I/O |
| `Termicap.Graphics.IO` (spec) | Off | N/A | Declares `Detect_Graphics`/`Uncached`; both involve I/O |
| `Termicap.Graphics.IO` (body, POSIX) | Off | N/A | Calls `Probe_Session`, `Detect_DA1`, `Detect_XTVERSION`, `Sentinel_Query`, env access |
| `Termicap.Graphics.IO` (body, Windows) | Off | N/A | Same as POSIX, plus Win32 FFI |
| Internal helpers (`Has_Sixel_From_Env`, `Has_Sixel_From_XTVERSION_Name`, `Has_Kitty_Graphics_From_Env`, `Run_APC_Probe`, body constructors) | Off | N/A | Body-private; depend on environment access and Probe_Session |

### O.2 Mixed-SPARK pattern (per ADR-0013)

`Termicap.Graphics` follows the established pattern of MOUSE / KKB / DA1 /
XTVERSION:

- **Spec** declares pure functions and types with `SPARK_Mode => On`.
- **Body** is package-level `SPARK_Mode => Off`.
- **Each pure function body** carries a local `pragma SPARK_Mode (On);` at
  its start.

The package body is small (~100 LOC) — it contains only
`Parse_Kitty_APC_Response` plus an internal helper. The orchestration logic
lives in `Termicap.Graphics.IO`.

### O.3 SPARK boundary justification

`Termicap.Graphics.IO` calls `Probe_Session`, `Detect_DA1`, `Detect_XTVERSION`,
and environment-access procedures — all SPARK_Mode Off. Marking
`Termicap.Graphics.IO` as `SPARK_Mode => Off` is the only correct choice;
lowering the boundary deeper does not buy any provability because all the
external dependencies are already non-SPARK.

The SPARK Silver target applies to:

- `Parse_Kitty_APC_Response` (~30 LOC, fully provable)
- The `Graphics_Capabilities` and `APC_Parse_Result` type declarations
  themselves (provable by virtue of being plain records / enums).

Total provable surface: ~50 LOC, the same as MOUSE's parser+cascade.

---

## P. Integration Points

### P.1 Dependency diagram (text form)

```
                        Termicap.Graphics.IO  (POSIX or Windows body, SPARK Off)
                                  |
       +---------------+----------+---------+---------------+----------------+
       |               |                    |               |                |
       v               v                    v               v                v
Termicap.Graphics  Termicap.OSC      Termicap.DA1.IO  Termicap.XTVERSION.IO  Termicap.TTY
  (SPARK On)       (SPARK Off)         (SPARK Off)       (SPARK Off)        (SPARK Off)
       |               |                    |                |
       |               v                    |                |
       |       Termicap.OSC.Parsing         |                |
       |          (SPARK On)                |                |
       |                                    v                v
       v                            Termicap.DA1     Termicap.XTVERSION
Interfaces.C                         (SPARK On)        (SPARK On)

                        Termicap.Environment  (SPARK Off)
                        Termicap.Environment.Capture  (SPARK Off)
```

### P.2 New compile-time dependencies introduced

- POSIX body: `Ada.Strings.Unbounded`, `Ada.Strings.Fixed`, `Ada.Characters.Handling`,
  `Termicap.DA1.IO`, `Termicap.XTVERSION.IO`. None require new alire crates.
- Windows body: same as POSIX, plus `Termicap.Win32_VT`, `Win32`,
  `Win32.Winbase`, `Win32.Wincon`, `Win32.Winnt`. All already present in the
  repository's `windows/` source dir.

### P.3 Files explicitly **not** modified

- `src/termicap-da1.ads` / `.adb` — reused unchanged; `Sixel_Graphics` enum
  literal already exists.
- `src/termicap-da1-io.adb` — reused unchanged via `Detect_DA1`.
- `src/termicap-xtversion.ads` / `.adb` — reused unchanged.
- `src/termicap-xtversion-io.adb` — reused unchanged via `Detect_XTVERSION`.
- `src/termicap-osc.ads` / `.adb` — reused unchanged via `Probe_Session`,
  `Sentinel_Query`.
- `src/termicap-tty.ads` — reused unchanged via `Is_TTY`, `Stdout`.
- `src/termicap-environment*.ads` / `.adb` — reused unchanged.
- `src/termicap-capabilities.ads` — FUNC-SXL-019 deferred per §P.4.
- `alire.toml`, `termicap.gpr` — no new external crates.

### P.4 FUNC-SXL-019 deferral

Per FUNC-SXL-019 explicit text: "Integration into Terminal_Capabilities is
**OUT OF SCOPE** for this feature specification and is deferred as an
explicit non-goal."

This mirrors:

- ADR-0021 (defer Keyboard_Capability integration into Terminal_Capabilities)
- ADR-0026 (defer Mouse_Capabilities integration into Terminal_Capabilities)

A sibling ADR for Graphics deferral is **not** written for this spec: the
FUNC-SXL-019 requirement text itself is unambiguous, and ADR-0021/ADR-0026
already establish the pattern. Adding a third ADR would be ceremonial
noise. If reviewers prefer a dedicated ADR, it would be ADR-0030 with the
identical structure as ADR-0026.

---

## Q. Test Strategy

### Q.1 Unit tests — pure parser (provable subset)

All tests in this tier are deterministic, FFI-free, and runnable in any CI
environment. Test package: `tests/src/test_graphics_parser.adb`.

#### `Parse_Kitty_APC_Response` vectors (FUNC-SXL-011)

| Input bytes (`ESC` denotes 0x1B) | Length | Expected result |
|----------------------------------|--------|------------------|
| `ESC _ G i=1; OK ESC \` (canonical kitty success) | 14 | `OK` |
| `ESC _ G ; OK ESC \` (minimal OK) | 9 | `OK` |
| `ESC _ G ; OK BEL` (BEL terminator) | 7 | `OK` |
| `ESC _ G i=1; EINVAL ESC \` | 18 | `Error` |
| `ESC _ G ; EINVAL BEL` (BEL term) | 11 | `Error` |
| `ESC [ ? 1 ; 0 c` (only DA1, no APC envelope) | 8 | `Not_Present` |
| empty buffer | 0 | `Not_Present` |
| `ESC _ G payload-with-no-OK-or-EINVAL ESC \` | varies | `Error` (envelope present but no marker) |
| Truncated `ESC _ G` (no terminator) | 3 | `Not_Present` |
| Garbled prefix bytes followed by valid `ESC _ G ; OK ESC \` | varies | `OK` (parser scans past leading garbage) |
| Two APC frames concatenated, first OK then EINVAL | varies | `OK` (first match wins) |
| `ESC _ Z ... ESC \` (APC but not G) | varies | `Not_Present` (G is required) |
| `ESC _ G OK without terminator and no closing ESC` | varies | `Not_Present` |

Target: 12+ vectors, 100% line coverage of `Parse_Kitty_APC_Response`.

#### `Has_Sixel_From_XTVERSION_Name` vectors (FUNC-SXL-007)

| Input `Terminal_Name` | Expected |
|------------------------|----------|
| `"kitty 0.35.2"` | True |
| `"KITTY"` (uppercase) | True (case-insensitive) |
| `"WezTerm 20240203-110809-5046fc22"` | True |
| `"wezterm"` (lowercase) | True |
| `"xterm 388"` | False |
| `"foot 1.16.2"` | False |
| `"tmux 3.4"` | False |
| empty string | False |

Target: 8 vectors, 100% branch coverage.

#### `Has_Sixel_From_Env` and `Has_Kitty_Graphics_From_Env` vectors

These test the env-var helpers in isolation by constructing
`Termicap.Environment.Environment` snapshots.

| TERM | TERM_PROGRAM | KITTY_WINDOW_ID | Expected Sixel | Expected Kitty |
|------|---------------|------------------|----------------|----------------|
| `xterm-kitty` | (unset) | (unset) | True (TERM=xterm-kitty) | True (TERM exact match) |
| `xterm-kitty` | (unset) | `42` | True | True (KITTY_WINDOW_ID wins) |
| `xterm-256color` | `WezTerm` | (unset) | True (TERM_PROGRAM) | True (TERM_PROGRAM) |
| `foot` | (unset) | (unset) | True (TERM exact) | False |
| `mlterm` | (unset) | (unset) | True (TERM exact) | False |
| `xterm-mono` | (unset) | (unset) | True (xterm prefix; imprecise) | False |
| `dumb` | (unset) | (unset) | False | False |
| `screen-256color` | (unset) | `7` | False (no env Sixel signal) | True (KITTY_WINDOW_ID) |
| `screen-256color` | (unset) | (unset) | False | False |
| (unset) | `iTerm.app` | (unset) | False (iTerm2 is not in Sixel env list per FUNC-SXL-008) | False |

Target: 10+ vectors per helper, 100% branch coverage.

### Q.2 Integration tests — FFI path (CI-gated where possible)

| Test scenario | Mechanism | CI-safe | FUNC-SXL coverage |
|---------------|-----------|---------|-------------------|
| Non-TTY stdout → `Probed=False`; passive flags set per env | `(./bin/...) > /tmp/out.txt`; inspect | Yes | FUNC-SXL-012, FUNC-SXL-013 |
| `KITTY_WINDOW_ID=1 ./bin/...` outside kitty → `Kitty_Graphics_Supported=True` | Env injection in CI | Yes | FUNC-SXL-009 step 1 |
| `TERM=xterm-kitty TERM_PROGRAM= ./bin/...` → `Kitty_Graphics_Supported=True` | Env injection | Yes | FUNC-SXL-009 step 2 |
| `TERM_PROGRAM=WezTerm ./bin/...` → both Sixel and Kitty True via env | Env injection | Yes | FUNC-SXL-008, FUNC-SXL-009 step 3 |
| `TERM=foot ./bin/...` → `Sixel_Supported=True` (env), Kitty False | Env injection | Yes | FUNC-SXL-008 |
| `TERM=dumb ./bin/...` (non-TTY) → all False | Env injection | Yes | FUNC-SXL-013 |
| Native xterm with `--enable-sixel` → `Sixel_Via_DA1=True`, Kitty False | Manual on real xterm | No | FUNC-SXL-005 |
| Native kitty → Sixel True (XTVERSION name); Kitty True (env) | Manual on kitty | No | FUNC-SXL-007, FUNC-SXL-009 |
| Native foot → `Sixel_Via_DA1=True`, Kitty False | Manual on foot | No | FUNC-SXL-005 |
| Native WezTerm → both True; Sixel via DA1 or env-var; Kitty via APC or env | Manual on WezTerm | No | FUNC-SXL-005, FUNC-SXL-008, FUNC-SXL-009/010 |
| Windows native console (cmd.exe) → all False, `Probed=False` | Windows CI | Yes (Windows CI) | FUNC-SXL-012 Guard 4 |
| Windows + git-bash (Cygwin PTY) on a kitty-graphics-capable terminal | Manual on Windows dev | No | FUNC-SXL-012 fall-through |
| Inside tmux (3.2+) running inside kitty → Kitty True via KITTY_WINDOW_ID | Manual under tmux | No | FUNC-SXL-009 step 1 surviving multiplexer |

### Q.3 Per-requirement test type assignment

| Requirement | Unit test? | Integration test? | Ada precondition? |
|-------------|------------|-------------------|---------------------|
| FUNC-SXL-001 (record) | Default-init values match `NO_GRAPHICS_CAPABILITIES` | n/a | n/a |
| FUNC-SXL-002 (`Sixel_Color_Registers`) | Default = 0 | n/a | n/a |
| FUNC-SXL-003 (`Kitty_Graphics_Version`) | Default = 0 | n/a | n/a |
| FUNC-SXL-004 (constants) | Value equality (`TERM_XTERM_KITTY = "xterm-kitty"`, etc.) | n/a | n/a |
| FUNC-SXL-005 (DA1 path) | n/a | xterm/foot integration | n/a |
| FUNC-SXL-006 (DA1 probe session) | n/a | xterm integration | Inherited from `Detect_DA1` |
| FUNC-SXL-007 (XTVERSION name) | 8+ name-match vectors | kitty/WezTerm integration | n/a |
| FUNC-SXL-008 (Sixel env-var) | 10+ env vectors | env-injection CI tests | n/a |
| FUNC-SXL-009 (Kitty env-var) | 10+ env vectors | env-injection CI tests | n/a |
| FUNC-SXL-010 (APC probe) | n/a | kitty/WezTerm integration; non-Kitty terminal returns Not_Present | n/a |
| FUNC-SXL-011 (APC parser) | 12+ APC-response vectors | Implicit | `Pre => Length <= Buffer'Length` |
| FUNC-SXL-012 (guards) | n/a | Non-TTY / Windows console CI | n/a |
| FUNC-SXL-013 (no-TTY fallback) | n/a | Non-TTY env-injection CI | n/a |
| FUNC-SXL-014 (termios restore) | n/a | Manual: probe under stress; check `stty -a` after | Inherited from `Probe_Session` RAII |
| FUNC-SXL-015 (timeouts) | n/a | TERM=dumb (active probes time out) | n/a |
| FUNC-SXL-016 (no-exception) | Inject various invalid inputs to parser; observe no `Constraint_Error` | n/a | Implicit via `Pre =>` on parser |
| FUNC-SXL-017 (cache) | Two consecutive `Detect_Graphics` calls return identical records | Manual: cache survives multiple calls | n/a |
| FUNC-SXL-018 (package structure) | Build succeeds | n/a | `pragma SPARK_Mode (On)`/`(Off)` placement |
| FUNC-SXL-019 (deferred) | Verify `Terminal_Capabilities` does **not** contain a `Graphics` field | n/a | n/a |

### Q.4 Mock/fake inputs needed

- **Synthetic byte arrays** for `Parse_Kitty_APC_Response` unit tests
  (constructed via `[16#1B#, 16#5F#, ...]` aggregates).
- **Constructed `Termicap.Environment.Environment` snapshots** for env-var
  helper tests. The existing `Termicap.Environment` package supports
  programmatic construction of an `Environment` value with arbitrary
  key/value pairs (used by `tests/src/test_environment.adb`).
- **Mock TTY redirection** via `(./bin/...) </dev/null >/tmp/out.txt` for
  Guard 1 tests.
- **No mock terminal emulator**: the integration tests against real
  xterm/foot/kitty/WezTerm are necessarily manual.

### Q.5 Coverage target

Project-wide target: >95% line coverage (CLAUDE.md). The pure parser
(`Parse_Kitty_APC_Response`) and the env-var helpers must reach 100% line
coverage via the unit vectors. `Detect_Graphics` itself reaches ~80% via
non-TTY / env-injection paths (the probe-positive branches require a real
TTY harness and are exercised manually).

### Q.6 Example program

`examples/graphics_demo/src/graphics_demo.adb` calls `Detect_Graphics`,
prints the returned `Graphics_Capabilities` in human-readable form (one
field per line: Sixel/Kitty support, provenance, Probed), and exits.
Useful for developer verification on any terminal.

---

## R. ADRs Produced Alongside This Spec

This spec is accompanied by **three** new ADRs:

| ADR | File | Title | Significance |
|-----|------|-------|--------------|
| **ADR-0027** | `docs/adr/0027-da1-reuse-vs-fresh-probe.md` | Reuse `Termicap.DA1.IO.Detect_DA1` Rather Than Issue a Private DA1 Probe | Avoids duplicating ~70 LOC of session lifecycle |
| **ADR-0028** | `docs/adr/0028-graphics-independent-probe-sessions.md` | DA1 and APC Run as Independent Probe Sessions, Not Batched | Confirms FUNC-SXL-015's design with rationale |
| **ADR-0029** | `docs/adr/0029-graphics-package-naming.md` | Package Name `Termicap.Graphics` (Over `Sixel` / `Graphics_Protocol`) | Documents the naming choice required to pass code review |

### R.1 Why these three?

The three ADRs cover the **first-order design decisions that have meaningful
alternatives**:

1. **DA1 reuse vs. private probe** (ADR-0027). The spec text in FUNC-SXL-005
   says "if a DA1 result is already available... the cached DA1_Capabilities
   record shall be reused" — but it does not specify *how* the reuse happens.
   We could either (a) call `Termicap.DA1.IO.Detect_DA1` and rely on its
   internal caching, or (b) maintain our own DA1-result cache inside
   `Termicap.Graphics.IO`, or (c) duplicate the DA1 session lifecycle.
   This is a real design choice with consequences for coupling, code
   duplication, and testing surface. ADR-0027 records the decision.

2. **Independent vs. batched probes** (ADR-0028). FUNC-SXL-015 text says
   "they shall be performed as separate sessions"; the ADR records *why*
   this is correct (the alternative — batching — is technically possible
   but creates parser ambiguity and conflicts with `Detect_DA1`'s use of
   `Timeout_Query`). MOUSE made the opposite choice (batched session,
   ADR-0022); this asymmetry needs explicit justification.

3. **Package name** (ADR-0029). FUNC-SXL-018 commentary text mentions the
   name choice, but does not record the alternatives evaluated (`Sixel`,
   `Graphics_Protocol`, `Image`). ADR-0029 records all three rejected
   alternatives.

### R.2 Why **not** ADRs for…

- **FUNC-SXL-019 deferral.** Already covered structurally by ADR-0021 and
  ADR-0026. A third ADR would duplicate their content. The deferral is
  documented in §P.4 of this spec.
- **`KITTY_APC_QUERY` byte sequence.** Adopted verbatim from notcurses
  `KITTYQUERY`. The byte sequence is normative; there is no alternative
  to consider.
- **Pure SPARK parser pattern.** Established by ADR-0013 (mixed SPARK
  annotation split) and reused by every Tier 4 feature. No new decision.
- **Cache shape.** Established by ADR-0012. Reused unchanged.
- **Platform body dispatch via source dirs.** Established by ADR-0018.
  Reused unchanged.

---

## S. Open Questions / Risks

| Risk / Question | Likelihood | Impact | Mitigation / Resolution |
|------------------|-----------|--------|--------------------------|
| A non-Kitty terminal echoes the APC query bytes back into the user's terminal | Low (raw mode prevents echo) | Medium (user sees garbage) | Raw mode is unconditional inside `Probe_Session`; restored on every exit path |
| The 1000 ms × 3 (worst case 3 s) startup cost is too long | Medium | Low | DA1 fast-fail (<100 ms) on any non-Sixel terminal; APC skipped when KITTY_WINDOW_ID set; XTVERSION skipped when DA1 confirms; in practice <500 ms is typical |
| `Detect_DA1` side-effects (caching) interact badly with `Detect_Graphics`'s caching | Low | Low | Both caches store final structured results; no shared mutable intermediate state |
| `Has_Sixel_From_XTVERSION_Name` matches false positives (e.g., a terminal called "winkitty" in a future product) | Very low | Low | Substring match is intentionally permissive; ADR-0029 accepts the false-positive risk for substring vs. exact-match |
| The xterm-prefix env-var heuristic flags non-Sixel xterm builds (e.g., compiled without `--enable-sixel`) | Medium | Low | Documented as imprecise in FUNC-SXL-008; DA1 path corrects this in TTY mode |
| A future kitty version adds new APC commands that break our parser's substring match | Very low | Low | Parser is forward-compatible: any payload that contains "OK" returns OK; absence returns Not_Present or Error |
| WezTerm or kitty changes the `KITTY_WINDOW_ID` env var name | Very low | Medium | Constant `ENV_KITTY_WINDOW_ID` is centralised; one-line change |
| `XTVERSION_NAME_WEZTERM` case-sensitivity bug: WezTerm sometimes reports "wezterm" lowercase | Low | Low | Case-insensitive comparison in `Has_Sixel_From_XTVERSION_Name` already handles this |

### S.1 Open question: Is `STD_OUTPUT_HANDLE` the right Win32 handle?

**Considered:** use `STD_INPUT_HANDLE` (as MOUSE does) for symmetry.

**Resolution:** **Use `STD_OUTPUT_HANDLE`.** The graphics question is "can
stdout render images" — the relevant Win32 predicate is whether stdout is a
console handle. MOUSE checks stdin because mouse events arrive via
`ReadConsoleInput` from stdin. The two features test different streams.
This is consistent with `Termicap.TTY.Is_TTY (Stdout)` in Guard 1.

### S.2 Open question: Should the spec ship with XTSMGRAPHICS active probing?

**Considered:** populate `Sixel_Color_Registers` via `CSI ? 1 ; 1 ; 0 S`.

**Resolution:** **Defer to a future feature.** FUNC-SXL-002 explicitly
permits `Sixel_Color_Registers = 0` as the default v1 value. XTSMGRAPHICS
adds another active probe (a fourth session) to the cascade and another
parser. Out of scope for v1; tracked separately if/when needed.

### S.3 Open question: Should `Kitty_Graphics_Version` be parsed from the
XTVERSION version string?

**Considered:** parse the version string from `Detect_XTVERSION` for kitty
terminals to populate `Kitty_Graphics_Version`.

**Resolution:** **Defer.** FUNC-SXL-003 is Could-priority and explicitly
permits `Kitty_Graphics_Version = 0` as the default. Adding the parser is
useful for callers that need to gate features on kitty version (e.g.,
animation requires kitty >= 0.20.0 per notcurses); it is not required for
basic graphics detection.

---

## T. Files Created / Modified

### New files

| File | Purpose | Approx LOC |
|------|---------|------------|
| `src/termicap-graphics.ads` | Spec: types, constants, parser signature (SPARK_Mode => On) | 220 |
| `src/termicap-graphics.adb` | Body: `Parse_Kitty_APC_Response` (locally SPARK On) | 100 |
| `src/termicap-graphics-io.ads` | Spec: `Detect_Graphics`, `Detect_Graphics_Uncached` (SPARK_Mode => Off) | 100 |
| `src/posix/termicap-graphics-io.adb` | POSIX body: cascade with TTY/foreground/probe | 280 |
| `src/windows/termicap-graphics-io.adb` | Windows body: Win32 gate + Cygwin fall-through | 200 |
| `tests/src/test_graphics_parser.ads` | Test spec: parser/env-helper unit vectors | 30 |
| `tests/src/test_graphics_parser.adb` | Test body: 30+ vectors across parser and env helpers | 300 |
| `examples/graphics_demo/src/graphics_demo.adb` | Demo program | 80 |
| `examples/graphics_demo/alire.toml` | Alire crate manifest | 20 |
| `examples/graphics_demo/graphics_demo.gpr` | GPR | 15 |
| `docs/adr/0027-da1-reuse-vs-fresh-probe.md` | ADR | 130 |
| `docs/adr/0028-graphics-independent-probe-sessions.md` | ADR | 130 |
| `docs/adr/0029-graphics-package-naming.md` | ADR | 110 |

Total new code: ~1715 LOC (~700 spec/body, ~330 tests, ~115 example,
~370 docs/ADRs).

### Modified files

| File | Change |
|------|--------|
| `tests/src/termicap_tests.adb` | Register `test_graphics_parser` in the harness |
| `examples/termicap_examples.gpr` | Include `graphics_demo` |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Graphics` and `Termicap.Graphics.IO` subsections (handled by `/doc-update` after implementation) |
| `docs/architecture/04-runtime-view.md` | Add "Graphics protocol detection" scenario (handled by `/doc-update`) |

### Files explicitly **not** modified

- `src/termicap-da1.ads` / `.adb` / `-io.adb` — reused unchanged.
- `src/termicap-xtversion.ads` / `.adb` / `-io.adb` — reused unchanged.
- `src/termicap-osc.ads` / `.adb` — reused unchanged.
- `src/termicap-tty.ads` — reused unchanged.
- `src/termicap-environment*.ads` / `.adb` — reused unchanged.
- `src/termicap-capabilities.ads` — FUNC-SXL-019 deferred.
- `alire.toml`, `termicap.gpr` — no new external dependencies.

---

## U. Requirements Traceability (canonical table)

| Requirement | Design element | Tech-spec section |
|-------------|----------------|---------------------|
| FUNC-SXL-001 | `Graphics_Capabilities` record + `NO_GRAPHICS_CAPABILITIES` constant | §F.2 |
| FUNC-SXL-002 | `Sixel_Color_Registers : Natural := 0` field | §F.2 |
| FUNC-SXL-003 | `Kitty_Graphics_Version : Natural := 0` field | §F.2 |
| FUNC-SXL-004 | Named String constants in `Termicap.Graphics` spec | §F.3 |
| FUNC-SXL-005 | `Termicap.DA1.Has_Capability (DA1_Caps, Sixel_Graphics)` call | §G.2; ADR-0027 |
| FUNC-SXL-006 | Delegation to `Termicap.DA1.IO.Detect_DA1` | §G.2; ADR-0027 |
| FUNC-SXL-007 | `Has_Sixel_From_XTVERSION_Name` body-private helper | §G.3 |
| FUNC-SXL-008 | `Has_Sixel_From_Env` body-private helper | §G.4 |
| FUNC-SXL-009 | `Has_Kitty_Graphics_From_Env` body-private helper | §G.5 |
| FUNC-SXL-010 | `Run_APC_Probe` body-private helper | §G.6; ADR-0029 (no — that's naming; APC probe is FUNC-SXL-010 covered in §G.6) |
| FUNC-SXL-011 | `Parse_Kitty_APC_Response` pure SPARK function | §F.4, §G.7 |
| FUNC-SXL-012 | Guard sequence in `Run_Cascade` | §H |
| FUNC-SXL-013 | Passive heuristics applied before guards; cascade returns on guard fail | §H.2 |
| FUNC-SXL-014 | `Probe_Session` RAII guarantees termios restore | §M |
| FUNC-SXL-015 | Three independent 1000 ms session timeouts | §K; ADR-0028 |
| FUNC-SXL-016 | Per-call outer `when others` handler | §L |
| FUNC-SXL-017 | Protected-object cache + `Detect_Graphics_Uncached` bypass | §N |
| FUNC-SXL-018 | Package split `Termicap.Graphics` (SPARK On) + `.IO` child; platform bodies | §E, §O |
| FUNC-SXL-019 | **Deferred** per §P.4; migration path mirrors ADR-0021 / ADR-0026 | §P.4 |

---

## V. Related Documents

- **Tech Spec MOUSE** (`docs/tech-specs/mouse-protocol.md`) — Closest
  structural analogue: Tier 4, FFI, mixed SPARK boundary, sentinel-bounded
  active probe, deferred capability-record integration, protected-object
  cache. SIXEL borrows the package shape and the constructor-helper pattern.
- **Tech Spec KITTY-KB** (`docs/tech-specs/kitty-keyboard.md`) — Sister Tier 4
  active-probe feature; identical mixed-SPARK + cache layout.
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`) — Parent
  infrastructure: provides `DA1_Capability`, `Sixel_Graphics` literal,
  `Has_Capability`. ADR-0027 is the SIXEL/DA1 interaction ADR.
- **Tech Spec XTVERSION** (`docs/tech-specs/xtversion.md`) — Parent
  infrastructure: provides `XTVERSION_Result`, `Terminal_Name` field.
- **Tech Spec OSC-INFRA** (`docs/tech-specs/osc-query-infra.md`) — Parent
  infrastructure: provides `Probe_Session`, `Sentinel_Query`.
- **Tech Spec Capability Record** (`docs/tech-specs/capability-record.md`) —
  Integration target for FUNC-SXL-019 (deferred).
- **ADR-0012** (`docs/adr/0012-capability-cache-design.md`) — Protected-object
  cache template.
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`) —
  Mixed `SPARK_Mode` pattern for parser bodies.
- **ADR-0015** (`docs/adr/0015-probe-session-limited-controlled.md`) —
  `Probe_Session` `Limited_Controlled` (justifies termios-restore-for-free).
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`) — DA1 query
  uses `Timeout_Query` (relevant to ADR-0028's argument against batching).
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) —
  Platform-specific body selection via GPR source dirs.
- **ADR-0021** (`docs/adr/0021-defer-keyboard-capability-integration.md`) —
  Sister ADR for KKB integration deferral; pattern reused for SIXEL.
- **ADR-0026** (`docs/adr/0026-defer-mouse-capability-integration.md`) —
  Sister ADR for MOUSE integration deferral; pattern reused for SIXEL.
- **ADR-0027** (`docs/adr/0027-da1-reuse-vs-fresh-probe.md`) — This spec.
- **ADR-0028** (`docs/adr/0028-graphics-independent-probe-sessions.md`) —
  This spec.
- **ADR-0029** (`docs/adr/0029-graphics-package-naming.md`) — This spec.
- **Requirements** (`docs/requirements/sixel-graphics.sdoc`) — FUNC-SXL-001
  through FUNC-SXL-019.
- **Reference** (`reference-frameworks/notcurses/src/lib/termdesc.c:383`) —
  Canonical `KITTYQUERY` byte sequence (`\x1b_Gi=1,a=q;\x1b\\`); SIXEL
  adopts this verbatim.
- **Reference** (`reference-frameworks/wezterm/wezterm-escape-parser/src/apc.rs`)
  — Full Kitty graphics protocol parser (emulator side); validates that
  WezTerm parses and answers `i=1,a=q`.
- **Analysis** (`reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` §2.13)
  — Cross-language synthesis of graphics detection.
- **Analysis** (`reference-frameworks/projects-reference.md` lines 519-520,
  679-685) — notcurses, kitty, WezTerm graphics support summary.
