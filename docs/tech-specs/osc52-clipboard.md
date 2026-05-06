# OSC52: OSC 52 Clipboard Detection

**Feature:** OSC 52 clipboard capability detection (Tier 4 Stretch Goal)
**Requirements:** FUNC-C52-001 through FUNC-C52-019 (`docs/requirements/osc52.sdoc`)
**Parent Requirements:** OSC-INFRA (REQ-OSC), DA1 (REQ-DA1), TTY (REQ-TTY), CYGWIN (REQ-CYG), TERM-ID (REQ-TID)
**Status:** Proposed
**Date:** 2026-05-06

---

## A. Overview

OSC 52 (Operating System Command 52) is an XTerm escape sequence protocol that
allows terminal applications to read from and write to the host system clipboard.
The protocol uses the form `ESC ] 52 ; Pc ; Pd BEL` (or ST-terminated), where
`Pc` selects the clipboard buffer (`c` for clipboard, `p` for primary) and `Pd`
is either base64-encoded content (write) or `?` (query/read).

This feature adds a new package `Termicap.Clipboard` (SPARK On spec, SPARK Off
body with locally-annotated pure parsers) and its platform-specific I/O child
`Termicap.Clipboard.IO`. The public entry point `Detect_Clipboard` returns a
`Clipboard_Capabilities` record with a three-level `Clipboard_Support`
enumeration (`None`, `Write_Only`, `Read_Write`) and provenance flags tracking
which detection path established the result.

The detection implements a three-phase cascade: **DA1 passive (Ps=52) ->
active OSC 52 read-back probe -> environment-variable heuristics**, layered
on top of existing infrastructure:

- **DA1** -- `Termicap.DA1` already provides `DA1_Capabilities` and
  `Has_Capability`. A new `Clipboard_Access` enum literal (Ps=52) must be
  added to `DA1_Capability`.
- **OSC-INFRA** -- `Termicap.OSC.Probe_Session` and `Sentinel_Query` provide
  the raw-mode lifecycle and DA1-bounded read loop reused by the active probe.
- **OSC.Parsing** -- `Wrap_For_Passthrough` handles multiplexer DCS wrapping
  for the OSC 52 query when running inside tmux or screen.

The feature introduces no new C wrappers and no new system calls. The genuinely
new code is (a) a SPARK Silver OSC 52 response parser, (b) the DA1 extension
(one new enum literal + one Ps-value mapping), and (c) the orchestration glue
that combines DA1, active probe, and env-var heuristics into a single
`Clipboard_Capabilities` value.

Integration into `Terminal_Capabilities` (FUNC-C52-019) is intentionally
deferred, mirroring ADR-0021, ADR-0026, and the SIXEL pattern.

---

## B. Requirements Traceability

| UID | Priority | Summary | Design element / location |
|-----|----------|---------|----------------------------|
| FUNC-C52-001 | Must | `Clipboard_Support` enumeration (None/Write_Only/Read_Write) | S.F.2; spec of `Termicap.Clipboard` |
| FUNC-C52-002 | Must | `Clipboard_Capabilities` result record with provenance flags | S.F.3; spec of `Termicap.Clipboard` |
| FUNC-C52-003 | Must | `Clipboard_Access` literal in `DA1_Capability` enumeration | S.D.1; modification of `Termicap.DA1` |
| FUNC-C52-004 | Must | Named constant `DA1_PS_CLIPBOARD_ACCESS := 52` | S.D.1; `Termicap.DA1` |
| FUNC-C52-005 | Must | Named string constants for known clipboard-capable terminals | S.F.4; spec of `Termicap.Clipboard` |
| FUNC-C52-006 | Must | Clipboard support inference from DA1 Ps=52 | S.G.2 |
| FUNC-C52-007 | Should | Active OSC 52 read-back probe | S.G.3 |
| FUNC-C52-008 | Should | OSC 52 response parser (SPARK Silver) | S.F.5; spec of `Termicap.Clipboard` |
| FUNC-C52-009 | Must | Passive detection via known terminal identifiers (env-var heuristics) | S.G.4 |
| FUNC-C52-010 | Should | Combined detection cascade (DA1 -> active probe -> env-var) | S.G.1 |
| FUNC-C52-011 | Should | tmux and screen OSC 52 query passthrough | S.I |
| FUNC-C52-012 | Must | Pre-condition guards and TTY guards | S.H |
| FUNC-C52-013 | Must | No-TTY passive fallback | S.H.2 |
| FUNC-C52-014 | Must | Termios restore on all exit paths | S.M |
| FUNC-C52-015 | Must | 1000 ms probe session timeout | S.K |
| FUNC-C52-016 | Must | No-exception guarantee for `Detect_Clipboard` | S.L |
| FUNC-C52-017 | Must | One-probe-per-process caching; `Detect_Clipboard_Uncached` bypass (Should) | S.N |
| FUNC-C52-018 | Must | Package structure and SPARK boundary | S.E, S.O |
| FUNC-C52-019 | Could | **Deferred** -- Terminal_Capabilities integration is out of scope | S.P |

---

## C. Framework Survey

### tcell (Go) -- DA1 attribute 52 as clipboard indicator

tcell is the primary reference for DA1-based clipboard detection. In
`reference-frameworks/tcell/input.go` line 916, the DA1 response parser sets
`evDA.Clipboard = true` when parameter value 52 is encountered (line 1182:
`Clipboard bool // OSC-52 support (DA 52)`). The `tScreen` struct stores this
as `hasClipboard bool` (line 220 of tcell-analysis.md). Detection is lazy,
performed at `engage()` time with a 1-second timeout (line 237 of
tcell-analysis.md).

tcell does not distinguish Read_Write from Write_Only: `hasClipboard` is a
single Boolean. It does not perform an active OSC 52 query probe. Clipboard
read-back is not gated on `hasClipboard`; it is attempted unconditionally when
requested. This is a gap that Termicap's three-level model addresses.

**Lessons for Termicap.** The DA1 Ps=52 mechanism is validated by tcell as the
primary passive clipboard indicator. The single-Boolean model is too coarse;
Termicap's `None/Write_Only/Read_Write` enumeration provides the additional
granularity needed to gate clipboard read-back safely.

### termenv (Go) -- OSC 52 emission with multiplexer adaptation

`reference-frameworks/termenv/copy.go` (38 lines) implements OSC 52 clipboard
write via the `go-osc52` library. It does **not** detect clipboard support; it
unconditionally emits OSC 52 write sequences. The key insight is the screen
multiplexer adaptation (line 12): when `TERM` starts with `"screen"`, the
sequence is wrapped using `s.Screen()` from the `go-osc52` library.

**Lessons for Termicap.** termenv validates the need for multiplexer passthrough
wrapping when emitting OSC 52 inside GNU screen. The wrapping semantics are
implemented by our existing `Termicap.OSC.Parsing.Wrap_For_Passthrough` (with
the tmux DCS envelope using doubled-ESC, and the screen DCS envelope without).

### crossterm (Rust) -- write-only clipboard behind feature flag

`reference-frameworks/crossterm/src/clipboard.rs` implements OSC 52 clipboard
write (`CopyToClipboard` command) behind the `osc52` feature flag. It supports
multiple clipboard selections (`ClipboardType::Clipboard`, `Primary`, `Other`).
No detection or read-back is implemented. The analysis (line 50 of
crossterm-analysis.md) explicitly states: "Write-only (copy to clipboard). No
paste/read from clipboard via OSC 52."

**Lessons for Termicap.** crossterm's write-only scope confirms that clipboard
write is the primary use case, and clipboard read-back is an advanced feature
requiring additional detection. Termicap's `Write_Only` level covers crossterm's
use case; `Read_Write` is the advanced upgrade.

### WezTerm (Rust) -- emulator-side; full OSC 52 support

WezTerm is on the terminal side. Its DA1 response advertises Ps=52 alongside
Sixel (Ps=4) and ANSI Color (Ps=22): the wezterm-analysis.md (line 33) shows
`CSI ?65;4;6;18;22;52c`. WezTerm supports full OSC 52 read and write for
multiple selections (clipboard, primary, cut0-9) as documented in
wezterm-analysis.md (line 58).

**Lessons for Termicap.** WezTerm is a confirmed Read_Write terminal that
advertises Ps=52 in DA1. Both the DA1 path (Ps=52 -> Write_Only) and the active
probe (OSC 52 query returns clipboard content -> upgrade to Read_Write) will
succeed for WezTerm.

### blessed (JavaScript) -- iTerm2 capabilities query

blessed-analysis.md (line 49) documents an `OSC 1337;Capabilities` query
specific to iTerm2 that returns a feature bitmap including clipboard support.
This is iTerm2-specific and not standardised. Termicap uses the more
portable DA1 + active probe + env-var approach.

### Cross-language consensus and Termicap's choices

| Aspect | tcell (Go) | termenv (Go) | crossterm (Rust) | WezTerm (emulator) | Termicap (this feature) |
|--------|-----------|-------------|-----------------|---------------------|--------------------------|
| Detection mechanism | DA1 Ps=52 Boolean | None (emit-only) | None (emit-only) | Advertises Ps=52 | **DA1 Ps=52 -> active OSC 52 probe -> env-var heuristics** |
| Support model | Boolean (has/hasn't) | Assumed present | Feature-gated compile-time | Full support | **Three-level: None/Write_Only/Read_Write** |
| Read-back detection | Not performed | Not supported | Not supported | N/A (emulator) | **Active OSC 52 query with DA1 sentinel** |
| Multiplexer wrapping | Not documented | Screen adaptation via go-osc52 | Not documented | N/A | **tmux DCS + screen DCS via Wrap_For_Passthrough** |
| Provenance tracking | None | None | None | N/A | **Via_DA1, Via_Active_Probe, Via_Env_Heuristic flags** |

**What Termicap adopts:**

| Pattern | Borrowed from | Adaptation |
|---------|---------------|------------|
| DA1 Ps=52 as clipboard indicator | tcell (`hasClipboard` from DA1 attribute 52) | Extended to three-level model; DA1 -> Write_Only, not Read_Write |
| Screen multiplexer wrapping | termenv (copy.go, line 12: `s.Screen()`) | Reuse `Wrap_For_Passthrough` with `Screen_Passthrough` mode |
| OSC 52 query format `ESC ] 52 ; c ; ? BEL` | XTerm specification (ctlseqs) | Standard query; DA1 sentinel boundary pattern from OSC-INFRA |
| Active probe with DA1 sentinel | Termicap OSC-INFRA pattern (from MOUSE, KKB, SIXEL) | Same sentinel-bounded read pattern applied to OSC 52 |

**Primary-source citations:**

- XTerm `ctlseqs.ms` -- "OSC Ps ; Pt ST. Ps = 52 ; Clipboard manipulation.
  Pt = Pc ; Pd. Pc: clipboard designator (c = clipboard, p = primary). Pd: ?
  for query, base64 data for set, empty for clear."
- tcell `input.go` line 916: `evDA.Clipboard = true` when DA1 parameter is 52.
  Authoritative for FUNC-C52-003 / FUNC-C52-006.
- termenv `copy.go` line 12: screen multiplexer detection via TERM prefix.
  Validates FUNC-C52-011 screen passthrough wrapping.

### Conclusion of survey

Termicap adopts **tcell's DA1 Ps=52 mechanism** as the primary passive indicator,
extends it with an **active OSC 52 read-back probe** (which no surveyed library
implements for detection purposes), and adds **env-var heuristics** as the
last-resort fallback. The three-level `None/Write_Only/Read_Write` model
provides strictly more information than any surveyed library. The multiplexer
passthrough reuses existing infrastructure and is validated by termenv's
screen-mode adaptation.

---

## D. Existing Infrastructure Used

### D.1 `Termicap.DA1` -- `src/termicap-da1.ads` (to be modified)

| Symbol | Used for | Modification required |
|--------|----------|------------------------|
| `DA1_Capability` enum | Add `Clipboard_Access` literal (FUNC-C52-003) | **Yes**: new enum literal |
| `DA1_Capabilities` record | Aggregated DA1 result; `Capability_Flags` auto-acquires new slot | No (auto-extended by enum addition) |
| `Has_Capability` function | Test `Has_Capability (DA1_Caps, Clipboard_Access)` | No |
| `Interpret_DA1` function body | Map Ps=52 to `Clipboard_Access` flag | **Yes**: new case in body |

A named constant `DA1_PS_CLIPBOARD_ACCESS : constant := 52` must be added
to `Termicap.DA1` (FUNC-C52-004). The body of `Interpret_DA1` must add a
mapping: `52 => Clipboard_Access` in the scan loop, following the existing
pattern (2 => Printer, 3 => ReGIS_Graphics, 4 => Sixel_Graphics, ...).

### D.2 `Termicap.DA1.IO` -- `src/termicap-da1-io.ads`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Detect_DA1 (Timeout_Ms)` | Convenience entry point: probe + parse + interpret | Default DA1 probe path; reuses cached DA1 result (ADR-0027) |

We use `Termicap.DA1.IO.Detect_DA1` (not lower-level `Query_DA1`) because it
already handles session lifecycle, multiplexer passthrough, and DA1 response
parsing.

### D.3 `Termicap.OSC` -- `src/termicap-osc.ads`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Probe_Session` (controlled type) | RAII open/raw/restore/close lifecycle | Local declaration in OSC 52 active probe |
| `Sentinel_Query` | DA1-sentinel-bounded read for the OSC 52 probe | Called once per active probe |
| `Response_Buffer` (subtype) | 4096-byte response accumulator | Local buffer for OSC 52 probe |
| `Session_Status` enum | Open outcome | Discriminator for guard fall-through |
| `Byte`, `Byte_Array` | Wire-level types | Converted to `Termicap.Clipboard.Byte_Array` |

### D.4 `Termicap.OSC.Parsing` -- `src/termicap-osc-parsing.ads`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Wrap_For_Passthrough` | Multiplexer DCS wrapping for the OSC 52 query (FUNC-C52-011) | Called when tmux or screen is detected |
| `Passthrough_Mode` enum | Identifies tmux/screen/none | Derived from Terminal_Identity |

### D.5 `Termicap.TTY` -- `src/termicap-tty.ads`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Is_TTY` | Stdout TTY guard (Guard 1) | First test before any active probe |
| `Stdout` (constant of `Stream_Kind`) | Stream selector | Argument to `Is_TTY` per FUNC-C52-012 |

### D.6 `Termicap.Environment` / `Termicap.Environment.Capture`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Capture_Current` | Snapshot of process env | Called once at the top of `Run_Cascade` |
| `Value` | Read TERM, TERM_PROGRAM, WT_SESSION, TMUX, STY | Multiple reads per detection call |
| `Equal_Case_Insensitive` | Case-insensitive comparison helper | TERM_PROGRAM matching per FUNC-C52-009 |
| `Has` (or `Value` with length check) | Test env-var presence | WT_SESSION, TMUX, STY presence checks |

### D.7 `Termicap.Terminal_Id` -- `src/termicap-terminal_id.ads`

| Symbol | Used for | `Termicap.Clipboard` callsite |
|--------|----------|-------------------------------|
| `Terminal_Identity` | Multiplexer identification for passthrough | Derive `Passthrough_Mode` for OSC 52 wrapping |

### What we do **not** reuse

- `Termicap.XTVERSION` -- clipboard support is not discoverable via XTVERSION
  terminal name matching. Unlike Sixel (which can be inferred from "kitty" or
  "WezTerm" in XTVERSION), clipboard support is too inconsistently implemented
  to infer from the terminal name alone.
- `Termicap.DECRPM` -- clipboard is not a private mode queryable via DECRPM.
- `Termicap.Mouse` / `Termicap.Keyboard` / `Termicap.Graphics` -- sibling
  Tier 4 features; no dependency in either direction.
- `Termicap.Capabilities` -- explicitly deferred (FUNC-C52-019).

---

## E. Package Structure

### Package hierarchy

```
Termicap.Clipboard                  (src/termicap-clipboard.ads: SPARK_Mode => On)
  |   Types:      Clipboard_Support, Clipboard_Capabilities, OSC52_Parse_Result
  |   Constants:  TERM_PROGRAM_WEZTERM, TERM_PROGRAM_ITERM2, TERM_PROGRAM_VSCODE,
  |               ENV_WT_SESSION, ENV_TMUX, ENV_STY,
  |               TERM_XTERM_KITTY, TERM_XTERM,
  |               CLIPBOARD_PROBE_TIMEOUT_MS, NO_CLIPBOARD_CAPABILITIES,
  |               OSC52_QUERY  (constant byte_array for the active probe)
  |   Parsers:    Parse_OSC52_Response  (SPARK_Mode => On)
  |
  |-- Termicap.Clipboard.IO         (src/termicap-clipboard-io.ads: SPARK_Mode => Off)
  |     Public:   Detect_Clipboard            : function return Clipboard_Capabilities
  |               Detect_Clipboard_Uncached   : function return Clipboard_Capabilities
  |                                             (cache-bypass, FUNC-C52-017 Should clause)
  |     Private:  Cache : protected object (FUNC-C52-017)
  |               Run_Cascade : internal worker
  |               Helpers:  Infer_Clipboard_From_DA1,
  |                         Run_OSC52_Probe,
  |                         Infer_Clipboard_From_Env
  |
  |     POSIX body:  src/posix/termicap-clipboard-io.adb
  |         Cascade starts at TTY guard; no Win32 dependencies.
  |
  |     Windows body: src/windows/termicap-clipboard-io.adb
  |         Cascade starts at Win32 gate (FUNC-C52-012 Guard 4 evaluated first
  |         per requirement final paragraph); falls through to TTY/foreground
  |         guards for Cygwin/MSYS PTY.
```

### Why `Termicap.Clipboard`?

The package name `Termicap.Clipboard` accurately describes the feature scope:
clipboard capability detection via the OSC 52 protocol. Alternatives considered:

- `Termicap.OSC52` -- too protocol-specific; the clipboard feature may evolve
  to detect non-OSC-52 clipboard mechanisms in the future.
- `Termicap.Clipboard_Detection` -- verbose; other packages use the capability
  noun without a "_Detection" suffix (Graphics, Mouse, Keyboard).

`Termicap.Clipboard` is consistent with the naming convention of sibling
packages and aligns with FUNC-C52-018.

### Why two packages and not one?

Same reasoning as MOUSE, KKB, and SIXEL:

- **`Termicap.Clipboard`** (SPARK On): pure types, named String constants,
  one pure parser (`Parse_OSC52_Response`).
- **`Termicap.Clipboard.IO`** (SPARK Off): `Detect_Clipboard` and
  `Detect_Clipboard_Uncached`; protected-object cache; per-platform body files.

### File layout

| File | Purpose | SPARK_Mode | Approx LOC |
|------|---------|------------|------------|
| `src/termicap-clipboard.ads` | Spec: types, constants, parser signature (SPARK On) | On | 180 |
| `src/termicap-clipboard.adb` | Body: `Parse_OSC52_Response` (locally SPARK On) | Off (package); On (local) | 100 |
| `src/termicap-clipboard-io.ads` | Spec: `Detect_Clipboard`, `Detect_Clipboard_Uncached` | Off | 90 |
| `src/posix/termicap-clipboard-io.adb` | POSIX body: cascade with TTY/foreground/probe | Off | 250 |
| `src/windows/termicap-clipboard-io.adb` | Windows body: Win32 gate + Cygwin fall-through | Off | 180 |

Total new code: ~800 LOC. Plus ~10 LOC modification to `Termicap.DA1` (ads + adb).

### Dependency graph

```
Termicap.Clipboard.IO (POSIX body)
  |-- Termicap.Clipboard              (types, parser, constants)
  |-- Termicap.OSC                    (Probe_Session, Sentinel_Query, Byte_Array,
  |                                    Response_Buffer, Session_Status)
  |-- Termicap.OSC.Parsing            (Wrap_For_Passthrough, Passthrough_Mode)
  |-- Termicap.DA1                    (DA1_Capability, Has_Capability, Clipboard_Access)
  |-- Termicap.DA1.IO                 (Detect_DA1)
  |-- Termicap.TTY                    (Is_TTY, Stdout)
  |-- Termicap.Terminal_Id            (Terminal_Identity, for multiplexer detection)
  |-- Termicap.Environment            (Value, Equal_Case_Insensitive)
  |-- Termicap.Environment.Capture    (Capture_Current)

Termicap.Clipboard.IO (Windows body)
  |-- everything from POSIX, plus:
  |-- Termicap.Win32_VT               (Is_Valid_Handle)
  |-- Win32                           (BOOL, FALSE, DWORD)
  |-- Win32.Winbase                   (GetStdHandle, STD_OUTPUT_HANDLE)
  |-- Win32.Wincon                    (GetConsoleMode)
  |-- Win32.Winnt                     (HANDLE)

Termicap.Clipboard (spec; SPARK On)
  |-- Interfaces.C                    (unsigned_char)
```

---

## F. Type Design

All types in F.1 through F.5 are declared in `Termicap.Clipboard`
(SPARK_Mode => On). The cache type in F.6 is in `Termicap.Clipboard.IO`
(SPARK_Mode => Off).

### F.1 `Byte` and `Byte_Array` (representation-compatible boundary)

```ada
subtype Byte is Interfaces.C.unsigned_char;
type Byte_Array is array (Positive range <>) of Byte;
```

Same pattern as `Termicap.Mouse`, `Termicap.Keyboard`, `Termicap.Graphics`,
`Termicap.DA1`. The body converts between `Termicap.OSC.Byte_Array` and
`Termicap.Clipboard.Byte_Array` via direct array conversion (zero copy).

### F.2 `Clipboard_Support` enumeration (FUNC-C52-001)

```ada
--  @relation(FUNC-C52-001)
type Clipboard_Support is (None, Write_Only, Read_Write);
--  None       -- No clipboard access detected.
--  Write_Only -- Terminal accepts OSC 52 write; does not respond to read queries.
--  Read_Write -- Terminal supports both writing and reading via OSC 52.
--
--  Ordering: None < Write_Only < Read_Write (increasing capability).
--  Callers can compare: if Support >= Write_Only then emit OSC 52 writes.
```

The enumeration's position values (`None = 0`, `Write_Only = 1`,
`Read_Write = 2`) provide the documented ordering via Ada's default comparison
operators on enumeration types.

### F.3 `Clipboard_Capabilities` record (FUNC-C52-002)

```ada
--  @relation(FUNC-C52-002)
type Clipboard_Capabilities is record

   --  The detected clipboard access level (FUNC-C52-001). Default: None.
   Support            : Clipboard_Support := None;

   --  True when Support was set based on DA1 Ps=52 (FUNC-C52-006).
   Via_DA1            : Boolean := False;

   --  True when Support was upgraded to Read_Write by active OSC 52 probe.
   Via_Active_Probe   : Boolean := False;

   --  True when Support was set by env-var heuristics alone (FUNC-C52-009).
   Via_Env_Heuristic  : Boolean := False;

   --  True when at least one active probe (DA1 or OSC 52) was attempted.
   Probed             : Boolean := False;
end record;
```

**Default-initialisation invariant**: a `Clipboard_Capabilities` declared
without an explicit aggregate equals `NO_CLIPBOARD_CAPABILITIES`.

**Implicit invariants** (enforced by construction in `Run_Cascade`, not by
`Type_Invariant`):

- *I1.* `Via_DA1 = True` implies `Support >= Write_Only` and `Probed = True`.
- *I2.* `Via_Active_Probe = True` implies `Support = Read_Write` and
  `Probed = True`.
- *I3.* `Via_Env_Heuristic = True` implies `Via_DA1 = False` and
  `Via_Active_Probe = False` (env-var heuristics are the sole source).
- *I4.* `Probed = False` implies `Via_DA1 = False` and
  `Via_Active_Probe = False`.

### F.4 Named String constants (FUNC-C52-005)

```ada
--  TERM_PROGRAM values for terminals with known OSC 52 support
TERM_PROGRAM_WEZTERM   : constant String := "WezTerm";
TERM_PROGRAM_ITERM2    : constant String := "iTerm.app";
TERM_PROGRAM_VSCODE    : constant String := "vscode";

--  Environment variable names used in passive detection
ENV_WT_SESSION         : constant String := "WT_SESSION";
ENV_TMUX               : constant String := "TMUX";
ENV_STY                : constant String := "STY";

--  TERM values for terminals with known OSC 52 support
TERM_XTERM_KITTY       : constant String := "xterm-kitty";
TERM_XTERM             : constant String := "xterm";

--  Probe timeout (FUNC-C52-015)
CLIPBOARD_PROBE_TIMEOUT_MS : constant Natural := 1_000;
```

All naming follows ALL_CAPS_WITH_UNDERSCORES per the project coding standard.

Note: `TERM_PROGRAM_WEZTERM`, `TERM_XTERM_KITTY`, and `TERM_XTERM` are
string-value duplicates of the identically-named constants in
`Termicap.Graphics`. The duplication is intentional to avoid a dependency
from `Termicap.Clipboard` to `Termicap.Graphics` (the two are peer Tier 4
features with no coupling). The values are short string literals whose
duplication costs negligible ROM.

### F.5 OSC 52 query bytes and parser (FUNC-C52-007, FUNC-C52-008)

```ada
--  OSC 52 clipboard read query: ESC ] 52 ; c ; ? BEL  (7 bytes)
--  @relation(FUNC-C52-007)
OSC52_QUERY : constant Byte_Array :=
  [16#1B#,                  --  ESC      (0x1B)
   16#5D#,                  --  ]        (0x5D, OSC introducer)
   Character'Pos ('5'),     --  5        (0x35)
   Character'Pos ('2'),     --  2        (0x32)
   Character'Pos (';'),     --  ;        (0x3B)
   Character'Pos ('c'),     --  c        (0x63, clipboard selection)
   Character'Pos (';'),     --  ;        (0x3B)
   Character'Pos ('?'),     --  ?        (0x3F, query)
   16#07#];                 --  BEL      (0x07, terminator)

--  @relation(FUNC-C52-008)
type OSC52_Parse_Result is (Not_Present, Valid_Response, Malformed);

--  @relation(FUNC-C52-008)
function Parse_OSC52_Response
  (Buffer : Byte_Array; Length : Natural)
   return OSC52_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length,
  Post       => True;
```

**Semantics of `Parse_OSC52_Response`:**

- Scans `Buffer (Buffer'First .. Buffer'First + Length - 1)` for an OSC 52
  response matching the pattern:
  `ESC ] 52 ; <selection> ; <base64-or-empty> BEL`
  or
  `ESC ] 52 ; <selection> ; <base64-or-empty> ESC \`

- Return values:
  - `Valid_Response` -- A well-formed OSC 52 response was found. The selection
    character is one or more printable characters, and the payload is either
    empty or composed of base64 alphabet characters (A-Z, a-z, 0-9, +, /, =).
  - `Not_Present` -- No OSC 52 introducer (`ESC ] 52`) was found. The DA1
    sentinel arrived first, or the terminal did not respond.
  - `Malformed` -- An OSC 52 introducer was found but the response did not
    terminate correctly or contained unexpected bytes.

- Both `Not_Present` and `Malformed` map to "read-back not available" for the
  purpose of FUNC-C52-007. The distinction is preserved for test assertions
  and debugging.

- The function never raises; out-of-range or stray bytes are skipped.

**Canonical "no result" constant:**

```ada
NO_CLIPBOARD_CAPABILITIES : constant Clipboard_Capabilities :=
  (Support           => None,
   Via_DA1           => False,
   Via_Active_Probe  => False,
   Via_Env_Heuristic => False,
   Probed            => False);
```

### F.6 Cache type (FUNC-C52-017) -- body of `Termicap.Clipboard.IO`

```ada
type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Clipboard_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_CLIPBOARD_CAPABILITIES);
end Cache;
```

ADR-0012 (capability cache design) governs.

### F.7 Public spec contracts

```ada
--  In Termicap.Clipboard (SPARK_Mode => On)

function Parse_OSC52_Response
  (Buffer : Byte_Array; Length : Natural)
   return OSC52_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length;

--  In Termicap.Clipboard.IO (SPARK_Mode => Off)

function Detect_Clipboard return Clipboard_Capabilities;
function Detect_Clipboard_Uncached return Clipboard_Capabilities;
```

`Detect_Clipboard` and `Detect_Clipboard_Uncached` carry no SPARK contracts:
both involve I/O and protected-object access. The no-exception guarantee
(FUNC-C52-016) is encoded as a comment-level invariant enforced by an outer
`when others => return NO_CLIPBOARD_CAPABILITIES` handler.

---

## G. Detection Algorithm

### G.1 Cascade overview

```ada
function Detect_Clipboard return Clipboard_Capabilities is
   Cached : constant Cache_Slot := Cache.Get_Cached;
begin
   if Cached.Initialized then
      return Cached.Value;
   end if;
   declare
      Result : constant Clipboard_Capabilities := Run_Cascade;
   begin
      Cache.Set_Cached (Result);
      return Result;
   end;
exception
   when others => return NO_CLIPBOARD_CAPABILITIES;   --  FUNC-C52-016
end;

function Run_Cascade return Clipboard_Capabilities is
   Caps : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
begin
   --  Step 0: Capture environment once for all subsequent passive checks.
   Capture_Current (Env);

   --  Guard 4 (Windows only): Win32 Console gate (FUNC-C52-012).
   --  On Windows, evaluated FIRST per FUNC-C52-012 final paragraph.
   #if Platform = Windows then
      if Is_Win32_Console then
         Infer_Clipboard_From_Env (Env, Caps);
         return Caps;  --  Probed = False
      end if;
   #end if;

   --  Guard 1: TTY guard (FUNC-C52-012).
   if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdout) then
      Infer_Clipboard_From_Env (Env, Caps);
      return Caps;  --  Probed = False; passive results preserved.
   end if;
   --  Guards 2 + 3 are composed inside Probe_Session.Open below.

   --  Phase 1: DA1 passive detection (FUNC-C52-006).
   --  Reuses cached DA1 result from Termicap.DA1.IO if available (ADR-0027).
   declare
      DA1_Caps : constant Termicap.DA1.DA1_Capabilities :=
                   Termicap.DA1.IO.Detect_DA1
                     (Timeout_Ms => CLIPBOARD_PROBE_TIMEOUT_MS);
   begin
      if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Clipboard_Access) then
         Caps.Support   := Write_Only;
         Caps.Via_DA1   := True;
         Caps.Probed    := True;
      elsif DA1_Caps.Supported then
         --  DA1 returned a valid response but no Ps=52. Probed but no clipboard.
         Caps.Probed := True;
      else
         --  DA1 timed out entirely; Probed stays False.
         null;
      end if;
   end;

   --  Phase 2: Active OSC 52 read-back probe (FUNC-C52-007).
   --  Proceeds regardless of Phase 1 outcome: can upgrade Write_Only to
   --  Read_Write, or detect Read_Write when DA1 lacked Ps=52.
   if Caps.Support /= Read_Write then
      declare
         OSC52_Result : OSC52_Parse_Result;
      begin
         OSC52_Result := Run_OSC52_Probe (Env);
         if OSC52_Result = Valid_Response then
            Caps.Support          := Read_Write;
            Caps.Via_Active_Probe := True;
            Caps.Probed           := True;
         end if;
      end;
   end if;

   --  Phase 3: Environment-variable heuristics (FUNC-C52-009).
   --  Applied only when Support is still None after Phases 1 and 2.
   --  If Phase 1 yielded Write_Only via DA1, Phase 3 is skipped (DA1 is
   --  more authoritative than env vars).
   if Caps.Support = None then
      Infer_Clipboard_From_Env (Env, Caps);
   end if;

   return Caps;
end Run_Cascade;
```

The Windows body's `Run_Cascade` evaluates Guard 4 (Win32 gate) **first** per
FUNC-C52-012's final paragraph; Guards 1-3 run only if `GetConsoleMode`
returns False (Cygwin/MSYS PTY or pipe).

### G.2 DA1 passive detection (FUNC-C52-006)

The DA1 probe is delegated to `Termicap.DA1.IO.Detect_DA1`, the pre-existing
convenience function. The single test that matters:

```ada
if Termicap.DA1.Has_Capability (DA1_Caps, Termicap.DA1.Clipboard_Access) then
```

`Has_Capability` is an expression function: `Caps.Supported and then
Caps.Flags (Cap)`. The `Clipboard_Access` enum literal is the new
`DA1_Capability` value mapped from DA1 Ps=52 by `Interpret_DA1`.

When `Clipboard_Access` is present, `Support` is set to `Write_Only` (not
`Read_Write`) because DA1 Ps=52 advertises that the terminal *understands*
OSC 52, but does not distinguish read-capable from write-only terminals.
xterm advertises Ps=52 even when `allowWindowOps` is false (read disabled).

### G.3 Active OSC 52 probe (FUNC-C52-007)

```ada
function Run_OSC52_Probe
  (Env : Termicap.Environment.Environment) return OSC52_Parse_Result
is
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

   --  Determine multiplexer passthrough mode from environment.
   declare
      Passthrough : Termicap.OSC.Parsing.Passthrough_Mode := Termicap.OSC.Parsing.No_Passthrough;
      Tmux_Val : constant String := Termicap.Environment.Value (Env, ENV_TMUX);
      STY_Val  : constant String := Termicap.Environment.Value (Env, ENV_STY);
   begin
      if Tmux_Val'Length > 0 then
         Passthrough := Termicap.OSC.Parsing.Tmux_Passthrough;
      elsif STY_Val'Length > 0 then
         Passthrough := Termicap.OSC.Parsing.Screen_Passthrough;
      end if;

      --  Wrap the OSC 52 query if inside a multiplexer.
      declare
         Wrapped_Query : constant Termicap.OSC.Byte_Array :=
           Termicap.OSC.Byte_Array
             (Termicap.OSC.Parsing.Wrap_For_Passthrough
                (Termicap.OSC.Parsing.Byte_Array (OSC52_QUERY), Passthrough));
      begin
         --  Sentinel_Query writes the query, appends DA1 sentinel, then reads.
         Termicap.OSC.Sentinel_Query
           (Session     => Session,
            Query       => Wrapped_Query,
            Response    => Resp_Buffer,
            Resp_Length => Resp_Length,
            Timeout_Ms  => CLIPBOARD_PROBE_TIMEOUT_MS,
            Timed_Out   => Timed_Out,
            Retry       => False);
      end;
   end;

   --  Probe_Session goes out of scope on return; RAII Finalize restores
   --  termios and closes /dev/tty (FUNC-C52-014).

   if Resp_Length = 0 then
      return Not_Present;
   end if;

   declare
      Slice : constant Termicap.Clipboard.Byte_Array :=
        Termicap.Clipboard.Byte_Array
          (Resp_Buffer (Resp_Buffer'First .. Resp_Buffer'First + Resp_Length - 1));
   begin
      return Parse_OSC52_Response (Slice, Resp_Length);
   end;
end Run_OSC52_Probe;
```

The exact byte sequence sent to the terminal (without multiplexer wrapping):

```
ESC ] 5 2 ; c ; ? BEL   (9 bytes; OSC52_QUERY)
ESC [ c                  (3 bytes; DA1 sentinel, appended by Sentinel_Query)
                         -----
                         12 bytes total
```

With tmux passthrough wrapping (FUNC-C52-011):

```
ESC P tmux ; ESC ESC ] 5 2 ; c ; ? BEL ESC \   (tmux DCS envelope)
ESC [ c                                         (DA1 sentinel, outside DCS)
```

Note the doubled ESC inside the tmux DCS envelope, per the tmux passthrough
convention: the inner `ESC ]` becomes `ESC ESC ]` (two ESC bytes: 0x1B 0x1B
0x5D). The DA1 sentinel is placed outside the DCS passthrough so that the
multiplexer forwards it directly to the outer terminal (FUNC-C52-011).

With screen passthrough wrapping:

```
ESC P ESC ] 5 2 ; c ; ? BEL ESC \   (screen DCS envelope, no ESC doubling)
ESC [ c                               (DA1 sentinel, outside DCS)
```

Expected response patterns:

```
Pattern 1 (read-capable terminal: WezTerm, kitty, iTerm2 with clipboard access):
   ESC ] 52 ; c ; <base64-data> BEL   (or ESC \ terminated)
   ESC [ ? ... c                       (DA1 sentinel response)
   -> Parse_OSC52_Response returns Valid_Response

Pattern 2 (write-only terminal: Windows Terminal, xterm with allowWindowOps=false):
   ESC [ ? ... c                       (DA1 only; no OSC 52 response)
   -> Parse_OSC52_Response returns Not_Present

Pattern 3 (terminal does not understand OSC 52 at all):
   ESC [ ? ... c                       (DA1 only)
   -> Parse_OSC52_Response returns Not_Present
```

### G.4 Environment-variable heuristics (FUNC-C52-009)

```ada
procedure Infer_Clipboard_From_Env
  (Env  : Termicap.Environment.Environment;
   Caps : in out Clipboard_Capabilities)
is
   TP : constant String := Termicap.Environment.Value (Env, "TERM_PROGRAM");
   T  : constant String := Termicap.Environment.Value (Env, "TERM");
   WT : constant String := Termicap.Environment.Value (Env, ENV_WT_SESSION);
begin
   --  Step 1: TERM_PROGRAM = WezTerm (case-insensitive) -> Read_Write
   if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_WEZTERM) then
      Caps.Support          := Read_Write;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  Step 1 continued: TERM_PROGRAM = iTerm.app (case-insensitive) -> Read_Write
   if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_ITERM2) then
      Caps.Support          := Read_Write;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  Step 2: TERM_PROGRAM = vscode (case-insensitive) -> Write_Only
   if Termicap.Environment.Equal_Case_Insensitive (TP, TERM_PROGRAM_VSCODE) then
      Caps.Support          := Write_Only;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  Step 3: WT_SESSION present and non-empty -> Write_Only
   if WT'Length > 0 then
      Caps.Support          := Write_Only;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  Step 4: TERM = xterm-kitty (exact match) -> Read_Write
   if Termicap.Environment.Equal_Case_Insensitive (T, TERM_XTERM_KITTY) then
      Caps.Support          := Read_Write;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  Step 4 continued: TERM starts with "xterm" (prefix match) -> Write_Only
   if T'Length >= TERM_XTERM'Length
      and then Ada.Characters.Handling.To_Lower
                 (T (T'First .. T'First + TERM_XTERM'Length - 1)) = TERM_XTERM
   then
      Caps.Support          := Write_Only;
      Caps.Via_Env_Heuristic := True;
      return;
   end if;

   --  No heuristic matched. Support remains None.
end Infer_Clipboard_From_Env;
```

Step ordering (Read_Write before Write_Only) ensures that a more capable
classification is not masked by a less capable one. The xterm-prefix branch
is intentionally conservative: `Write_Only` is the safe default for xterm
because `allowWindowOps` (which gates read-back) is disabled by default in
most distributions.

### G.5 Parsing the OSC 52 response (FUNC-C52-008)

```ada
function Parse_OSC52_Response
  (Buffer : Byte_Array; Length : Natural) return OSC52_Parse_Result
is
   pragma SPARK_Mode (On);
   I    : Positive := Buffer'First;
   Last : constant Natural := Buffer'First + Length - 1;
   --  OSC 52 response: ESC ] 52 ; <sel> ; <base64-or-empty> BEL
   --                   or: ESC ] 52 ; <sel> ; <base64-or-empty> ESC \
begin
   --  Search for ESC ] (OSC introducer).
   while I <= Last - 4 loop
      if Buffer (I) = 16#1B# and then Buffer (I + 1) = 16#5D#
         and then Buffer (I + 2) = Character'Pos ('5')
         and then Buffer (I + 3) = Character'Pos ('2')
      then
         --  Found OSC 52 introducer. Look for the terminator.
         declare
            J : Positive := I + 4;
            Semicolons : Natural := 0;
         begin
            --  Expect: ; <selection> ; <payload> <terminator>
            while J <= Last loop
               if Buffer (J) = Character'Pos (';') then
                  Semicolons := Semicolons + 1;
               end if;
               --  Check for BEL terminator
               if Buffer (J) = 16#07# then
                  if Semicolons >= 2 then
                     return Valid_Response;
                  else
                     return Malformed;
                  end if;
               end if;
               --  Check for ST terminator (ESC \)
               if Buffer (J) = 16#1B# and then J + 1 <= Last
                  and then Buffer (J + 1) = 16#5C#
               then
                  if Semicolons >= 2 then
                     return Valid_Response;
                  else
                     return Malformed;
                  end if;
               end if;
               J := J + 1;
            end loop;
            --  No terminator found.
            return Malformed;
         end;
      end if;
      I := I + 1;
   end loop;

   return Not_Present;
end Parse_OSC52_Response;
```

The parser is `O(Length)` worst-case (linear scan for `ESC ] 52` introducer,
then linear scan for terminator). All bounds are checked; SPARK Silver
provability is preserved. The base64 content is not decoded -- only structural
presence matters for capability detection (the fact that a response arrived is
sufficient to confirm Read_Write support).

### G.6 Detection priority cascade summary

```
Phase 1: DA1 Ps=52 passive (TTY-only)           -> Write_Only, Via_DA1=True
Phase 2: Active OSC 52 probe (TTY-only)          -> Read_Write upgrade, Via_Active_Probe=True
Phase 3: Env-var heuristics (always as fallback)  -> Write_Only or Read_Write, Via_Env_Heuristic=True
```

Phase 2 always runs (when guards pass) regardless of Phase 1 outcome, because
it can upgrade `Write_Only` to `Read_Write`. Phase 3 runs only when
`Support = None` after Phases 1 and 2 (DA1/probe results are more authoritative
than env-var inference).

---

## H. Platform Gating and TTY Guards (FUNC-C52-012)

### H.1 Guard sequence

| Guard | Test | Action on failure | POSIX order | Windows order |
|-------|------|-------------------|-------------|---------------|
| 1 | `Termicap.TTY.Is_TTY (Stdout)` | Skip active probes; passive only; `Probed := False` | 1 | 2 |
| 2 | `Is_Foreground_Process` (inside `Probe_Session.Open`) | Skip active probes; passive only; `Probed := False` | 2 | 3 |
| 3 | `Open_TTY` succeeds (inside `Probe_Session.Open`) | Skip active probes; passive only; `Probed := False` | 3 | 4 |
| 4 | (Windows only) `GetConsoleMode (STD_OUTPUT_HANDLE)` returns False | If True (genuine Win32 Console): skip probes; passive only | n/a | **1** |

On POSIX, Guards 1-3 run as listed; Guard 4 is absent (compile-time, via
ADR-0018 platform-dispatch). On Windows, Guard 4 is evaluated **first** per
FUNC-C52-012's final paragraph. If Guard 4 reports a genuine Win32 Console,
no further probing happens; passive heuristics still apply (Windows Terminal
may set `WT_SESSION`, yielding `Write_Only`). If Guard 4 falls through
(Cygwin/MSYS PTY or pipe), Guards 1-3 are evaluated as on POSIX.

### H.2 No-TTY passive fallback (FUNC-C52-013)

When Guard 1 (or any subsequent guard) fails, the cascade returns with:

- `Probed = False`
- `Via_DA1 = False`
- `Via_Active_Probe = False`
- `Support` and `Via_Env_Heuristic` set per env-var heuristics (FUNC-C52-009).

Rationale: a process piping output within a WezTerm session still has
`TERM_PROGRAM=WezTerm` set. The caller can infer clipboard availability and
choose to emit OSC 52 write sequences even into a pipe (the decision belongs
to the caller).

### H.3 Win32 Cygwin / MSYS2 fall-through

On Windows, when `GetConsoleMode (STD_OUTPUT_HANDLE)` returns False, stdout is
a Cygwin/MSYS2 PTY (real PTY semantics; mintty supports VT escapes) or a
pipe/file (no terminal at all). The Win32 gate falls through to POSIX-like
Guards 1-3. This mirrors the MOUSE and SIXEL Windows body patterns.

---

## I. Multiplexer Passthrough (FUNC-C52-011)

### I.1 DA1 probe multiplexer handling

The DA1 probe is delegated to `Termicap.DA1.IO.Detect_DA1`, which already
handles multiplexer-passthrough per FUNC-DA1-012:

- `tmux` -- wrap DA1_QUERY in `DCS tmux; ... ST` envelope.
- `screen` -- wrap in `DCS ; ... ST` envelope.
- Other multiplexers / no multiplexer -- no wrapping.

### I.2 OSC 52 probe multiplexer handling

The OSC 52 active probe wraps the query using
`Termicap.OSC.Parsing.Wrap_For_Passthrough` when running inside tmux or GNU
screen:

- **tmux**: `ESC P tmux ; ESC <query> ESC \`. The inner `ESC` in the OSC
  sequence is doubled (0x1B 0x1B) per the tmux passthrough convention.
- **screen**: `ESC P <query> ESC \`. No ESC doubling required.

The DA1 sentinel is written **outside** the DCS passthrough envelope, ensuring
that the multiplexer forwards it directly to the outer terminal's input queue
for sentinel detection (FUNC-C52-011).

Multiplexer detection uses the environment variables `TMUX` (for tmux) and
`STY` (for GNU screen), consistent with the existing passthrough detection
in `Termicap.DA1.IO` and `Termicap.BG_Color.IO`.

---

## J. Two-Session Decision: DA1 and OSC 52 Run Independently (FUNC-C52-015)

FUNC-C52-015 states: "When a DA1 probe and the OSC 52 active probe are both
performed in the same detection call, they shall be performed as separate
sessions with independent timeouts, not as a single batched session."

Rationale (mirroring ADR-0028 for SIXEL):

1. The DA1 probe uses `Termicap.OSC.Timeout_Query` (no DA1 sentinel -- the
   DA1 *response* is the data). The OSC 52 probe uses `Sentinel_Query` (DA1
   *is* the sentinel). Mixing them creates response parsing ambiguity.
2. `Detect_DA1` is a pre-existing function that manages its own session
   lifecycle. Using it means the clipboard feature has zero new I/O code for
   the DA1 path -- only orchestration.
3. The cost of two sessions (two `tcgetattr`+`tcsetattr` cycles) is negligible
   for a once-per-process detection call.

---

## K. Timeout Behaviour (FUNC-C52-015)

### K.1 Per-session timeouts

| Session | Timeout | Pre-existing function | Rationale |
|---------|---------|------------------------|-----------|
| DA1 probe | `CLIPBOARD_PROBE_TIMEOUT_MS` (1000 ms) | `Termicap.DA1.IO.Detect_DA1` | Matches FUNC-OSC-004 default |
| OSC 52 probe | `CLIPBOARD_PROBE_TIMEOUT_MS` (1000 ms) | `Termicap.OSC.Sentinel_Query` | Same |

Worst-case latency of `Detect_Clipboard`: 1000 ms (DA1) + 1000 ms (OSC 52)
= **2 seconds**. This worst case occurs only when both probes time out
completely.

In the common case (DA1 succeeds quickly, or DA1 cached from a prior feature),
latency is dominated by the OSC 52 probe (if needed). When the active probe
confirms Read_Write on a responsive terminal, the round-trip is typically
<100 ms.

### K.2 Per-session timeout handling

- **DA1 timeout**: `Detect_DA1` returns `DA1_Capabilities` with
  `Supported = False`. `Has_Capability` returns False. `Via_DA1` stays False.
  The cascade continues to Phase 2 (active probe) and Phase 3 (heuristics).
- **OSC 52 timeout**: `Sentinel_Query` returns `Timed_Out = True`. If
  `Resp_Length = 0`, `Parse_OSC52_Response` returns `Not_Present`. Support
  stays as established by Phase 1 (DA1) or falls through to Phase 3 (env-var).

---

## L. Error Handling (FUNC-C52-016)

Per FUNC-C52-016, every failure mode is silent: no exception escapes
`Detect_Clipboard`. The catalogue:

| Failure mode | Catch location | `Clipboard_Capabilities` returned |
|--------------|----------------|------------------------------------|
| `/dev/tty` unopenable in DA1 path | `Detect_DA1` returns Supported=False | DA1 contributes nothing; active probe + heuristics |
| `tcgetattr`/`tcsetattr` fail in DA1 path | `Detect_DA1` returns Supported=False | Same |
| DA1 session times out | `Detect_DA1` returns Supported=False | Same |
| DA1 buffer cannot be parsed | `Detect_DA1` returns Supported=False (Count=0) | Same |
| OSC 52 session fails to open | `Run_OSC52_Probe` returns Not_Present | Support stays as set by DA1/heuristics |
| OSC 52 `Write_Query` fails | `Sentinel_Query` sets Timed_Out=True, Resp_Length=0 | `Parse_OSC52_Response` returns Not_Present |
| OSC 52 times out | Same | Same |
| OSC 52 response is garbled | `Parse_OSC52_Response` returns Malformed | Treated as Not_Present for Support |
| Env-var read raises | Wrapped in outer `when others` of `Run_Cascade` | Returns NO_CLIPBOARD_CAPABILITIES |
| `GetConsoleMode` raises (Windows) | Outer `when others` | Same |
| Multiplexer wrapping oversized | `Wrap_For_Passthrough` returns unbounded; caught at `Sentinel_Query` level | Graceful degradation |
| `Restore_Termios` fails after probe | `Probe_Session.Close` swallows | No impact on result |
| Any unexpected exception | Outer `when others` in `Detect_Clipboard` | Returns NO_CLIPBOARD_CAPABILITIES |

### L.2 Outer exception handler

```ada
function Detect_Clipboard return Clipboard_Capabilities is
   ...
begin
   ...
   return Result;
exception
   when others =>
      return NO_CLIPBOARD_CAPABILITIES;
end Detect_Clipboard;

function Detect_Clipboard_Uncached return Clipboard_Capabilities is
begin
   return Run_Cascade;
exception
   when others =>
      return NO_CLIPBOARD_CAPABILITIES;
end Detect_Clipboard_Uncached;
```

This is the universal Termicap pattern (cf. FUNC-MSE-014, FUNC-KKB-014,
FUNC-SXL-016).

---

## M. Termios Safety (FUNC-C52-014)

Owned by `Termicap.OSC.Probe_Session`'s RAII semantics. The DA1 probe (via
`Detect_DA1`) and OSC 52 probe (via local `Run_OSC52_Probe`) each declare a
local `Probe_Session`; on every return path the `Limited_Controlled.Finalize`
operation runs and restores termios + closes /dev/tty. This is identical to
the guarantee MOUSE (FUNC-MSE-015), KKB (FUNC-KKB-015), and SIXEL
(FUNC-SXL-014) inherit.

The clipboard feature does **not** call `tcgetattr`, `tcsetattr`,
`Save_Termios`, `Restore_Termios`, `Set_Raw_Mode`, `Open_Terminal`, or
`Close_Terminal` directly. All termios manipulation is mediated through:

- `Termicap.DA1.IO.Detect_DA1` (which uses `Termicap.OSC.Probe_Session`).
- The local `Run_OSC52_Probe` (which declares a `Probe_Session` directly).

ADR-0015 (Probe_Session as Limited_Controlled) is the foundational decision;
this feature inherits it.

---

## N. Caching (FUNC-C52-017)

### N.1 Cache shape

A single-slot protected object identical to MOUSE's, KKB's, and SIXEL's:

```ada
type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Clipboard_Capabilities := NO_CLIPBOARD_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Clipboard_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_CLIPBOARD_CAPABILITIES);
end Cache;
```

`Detect_Clipboard` reads the cache first; on initialised, returns the cached
`Value`. On uninitialised, runs `Run_Cascade`, calls `Cache.Set_Cached
(Result)`, and returns. Race between two concurrent first callers: both run
the cascade, both write to the cache, last-writer wins. Both results are
semantically equivalent (the terminal does not change mid-cascade).

### N.2 Cache-bypass variant -- `Detect_Clipboard_Uncached`

The Should clause of FUNC-C52-017 ("a separate Detect_Clipboard_Uncached
function that bypasses the cache") is satisfied by:

```ada
function Detect_Clipboard_Uncached return Clipboard_Capabilities;
```

Runs the full cascade every time, **does not** read or write the cache.
Intended for test harnesses and edge cases (terminal change mid-process).

### N.3 SIGWINCH not relevant

Per FUNC-C52-017 final paragraph: clipboard protocol support is a property of
the terminal emulator, not the terminal size. Cache is **not** invalidated
on SIGWINCH.

### N.4 Lazy initialisation

The protected object's `Slot` is default-initialised by Ada elaboration to
`(Initialized => False, Value => NO_CLIPBOARD_CAPABILITIES)`. **No probe runs
at elaboration time.** The first call to `Detect_Clipboard` triggers the
cascade.

### N.5 DA1 sub-cache

When `Detect_Clipboard` calls `Termicap.DA1.IO.Detect_DA1`, the DA1 result is
**also** cached at the `Termicap.DA1` level (per the DA1 feature's own caching).
A subsequent independent caller invoking `Termicap.DA1.IO.Detect_DA1` directly
hits the DA1 cache (free). A subsequent `Detect_Clipboard` call hits the
clipboard cache (the inner DA1 cache is not consulted).

---

## O. SPARK Boundary

### O.1 Per-package SPARK_Mode summary

| Package / subprogram | SPARK_Mode | Target | Rationale |
|----------------------|------------|--------|-----------|
| `Termicap.Clipboard` (spec) | On (package) | Silver | Pure types, named String constants, parser signature |
| `Termicap.Clipboard` (body, package level) | Off | N/A | Body contains only `Parse_OSC52_Response` |
| `Parse_OSC52_Response` (body) | On (locally) | Silver | Pure scan; provable bounds; no I/O |
| `Termicap.Clipboard.IO` (spec) | Off | N/A | Declares `Detect_Clipboard` / `Uncached`; both involve I/O |
| `Termicap.Clipboard.IO` (body, POSIX) | Off | N/A | Calls `Probe_Session`, `Detect_DA1`, `Sentinel_Query`, env access |
| `Termicap.Clipboard.IO` (body, Windows) | Off | N/A | Same as POSIX, plus Win32 FFI |
| Internal helpers (`Infer_Clipboard_From_Env`, `Run_OSC52_Probe`, body locals) | Off | N/A | Body-private; depend on env access and Probe_Session |

### O.2 Mixed-SPARK pattern (per ADR-0013)

`Termicap.Clipboard` follows the established pattern of MOUSE / KKB / DA1 /
SIXEL:

- **Spec** declares pure functions and types with `SPARK_Mode => On`.
- **Body** is package-level `SPARK_Mode => Off`.
- **Each pure function body** carries a local `pragma SPARK_Mode (On);`.

### O.3 SPARK boundary justification

`Termicap.Clipboard.IO` calls `Probe_Session`, `Detect_DA1`, and
environment-access procedures -- all SPARK_Mode Off. The SPARK Silver target
applies to:

- `Parse_OSC52_Response` (~40 LOC, fully provable)
- The `Clipboard_Support`, `Clipboard_Capabilities`, and `OSC52_Parse_Result`
  type declarations (provable by virtue of being plain enums / records).

Total provable surface: ~60 LOC.

---

## P. Integration Points

### P.1 Dependency diagram (text form)

```
                        Termicap.Clipboard.IO  (POSIX or Windows body, SPARK Off)
                                  |
       +---------------+----------+---------+---------------+
       |               |                    |               |
       v               v                    v               v
Termicap.Clipboard  Termicap.OSC      Termicap.DA1.IO   Termicap.TTY
  (SPARK On)       (SPARK Off)         (SPARK Off)      (SPARK Off)
       |               |                    |
       |               v                    |
       |       Termicap.OSC.Parsing         |
       |          (SPARK On)                |
       |                                    v
       v                            Termicap.DA1
Interfaces.C                         (SPARK On)

                        Termicap.Environment  (SPARK Off)
                        Termicap.Environment.Capture  (SPARK Off)
                        Termicap.Terminal_Id  (SPARK Off)
```

### P.2 New compile-time dependencies introduced

- POSIX body: `Ada.Characters.Handling`, `Termicap.DA1.IO`,
  `Termicap.OSC.Parsing`, `Termicap.Terminal_Id`. None require new Alire crates.
- Windows body: same as POSIX, plus `Termicap.Win32_VT`, `Win32`,
  `Win32.Winbase`, `Win32.Wincon`, `Win32.Winnt`. All already present.

### P.3 Files modified

| File | Change | Lines affected |
|------|--------|---------------|
| `src/termicap-da1.ads` | Add `Clipboard_Access` to `DA1_Capability` enum; add `DA1_PS_CLIPBOARD_ACCESS` constant | ~5 |
| `src/termicap-da1.adb` | Add `52 => Clipboard_Access` mapping in `Interpret_DA1` scan loop | ~3 |

### P.4 Files explicitly **not** modified

- `src/termicap-da1-io.adb` -- reused unchanged via `Detect_DA1`.
- `src/termicap-osc.ads` / `.adb` -- reused unchanged via `Probe_Session`,
  `Sentinel_Query`.
- `src/termicap-osc-parsing.ads` / `.adb` -- reused unchanged via
  `Wrap_For_Passthrough`.
- `src/termicap-tty.ads` -- reused unchanged via `Is_TTY`, `Stdout`.
- `src/termicap-environment*.ads` / `.adb` -- reused unchanged.
- `src/termicap-capabilities.ads` -- FUNC-C52-019 deferred.
- `alire.toml`, `termicap.gpr` -- no new external crates.

### P.5 FUNC-C52-019 deferral

Per FUNC-C52-019 explicit text: "Integration into Terminal_Capabilities is
**OUT OF SCOPE** for this feature specification and is deferred as an
explicit non-goal." This mirrors ADR-0021 (keyboard), ADR-0026 (mouse), and
FUNC-SXL-019 (graphics).

---

## Q. File Layout Summary

### New files

| File | Purpose |
|------|---------|
| `src/termicap-clipboard.ads` | SPARK On spec: types, constants, parser signature |
| `src/termicap-clipboard.adb` | Body: `Parse_OSC52_Response` with local SPARK On |
| `src/termicap-clipboard-io.ads` | SPARK Off spec: `Detect_Clipboard`, `Detect_Clipboard_Uncached` |
| `src/posix/termicap-clipboard-io.adb` | POSIX body: full cascade |
| `src/windows/termicap-clipboard-io.adb` | Windows body: Win32 gate + Cygwin fall-through |

### Modified files

| File | Change |
|------|--------|
| `src/termicap-da1.ads` | Add `Clipboard_Access` enum literal + `DA1_PS_CLIPBOARD_ACCESS` constant |
| `src/termicap-da1.adb` | Add `52 => Clipboard_Access` mapping in `Interpret_DA1` |

### Test files (to be created by spec-to-test)

| File | Purpose |
|------|---------|
| `tests/src/termicap-clipboard-tests.adb` | Unit tests for `Parse_OSC52_Response`, env-var heuristics |
| `tests/src/termicap-da1-clipboard-tests.adb` | Unit tests for DA1 Ps=52 mapping |

---

## R. Open Questions / ADR Candidates

### R.1 ADR-0031: Defer Terminal_Capabilities integration for OSC 52

Following the established pattern of ADR-0021 (keyboard), ADR-0026 (mouse),
and FUNC-SXL-019 (graphics), the integration of `Clipboard_Capabilities` into
`Terminal_Capabilities` is deferred until OSC52 is promoted from Draft to
Approved and the Tier 4 capability record update is scheduled. This decision
is documented in ADR-0031.

### R.2 No additional ADRs required

All significant design decisions for the clipboard feature are covered by
existing ADRs:

- **ADR-0012** (capability cache design) -- governs the protected-object cache.
- **ADR-0013** (SPARK annotation split) -- governs the mixed SPARK_Mode pattern.
- **ADR-0015** (Probe_Session as Limited_Controlled) -- governs termios safety.
- **ADR-0017** (DA1 timeout-only read loop) -- governs the DA1 probe semantics.
- **ADR-0018** (platform dispatch via source dirs) -- governs the per-platform body files.
- **ADR-0027** (DA1 reuse vs. fresh probe) -- governs DA1 result reuse.
- **ADR-0028** (independent probe sessions) -- governs the two-session decision.

The OSC 52 feature does not introduce any new architectural patterns; it follows
the established Tier 4 detection template exactly. The only new decision
warranting an ADR is the deferral of Terminal_Capabilities integration (R.1
above), which follows the well-established precedent.
