# MOUSE: Mouse Protocol Detection

**Feature:** Mouse protocol & encoding detection (X10 / URXVT / SGR / SGR-Pixels / GPM / Win32)
**Requirements:** FUNC-MSE-001 through FUNC-MSE-018 (`docs/requirements/mouse-protocol.sdoc`)
**Parent Requirements:** OSC-INFRA (REQ-OSC), DECRPM (REQ-RPM), DA1 (REQ-DA1), CYGWIN (REQ-CYG), TERM-ID (REQ-TID)
**Status:** Proposed
**Date:** 2026-04-23

---

## A. Summary

At process startup, applications that route mouse input through Termicap need to know two things about the controlling terminal:

1. **Which mouse encoding** the terminal can emit (X10, URXVT, SGR, or SGR-Pixels), so the caller knows which DECSET sequence to send and which event format to parse.
2. **Which tracking modes** the terminal recognises (button-only, button-event/drag, any-event/motion), so the caller does not enable a mode that produces no events.

This feature adds a new package `Termicap.Mouse` (SPARK On spec, SPARK Off body with locally-annotated pure parsers and cascade) and its platform-specific I/O child `Termicap.Mouse.IO`. The public entry point `Detect_Mouse_Protocols` returns a `Mouse_Capabilities` record. It implements **Win32-gate > GPM-heuristic > guards > batched-DECRPM-probe > cascade**, reusing `Termicap.OSC.Probe_Session` and `Termicap.OSC.Sentinel_Query` for a single sentinel-bounded session that collects all six DECRPM responses before the DA1 sentinel terminates the read loop. The DECRPM response parser (`Parse_Mouse_DECRPM_Response`) and the encoding cascade (`Resolve_Best_Encoding`) are pure SPARK Silver-provable functions. The result is cached in a package-level protected object for the process lifetime (FUNC-MSE-016). Integration into `Terminal_Capabilities` (FUNC-MSE-018) is intentionally deferred (mirroring ADR-0021); the standalone `Detect_Mouse_Protocols` function is the primary API.

This feature stands on the shoulders of three already-shipped infrastructure features: DECRPM (FUNC-RPM-001..017) supplies `Mode_Id`, `Mode_Status`, the `DECRPM_Query` byte builder, and `Parse_DECRPM_Response`; OSC-INFRA (FUNC-OSC-001..015) supplies `Probe_Session` and `Sentinel_Query`; TERM-ID (FUNC-TID-001..011) supplies multiplexer detection. Mouse protocol detection introduces no new C wrappers and no new system calls beyond a single `Ada.Directories.Exists ("/dev/gpmctl")` check on Linux.

---

## B. Scope & Requirements

Each approved FUNC-MSE requirement is satisfied by a specific design element.

| UID | Priority | Summary | Non-trivial interpretation |
|-----|----------|---------|----------------------------|
| FUNC-MSE-001 | Must | `Mouse_Encoding` enumeration with six values (`Unknown`, `None`, `X10`, `URXVT`, `SGR`, `SGR_Pixels`) | No |
| FUNC-MSE-002 | Must | `Mouse_Capabilities` record: `Best_Encoding` + six `Supports_*` Booleans + `Win32_Console_Mouse` + `GPM_Available` + `Probed`; canonical "no result" specified | No |
| FUNC-MSE-003 | Must | Six `MODE_MOUSE_*` named constants (1000, 1002, 1003, 1015, 1006, 1016) of type `Mode_Id` | No |
| FUNC-MSE-004 | Must | Six DECRPM queries issued in a fixed order; responses matched by `Ps`, not by position | No |
| FUNC-MSE-005 | Must | Single batched probe session: open + raw + write all six queries + DA1 sentinel + sentinel-bounded read + restore + close | **Yes** — see §F and ADR-0022 |
| FUNC-MSE-006 | Must | `Pm = 0` => `Supports_* = False`; `Pm in 1..4` => `Supports_* = True`; missing response => `False` | No |
| FUNC-MSE-007 | Must | Pure SPARK `Parse_Mouse_DECRPM_Response (Buffer, Length) return DECRPM_Parse_Result` | No |
| FUNC-MSE-008 | Must | Pure SPARK `Resolve_Best_Encoding (Caps) return Mouse_Encoding` cascade SGR_Pixels > SGR > URXVT > X10 > None | No |
| FUNC-MSE-009 | Must | Five guards in fixed order (Win32 > GPM > TTY > foreground > /dev/tty open) before any DECRPM probe runs | No |
| FUNC-MSE-010 | Must | Win32 platform gate: `GetConsoleMode (STD_INPUT_HANDLE) /= FALSE` => return `Win32_Console_Mouse` immediately | No |
| FUNC-MSE-011 | Must | Linux/GPM heuristic: `TERM = "linux"` and `Ada.Directories.Exists ("/dev/gpmctl")` => return `GPM_Available` immediately | **Yes** — see ADR-0024 |
| FUNC-MSE-012 | Should | Multiplexer awareness: probe regardless; populate from whatever responds; document caveat; defer DCS passthrough | No |
| FUNC-MSE-013 | Must | 1000 ms total session timeout; partial results preserved; total timeout => `Unknown` | No |
| FUNC-MSE-014 | Must | No-exception contract for `Detect_Mouse_Protocols` across all enumerated failure modes | No |
| FUNC-MSE-015 | Must | Termios restore on every exit path — guaranteed by `Probe_Session` RAII | No |
| FUNC-MSE-016 | Must | One-probe-per-process cache; lazy elaboration; not invalidated by SIGWINCH | No |
| FUNC-MSE-017 | Must | Package structure `Termicap.Mouse` (SPARK On spec) + `Termicap.Mouse.IO` child (SPARK Off); platform-specific bodies under `src/posix/` and `src/windows/` | No |
| FUNC-MSE-018 | Could | **Deferred** — extension of `Terminal_Capabilities` with `Mouse` field is out of scope for this feature | **Yes** — see §M and ADR-0026 |

### Non-trivial interpretations

**FUNC-MSE-005 batched session — single sentinel for six queries.** The requirement is explicit that all six DECRPM queries are dispatched as one batch followed by **one** DA1 sentinel. The naïve alternative — six independent `Sentinel_Query` calls inside a single `Probe_Session` — would also work but pays a per-probe round-trip cost and emits six DA1 sentinels into the terminal's input stream (six harmless but visible echo opportunities). Batching reduces to a single round-trip and a single DA1 echo. The trade-off is parser complexity: the response stream interleaves up to six `CSI ? Ps ; Pm $ y` fragments. The parser handles this by scanning forward through the accumulated pre-sentinel bytes for each well-formed DECRPM frame. This is documented as ADR-0022.

**FUNC-MSE-011 GPM heuristic.** The requirement specifies `TERM=linux + /dev/gpmctl exists` as the GPM detection rule. We implement exactly this — no `connect()` probe, no `GPM_OPEN` request — as documented in ADR-0024. The cost is a small false-positive risk (gpmctl exists but daemon is unresponsive), accepted for simplicity and zero added latency.

**FUNC-MSE-018 deferral — see §M.** Mirrors ADR-0021 for keyboard. The Could-priority field addition to `Terminal_Capabilities` is out of scope; the standalone `Detect_Mouse_Protocols` function is the primary API. ADR-0026 records the deferral.

---

## C. Framework Survey

Mouse protocol detection is one of the **least uniformly handled** capabilities across the surveyed reference frameworks: most libraries either (a) **enable** the modes blindly without probing first (relying on terminals to ignore unknown modes), or (b) probe a single mode (usually `1006` SGR) and infer the rest. Termicap takes a third path: probe **all six** modes in one batched session and let the cascade pick the best.

### tcell (Go) — DECRPM probing for `1000`/`1006`, blind enable for the rest

`reference-frameworks/tcell/tscreen.go` lines 213–217 declare per-capability Boolean flags including `haveMouse` and `haveMouseSgr` (no flag for X10, URXVT, button-event, any-event, or SGR-Pixels — they are treated as implied or ignored). Lines 1231–1232 emit the **probe**:

```go
t.Print(vt.PmMouseButton.Query())   // CSI ? 1000 $ p
t.Print(vt.PmMouseSgr.Query())      // CSI ? 1006 $ p
```

Lines 366–376 process the DECRPM responses inside the event loop:

```go
case vt.PmMouseSgr:
    t.haveMouseSgr = ev.Status.Changeable()
case vt.PmMouseButton:
    t.haveMouse = ev.Status.Changeable()
```

`Status.Changeable()` is true for status codes 1, 2 (i.e., recognised but possibly disabled), false for 0 — exactly Termicap's `Pm in 1..4 => Supports = True` rule.

`enableMouse` (lines 888–923) then blindly emits DECSET sequences for `?1002`, `?1003`, `?1006`, never querying `1015`, `1016`, or `1003`. The decision is documented in a comment: *"we rely on dec private mode queries for this. If your terminal doesn't support these, then ask them to fix it"*. tcell's design optimises for round-trip count (probe two, enable five) at the cost of detection completeness.

**Lessons for Termicap.** Probe-first, enable-later separation is correct — tcell validates the design. But Termicap probes **six** modes (not two) because the cost is negligible (one extra DECRPM per mode in a single batched session) and the information is useful: knowing `Supports_SGR_Pixels` separately from `Supports_SGR` lets a caller pick the richer encoding without speculative enable/disable round-trips later.

### crossterm (Rust) — no probing, blind blanket enable

`reference-frameworks/crossterm/src/event.rs` lines 305–319 (`EnableMouseCapture::write_ansi`) shows crossterm's strategy:

```rust
f.write_str(concat!(
    csi!("?1000h"),  // Normal tracking
    csi!("?1002h"),  // Button-event (drag)
    csi!("?1003h"),  // Any-event tracking
    csi!("?1015h"),  // RXVT mouse
    csi!("?1006h"),  // SGR mouse
))
```

Crossterm enables all five modes simultaneously and parses whichever encoding the terminal happens to emit at runtime. There is **no DECRPM probe**. Detection is pushed to the event-decode stage: the input parser handles `ESC [ M ...`, `ESC [ <...M/m`, and `ESC [ ...;...;...M` shapes opportunistically.

**Lessons for Termicap.** Crossterm's approach is operationally simple but has one downside: callers cannot know **before** writing data which encoding will be used, so they must be prepared to parse all formats. Termicap's design lets the caller select an encoding deterministically based on the result of `Detect_Mouse_Protocols`, simplifying the application's input-parsing path. crossterm's omission of mode 1016 (SGR-Pixels) is also notable — it leaves pixel-precision opt-in to the caller.

### blessed (Python) — DECRPM probing, full encoding cascade

`reference-frameworks/blessed/blessed/dec_modes.py` lines 291–305 define the **complete** mouse-mode constant set Termicap targets:

```python
MOUSE_REPORT_CLICK    = 1000
MOUSE_REPORT_DRAG     = 1002
MOUSE_ALL_MOTION      = 1003
MOUSE_EXTENDED_SGR    = 1006
MOUSE_URXVT           = 1015
MOUSE_SGR_PIXELS      = 1016
```

`reference-frameworks/blessed/blessed/mouse.py` (and the test suite at `tests/test_mouse.py` lines 38–82) explicitly documents the SGR-Pixels-over-SGR preference:

> *"When both 1006 and 1016 are enabled, 1016 (SGR-Pixels) is preferred"*

Test vectors (`tests/test_mouse.py` lines 629–633) parametrise the cascade:

```python
(True, False, False, False, [1006, 1000]),       # X10 + SGR
(False, True, False, False, [1006, 1002]),       # button-event + SGR
(False, False, True, False, [1006, 1003]),       # any-event + SGR
(True, False, False, True,  [1006, 1000, 1016]), # X10 + SGR + SGR-Pixels
```

blessed probes each mode individually with a per-mode cache (`_dec_mode_cache`) and short-circuits **all** further DECRPM queries after the first timeout (`_dec_first_query_failed`). The first-timeout-kills-all heuristic recognises that a terminal that fails to answer one DECRPM query will fail to answer them all.

**Lessons for Termicap.** The blessed design is the closest to Termicap's: probe all relevant modes, derive a preferred encoding from the responses, cascade SGR-Pixels > SGR > others. Termicap differs by **batching** all six queries in a single sentinel-bounded session (rather than per-mode) — which avoids the overhead of six raw-mode enter/restore cycles and obviates the need for blessed's first-timeout heuristic (the DA1 sentinel naturally bounds the batch).

### notcurses (C) — DECRPM probing for SGR/Pixels + GPM bypass for Linux console

`reference-frameworks/notcurses/src/lib/gpm.c` is the canonical reference for the **Linux console / GPM** path. Key excerpts:

```c
gpmconn.eventMask = GPM_DRAG | GPM_DOWN | GPM_UP;
if (Gpm_Open (&gpmconn, 0) == -1) {
    logerror ("couldn't connect to gpm");
    ...
}
loginfo ("connected to gpm on %d", gpm_fd);
```

Notcurses `Gpm_Open()`s the daemon and then `pthread_create()`s a watcher thread that translates GPM events into XTerm-style events (`gpm.c` lines 10–25). Detection of GPM availability is implicit: if `Gpm_Open` succeeds, GPM is available; if not, fall back to escape-sequence parsing.

`reference-frameworks/notcurses/src/info/main.c` line 471 reports GPM in the capability dump:

```c
tinfo_debug_cap (n, "gpm", ti->gpmfd >= 0);
```

**Lessons for Termicap.** Notcurses is the most thorough reference for Linux console mouse support: GPM is a real, separate event source, not a fallback within DECRPM. Termicap's GPM heuristic deliberately avoids opening a connection (which would require linking `libgpm` and add startup cost); we report **availability** only, and let the caller decide whether to integrate GPM. ADR-0024 records this trade-off.

### termenv (Go) — no probing; only DECSET strings exposed

`reference-frameworks/termenv/screen.go` lines 37–48 enumerate the DECSET enable/disable strings for modes 1000, 1002, 1003, 1006, 1016 (no 1015):

```go
EnableMouseSeq              = "?1000h"
EnableMouseCellMotionSeq    = "?1002h"
EnableMouseAllMotionSeq     = "?1003h"
EnableMouseExtendedModeSeq  = "?1006h"
EnableMousePixelsModeSeq    = "?1016h"
```

termenv exposes these as raw byte sequences for the application to write. There is no detection path. As noted in the kitty-keyboard tech spec, termenv focuses on color/size/Unicode and does not implement keyboard or mouse capability probing.

**Lessons for Termicap.** None directly — termenv confirms the canonical encoding-mode constants but offers no detection design.

### WezTerm (Rust) — emulator-side `MouseEncoding` enum

`reference-frameworks/wezterm/term/src/terminalstate/mod.rs` lines 57–63 define the same shape Termicap proposes:

```rust
pub(crate) enum MouseEncoding {
    X10,
    Utf8,
    SGR,
    SgrPixels,
}
```

WezTerm sits on the **emulator** side: it reports whichever encoding the application enables via DECSET. Our `Mouse_Encoding` enumeration is the dual of WezTerm's: same set of named encodings, but representing what the **terminal advertises** to the application rather than what the application has selected. We add `URXVT` (mode 1015) which WezTerm does not implement, because URXVT is still encountered in urxvt-derived terminals and `foot`. We omit `Utf8` (mode 1005) because it has been deprecated in favour of SGR/URXVT for over a decade.

**Lessons for Termicap.** Validates the four-encoding shape (X10, URXVT, SGR, SGR-Pixels). The `Unknown` and `None` sentinels are Termicap-specific (mirroring `Keyboard_Protocol`).

### Cross-language consensus & Termicap's choices

| Aspect | tcell (Go) | crossterm (Rust) | blessed (Python) | notcurses (C) | termenv (Go) | Termicap (this feature) |
|--------|-----------|------------------|------------------|---------------|--------------|--------------------------|
| Modes probed | 1000, 1006 | none (blind enable) | per-call, cached | 1000, 1006 + GPM | n/a | **all six**: 1000, 1002, 1003, 1015, 1006, 1016 |
| Encoding cascade | implicit (SGR if `haveMouseSgr`) | none | SGR-Pixels > SGR > X10 | SGR-Pixels > SGR > Utf8 > X10 | n/a | **SGR-Pixels > SGR > URXVT > X10 > None** |
| GPM/Linux console | not handled | not handled | not handled | `Gpm_Open()` + thread | not handled | **`TERM=linux` + `/dev/gpmctl`** existence check (no connect) |
| Probe protocol | per-query inside session | none | per-query individual | per-query | n/a | **single batched session** with one DA1 sentinel |
| Timeout | not documented | n/a | first-timeout-kills-all | tied to screen init | n/a | **1000 ms** total batch timeout |
| Win32 path | falls back to `MOUSE_INPUT` records | `enable_mouse_capture` Win32 | not applicable | not applicable | not applicable | **Win32 gate**: `GetConsoleMode` short-circuit |
| Result type | per-flag Booleans on `tScreen` | n/a (no detection) | `DecModeResponse` per mode | per-flag Booleans on `tinfo` | n/a | **`Mouse_Capabilities` record**: orthogonal Booleans + `Best_Encoding` |

**What Termicap adopts:**

| Pattern | Borrowed from | Adaptation |
|---------|---------------|------------|
| Six-mode set (1000, 1002, 1003, 1015, 1006, 1016) | blessed `dec_modes.py` | Lifted exactly; declared as `MODE_MOUSE_*` constants of type `Mode_Id` |
| `MouseEncoding` enum shape (X10/SGR/SgrPixels) | wezterm `terminalstate/mod.rs` | Renamed to `Mouse_Encoding`; added `URXVT`, `Unknown`, `None` |
| SGR-Pixels > SGR > others cascade order | blessed `tests/test_mouse.py`, notcurses precedent | Encoded as a pure SPARK function `Resolve_Best_Encoding`; URXVT placed above X10 |
| DECRPM probe-then-enable separation | tcell `tscreen.go`, blessed | Termicap probes only, never enables — caller controls activation |
| GPM bypass for Linux console | notcurses `lib/gpm.c` | Detect availability via `Ada.Directories.Exists`; do **not** open a connection |
| Per-mode orthogonal Booleans in result record | tcell `haveMouse`/`haveMouseSgr` | Generalised to all six modes; ADR-0025 |
| Sentinel-bounded probe + DA1 termination | Termicap `Sentinel_Query` (existing) | One DA1 sentinel for the full six-query batch, not per-query (ADR-0022) |

**Primary-source citations** for protocol details:

- xterm DECRPM specification: `xterm` ctlseqs.ms — *"Request Private Mode (DECRQM): CSI ? Ps $ p; Reply: CSI ? Ps; Pm $ y"* — supports the wire-format check in `Parse_Mouse_DECRPM_Response`.
- xterm mouse encoding specification: `xterm` ctlseqs.ms §"Normal tracking mode"; *"SGR (1006) sends `CSI < Pb ; Px ; Py M` (or `m` on release)"*; *"SGR-Pixels (1016) is identical to 1006 except coordinates are pixels"*.
- URXVT mouse extension: `rxvt-unicode(7)` man page — *"mode 1015 enables decimal coordinates with no upper bound"*.
- GPM daemon control socket: `gpm(8)` man page — *"the GPM daemon listens on `/dev/gpmctl`, a SOCK_STREAM Unix domain socket"*. Confirms that **existence** of the socket is a reliable proxy for daemon availability on a properly-configured Linux console.

### Conclusion of survey

Termicap adopts the **blessed** mode set (six modes) and **cascade order** (SGR-Pixels > SGR > URXVT > X10 > None), but executes the probe with the **Termicap-native batched-sentinel** pattern (closer in spirit to tcell's "probe at terminal init" than to blessed's per-query approach). The result type is the `Mouse_Capabilities` record: orthogonal Booleans (à la tcell) plus a derived `Best_Encoding` (à la wezterm's `MouseEncoding`). The Linux/GPM bypass borrows notcurses' insight but stays one level shallower (existence check, not `Gpm_Open`) for zero-cost detection. The Win32 gate reuses the same `GetConsoleMode` predicate already used by KITTY-KB (FUNC-KKB-010) and the Windows Console feature (FUNC-WIN-003).

---

## D. Existing Infrastructure Used

This feature is the densest reuse of pre-existing Termicap infrastructure of any Tier 4 feature. The full inventory:

### `Termicap.OSC` — `src/termicap-osc.ads`

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Probe_Session` (controlled type) | RAII open/save/raw/restore/close lifecycle | Local declaration in `Run_Cascade` |
| `Open` / `Close` (procedures) | Session lifecycle | `Open` in `Run_Cascade`; `Close` via `Finalize` |
| `Sentinel_Query` (procedure) | Single-sentinel batched read | Called once with the six-query batch |
| `Write_Query` (procedure) | Raw escape write | Used to send the six DECRPM queries before the DA1 sentinel |
| `Response_Buffer` (subtype) | 4096-byte response accumulator | Local in `Run_Cascade` |
| `Session_Status` enum | Open outcome | Discriminator for guard 5 |
| `MAX_RESPONSE_SIZE` constant | Buffer length bound | Re-exported as the parser's loop bound |
| `Byte`, `Byte_Array` | Wire-level types | Converted to `Termicap.Mouse.Byte_Array` at the I/O boundary |

The foreground process group check (`FUNC-OSC-007`) and the single-concurrent-session guard (`FUNC-OSC-012`) are inherited automatically through `Probe_Session.Open`. The mouse feature does **not** call `tcgetattr`, `tcsetattr`, `select`, `read`, `write`, or `Is_Foreground_Process` directly.

### `Termicap.DECRPM` — `src/termicap-decrpm.ads`

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Mode_Id` subtype | Type for mouse mode constants | `MODE_MOUSE_*` declarations |
| `Mode_Status` enum | DECRPM response status decoding | Per-mode `Supports_*` derivation |
| `DECRPM_Query` function | Build `CSI ? Ps $ p` query bytes | Called six times to build the batch |
| `Parse_DECRPM_Response` function | Pure SPARK response parser | Called by `Parse_Mouse_DECRPM_Response` (which scans for one frame) |
| `Contains_DECRPM_Response` function | Wire-shape predicate | Used inside the parser's outer scan loop |
| `MAX_RESPONSE_SIZE` constant | Same value as `Termicap.OSC` | Used in parser preconditions |

The mouse feature does **not** use `Termicap.DECRPM.IO.Detect_Mode` or `Detect_Modes`: those convenience functions issue per-query sentinel sessions, which is precisely the pattern we batch into one. We use only the SPARK On building blocks from `Termicap.DECRPM`.

### `Termicap.DA1` (sentinel) — `src/termicap-da1.ads`

The DA1 query (`ESC [ c`) is appended to the batched write by `Sentinel_Query` itself; the mouse feature does not need to with `Termicap.DA1` directly. The DA1 response (`CSI ? <Psc> c`) is detected inside `Sentinel_Query`'s read loop and terminates the batch. This is the same mechanism KITTY-KB uses.

### `Termicap.Terminal_Id` — `src/termicap-terminal_id.ads`

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Terminal_Identity` record | Multiplexer detection | Populated via `Detect_Terminal_Identity` |
| `Multiplexer_Kind` subtype | tmux/screen test | Membership test in the multiplexer-caveat path |
| `Detect_Terminal_Identity` function | Pure terminal classification | Called once at the top of `Run_Cascade` |

Multiplexer detection is **passive** (environment-variable based); it adds zero round-trip cost. The result is used only to decide whether to log a diagnostic note (FUNC-MSE-012); it does not change the probe sequence.

### `Termicap.Environment` / `Termicap.Environment.Capture`

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Capture_Current` (procedure) | Snapshot of process env | Called once for `Detect_Terminal_Identity` and `TERM=linux` check |
| `Value` (function) | Read `TERM` value | GPM heuristic in guard 2 |

### `Termicap.TTY` — `src/termicap-tty.ads`

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Is_TTY` (function) | Stdin TTY guard | Guard 3 |
| `Stdin` (constant of `Stream_Kind`) | Stream selector | Argument to `Is_TTY` |

### `Termicap.Win32_Cygwin`, `Termicap.Win32_VT` (Windows path only)

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Termicap.Win32_VT.Is_Valid_Handle` | Guard against `INVALID_HANDLE_VALUE` | Inside the Win32 gate (Windows body only) |
| `Win32.Winbase.GetStdHandle` (re-exported via win32ada) | Get `STD_INPUT_HANDLE` | Win32 gate input |
| `Win32.Wincon.GetConsoleMode` | TTY/console predicate | Win32 gate (FUNC-MSE-010) |

The mouse Windows body imports the same Win32 surface as the keyboard Windows body. No new Win32 symbols are introduced.

### `Ada.Directories` (standard library)

| Symbol | Used for | Termicap.Mouse callsite |
|--------|----------|--------------------------|
| `Ada.Directories.Exists` | `/dev/gpmctl` existence check | Guard 2 (POSIX body) |

`Ada.Directories.Exists` does **not** open or read the file; it returns False when the path does not exist or when access is denied. Per FUNC-MSE-014, the call is wrapped in an exception handler that treats any failure as "file absent".

### What we do **not** reuse

- `Termicap.DECRPM.IO.Detect_Mode` / `Detect_Modes` — superseded by the batched probe path; using them would emit one DA1 sentinel per mode (six versus one) and incur six raw-mode enter/restore cycles.
- `Termicap.OSC.Timeout_Query` — used by DA1 detection (where the DA1 response *is* the data), not relevant here because the DA1 response is the **boundary**, not the payload.
- `Termicap.Capabilities` — explicitly out of scope (FUNC-MSE-018 deferred per ADR-0026).

---

## E. Package Structure

### Package hierarchy

```
Termicap.Mouse                    (src/termicap-mouse.ads: SPARK_Mode => On)
  |   Types:      Mouse_Encoding, Mouse_Capabilities, DECRPM_Parse_Result
  |   Constants:  MODE_MOUSE_X10, MODE_MOUSE_BUTTON_EVENT, MODE_MOUSE_ANY_EVENT,
  |               MODE_MOUSE_URXVT, MODE_MOUSE_SGR, MODE_MOUSE_SGR_PIXELS,
  |               MOUSE_PROBE_TIMEOUT_MS, NO_MOUSE_CAPABILITIES,
  |               CSI_DA1_QUERY (re-export shim — see below)
  |   Parsers:    Parse_Mouse_DECRPM_Response  (SPARK_Mode => On)
  |   Cascade:    Resolve_Best_Encoding         (SPARK_Mode => On)
  |
  |-- Termicap.Mouse.IO            (src/termicap-mouse-io.ads: SPARK_Mode => Off)
  |     Public:   Detect_Mouse_Protocols  : function return Mouse_Capabilities
  |               Probe_Mouse_Protocols   : function return Mouse_Capabilities
  |                                          (cache-bypass, FUNC-MSE-016 Should clause)
  |     Private:  Cache : protected object (FUNC-MSE-016)
  |               Run_Cascade : internal worker function
  |
  |     POSIX body:  src/posix/termicap-mouse-io.adb
  |         Cascade starts at guard 2 (GPM heuristic).
  |         No Win32 dependencies.
  |
  |     Windows body: src/windows/termicap-mouse-io.adb
  |         Cascade starts at guard 1 (Win32 gate).
  |         Falls through to POSIX-like cascade on Cygwin/MSYS PTY.
```

### Why two packages and not three?

The kitty-keyboard spec (§D) splits `Termicap.Keyboard` (SPARK On, types + parsers) from `Termicap.Keyboard.IO` (SPARK Off, orchestration). Mouse follows the **identical** split:

- **`Termicap.Mouse`** (SPARK On): pure types, query/mode constants, two pure functions (`Parse_Mouse_DECRPM_Response`, `Resolve_Best_Encoding`).
- **`Termicap.Mouse.IO`** (SPARK Off): `Detect_Mouse_Protocols` and `Probe_Mouse_Protocols`; protected-object cache; per-platform body files.

We deliberately **do not** introduce a third `Termicap.Mouse.Parsing` package (e.g., to mirror `Termicap.OSC.Parsing`). The justification:

1. There is exactly one parser (`Parse_Mouse_DECRPM_Response`) and one cascade (`Resolve_Best_Encoding`). Both are short (≤30 lines of body). A separate package would add noise without isolating any boundary.
2. KITTY-KB sets the precedent: three pure functions live in `Termicap.Keyboard` itself, not in a `Termicap.Keyboard.Parsing` sibling. Symmetry with KKB minimises mental overhead for future maintainers.
3. The DECRPM dependency stays one level shallow: `Termicap.Mouse` withs `Termicap.DECRPM` only; `Termicap.DECRPM.IO` is not needed in the SPARK On spec.

This gives us **three new files** (one spec + two platform bodies for `.IO`) plus the SPARK On pair (`termicap-mouse.ads` / `.adb`), for a total of five new source files. KKB has the same count.

### Dependency graph

```
Termicap.Mouse.IO (POSIX body)
  |-- Termicap.Mouse                  (types, parsers, constants)
  |-- Termicap.OSC                    (Probe_Session, Sentinel_Query, Write_Query,
  |                                    Response_Buffer, Session_Status)
  |-- Termicap.DECRPM                 (DECRPM_Query, Mode_Id, Mode_Status)
  |-- Termicap.TTY                    (Is_TTY, Stdin)
  |-- Termicap.Environment            (Value, Equal_Case_Insensitive)
  |-- Termicap.Environment.Capture    (Capture_Current)
  |-- Termicap.Terminal_Id            (Detect_Terminal_Identity, Terminal_Identity,
  |                                    Multiplexer_Kind)
  |-- Ada.Directories                 (Exists)

Termicap.Mouse.IO (Windows body)
  |-- everything from POSIX, plus:
  |-- Termicap.Win32_VT               (Is_Valid_Handle)
  |-- Win32                           (BOOL, FALSE, DWORD)
  |-- Win32.Winbase                   (GetStdHandle, STD_INPUT_HANDLE)
  |-- Win32.Wincon                    (GetConsoleMode)
  |-- Win32.Winnt                     (HANDLE)

Termicap.Mouse (spec; SPARK On)
  |-- Interfaces.C                    (unsigned_char)
  |-- Termicap.DECRPM                 (Mode_Id, Mode_Status, MAX_RESPONSE_SIZE)
                                       — strictly SPARK On dependencies only
```

### Why Termicap.Mouse withs Termicap.DECRPM (and not the other way round)

`Termicap.DECRPM` is the lower-level provider: it owns `Mode_Id` and `Mode_Status`. `Termicap.Mouse` is the consumer that **specialises** the generic DECRPM types into the mouse domain: it declares mouse-specific mode constants of type `Mode_Id` and a mouse-specific parser that returns a `Mode_Status` field. Reverse dependency would force `Termicap.DECRPM` to know about mice — incorrect layering.

This withing pattern matches `Termicap.Keyboard`'s independent `Byte_Array` declaration (cf. KKB §D paragraph 2) but goes further: we additionally with `Termicap.DECRPM` because the type `Mode_Id` (a `Natural` subtype) and the type `Mode_Status` (an enum) are stable, public, and SPARK On — withing a SPARK On package from another SPARK On package is free.

### File layout

| File | Purpose | SPARK_Mode | Approx LOC |
|------|---------|------------|------------|
| `src/termicap-mouse.ads` | Spec: types, constants, parser/cascade signatures | On | 220 |
| `src/termicap-mouse.adb` | Body: `Parse_Mouse_DECRPM_Response`, `Resolve_Best_Encoding` (locally SPARK On) | Off (package); On (locally) | 180 |
| `src/termicap-mouse-io.ads` | Spec: `Detect_Mouse_Protocols`, `Probe_Mouse_Protocols` | Off | 90 |
| `src/posix/termicap-mouse-io.adb` | POSIX body: cascade starting at GPM/TTY/foreground guards | Off | 230 |
| `src/windows/termicap-mouse-io.adb` | Windows body: cascade with Win32 gate prepended | Off | 270 |

Total new code: ~990 LOC (~310 spec, ~680 body). Test files and example are listed in §P.

---

## F. Type Design

All types in §F.1 through §F.5 are declared in `Termicap.Mouse` (SPARK_Mode => On). The cache type in §F.6 is in `Termicap.Mouse.IO` (SPARK_Mode => Off).

### F.1 `Mouse_Encoding` enumeration (FUNC-MSE-001)

```ada
--  @relation(FUNC-MSE-001)
type Mouse_Encoding is
  (Unknown,     --  Detection not performed or could not be completed
   None,        --  Probed successfully; no supported encoding found
   X10,         --  Mode 1000 recognised; modes 1006/1016 not
   URXVT,       --  Mode 1015 recognised; modes 1006/1016 not
   SGR,         --  Mode 1006 recognised; mode 1016 not
   SGR_Pixels); --  Mode 1016 recognised
```

Ordering rationale:

- `Unknown` first so default-initialised `Mouse_Encoding` variables are safely `Unknown`.
- `None` second to express "probed but nothing found" as the cleanest non-error fallback.
- The four real encodings follow in **expressive-power order**: X10 (3-byte limited range) → URXVT (decimal unlimited) → SGR (decimal unlimited + press/release distinction) → SGR_Pixels (decimal unlimited + pixel coords).

`Mouse_Encoding` represents the **best** available encoding — the result of `Resolve_Best_Encoding` (FUNC-MSE-008). It does **not** carry per-mode flag information; that is the role of the `Supports_*` Booleans in `Mouse_Capabilities`.

### F.2 `Mouse_Capabilities` record (FUNC-MSE-002)

```ada
--  @relation(FUNC-MSE-002)
type Mouse_Capabilities is record

   --  Encoding preference (derived, FUNC-MSE-008)
   Best_Encoding         : Mouse_Encoding := Unknown;
   --     The highest-preference encoding available, per the FUNC-MSE-008 cascade.
   --     Mouse_Encoding'First (Unknown) when detection was not performed.

   --  Per-mode support flags (FUNC-MSE-006)
   Supports_X10          : Boolean        := False;
   --     True when DECRPM mode 1000 was recognised (Pm /= 0).
   Supports_Button_Event : Boolean        := False;
   --     True when DECRPM mode 1002 (button-event/drag) was recognised.
   Supports_Any_Event    : Boolean        := False;
   --     True when DECRPM mode 1003 (any-motion) was recognised.
   Supports_URXVT        : Boolean        := False;
   --     True when DECRPM mode 1015 (URXVT decimal) was recognised.
   Supports_SGR          : Boolean        := False;
   --     True when DECRPM mode 1006 (SGR decimal) was recognised.
   Supports_SGR_Pixels   : Boolean        := False;
   --     True when DECRPM mode 1016 (SGR pixel) was recognised.

   --  Platform-specific flags (FUNC-MSE-010, FUNC-MSE-011)
   Win32_Console_Mouse   : Boolean        := False;
   --     True when the Win32 gate fired; mutually exclusive with probed flags.
   GPM_Available         : Boolean        := False;
   --     True when the Linux/GPM heuristic fired.

   --  Probe metadata (FUNC-MSE-002 commentary)
   Probed                : Boolean        := False;
   --     True when an active DECRPM probe sequence was attempted.
end record;

--  Canonical "no result" value (FUNC-MSE-002 final paragraph)
NO_MOUSE_CAPABILITIES : constant Mouse_Capabilities :=
  (Best_Encoding         => Unknown,
   Supports_X10          => False,
   Supports_Button_Event => False,
   Supports_Any_Event    => False,
   Supports_URXVT        => False,
   Supports_SGR          => False,
   Supports_SGR_Pixels   => False,
   Win32_Console_Mouse   => False,
   GPM_Available         => False,
   Probed                => False);
```

**Default-initialisation invariant:** all-False / `Unknown`. A `Mouse_Capabilities` declared without an aggregate is equivalent to `NO_MOUSE_CAPABILITIES`.

**Why orthogonal Booleans rather than a discriminated record or a set?** See ADR-0025. Summary: SPARK provability and forward extensibility (adding mode 1004 = focus events would be a single field addition).

**Implicit invariants** (not enforced via `Type_Invariant` aspect — see §F.3 for why):

- *I1.* `Win32_Console_Mouse = True` implies all `Supports_* = False` and `Best_Encoding = Unknown` and `Probed = False`. Enforced by the constructor `Make_Win32_Capabilities` in the Windows body (not as a type predicate, to avoid SPARK proof complexity at the contract boundary of the Windows-only `Make_*` helper).
- *I2.* `GPM_Available = True` implies all `Supports_* = False` and `Best_Encoding = Unknown` and `Probed = False`. Enforced by the GPM-guard branch of `Run_Cascade`.
- *I3.* `Probed = False` implies `Best_Encoding = Unknown`. Enforced by the post-cascade assembly in `Run_Cascade`.
- *I4.* `Probed = True` implies `Best_Encoding = Resolve_Best_Encoding (Self)`. Enforced by the cascade call site in `Run_Cascade`.

### F.3 SPARK predicates considered and rejected

A `Type_Invariant` such as

```ada
type Mouse_Capabilities is record
   ...
end record
   with Type_Invariant => not Win32_Console_Mouse
                          or else (not Supports_X10 and not Supports_Button_Event
                                   and ...);
```

was considered. **Rejected** because:

1. `Type_Invariant` aspects on records with non-tagged components, when used inside a SPARK_Mode On package whose values cross into a SPARK_Mode Off package (`Termicap.Mouse.IO`), provoke SPARK boundary violations that GNATprove flags as `assume` chains.
2. The invariant constraints would force every record-aggregate update site (e.g., the Win32 short-circuit, the GPM short-circuit, the post-cascade assembly) to prove the invariant locally — adding 3+ lemmas per call site for no runtime benefit.
3. The mixed-SPARK pattern documented in ADR-0013 prefers explicit construction discipline (constructor helpers in the body) over type-level invariants for records that cross the SPARK boundary.

Instead, the body uses three **named constructor functions** (none exposed in the public spec):

```ada
--  Body of Termicap.Mouse.IO (Windows body):
function Make_Win32_Result return Mouse_Capabilities is
  ((Best_Encoding       => Unknown,
    Win32_Console_Mouse => True,
    others              => <False>));

--  Body of Termicap.Mouse.IO (POSIX body):
function Make_GPM_Result return Mouse_Capabilities is
  ((Best_Encoding => Unknown,
    GPM_Available => True,
    others        => <False>));

function Make_Probed_Result
  (Caps : Mouse_Capabilities) return Mouse_Capabilities
is
   Result : Mouse_Capabilities := Caps;
begin
   Result.Probed        := True;
   Result.Best_Encoding := Resolve_Best_Encoding (Result);
   return Result;
end Make_Probed_Result;
```

These helpers ensure I1–I4 hold by construction. They are **internal** to each body file (no spec); they do not appear in the public API.

### F.4 `DECRPM_Parse_Result` record (FUNC-MSE-007)

```ada
--  @relation(FUNC-MSE-007)
type DECRPM_Parse_Result is record
   Valid  : Boolean     := False;
   Mode   : Mode_Id     := 0;
   Status : Mode_Status := Not_Recognized;
end record;
```

Used as the return type of `Parse_Mouse_DECRPM_Response`. Invariant (not enforced via aspect, see §F.3 rationale): `not Valid implies (Mode = 0 and Status = Not_Recognized)`.

### F.5 Mode constants and timeout (FUNC-MSE-003, FUNC-MSE-013)

```ada
--  @relation(FUNC-MSE-003)
MODE_MOUSE_X10            : constant Mode_Id := 1000;
MODE_MOUSE_BUTTON_EVENT   : constant Mode_Id := 1002;
MODE_MOUSE_ANY_EVENT      : constant Mode_Id := 1003;
MODE_MOUSE_URXVT          : constant Mode_Id := 1015;
MODE_MOUSE_SGR            : constant Mode_Id := 1006;
MODE_MOUSE_SGR_PIXELS     : constant Mode_Id := 1016;

--  @relation(FUNC-MSE-013)
MOUSE_PROBE_TIMEOUT_MS    : constant Natural := 1000;

--  Maximum response buffer size used in parser preconditions
--  (re-export of Termicap.DECRPM.MAX_RESPONSE_SIZE for SPARK On boundary clarity)
MAX_RESPONSE_SIZE         : constant := Termicap.DECRPM.MAX_RESPONSE_SIZE;
```

All constants follow `ALL_CAPS_WITH_UNDERSCORES` per the project coding standard. The mode constants are typed as `Termicap.DECRPM.Mode_Id` to interoperate seamlessly with `DECRPM_Query`. `MOUSE_PROBE_TIMEOUT_MS` is a `Natural` to interoperate with `Sentinel_Query`'s `Timeout_Ms` parameter; it is named with a `_MS` suffix to make the unit explicit at every call site.

The **timeout choice of 1000 ms** matches FUNC-MSE-013 and aligns with the OSC-INFRA convention (`FUNC-OSC-004` comment) and the per-probe budget for KITTY-KB (FUNC-KKB-013). Justification vs. lower defaults (e.g., the 100–200 ms used by `Detect_DA1` and `Detect_Mode`):

- The mouse probe is one **batched** session containing six DECRPM round-trips; a 200 ms budget would average <33 ms per mode under good conditions and risk truncating the batch on a slow SSH link.
- 1000 ms is the same budget KKB uses per probe; KKB issues two probes (worst case 2 s); we issue one batch (worst case 1 s). MOUSE has lower worst-case latency than KKB.
- The implementation **may** lower the timeout to a minimum of 100 ms on local PTYs (FUNC-MSE-013 final paragraph). v1 ships with the conservative 1000 ms; an optimisation pass may revisit.

### F.6 Cache type (FUNC-MSE-016) — body of `Termicap.Mouse.IO`

```ada
--  Internal: protected-object cache; identical shape to
--  Termicap.Keyboard.IO.Cache (FUNC-KKB-017).

type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Mouse_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_MOUSE_CAPABILITIES);
end Cache;
```

The cache is identical to KKB's; ADR-0012 (capability cache design) governs.

### Public spec contracts

```ada
--  @relation(FUNC-MSE-007)
function Parse_Mouse_DECRPM_Response
  (Buffer : Byte_Array;
   Length : Natural) return DECRPM_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE,
  Post       => (if not Parse_Mouse_DECRPM_Response'Result.Valid
                 then Parse_Mouse_DECRPM_Response'Result.Mode = 0);

--  @relation(FUNC-MSE-008)
function Resolve_Best_Encoding
  (Caps : Mouse_Capabilities) return Mouse_Encoding
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => True,
  Post       =>
    (if not Caps.Probed
     then Resolve_Best_Encoding'Result = Unknown)
    and then
    (if Caps.Probed and Caps.Supports_SGR_Pixels
     then Resolve_Best_Encoding'Result = SGR_Pixels)
    and then
    (if Caps.Probed and not Caps.Supports_SGR_Pixels and Caps.Supports_SGR
     then Resolve_Best_Encoding'Result = SGR);
--  Postcondition is partial; remaining cascade levels are tested rather than proved.
--  Strengthening to a full case-analysis postcondition is a future Gold-level pass.
```

`Byte` and `Byte_Array` are re-declared in `Termicap.Mouse` as subtypes of `Interfaces.C.unsigned_char` and `array (Positive range <>) of Byte`, matching the representation-compatible convention already used by `Termicap.DA1`, `Termicap.XTVERSION`, `Termicap.Keyboard`, and `Termicap.DECRPM`. This lets `Termicap.Mouse.IO` convert between `Termicap.OSC.Byte_Array`, `Termicap.DECRPM.Byte_Array`, and `Termicap.Mouse.Byte_Array` via direct array-conversion (zero copy) at the I/O boundary.

---

## G. Detection Algorithm — Step by Step

### G.1 Cascade overview (FUNC-MSE-009)

```
function Detect_Mouse_Protocols return Mouse_Capabilities is
   ...
   if cached then return cached.Value;
   Result := Run_Cascade;
   Cache.Set_Cached (Result);
   return Result;
exception
   when others => return NO_MOUSE_CAPABILITIES;  --  FUNC-MSE-014
end;

function Run_Cascade return Mouse_Capabilities is
begin
   --  Guard 1: Win32 platform gate (Windows body only; FUNC-MSE-010)
   #if Platform = Windows then
      H := GetStdHandle (STD_INPUT_HANDLE);
      if Is_Valid_Handle (H) then
         Mode := 0;
         if GetConsoleMode (H, Mode'Access) /= FALSE then
            return Make_Win32_Result;  --  Win32_Console_Mouse=True
         end if;
      end if;
   #end if;

   --  Guard 2: Linux/GPM heuristic (POSIX path; FUNC-MSE-011)
   if Is_Linux_Console_With_GPM then
      return Make_GPM_Result;          --  GPM_Available=True
   end if;

   --  Guard 3: TTY guard (FUNC-MSE-009 step 3)
   if not Termicap.TTY.Is_TTY (Termicap.TTY.Stdin) then
      return NO_MOUSE_CAPABILITIES;    --  Probed=False
   end if;

   --  Guards 4 & 5: foreground + /dev/tty open (FUNC-MSE-009 steps 4-5;
   --  composed inside Probe_Session.Open per FUNC-OSC-007/008)
   Open (Session, Status);
   if Status /= Session_OK then
      return NO_MOUSE_CAPABILITIES;
   end if;

   --  Batched DECRPM probe (FUNC-MSE-005, FUNC-MSE-004)
   Caps := Run_Batched_DECRPM_Probe (Session);

   --  Probe session closes via RAII Finalize (FUNC-MSE-015)
   return Make_Probed_Result (Caps);
end Run_Cascade;
```

The Win32 gate is **compile-time absent** in the POSIX body (per ADR-0018 platform dispatch via source dirs). The POSIX body's `Run_Cascade` starts directly at guard 2.

### G.2 GPM heuristic helper (POSIX body)

```ada
function Is_Linux_Console_With_GPM return Boolean is
   Env : Termicap.Environment.Environment;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   if not Termicap.Environment.Equal_Case_Insensitive
            (Termicap.Environment.Value (Env, "TERM"), "linux")
   then
      return False;
   end if;

   declare
      Exists : Boolean := False;
   begin
      Exists := Ada.Directories.Exists ("/dev/gpmctl");
      return Exists;
   exception
      when others =>
         --  FUNC-MSE-014: Ada.Directories.Exists may raise on symlink loops
         --  or unusual /dev configurations; treat as "file absent".
         return False;
   end;
exception
   when others =>
      --  Belt-and-braces: any environment-capture failure means we cannot
      --  prove GPM availability; fall through to the DECRPM probe path.
      return False;
end Is_Linux_Console_With_GPM;
```

On the **Windows body**, this helper is **absent** (compile-time): the GPM heuristic is meaningless on Windows, and the function declaration would force a `with Ada.Directories` and `with Termicap.Environment` for no benefit. The Windows body's `Run_Cascade` skips guard 2 entirely.

### G.3 The batched DECRPM probe (FUNC-MSE-004, FUNC-MSE-005)

```ada
function Run_Batched_DECRPM_Probe
  (Session : in out Termicap.OSC.Probe_Session) return Mouse_Capabilities
is
   --  Per FUNC-MSE-004, queries are issued in this fixed order.
   --  Order does NOT affect parsing (responses are matched by Ps).
   Modes : constant array (1 .. 6) of Termicap.DECRPM.Mode_Id :=
     (MODE_MOUSE_X10,
      MODE_MOUSE_BUTTON_EVENT,
      MODE_MOUSE_ANY_EVENT,
      MODE_MOUSE_URXVT,
      MODE_MOUSE_SGR,
      MODE_MOUSE_SGR_PIXELS);

   Caps        : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
   Resp_Buffer : Termicap.OSC.Response_Buffer;
   Resp_Length : Natural := 0;
   Timed_Out   : Boolean := False;
   Written     : Natural;
   Write_OK    : Boolean;
begin
   --  Phase 1: Write all six DECRPM queries to the FD.
   --  We do NOT use Sentinel_Query for each query individually; instead we
   --  write the queries with Write_Query and let Sentinel_Query handle
   --  the DA1 sentinel + read loop for the entire batch.
   for I in Modes'Range loop
      declare
         Q : constant Termicap.DECRPM.Byte_Array :=
           Termicap.DECRPM.DECRPM_Query (Modes (I));
      begin
         Termicap.OSC.Write_Query
           (Session => Session,
            Query   => Termicap.OSC.Byte_Array (Q),
            Written => Written,
            Success => Write_OK);
         if not Write_OK then
            --  Partial write or write error: bail out without sending the
            --  remaining queries. Caps stays at NO_MOUSE_CAPABILITIES with
            --  Probed=False; the calling Run_Cascade returns Unknown.
            return NO_MOUSE_CAPABILITIES;
         end if;
      end;
   end loop;

   --  Phase 2: Single Sentinel_Query call with an EMPTY query argument so
   --  that Sentinel_Query writes ONLY the DA1 sentinel and then enters its
   --  read loop.  Sentinel_Query accumulates every byte received until
   --  the DA1 response pattern terminates the read.
   Termicap.OSC.Sentinel_Query
     (Session     => Session,
      Query       => Empty_Query_Bytes,
      Response    => Resp_Buffer,
      Resp_Length => Resp_Length,
      Timeout_Ms  => MOUSE_PROBE_TIMEOUT_MS,
      Timed_Out   => Timed_Out,
      Retry       => False);

   if Timed_Out and then Resp_Length = 0 then
      --  FUNC-MSE-013: total timeout, no usable data.
      return NO_MOUSE_CAPABILITIES;
   end if;

   --  Phase 3: Scan the accumulated buffer for DECRPM frames and update Caps.
   Caps := Parse_All_Responses (Resp_Buffer, Resp_Length);
   return Caps;
end Run_Batched_DECRPM_Probe;
```

**`Empty_Query_Bytes`** is a zero-length local constant of type `Termicap.OSC.Byte_Array`. `Termicap.OSC.Sentinel_Query` writes its `Query` argument followed by the DA1 sentinel; passing an empty array causes only the DA1 sentinel to be written. This is the existing-API-friendly way to express "send only the sentinel" without modifying `Sentinel_Query`.

**Why two phases (`Write_Query` + `Sentinel_Query` with empty query) instead of one?** Because `Sentinel_Query` writes its `Query` argument **once**. We need to write **six** different queries before the sentinel. The existing API does not have a "write multiple queries then sentinel-read" entry point, but it does have:

- `Write_Query` (FUNC-OSC-005) — writes arbitrary bytes to the FD without read.
- `Sentinel_Query` (FUNC-OSC-006) — writes its `Query` + DA1 + reads until DA1 response.

The composition `Write_Query × 6 + Sentinel_Query (empty, ...)` reuses both APIs cleanly and **does not require modifying `Termicap.OSC`**. This is a load-bearing reuse decision: it keeps OSC-INFRA stable and lets the mouse feature ship without any spec-level changes to a Tier 3 package.

The alternative — extending `Sentinel_Query` with a `Pre_Write : Byte_Array` parameter or a `Sentinel_Read` procedure — was considered and rejected as scope creep (would require an OSC-INFRA spec amendment, an ADR, and updates to existing call sites).

### G.4 Parsing the interleaved response stream (FUNC-MSE-006, FUNC-MSE-007)

The accumulated `Resp_Buffer (1 .. Resp_Length)` may contain up to six DECRPM responses (`CSI ? Ps ; Pm $ y`) in arbitrary order, possibly interleaved with stray bytes from the terminal (notably from the multiplexer transparency layer). The state machine for `Parse_All_Responses`:

```
function Parse_All_Responses
  (Buf  : Termicap.OSC.Response_Buffer;
   Len  : Natural) return Mouse_Capabilities
is
   Caps : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
   I    : Positive := Buf'First;
   --  Local rebind for the SPARK-On parser
   Slice : constant Termicap.Mouse.Byte_Array :=
     Termicap.Mouse.Byte_Array (Buf (Buf'First .. Buf'First + Len - 1));
begin
   while I <= Len loop
      --  Find next ESC (0x1B); skip non-ESC bytes (defensive).
      while I <= Len and then Slice (I) /= 16#1B# loop
         I := I + 1;
      end loop;
      exit when I > Len - 6;  --  Minimum DECRPM frame is 7 bytes; if fewer
                              --  bytes remain, no frame can match.

      --  Try to parse a single DECRPM frame starting at I.
      declare
         Tail   : constant Termicap.Mouse.Byte_Array :=
           Slice (I .. Len);
         Result : constant DECRPM_Parse_Result :=
           Parse_Mouse_DECRPM_Response (Tail, Tail'Length);
      begin
         if Result.Valid then
            Apply_Mode_Status (Caps, Result.Mode, Result.Status);
            --  Skip past the parsed frame.  Length is recoverable from
            --  the DECRPM grammar: ESC [ ? <digits>+ ; <digit> $ y, but
            --  for simplicity we re-scan for the next ESC starting at I+1.
            I := I + 1;
         else
            --  Not a DECRPM frame at this position; advance one byte and
            --  re-scan.  Worst case is O(N) over the buffer length.
            I := I + 1;
         end if;
      end;
   end loop;
   return Caps;
end Parse_All_Responses;

procedure Apply_Mode_Status
  (Caps   : in out Mouse_Capabilities;
   Mode   : Termicap.DECRPM.Mode_Id;
   Status : Termicap.DECRPM.Mode_Status)
is
   Supported : constant Boolean := Status /= Termicap.DECRPM.Not_Recognized;
begin
   case Mode is
      when MODE_MOUSE_X10          => Caps.Supports_X10          := Supported;
      when MODE_MOUSE_BUTTON_EVENT => Caps.Supports_Button_Event := Supported;
      when MODE_MOUSE_ANY_EVENT    => Caps.Supports_Any_Event    := Supported;
      when MODE_MOUSE_URXVT        => Caps.Supports_URXVT        := Supported;
      when MODE_MOUSE_SGR          => Caps.Supports_SGR          := Supported;
      when MODE_MOUSE_SGR_PIXELS   => Caps.Supports_SGR_Pixels   := Supported;
      when others => null;  --  Unrecognised mode in the response; ignore.
   end case;
end Apply_Mode_Status;
```

**Parsing complexity** is `O (Len)` because the outer loop advances by at least one byte per iteration. With `Len` bounded by `MAX_RESPONSE_SIZE = 4096`, this is trivially fast (microseconds). No allocation occurs; all buffers are stack-resident.

**`Parse_Mouse_DECRPM_Response` body** (declared in §F):

```ada
function Parse_Mouse_DECRPM_Response
  (Buffer : Byte_Array;
   Length : Natural) return DECRPM_Parse_Result
is
begin
   --  Delegate the bulk of the work to Termicap.DECRPM.Parse_DECRPM_Response,
   --  but carry the Valid flag explicitly via the Mode > 0 check.
   if Length < 7 then
      return (Valid => False, Mode => 0, Status => Not_Recognized);
   end if;
   declare
      DECRPM_Buffer : constant Termicap.DECRPM.Byte_Array :=
        Termicap.DECRPM.Byte_Array (Buffer);
      Report : constant Termicap.DECRPM.Mode_Report :=
        Termicap.DECRPM.Parse_DECRPM_Response (DECRPM_Buffer, Length);
   begin
      if Report.Mode = 0 then
         return (Valid => False, Mode => 0, Status => Not_Recognized);
      else
         return (Valid => True, Mode => Report.Mode, Status => Report.Status);
      end if;
   end;
end Parse_Mouse_DECRPM_Response;
```

This composes Termicap.DECRPM's already-proven SPARK Silver parser. The mouse parser adds only the boolean `Valid` flag and the type adaptation — both pure operations.

### G.5 Exact byte sequences sent and parsed

**Sent during the batched probe** (Phase 1 in §G.3, then Phase 2 sentinel write):

```
ESC [ ? 1 0 0 0 $ p   (8 bytes; MODE_MOUSE_X10)
ESC [ ? 1 0 0 2 $ p   (8 bytes; MODE_MOUSE_BUTTON_EVENT)
ESC [ ? 1 0 0 3 $ p   (8 bytes; MODE_MOUSE_ANY_EVENT)
ESC [ ? 1 0 1 5 $ p   (8 bytes; MODE_MOUSE_URXVT)
ESC [ ? 1 0 0 6 $ p   (8 bytes; MODE_MOUSE_SGR)
ESC [ ? 1 0 1 6 $ p   (8 bytes; MODE_MOUSE_SGR_PIXELS)
ESC [ c               (3 bytes; DA1 sentinel, written by Sentinel_Query)
                                                         ─────
                                                         51 bytes total
```

**Expected response** (best case, fully-supporting terminal):

```
ESC [ ? 1 0 0 0 ; 2 $ y   (Reset; supported)
ESC [ ? 1 0 0 2 ; 2 $ y   (Reset; supported)
ESC [ ? 1 0 0 3 ; 2 $ y   (Reset; supported)
ESC [ ? 1 0 1 5 ; 0 $ y   (Not_Recognized; URXVT not supported)
ESC [ ? 1 0 0 6 ; 2 $ y   (Reset; supported)
ESC [ ? 1 0 1 6 ; 2 $ y   (Reset; supported)
ESC [ ? 6 5 ; 1 ; ... c   (DA1 response; sentinel)
```

Order may be permuted by the terminal. Some modes may be omitted entirely (terminals not supporting `1015` may simply not emit a response for that Ps). The parser handles all cases.

---

## H. Cascade Resolution

### H.1 `Resolve_Best_Encoding` — pure SPARK function (FUNC-MSE-008)

```ada
function Resolve_Best_Encoding
  (Caps : Mouse_Capabilities) return Mouse_Encoding
is
begin
   if not Caps.Probed then
      return Unknown;
   elsif Caps.Supports_SGR_Pixels then
      return SGR_Pixels;
   elsif Caps.Supports_SGR then
      return SGR;
   elsif Caps.Supports_URXVT then
      return URXVT;
   elsif Caps.Supports_X10 then
      return X10;
   else
      return None;
   end if;
end Resolve_Best_Encoding;
```

Pure, no I/O, no globals. SPARK Silver provable. Cyclomatic complexity = 6.

### H.2 Cascade truth table

The cascade depends on five Booleans (`Probed`, `Supports_SGR_Pixels`, `Supports_SGR`, `Supports_URXVT`, `Supports_X10`). The full truth table:

| Probed | SGR_Pixels | SGR | URXVT | X10 | Best_Encoding |
|--------|------------|-----|-------|-----|---------------|
| F | * | * | * | * | `Unknown` |
| T | T | * | * | * | `SGR_Pixels` |
| T | F | T | * | * | `SGR` |
| T | F | F | T | * | `URXVT` |
| T | F | F | F | T | `X10` |
| T | F | F | F | F | `None` |

`*` denotes "don't care". The `Supports_Button_Event` and `Supports_Any_Event` flags are deliberately **not** inputs to the cascade (the encoding choice is orthogonal to the tracking-mode choice; an application that needs drag events checks `Supports_Button_Event` directly).

### H.3 Postconditions

The contract spec in §F includes three positive conjuncts of the cascade:

```ada
Post =>
   (if not Caps.Probed                     then Result = Unknown)
   and then (if Caps.Probed and Caps.Supports_SGR_Pixels
                                            then Result = SGR_Pixels)
   and then (if Caps.Probed and not Caps.Supports_SGR_Pixels and Caps.Supports_SGR
                                            then Result = SGR);
```

The remaining cascade levels (URXVT, X10, None) are tested via unit vectors (§N) rather than proved by postcondition. This is the same pragmatic Silver-not-Gold posture taken by `Parse_Kitty_Response` and `Contains_DECRPM_Response`. Strengthening the postcondition to a full case analysis is a future Gold-level pass.

### H.4 Why this cascade order? (ADR-0023)

`SGR_Pixels > SGR > URXVT > X10 > None` is the **expressive-power-descending** order:

- **SGR-Pixels (1016)** is the only encoding that returns pixel coordinates (useful for image-aware TUIs and graphical click-to-select on embedded images).
- **SGR (1006)** is the modern decimal encoding with explicit press/release distinction (`M` vs `m`) and unlimited coordinate range.
- **URXVT (1015)** has unlimited coordinate range but no press/release distinction in the wire format. Strictly inferior to SGR but strictly superior to X10.
- **X10 (1000)** has a 222-cell coordinate ceiling and a 3-byte raw-byte encoding that breaks on `\xff` bytes. Last-resort.
- **None** signals "no usable encoding"; the application should not enable mouse tracking.

ADR-0023 explores the alternatives (rejected reverse cascade; rejected including 1002/1003 in the cascade; rejected user-override hook for v1).

---

## I. Platform Gating

### I.1 Win32 Console (no PTY) — guard 1

The Windows body's Win32 gate is the **first** check in `Run_Cascade`:

```ada
H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_INPUT_HANDLE);
if Termicap.Win32_VT.Is_Valid_Handle (H) then
   Mode := 0;
   Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
   if Res /= Win32.FALSE then
      return Make_Win32_Result;  --  Win32_Console_Mouse=True
   end if;
end if;
--  Fall through to POSIX-like cascade for Cygwin/MSYS PTY case.
```

`Termicap.Win32_VT.Is_Valid_Handle` (already used by KKB Windows body) returns False for `INVALID_HANDLE_VALUE` and null handles, satisfying the defensive-programming requirement of FUNC-MSE-014 ("GetConsoleMode raises on Windows (treated as gate-not-fired)").

`Make_Win32_Result` is the body-private constructor introduced in §F.3:

```ada
function Make_Win32_Result return Mouse_Capabilities is
  ((Best_Encoding         => Unknown,
    Win32_Console_Mouse   => True,
    Supports_X10          => False,
    Supports_Button_Event => False,
    Supports_Any_Event    => False,
    Supports_URXVT        => False,
    Supports_SGR          => False,
    Supports_SGR_Pixels   => False,
    GPM_Available         => False,
    Probed                => False));
```

Per the requirement, when `Win32_Console_Mouse = True`:

- All `Supports_*` are False (the Windows Console emits `MOUSE_INPUT_RECORD`s through `ReadConsoleInput`, not DECRPM-style data).
- `Best_Encoding = Unknown` (the caller must use the Windows Console API).
- `Probed = False` (no DECRPM probe was attempted).

### I.2 Cygwin / MSYS2 — POSIX path

When `GetConsoleMode` returns FALSE on Windows, stdin is one of:

- A Cygwin/MSYS2 PTY (real PTY semantics, accepts and emits VT escape sequences correctly via `mintty`).
- A pipe or file (no DECRPM support).

The Win32 gate **falls through** to the POSIX-like cascade (guards 2–5). Cygwin/MSYS2 PTYs are caught by `Termicap.TTY.Is_TTY (Stdin)` returning True (via the Cygwin branch documented in `cygwin-pty.md`); pipes and files are caught returning False, exiting at guard 3 with `Unknown`. This matches the keyboard cascade exactly (KKB §M, ADR-0020). Since we share the OSC-INFRA Probe_Session with the keyboard feature, the mintty PTY's response handling is already validated.

### I.3 Linux console (TERM=linux + /dev/gpmctl) — guard 2

`Is_Linux_Console_With_GPM` (§G.2) lives in the **POSIX body only** (`src/posix/termicap-mouse-io.adb`). It is **absent from the Windows body**: the GPM heuristic is meaningless on Windows and would force the Windows body to with `Ada.Directories` for no reason.

When the heuristic fires (`TERM=linux` and `Ada.Directories.Exists ("/dev/gpmctl")`):

- `GPM_Available = True`
- `Best_Encoding = Unknown`
- All `Supports_* = False`
- `Probed = False`

Caller uses this signal to either link `libgpm` (out of scope for Termicap; this library detects, never imports `libgpm`) or display a user-facing message ("mouse on Linux console requires GPM"). The decision to detect availability via existence-check rather than `Gpm_Open` is documented in ADR-0024.

When `TERM=linux` but `/dev/gpmctl` does not exist: GPM is not running. The cascade falls through to guard 3, runs the DECRPM probe, expects all responses to be `Not_Recognized` (Linux console does not implement DECRPM), and returns `Best_Encoding = None` after the timeout drains.

### I.4 BSD console

BSDs (FreeBSD, OpenBSD, NetBSD) do **not** ship GPM. The `TERM` value on their text consoles is typically `cons25`, `wsvt25`, or similar — never `"linux"`. The GPM heuristic does not fire; the cascade proceeds to the DECRPM probe and returns `Best_Encoding = None` after the timeout drains. This is the correct fallback: BSD consoles support a non-GPM mouse model that is outside the scope of this feature.

### I.5 Platform behaviour summary

| Platform | Guard 1 (Win32) | Guard 2 (GPM) | Guard 3 (TTY) | Guard 4 (foreground) | Guard 5 (/dev/tty) | Result |
|----------|----------------|---------------|---------------|----------------------|--------------------|--------|
| Linux desktop terminal (xterm, gnome-terminal, kitty, alacritty) | skipped | not Linux console | passes | passes | opens | DECRPM-probed encoding |
| Linux text console (TTY) + GPM running | skipped | **fires** | — | — | — | `GPM_Available = True` |
| Linux text console (TTY) without GPM | skipped | does not fire (no socket) | passes | passes | opens | `Best_Encoding = None` after timeout |
| macOS Terminal.app | skipped | n/a | passes | passes | opens | `Best_Encoding = SGR` (no SGR-Pixels) |
| macOS iTerm2 | skipped | n/a | passes | passes | opens | `Best_Encoding = SGR_Pixels` |
| BSD desktop terminal | skipped | n/a | passes | passes | opens | DECRPM-probed encoding |
| BSD text console | skipped | n/a (TERM /= linux) | passes | passes | opens | `Best_Encoding = None` after timeout |
| Windows Terminal / conhost | **fires** | — | — | — | — | `Win32_Console_Mouse = True` |
| Windows + git-bash / MSYS2 (Cygwin PTY) | does not fire | n/a | passes (Cygwin branch) | passes | opens | DECRPM-probed encoding |
| Windows + redirected stdin | does not fire (pipe) | n/a | fails | — | — | `Unknown`, `Probed=False` |
| Linux + redirected stdin | skipped | depends on TERM | fails | — | — | `Unknown`, `Probed=False` |
| Linux + background job | skipped | depends on TERM | passes | fails (foreground guard) | — | `Unknown`, `Probed=False` |

---

## J. Multiplexer Behaviour

### J.1 Strategy (a) — probe regardless, accept partial results (FUNC-MSE-012)

Per FUNC-MSE-012, v1 adopts strategy (a): the cascade attempts the DECRPM probe regardless of multiplexer presence. Whatever the multiplexer reports is what the caller receives.

**Why:**

- tmux: Recent tmux versions (3.2+) implement DECRPM and respond with their own mouse-mode state. The response reflects what tmux supports (commonly `1000`, `1002`, `1003`, `1006`); modes the outer terminal supports but tmux does not are not advertised. Acceptable for callers that interact with the tmux mouse model (which is the typical case).
- screen: GNU screen does not implement DECRPM. The probe times out (1000 ms) and the cascade returns `Best_Encoding = None`. The application can still send mouse-enable DECSETs blindly; they are passed through to the inner shell.

### J.2 Diagnostic flag

The result record `Mouse_Capabilities` does **not** include a "multiplexer present" Boolean. Multiplexer detection is the orthogonal responsibility of `Termicap.Terminal_Id`; the mouse feature does not duplicate it. Callers that need to know "did this Mouse_Capabilities come from inside tmux?" call:

```ada
declare
   Env      : Termicap.Environment.Environment;
   Identity : Termicap.Terminal_Id.Terminal_Identity;
begin
   Termicap.Environment.Capture.Capture_Current (Env);
   Identity := Termicap.Terminal_Id.Detect_Terminal_Identity (Env);
   if Identity.Kind in Termicap.Terminal_Id.Multiplexer_Kind then
      Put_Line ("Note: mouse capabilities reflect tmux/screen, not the outer terminal.");
   end if;
end;
```

This composes cleanly with the existing TERM-ID API and keeps `Mouse_Capabilities` focused on mouse state.

### J.3 DCS passthrough — deferred

DCS passthrough (strategy b) — wrapping each DECRPM query in a `DCS tmux; ... ST` envelope so the outer terminal receives and responds — is a **known limitation** for v1. The infrastructure exists in `Termicap.OSC.Parsing.Wrap_For_Passthrough` (used by `XTVERSION` and `BG-COLOR`), but for DECRPM specifically the passthrough wrapping is not standardised across tmux/screen versions and would require additional probing of the multiplexer's capability — turning a one-batch session into a multi-stage probe. Deferred to a future feature; tracked via FUNC-MSE-012's last paragraph.

---

## K. Timeout & Partial Response

### K.1 Timeout machinery — reuse `Sentinel_Query`

`Sentinel_Query` (FUNC-OSC-006) implements the deadline. We pass `Timeout_Ms => MOUSE_PROBE_TIMEOUT_MS` (1000 ms) to a single call covering the entire batched read. No per-mode sub-timeout is needed: the DA1 sentinel is the natural batch terminator, and a fast terminal answers the whole batch in <50 ms; a slow or non-responsive terminal trips the 1000 ms ceiling.

### K.2 Partial response handling (FUNC-MSE-013 second paragraph)

**Total timeout** (no DA1 received, `Resp_Length = 0`):

- `Timed_Out = True` and `Resp_Length = 0` after `Sentinel_Query`.
- Return `NO_MOUSE_CAPABILITIES` from `Run_Batched_DECRPM_Probe` (i.e., `Best_Encoding = Unknown`, `Probed = False`).
- The outer cascade returns this directly.

**Partial response** (DA1 sentinel arrived but only some DECRPM responses):

- `Timed_Out = False` (or `True` with `Resp_Length > 0` if implementation chooses to reject ambiguous timeouts; per FUNC-MSE-013 we accept whatever bytes arrived).
- `Parse_All_Responses` populates only those `Supports_*` flags whose responses were received. The rest stay `False` (which is the correct interpretation of "the terminal did not advertise this mode").
- Return `Make_Probed_Result (Caps)` — `Probed = True`, `Best_Encoding = Resolve_Best_Encoding (Caps)`.

This means a terminal that responds for `1000`, `1002`, `1006` but is interrupted before responding for `1015`, `1016` yields `Best_Encoding = SGR` (not SGR_Pixels) — consistent with the cascade.

**Edge case**: The accumulated buffer contains bytes that **look** like DECRPM responses but are actually unrelated (e.g., a stray mouse-event from a misbehaving terminal). `Parse_Mouse_DECRPM_Response` requires the exact `ESC [ ? <digits>+ ; <digit> $ y` pattern; mismatches return `Valid = False` and the byte is skipped. False-positive risk is negligible.

### K.3 Why 1000 ms (not OSC-INFRA's lower default)?

`OSC-INFRA`'s default per-query timeout (FUNC-OSC-004 comment) is application-dependent. `Detect_DA1` uses 100 ms. `Detect_Mode` uses 100 ms. `Detect_Modes` uses 200 ms total split across N modes.

Mouse probing is the **batched** equivalent of `Detect_Modes (six modes, 200 ms / 6 = 33 ms per mode)` — but with a single sentinel-bounded read instead of six. The 33 ms per-mode budget would fail on slow SSH links. We allocate 1000 ms for the entire batch, matching the KKB per-probe budget and giving the terminal up to 167 ms per mode on average. Justified per FUNC-MSE-013.

---

## L. Error Handling

### L.1 Failure-mode catalogue (FUNC-MSE-014)

Every failure mode listed in FUNC-MSE-014, with the catch location and the resulting return value:

| Failure mode | Catch location | `Mouse_Capabilities` returned |
|--------------|----------------|--------------------------------|
| `/dev/tty` unopenable | `Probe_Session.Open` returns `Session_No_Terminal` | `NO_MOUSE_CAPABILITIES` (`Best_Encoding = Unknown`, `Probed = False`) |
| `tcgetattr` fails | `Open` returns `Session_Save_Failed` | `NO_MOUSE_CAPABILITIES` |
| `tcsetattr` fails | `Open` returns `Session_Raw_Failed` | `NO_MOUSE_CAPABILITIES` |
| `Write_Query` returns `Success = False` for any DECRPM query | Phase 1 of `Run_Batched_DECRPM_Probe` returns early | `NO_MOUSE_CAPABILITIES` (Probed=False) |
| `Write_Query` returns `Success = False` for the DA1 sentinel | `Sentinel_Query` sets `Timed_Out := True`, `Resp_Length := 0` | `NO_MOUSE_CAPABILITIES` |
| Total timeout (no DA1, no usable bytes) | `Sentinel_Query` returns `Timed_Out=True, Resp_Length=0` | `NO_MOUSE_CAPABILITIES` |
| Garbled response (no DECRPM frame in the buffer) | `Parse_All_Responses` returns `NO_MOUSE_CAPABILITIES` with `Probed=False` already set; `Make_Probed_Result` then sets `Probed=True, Best_Encoding=None` | `(Probed=True, Best_Encoding=None, all Supports_*=False)` |
| Partial garbled (some valid frames, others garbled) | Valid frames update `Supports_*`; garbled bytes are skipped | Partial `Mouse_Capabilities`; `Probed=True`; `Best_Encoding` per cascade |
| EINTR/EAGAIN during read | `Termicap.OSC.Timed_Read` retries internally (FUNC-OSC-004 invariant) | (no impact; `Sentinel_Query` continues until timeout or DA1) |
| `Restore_Termios` fails | `Probe_Session.Close` swallows the failure (per FUNC-OSC-002); cascade continues | (no impact on result) |
| `Ada.Directories.Exists` raises (symlink loop, permission denied on /dev) | Local `exception when others => return False` in `Is_Linux_Console_With_GPM` | GPM heuristic does not fire; cascade falls through to DECRPM probe |
| `GetConsoleMode` raises (Windows) | Outer `when others` in `Detect_Mouse_Protocols` | `NO_MOUSE_CAPABILITIES` |
| `Termicap.Environment.Capture.Capture_Current` raises | Wrapped in the GPM helper's `exception when others`; cascade falls through | (handled; no impact on result) |
| Null/invalid file descriptor | `Probe_Session.Open` returns `Session_No_Terminal` | `NO_MOUSE_CAPABILITIES` |
| Any unanticipated exception in the cascade | Outer `when others` in `Detect_Mouse_Protocols` and `Probe_Mouse_Protocols` | `NO_MOUSE_CAPABILITIES` |

### L.2 Outer exception handler

Both public functions in `Termicap.Mouse.IO` wrap their bodies in `when others => return NO_MOUSE_CAPABILITIES`:

```ada
function Detect_Mouse_Protocols return Mouse_Capabilities is
   ...
begin
   ...
   return Result;
exception
   when others =>
      return NO_MOUSE_CAPABILITIES;
end Detect_Mouse_Protocols;

function Probe_Mouse_Protocols return Mouse_Capabilities is
begin
   return Run_Cascade;
exception
   when others =>
      return NO_MOUSE_CAPABILITIES;
end Probe_Mouse_Protocols;
```

This is the universal Termicap pattern (cf. KKB FUNC-KKB-014, CYG FUNC-CYG-016, DA1 detection). No exception ever propagates to the caller, satisfying FUNC-MSE-014.

---

## M. Termios Safety (FUNC-MSE-015)

Owned by `Termicap.OSC.Probe_Session`'s RAII semantics. When `Run_Cascade` declares `Session : Termicap.OSC.Probe_Session;` in a local scope and calls `Open`, the `Limited_Controlled.Finalize` operation is guaranteed by Ada to run on **every** scope exit, including:

- Normal return after a successful or partial probe.
- Return after the Win32 gate fires (no `Open` was called → `Finalize` is a no-op via `Is_Open` check inside the body).
- Return after the GPM heuristic fires (same as Win32 gate).
- Return after guard 3 (TTY) fails (no `Open` called).
- Return after guard 4/5 (foreground/open) fail (`Open` was called but returned an error; `Finalize` releases whatever partial state was acquired).
- Return after partial DECRPM probe (Open succeeded, queries written, sentinel timed out — `Finalize` restores termios and closes the FD).
- **Exception propagation** through the cascade (extremely unlikely given the no-exception-internal contract, but covered).

The mouse feature does not call `Save_Termios`, `Restore_Termios`, `Set_Raw_Mode`, `Open_Terminal`, `Close_Terminal`, or `Drain_Input` directly — all are mediated through `Probe_Session.Open` and `Probe_Session.Close` (the latter invoked automatically by `Finalize`). This is the same RAII guarantee KKB enjoys (FUNC-KKB-015) and is the single most critical safety property of the feature.

ADR-0015 (Probe_Session as Limited_Controlled) is the foundational decision; this feature inherits it.

---

## N. Caching (FUNC-MSE-016)

### N.1 Cache shape

A single-slot protected object identical to KKB's:

```ada
type Cache_Slot is record
   Initialized : Boolean := False;
   Value       : Mouse_Capabilities := NO_MOUSE_CAPABILITIES;
end record;

protected Cache is
   function  Get_Cached return Cache_Slot;
   procedure Set_Cached (Caps : Mouse_Capabilities);
private
   Slot : Cache_Slot := (Initialized => False,
                         Value       => NO_MOUSE_CAPABILITIES);
end Cache;
```

`Detect_Mouse_Protocols` reads the cache first; on initialised, returns the cached `Value`. On uninitialised, runs `Run_Cascade`, calls `Cache.Set_Cached (Result)`, and returns. Race between two concurrent first callers: both run the cascade, both write to the cache, last-writer wins. Both results are semantically equivalent (the terminal does not change mid-cascade), so no correctness issue.

This design follows ADR-0012 (capability cache design) and is the same shape as `Termicap.Capabilities.Cache` and `Termicap.Keyboard.IO.Cache`.

### N.2 Lazy initialisation (FUNC-MSE-016 explicit requirement)

The protected object's `Slot` is default-initialised by Ada elaboration to `(Initialized => False, Value => NO_MOUSE_CAPABILITIES)`. **No probe runs at elaboration time.** The first call to `Detect_Mouse_Protocols` triggers the cascade.

### N.3 Cache-bypass variant — `Probe_Mouse_Protocols`

The Should clause of FUNC-MSE-016 ("a separate Detect function that bypasses the cache") is satisfied by the public function:

```ada
--  @relation(FUNC-MSE-016 Should clause): cache-bypass detection.
function Probe_Mouse_Protocols return Mouse_Capabilities;
```

`Probe_Mouse_Protocols` runs the full cascade every time, **does not** read or write the cache, and is intended for test harnesses and edge cases (e.g., terminal emulator changed mid-process — exotic but possible under `tmux attach`). Analogous to `Termicap.Capabilities.Detect` vs. `Termicap.Capabilities.Get` and `Termicap.Keyboard.IO.Probe_Keyboard_Protocol` vs. `Detect_Keyboard_Protocol`.

### N.4 SIGWINCH

Not relevant. The cache is **not** invalidated on SIGWINCH. Mouse protocol support is a property of the terminal emulator; it does not change when the window resizes. Explicit per FUNC-MSE-016 final paragraph.

### N.5 Thread-safety posture

Identical to KKB §I and `Termicap.Capabilities`'s cache. The protected object grants mutex per call; the `Get_Cached`/`Set_Cached` pair is non-blocking in the cached-hit case (`Get_Cached` is a `function`, read-only). Elaboration of the protected object precedes concurrent task startup.

---

## O. SPARK Boundary

### O.1 Per-package SPARK_Mode summary

| Package / subprogram | SPARK_Mode | Target | Rationale |
|----------------------|------------|--------|-----------|
| `Termicap.Mouse` (spec) | On (package) | Silver | Pure types, mode constants, parser/cascade signatures |
| `Termicap.Mouse` (body, package level) | Off | N/A | Re-uses `Termicap.DECRPM` body utilities; mixed pattern per ADR-0013 |
| `Parse_Mouse_DECRPM_Response` (body) | On (locally) | Silver | Pure delegation to `Termicap.DECRPM.Parse_DECRPM_Response`; trivial type adaptation |
| `Resolve_Best_Encoding` (body) | On (locally) | Silver | Pure if-elsif chain; cyclomatic complexity 6; provable |
| `Termicap.Mouse.IO` (spec) | Off | N/A | Declares `Detect_Mouse_Protocols` and `Probe_Mouse_Protocols`; both touch I/O |
| `Termicap.Mouse.IO` (body, POSIX) | Off | N/A | Calls `Probe_Session`, `Sentinel_Query`, `Write_Query`, `Ada.Directories` |
| `Termicap.Mouse.IO` (body, Windows) | Off | N/A | Same as POSIX, plus Win32 FFI |
| Internal helpers (`Make_Win32_Result`, `Make_GPM_Result`, `Make_Probed_Result`, `Apply_Mode_Status`, `Parse_All_Responses`) | Off | N/A | Body-private; live in `.IO` body files; not exposed |

### O.2 Mixed-SPARK pattern (per ADR-0013)

`Termicap.Mouse` follows the established `Termicap.Keyboard` / `Termicap.DA1` / `Termicap.DECRPM` pattern:

- **Spec** declares pure functions with `SPARK_Mode => On` aspects on each subprogram.
- **Body** is package-level `SPARK_Mode => Off` (it withs `Termicap.DECRPM` whose body utilities are not all SPARK-On).
- **Each pure function body** carries a local `pragma SPARK_Mode (On);` at its start.

This pattern avoids the circular SPARK boundary issue documented in ADR-0013 and keeps the parsing/cascade logic individually provable without forcing the whole body to be SPARK On.

### O.3 SPARK boundary justification — why not Silver for the I/O layer?

`Termicap.Mouse.IO` calls `Probe_Session` (a `Limited_Controlled` type) and `Sentinel_Query` (which depends on POSIX `select()`/`read()`/`write()`). Both are outside the SPARK 2014 language subset. Marking `Termicap.Mouse.IO` as `SPARK_Mode => Off` is the only correct choice; lowering the boundary deeper (e.g., into a hypothetical `Termicap.Mouse.Cache` SPARK package) would not buy any new provability because the protected object itself is in scope of GNATprove only with `SPARK_Mode => On` containers, and `Mouse_Capabilities` is a record with no invariant aspect (per §F.3). The current split is the minimum-surface boundary.

---

## P. Files Created / Modified

### New files

| File | Purpose | Approx LOC |
|------|---------|------------|
| `src/termicap-mouse.ads` | Spec: types, constants, parser/cascade signatures (SPARK_Mode => On) | 220 |
| `src/termicap-mouse.adb` | Body: `Parse_Mouse_DECRPM_Response`, `Resolve_Best_Encoding` (locally SPARK On) | 180 |
| `src/termicap-mouse-io.ads` | Spec: `Detect_Mouse_Protocols`, `Probe_Mouse_Protocols` (SPARK_Mode => Off) | 90 |
| `src/posix/termicap-mouse-io.adb` | POSIX body: cascade with GPM heuristic, no Win32 gate | 230 |
| `src/windows/termicap-mouse-io.adb` | Windows body: cascade with Win32 gate prepended | 270 |
| `tests/src/test_mouse_parser.ads` | Test spec: parser/cascade unit vectors | 30 |
| `tests/src/test_mouse_parser.adb` | Test body: 25+ vectors across the parser and the cascade | 280 |
| `examples/mouse_protocols_demo/src/mouse_protocols_demo.adb` | Demo program | 80 |
| `examples/mouse_protocols_demo/alire.toml` | Alire crate manifest | 20 |
| `examples/mouse_protocols_demo/mouse_protocols_demo.gpr` | GPR | 15 |

Total new code: ~1415 LOC (~310 spec, ~1105 body/test/example).

### Modified files

| File | Change |
|------|--------|
| `tests/src/termicap_tests.adb` | Register `test_mouse_parser` in the harness |
| `examples/termicap_examples.gpr` | Include `mouse_protocols_demo` |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.Mouse` and `Termicap.Mouse.IO` subsections (handled by `/doc-update` after implementation) |
| `docs/architecture/04-runtime-view.md` | Add "Mouse protocol detection" scenario (handled by `/doc-update`) |

### Files explicitly **not** modified in this feature

- `src/termicap-capabilities.ads` / `src/*/termicap-capabilities.adb` — FUNC-MSE-018 deferred per §M and ADR-0026.
- `src/termicap-osc.ads` / `.adb` — no changes; reused unchanged via `Probe_Session`, `Sentinel_Query`, `Write_Query`.
- `src/termicap-decrpm.ads` / `.adb` — no changes; reused unchanged via `DECRPM_Query`, `Parse_DECRPM_Response`, `Mode_Id`, `Mode_Status`.
- `src/termicap-tty.ads` / `src/*/termicap-tty.adb` — no changes.
- `alire.toml`, `termicap.gpr` — no new external dependencies.

---

## Q. Testing Strategy

The test suite has three tiers, each scoped to a specific subset of FUNC-MSE-* requirements.

### Q.1 Unit tests — pure parsers and cascade (provable subset)

All tests in this tier are deterministic, FFI-free, and runnable in any CI environment. Test package: `tests/src/test_mouse_parser.adb`.

#### `Parse_Mouse_DECRPM_Response` vectors (FUNC-MSE-007)

| Input bytes | Length | Expected `Valid` | Expected `Mode` | Expected `Status` |
|-------------|--------|------------------|-----------------|-------------------|
| `ESC [ ? 1 0 0 0 ; 0 $ y` | 11 | True | 1000 | `Not_Recognized` |
| `ESC [ ? 1 0 0 0 ; 1 $ y` | 11 | True | 1000 | `Set` |
| `ESC [ ? 1 0 0 0 ; 2 $ y` | 11 | True | 1000 | `Reset` |
| `ESC [ ? 1 0 0 0 ; 3 $ y` | 11 | True | 1000 | `Permanently_Set` |
| `ESC [ ? 1 0 0 0 ; 4 $ y` | 11 | True | 1000 | `Permanently_Reset` |
| `ESC [ ? 1 0 0 6 ; 2 $ y` | 11 | True | 1006 | `Reset` |
| `ESC [ ? 1 0 1 6 ; 1 $ y` | 11 | True | 1016 | `Set` |
| `ESC [ ? 1 0 1 5 ; 0 $ y` | 11 | True | 1015 | `Not_Recognized` |
| `ESC [ ? 1 0 0 2 ; 5 $ y` | 11 | True | 1002 | `Not_Recognized` (Pm out of range maps to Not_Recognized) |
| empty buffer | 0 | False | 0 | `Not_Recognized` |
| `ESC [ ? 1 0 0 0 ; 1` (no terminator) | 9 | False | 0 | `Not_Recognized` |
| `ESC [ ? ; 1 $ y` (no mode digits) | 8 | False | 0 | `Not_Recognized` |
| `ESC [ ? 1 0 0 0 $ y` (no semicolon/status) | 10 | False | 0 | `Not_Recognized` |
| `ESC [ M ! ! !` (X10 mouse-event-shape, not DECRPM) | 6 | False | 0 | `Not_Recognized` |
| `ESC [ ? 0 ; 1 $ y` (mode 0; pathological) | 8 | False | 0 | `Not_Recognized` |
| Truncated `ESC [ ?` | 3 | False | 0 | `Not_Recognized` |

Target: 16+ vectors, 100% line coverage of `Parse_Mouse_DECRPM_Response`.

#### `Resolve_Best_Encoding` vectors (FUNC-MSE-008)

The cascade has 32 distinct `(Probed, SGR_Pixels, SGR, URXVT, X10)` input combinations (2^5). The cascade output depends only on the highest True among `SGR_Pixels`, `SGR`, `URXVT`, `X10` (when `Probed = True`). We test the six distinct truth-table rows from §H.2 plus a few corner cases:

| `Probed` | `SGR_Pixels` | `SGR` | `URXVT` | `X10` | Expected `Best_Encoding` |
|----------|--------------|-------|---------|-------|---------------------------|
| F | F | F | F | F | `Unknown` |
| F | T | T | T | T | `Unknown` (`Probed=False` dominates) |
| T | F | F | F | F | `None` |
| T | T | F | F | F | `SGR_Pixels` |
| T | F | T | F | F | `SGR` |
| T | F | F | T | F | `URXVT` |
| T | F | F | F | T | `X10` |
| T | T | T | T | T | `SGR_Pixels` (cascade ordering) |
| T | F | T | T | T | `SGR` |
| T | F | F | T | T | `URXVT` |

Target: 10 vectors, 100% branch coverage.

#### Combined-batch synthetic vectors (FUNC-MSE-006)

Testing `Parse_All_Responses` (the body-private helper for the interleaved-stream parse). These vectors are **not** strictly unit tests in the SPARK sense (the helper lives in the I/O body), but they are FFI-free and run in CI.

| Input bytes (concatenated DECRPM responses) | Expected `Mouse_Capabilities` |
|---------------------------------------------|-------------------------------|
| `ESC[?1000;2$y ESC[?1006;2$y ESC[?1016;2$y` (three modes supported) | `Best_Encoding=SGR_Pixels`, `Supports_X10=Supports_SGR=Supports_SGR_Pixels=True` (after `Make_Probed_Result`) |
| `ESC[?1000;0$y ESC[?1006;0$y ESC[?1016;0$y` (none recognised) | `Best_Encoding=None`, all `Supports_*=False`, `Probed=True` |
| `ESC[?1006;2$y` (only one frame) | `Best_Encoding=SGR`, `Supports_SGR=True`, others False |
| `ESC[?1015;1$y ESC[?1000;1$y` (URXVT + X10 only) | `Best_Encoding=URXVT`, `Supports_URXVT=Supports_X10=True` |
| Empty buffer (`Resp_Length=0`) | `Best_Encoding=None`, all `Supports_*=False`, `Probed=True` (would be wrapped to Probed=False at the caller for total-timeout case) |
| Buffer with stray bytes between frames (`xxxxESC[?1006;1$yxxxxx`) | `Supports_SGR=True`; stray bytes ignored |

Target: 6+ vectors, exercises every branch of `Apply_Mode_Status` and the outer scan loop of `Parse_All_Responses`.

### Q.2 Integration tests — FFI path (CI-gated where possible)

These require a live terminal or a controlled stdin redirection. Some are CI-safe, others are manual.

| Test scenario | Mechanism | CI-safe | FUNC-MSE coverage |
|---------------|-----------|---------|-------------------|
| Non-TTY stdin → `(Unknown, Probed=False)` | Run binary with stdin redirected from `/dev/null` | Yes | FUNC-MSE-009 (guard 3) |
| Background-job stdin → `(Unknown, Probed=False)` | Run via `(./bin/...) &; wait`; inspect output | Yes (POSIX CI) | FUNC-MSE-009 (guard 4) |
| `TERM=linux` + `/dev/gpmctl` mocked → `GPM_Available=True` | Pre-create `/dev/gpmctl` symlink to `/dev/null` and `TERM=linux ./bin/...`; CI-safe via Linux container | Partial (Linux only) | FUNC-MSE-011 |
| `TERM=linux` + no `/dev/gpmctl` → DECRPM probe runs and times out (1 s) → `(None, Probed=True)` | Run with `TERM=linux` outside a Linux console | Yes (any POSIX) | FUNC-MSE-011 fall-through |
| Native xterm → `Best_Encoding=SGR` | Manual on a real xterm | No | FUNC-MSE-005, FUNC-MSE-006, FUNC-MSE-008 |
| Native kitty → `Best_Encoding=SGR_Pixels` | Manual on a real kitty | No | FUNC-MSE-005..008 |
| Native iTerm2 → `Best_Encoding=SGR_Pixels` | Manual on macOS | No | FUNC-MSE-005..008 |
| macOS Terminal.app → `Best_Encoding=SGR` (no SGR-Pixels) | Manual on macOS | No | FUNC-MSE-005..008 |
| Windows native console → `(Win32_Console_Mouse=True, Probed=False)` | Manual on Windows CI | Yes (Windows CI) | FUNC-MSE-010 |
| Windows + git-bash (Cygwin PTY) → DECRPM-probed result | Manual on Windows dev | No | FUNC-MSE-010 fall-through |
| Inside tmux → `Best_Encoding` reflects tmux's own modes | Manual under tmux 3.2+ | No | FUNC-MSE-012 |
| Inside GNU screen → `Best_Encoding=None` (timeout) | Manual under screen | No | FUNC-MSE-012 |

### Q.3 Per-requirement test type assignment

| Requirement | Unit test? | Integration test? | Ada precondition? |
|-------------|------------|-------------------|---------------------|
| FUNC-MSE-001 (enum) | Type instantiation | n/a | n/a |
| FUNC-MSE-002 (record) | Default-init values match `NO_MOUSE_CAPABILITIES` | n/a | n/a |
| FUNC-MSE-003 (constants) | Value equality (`MODE_MOUSE_X10 = 1000`, etc.) | n/a | n/a |
| FUNC-MSE-004 (query order) | Order of `Modes` array in `Run_Batched_DECRPM_Probe` (visual review) | Manual integration on supporting terminal | n/a |
| FUNC-MSE-005 (batched session) | n/a | All §Q.2 integration tests | n/a |
| FUNC-MSE-006 (status interpretation) | Combined-batch vectors (Q.1) | Manual integration on supporting terminal | n/a |
| FUNC-MSE-007 (parser) | 16+ parser vectors (Q.1) | Implicit in integration tests | `Pre => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE` |
| FUNC-MSE-008 (cascade) | 10 cascade vectors (Q.1) | Implicit in integration tests | None (function is total) |
| FUNC-MSE-009 (guards order) | n/a | Non-TTY/background CI tests | n/a |
| FUNC-MSE-010 (Win32 gate) | n/a | Windows CI test | n/a |
| FUNC-MSE-011 (GPM heuristic) | n/a | Mocked /dev/gpmctl CI test | n/a |
| FUNC-MSE-012 (multiplexer) | n/a | Manual under tmux/screen | n/a |
| FUNC-MSE-013 (timeout) | Combined-batch vector with empty buffer (Q.1) simulates total timeout | TERM=linux without GPM | n/a |
| FUNC-MSE-014 (no-exception) | Inject various invalid inputs to parser, observe no `Constraint_Error` | n/a | Implicit via `Pre =>` on `Parse_*` |
| FUNC-MSE-015 (termios restore) | n/a | Manual: probe under `tmux`, check `stty -a` after probe | Inherited from `Probe_Session` RAII |
| FUNC-MSE-016 (cache) | Two consecutive `Detect_Mouse_Protocols` calls return identical records via reference comparison | Manual: cache survives across `tmux detach`/`attach` | n/a |
| FUNC-MSE-017 (package structure) | Build succeeds | n/a | `pragma SPARK_Mode (On)` / `(Off)` placement |
| FUNC-MSE-018 (deferred) | Verify `Terminal_Capabilities` does **not** contain a `Mouse` field | n/a | n/a |

### Q.4 Coverage target

Project-wide target: >95% line coverage (CLAUDE.md). The two pure parsers and the cascade must reach 100% line coverage via the unit vectors. `Detect_Mouse_Protocols` itself reaches ~80% via the non-TTY / GPM-mock / Win32 paths (the probe-positive branches are not exercisable in POSIX CI without a PTY harness).

### Q.5 Example program

`examples/mouse_protocols_demo/src/mouse_protocols_demo.adb` calls `Detect_Mouse_Protocols`, prints the returned `Mouse_Capabilities` in human-readable form (one field per line), and exits. Useful for developer verification on any terminal.

---

## R. Open Questions / Risks

| Risk / Question | Likelihood | Impact | Mitigation / Resolution |
|------------------|-----------|--------|-------------------------|
| A terminal echoes the DECRPM queries back before responding (e.g., misconfigured cooked-mode passthrough) | Low | Low | `Parse_Mouse_DECRPM_Response` rejects echoes (no `;<digit>$y` suffix); they are skipped |
| The 1000 ms timeout is exceeded on a slow SSH link, even though the terminal supports all six modes | Medium | Medium | Documented; FUNC-MSE-013 explicitly permits shorter timeouts on local PTYs and lengthening on slow links is supported by `Sentinel_Query`'s `Retry => True` (not used here for v1 to keep worst case bounded) |
| `Ada.Directories.Exists ("/dev/gpmctl")` returns True but the daemon is dead | Low (gpmctl is created/removed by `gpm` startup/shutdown) | Low | Caller's responsibility to handle GPM connection failure; we report availability, not liveness |
| The interleaved-response parser misinterprets a stray byte sequence as a DECRPM frame (false positive) | Very low | Low | Frame requires exact `ESC [ ? <digits>+ ; <digit> $ y` match; collision probability is astronomically low |
| Concurrent first calls to `Detect_Mouse_Protocols` from two tasks each run the cascade | Very low | Low | Both runs are deterministic; last-writer wins; no correctness issue (matches KKB pattern) |
| Future addition of mode 1004 (focus-event tracking) — not part of this feature but commonly bundled | Medium | Low | `Mouse_Capabilities` extension is backward-compatible: add `Supports_Focus_Event : Boolean := False` field; cascade unchanged |
| User wants to override the cascade (force X10 for legacy compatibility) | Low | Low | Out of scope for v1; ADR-0023 rejects user-override hook; caller can ignore `Best_Encoding` and read individual `Supports_*` flags directly |

### R.1 Open question: should the multiplexer-caveat note live in `Mouse_Capabilities`?

**Considered:** add a `Multiplexer_Detected : Boolean` field to `Mouse_Capabilities` populated from `Termicap.Terminal_Id.Detect_Terminal_Identity` at probe time, satisfying FUNC-MSE-012's "diagnostic note" clause inside the result record.

**Resolution:** **No.** Multiplexer detection is the orthogonal responsibility of `Termicap.Terminal_Id`. Adding a `Multiplexer_Detected` field would force `Termicap.Mouse` to with `Termicap.Terminal_Id` (which it currently does, but only in the body — adding to the result record would also pollute the spec) and would couple two semi-independent capabilities. Per FUNC-MSE-012, the result record has `Probed = True` whenever the probe was attempted; the caller can independently call `Termicap.Terminal_Id.Detect_Terminal_Identity` to check for a multiplexer. Documented in the User Guide caveat; not a record field.

### R.2 Open question: should `Probe_Mouse_Protocols` exist?

**Considered:** drop `Probe_Mouse_Protocols` and rely solely on cached `Detect_Mouse_Protocols`.

**Resolution:** **Keep** `Probe_Mouse_Protocols`. The cache-bypass entry point is an FUNC-MSE-016 Should clause and follows the established KKB / `Capabilities` pattern (`Probe_Keyboard_Protocol`, `Capabilities.Detect`). Keeps test harnesses ergonomic.

### R.3 Open question: should the parser preserve all received DECRPM responses for diagnostic logging?

**Considered:** add a `Last_Raw_Response : Bounded_Byte_Array` field to `Mouse_Capabilities` for callers that want to debug.

**Resolution:** **No** for v1. Out of scope. The example program (`examples/mouse_protocols_demo`) prints the structured capabilities; a debug-logging variant is a separate feature.

---

## S. ADRs Produced Alongside This Spec

This spec is accompanied by five new ADRs:

| ADR | File | Title |
|-----|------|-------|
| **ADR-0022** | `docs/adr/0022-batched-single-sentinel-decrpm-mouse-probe.md` | Batched Single-Sentinel DECRPM Session for Mouse Probing |
| **ADR-0023** | `docs/adr/0023-mouse-encoding-cascade-order.md` | Mouse Encoding Cascade Order (SGR_Pixels > SGR > URXVT > X10) |
| **ADR-0024** | `docs/adr/0024-gpm-detection-heuristic.md` | GPM Detection Heuristic (TERM=linux + /dev/gpmctl Existence Check) |
| **ADR-0025** | `docs/adr/0025-mouse-capability-record-shape.md` | Mouse Capability Record Shape: Orthogonal Booleans + Derived Best_Encoding |
| **ADR-0026** | `docs/adr/0026-defer-mouse-capability-integration.md` | Defer Mouse Capability Integration into Terminal_Capabilities |

ADR-0022 records the load-bearing batched-session decision; ADR-0026 mirrors ADR-0021 for `Terminal_Capabilities` integration deferral. ADR-0023, ADR-0024, ADR-0025 document the three remaining first-order design choices.

---

## T. Requirements Traceability

| Requirement | Design element | Section |
|-------------|---------------|---------|
| FUNC-MSE-001 | `Mouse_Encoding` enum in `Termicap.Mouse` spec | F.1 |
| FUNC-MSE-002 | `Mouse_Capabilities` record + `NO_MOUSE_CAPABILITIES` constant | F.2 |
| FUNC-MSE-003 | `MODE_MOUSE_*` constants (six) | F.5 |
| FUNC-MSE-004 | `Modes` array order in `Run_Batched_DECRPM_Probe` | G.3 |
| FUNC-MSE-005 | Two-phase `Write_Query × 6 + Sentinel_Query (empty,...)` orchestration | G.3, ADR-0022 |
| FUNC-MSE-006 | `Apply_Mode_Status` body-private helper | G.4 |
| FUNC-MSE-007 | `Parse_Mouse_DECRPM_Response` pure SPARK function | F.5, G.4 |
| FUNC-MSE-008 | `Resolve_Best_Encoding` pure SPARK function + cascade | H |
| FUNC-MSE-009 | Guard sequence in `Run_Cascade` | G.1, I |
| FUNC-MSE-010 | Win32 gate in Windows body (`GetConsoleMode`) | G.1, I.1 |
| FUNC-MSE-011 | `Is_Linux_Console_With_GPM` helper in POSIX body | G.2, I.3, ADR-0024 |
| FUNC-MSE-012 | Strategy (a) — probe-anyway; multiplexer note in user docs | J |
| FUNC-MSE-013 | `MOUSE_PROBE_TIMEOUT_MS = 1000`; partial-response handling | F.5, K |
| FUNC-MSE-014 | Per-call outer `when others` handler + per-helper local handlers | L |
| FUNC-MSE-015 | `Probe_Session` RAII guarantees termios restore | M |
| FUNC-MSE-016 | Protected-object cache + `Probe_Mouse_Protocols` bypass function | N |
| FUNC-MSE-017 | Package split `Termicap.Mouse` (SPARK On) + `.IO` child; platform bodies | E, O |
| FUNC-MSE-018 | **Deferred** per §M and ADR-0026; migration path documented | M, ADR-0026 |

---

## U. Related Documents

- **Tech Spec KITTY-KB** (`docs/tech-specs/kitty-keyboard.md`) — Closest structural analogue: Tier 4, FFI, mixed SPARK boundary, sentinel-bounded probe
- **Tech Spec DECRPM** (`docs/tech-specs/decrpm.md`) — Parent infrastructure: provides `Mode_Id`, `Mode_Status`, `DECRPM_Query`, `Parse_DECRPM_Response`
- **Tech Spec OSC-INFRA** (`docs/tech-specs/osc-query-infra.md`) — Parent infrastructure: provides `Probe_Session`, `Sentinel_Query`, `Write_Query`
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`) — DA1 sentinel mechanics used by `Sentinel_Query`
- **Tech Spec CYGWIN** (`docs/tech-specs/cygwin-pty.md`) — Windows Cygwin detection; underpins the Cygwin fall-through on the Windows Mouse body
- **Tech Spec Capability Record** (`docs/tech-specs/capability-record.md`) — Integration target for FUNC-MSE-018 (deferred)
- **ADR-0012** (`docs/adr/0012-capability-cache-design.md`) — Protected-object cache design template
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`) — Mixed `SPARK_Mode` pattern for parser bodies
- **ADR-0015** (`docs/adr/0015-probe-session-limited-controlled.md`) — `Probe_Session` `Limited_Controlled` (justifies termios-restore-for-free)
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`) — DA1 query uses `Timeout_Query` (contrast with this feature, which uses `Sentinel_Query` with empty query for sentinel-only write)
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — Platform-specific body selection via GPR source dirs
- **ADR-0021** (`docs/adr/0021-defer-keyboard-capability-integration.md`) — Sister ADR for KKB integration deferral; ADR-0026 mirrors its structure
- **ADR-0022..ADR-0026** — This spec's own ADRs (see §S)
- **Requirements** (`docs/requirements/mouse-protocol.sdoc`) — FUNC-MSE-001 through FUNC-MSE-018
- **Reference** (`reference-frameworks/blessed/blessed/dec_modes.py` lines 291–305) — Canonical six-mode enumeration
- **Reference** (`reference-frameworks/wezterm/term/src/terminalstate/mod.rs` lines 57–63) — `MouseEncoding` enum shape adopted (renamed)
- **Reference** (`reference-frameworks/tcell/tscreen.go` lines 213–217, 1231–1232) — DECRPM probing pattern at terminal-init
- **Reference** (`reference-frameworks/notcurses/src/lib/gpm.c`) — GPM daemon integration reference (we detect availability only, do not link `libgpm`)
- **Analysis** (`reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` §2.6) — Cross-language mouse input synthesis (citation for the encoding ladder)
