# API Reference: `Termicap.Mouse` and `Termicap.Mouse.IO`

Package pair providing SPARK Silver-provable response parsing and an I/O boundary for active mouse protocol detection. Detects which of six mouse encodings the controlling terminal supports: `SGR_Pixels`, `SGR`, `URXVT`, `X10`, `None`, or `Unknown`.

**Files:**
- `src/termicap-mouse.ads`, `src/termicap-mouse.adb`
- `src/termicap-mouse-io.ads`
- `src/posix/termicap-mouse-io.adb` (POSIX)
- `src/windows/termicap-mouse-io.adb` (Windows)

**SPARK_Mode:** `Termicap.Mouse` — On (spec, Silver level); `Termicap.Mouse.IO` — Off (spec and both bodies)
**License:** Apache-2.0

---

## Overview

The Mouse feature detects which mouse encoding protocols the controlling terminal supports by sending six DECRPM queries (`CSI ? Ps $ p` for modes 1000, 1002, 1003, 1015, 1006, and 1016) in a single batched session, followed by one DA1 sentinel, and collecting the DECRPM response frames (`CSI ? Ps ; Pm $ y`) from the pre-sentinel buffer. The encoding cascade is:

**SGR_Pixels > SGR > URXVT > X10 > None**

Platform fast-paths short-circuit before any probe:
- **Windows native console:** `GetConsoleMode (STD_INPUT_HANDLE)` succeeds → `Win32_Console_Mouse = True` without a probe.
- **Linux/GPM:** `TERM=linux` and `/dev/gpmctl` exists → `GPM_Available = True` without a probe.
- **Non-interactive / error:** non-TTY stdin, background process, probe failure → `Unknown` (`NO_MOUSE_CAPABILITIES`, `Probed => False`).

`Termicap.Mouse` contains all SPARK-provable building blocks: the `Mouse_Encoding` enumeration, the `Mouse_Capabilities` and `DECRPM_Parse_Result` record types, six `MODE_MOUSE_*` DEC private mode constants, the timeout constant, and two pure parsing functions. These functions carry `Global => null` contracts and are verifiable at SPARK Silver level.

`Termicap.Mouse.IO` contains the I/O boundary: `Detect_Mouse_Protocols` drives the five-guard cascade and caches the result; `Probe_Mouse_Protocols` is the uncached variant. The result is cached in a package-level protected object for the process lifetime.

---

## Package `Termicap.Mouse`

### Types

#### `Mouse_Encoding`

```ada
type Mouse_Encoding is
  (Unknown,
   None,
   X10,
   URXVT,
   SGR,
   SGR_Pixels);
```

Six-value enumeration representing the best available mouse encoding detected in the controlling terminal.

| Value | Meaning |
|-------|---------|
| `Unknown` | No probe was executed (non-TTY, background process, probe failure, or Win32 non-DECRPM path). `Probed = False`. |
| `None` | Probe completed successfully; all queried modes returned `Not_Recognized`. Terminal does not support mouse protocols. `Probed = True`. |
| `X10` | Mode 1000 recognised; best available encoding. Coordinate range limited to columns/rows 1–222 by the three-byte X10 encoding. `Probed = True`. |
| `URXVT` | Mode 1015 recognised; unlimited coordinate range via decimal encoding. Preferred over `X10` when both are available. `Probed = True`. |
| `SGR` | Mode 1006 recognised; unlimited coordinate range plus press/release distinction via `M`/`m` terminator. Preferred over `URXVT` when available. `Probed = True`. |
| `SGR_Pixels` | Mode 1016 recognised; pixel-precision coordinates (same wire format as `SGR`). Most expressive encoding; preferred over all others. `Probed = True`. |

Ordering: `Unknown` first so that default-initialised variables are `Unknown`. `None` is second to express "probed but nothing found" cleanly. The four real encodings follow in expressive-power order (weakest to richest).

**Requirements:** FUNC-MSE-001

---

#### `Mouse_Capabilities`

```ada
type Mouse_Capabilities is record
   Best_Encoding         : Mouse_Encoding := Unknown;
   Supports_X10          : Boolean := False;
   Supports_Button_Event : Boolean := False;
   Supports_Any_Event    : Boolean := False;
   Supports_URXVT        : Boolean := False;
   Supports_SGR          : Boolean := False;
   Supports_SGR_Pixels   : Boolean := False;
   Win32_Console_Mouse   : Boolean := False;
   GPM_Available         : Boolean := False;
   Probed                : Boolean := False;
end record;
```

Aggregate result of mouse protocol detection.

| Field | Description |
|-------|-------------|
| `Best_Encoding` | Derived encoding preference; result of `Resolve_Best_Encoding`. `Unknown` when `Probed = False`. |
| `Supports_X10` | `True` when DECRPM mode 1000 (X10/X11 button tracking) was recognised (`Pm in 1..4`). |
| `Supports_Button_Event` | `True` when DECRPM mode 1002 (button-event / drag tracking) was recognised. |
| `Supports_Any_Event` | `True` when DECRPM mode 1003 (any-motion tracking) was recognised. |
| `Supports_URXVT` | `True` when DECRPM mode 1015 (URXVT decimal encoding) was recognised. |
| `Supports_SGR` | `True` when DECRPM mode 1006 (SGR decimal encoding) was recognised. |
| `Supports_SGR_Pixels` | `True` when DECRPM mode 1016 (SGR pixel-precision encoding) was recognised. |
| `Win32_Console_Mouse` | `True` when the Win32 platform gate fired (`GetConsoleMode` succeeded on `STD_INPUT_HANDLE`). Mutually exclusive with `Probed = True`. |
| `GPM_Available` | `True` when the Linux/GPM heuristic fired (`TERM=linux` and `/dev/gpmctl` exists). Mutually exclusive with `Probed = True`. |
| `Probed` | `True` when an active DECRPM probe session was attempted (stdin was a TTY, foreground guard passed, session opened, and the six-query batch was sent). `False` when the result was determined without probing. |

**Canonical interpretations:**

| State | Meaning |
|-------|---------|
| `Best_Encoding = Unknown, Probed = False` | Detection was not performed or failed before any probe (non-TTY, foreground guard, `/dev/tty` open failure, Win32 gate, GPM heuristic, or total timeout with zero responses). |
| `Best_Encoding = None, Probed = True` | DECRPM probe completed; all six modes returned `Not_Recognized`. |
| `Best_Encoding in X10 \| URXVT \| SGR \| SGR_Pixels, Probed = True` | At least one encoding mode was recognised; `Best_Encoding` reflects the cascade result. |
| `Win32_Console_Mouse = True` | Windows Console API mouse is available. All `Supports_*` fields are `False` and `Probed = False`. |
| `GPM_Available = True` | Linux/GPM daemon detected. All `Supports_*` fields are `False` and `Probed = False`. |

**Requirements:** FUNC-MSE-002

---

#### `DECRPM_Parse_Result`

```ada
type DECRPM_Parse_Result is record
   Valid  : Boolean := False;
   Mode   : Termicap.DECRPM.Mode_Id := 0;
   Status : Termicap.DECRPM.Mode_Status := Termicap.DECRPM.Not_Recognized;
end record;
```

Result record returned by `Parse_Mouse_DECRPM_Response`.

| Field | When `Valid = True` | When `Valid = False` |
|-------|---------------------|----------------------|
| `Valid` | `True` — buffer matched `CSI ? Ps ; Pm $ y` | `False` — no match |
| `Mode` | Decoded `Ps` (mode number, > 0 for any recognised DEC private mode) | `0` (guaranteed by postcondition) |
| `Status` | Decoded `Mode_Status` from `Pm` | `Not_Recognized` |

`Pm` decoding: `0` → `Not_Recognized`; `1` → `Set`; `2` → `Reset`; `3` → `Permanently_Set`; `4` → `Permanently_Reset`.

**Requirements:** FUNC-MSE-007

---

### Constants

#### `NO_MOUSE_CAPABILITIES`

```ada
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

Canonical "no result" value. Used as the cache initial value and as the fallback on every error path of `Detect_Mouse_Protocols`. A `Mouse_Capabilities` declared without an explicit aggregate is equivalent to this value via default initialisation.

**Requirements:** FUNC-MSE-002

---

#### `MODE_MOUSE_*` Constants

All six constants are of subtype `Termicap.DECRPM.Mode_Id` (a subtype of `Natural`). They are the DEC private mode numbers sent in `CSI ? Ps $ p` queries.

| Constant | Value | DEC Private Mode |
|----------|-------|-----------------|
| `MODE_MOUSE_X10` | `1000` | X10/X11 button tracking — press and release events only. |
| `MODE_MOUSE_BUTTON_EVENT` | `1002` | Button-event / drag tracking — press, release, and drag motion. |
| `MODE_MOUSE_ANY_EVENT` | `1003` | Any-motion tracking — all motion events regardless of button state. |
| `MODE_MOUSE_URXVT` | `1015` | URXVT decimal mouse encoding — unlimited coordinate range. |
| `MODE_MOUSE_SGR` | `1006` | SGR decimal mouse encoding — unlimited range with press/release distinction via `M`/`m` terminator. |
| `MODE_MOUSE_SGR_PIXELS` | `1016` | SGR pixel-precision encoding — same wire format as SGR but `Cx`/`Cy` are pixel coordinates. |

**Requirements:** FUNC-MSE-003

---

#### `MOUSE_PROBE_TIMEOUT_MS`

```ada
MOUSE_PROBE_TIMEOUT_MS : constant Natural := 1_000;
```

Millisecond timeout for the entire batched six-query DECRPM probe session (one DA1 sentinel for all six queries). 1 000 ms matches FUNC-MSE-013 and is consistent with `KITTY_PROBE_TIMEOUT_MS` (FUNC-KKB-013) and the OSC-INFRA default (FUNC-OSC-004). Implementations may use a shorter timeout (minimum 100 ms) on local PTYs where round-trip latency is negligible.

**Requirements:** FUNC-MSE-013

---

#### `MAX_RESPONSE_SIZE`

```ada
MAX_RESPONSE_SIZE : constant := Termicap.DECRPM.MAX_RESPONSE_SIZE;
```

Re-export of `Termicap.DECRPM.MAX_RESPONSE_SIZE` (4 096 bytes). Maximum number of response bytes accumulated by the sentinel-bounded read loop. Bounds parsing loops for SPARK provability. `Parse_Mouse_DECRPM_Response` preconditions reference this symbol so they remain within the SPARK On package.

**Requirements:** FUNC-MSE-013

---

### Functions

#### `Parse_Mouse_DECRPM_Response`

```ada
function Parse_Mouse_DECRPM_Response
  (Buffer : Byte_Array;
   Length : Natural) return DECRPM_Parse_Result
with
  SPARK_Mode => On,
  Global => null,
  Pre  => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE,
  Post => (if not Parse_Mouse_DECRPM_Response'Result.Valid
           then Parse_Mouse_DECRPM_Response'Result.Mode = 0);
```

Parse a single DECRPM response frame beginning at `Buffer'First`. Returns a `DECRPM_Parse_Result` with `Valid = True` when `Buffer (Buffer'First .. Buffer'First + Length - 1)` matches:

```
ESC (0x1B) '[' (0x5B) '?' (0x3F) <Ps_digits>+ ';' (0x3B) <Pm_digit> '$' (0x24) 'y' (0x79)
```

where `<Ps_digits>+` is one or more ASCII decimal digits encoding `Ps`, and `<Pm_digit>` is a single ASCII digit in `'0'..'4'` encoding `Pm`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Raw response byte buffer. |
| `Length` | in | Number of valid bytes to examine (0 .. `MAX_RESPONSE_SIZE`). |

**Returns:** `DECRPM_Parse_Result` with:
- `Valid = True, Mode = Ps, Status = decoded_Pm` on a successful match.
- `Valid = False, Mode = 0, Status = Not_Recognized` on any mismatch (garbled, partial, or out-of-range `Pm`).

**SPARK contract:** `Global => null` — pure buffer scan, no state, no I/O. `Pre` bounds `Length` within `Buffer` and within `MAX_RESPONSE_SIZE` to prevent out-of-bounds access. Postcondition guarantees `Mode = 0` whenever `Valid = False`.

**Note:** This parser recognises exactly one frame beginning at `Buffer'First`. The multi-frame scanner in `Termicap.Mouse.IO` calls this function at successive positions across the full pre-sentinel buffer.

**Requirements:** FUNC-MSE-007

---

#### `Resolve_Best_Encoding`

```ada
function Resolve_Best_Encoding
  (Caps : Mouse_Capabilities) return Mouse_Encoding
with
  SPARK_Mode => On,
  Global => null,
  Pre  => True,
  Post =>
    (if not Caps.Probed then Resolve_Best_Encoding'Result = Unknown)
    and then
    (if Caps.Probed and then Caps.Supports_SGR_Pixels
     then Resolve_Best_Encoding'Result = SGR_Pixels)
    and then
    (if Caps.Probed and then not Caps.Supports_SGR_Pixels
        and then Caps.Supports_SGR
     then Resolve_Best_Encoding'Result = SGR);
```

Derive the best available mouse encoding from the per-mode `Supports_*` flags in `Caps`. When `Caps.Probed = False`, returns `Unknown` regardless of any `Supports_*` flags.

**Cascade (in priority order, ADR-0023):**

1. `Caps.Supports_SGR_Pixels` → `SGR_Pixels`
2. `Caps.Supports_SGR` → `SGR`
3. `Caps.Supports_URXVT` → `URXVT`
4. `Caps.Supports_X10` → `X10`
5. (else) → `None`

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Caps` | in | The `Mouse_Capabilities` record to evaluate. |

**Returns:** `Mouse_Encoding` denoting the best available encoding, or `Unknown` when `Probed = False`, or `None` when all `Supports_*` are `False`.

**Note:** Tracking-mode flags (`Supports_Button_Event`, `Supports_Any_Event`) are intentionally ignored in the encoding decision. Encoding scheme is orthogonal to tracking mode. Callers that need drag-support information should inspect `Supports_Button_Event` independently.

**SPARK contract:** `Global => null` — pure flag evaluation, no state, no I/O. Postcondition is partial (SPARK Silver); remaining cascade levels are validated by unit tests.

**Requirements:** FUNC-MSE-008

---

## Package `Termicap.Mouse.IO`

### Functions

#### `Detect_Mouse_Protocols`

```ada
function Detect_Mouse_Protocols return Mouse_Capabilities;
```

Return the mouse protocol capabilities for the controlling terminal. On the first call, the full five-guard cascade is executed and the result is stored in a package-level protected object. All subsequent calls return the cached value directly (< 1 µs, no I/O).

**Five-guard cascade (in order):**

1. Cache hit → return cached result.
2. *(Windows only)* `GetConsoleMode (STD_INPUT_HANDLE)` succeeds → return `(Win32_Console_Mouse => True, Probed => False, others => default)`.
3. *(POSIX only)* `TERM = "linux"` and `Ada.Directories.Exists ("/dev/gpmctl")` → return `(GPM_Available => True, Probed => False, others => default)`.
4. Non-TTY stdin → return `NO_MOUSE_CAPABILITIES`.
5. Not in foreground process group → return `NO_MOUSE_CAPABILITIES`.
6. `Probe_Session.Open` fails (`/dev/tty` not openable) → return `NO_MOUSE_CAPABILITIES`.
7. Batched probe: write six DECRPM queries (1000, 1002, 1003, 1015, 1006, 1016) + one DA1 sentinel in a single session; read until DA1 or timeout (ADR-0022); scan pre-sentinel bytes with `Parse_Mouse_DECRPM_Response`; run `Resolve_Best_Encoding`; set `Probed = True`.

**Timing:** worst-case 1 s cold-start (one batch times out). Typical < 100 ms when the terminal responds. Cached calls < 1 µs.

**Partial results:** If the session times out after receiving some DECRPM responses, those responses are preserved and `Probed = True` is set. A total timeout with zero pre-sentinel bytes returns `NO_MOUSE_CAPABILITIES` (`Probed = False`).

**Exception safety:** Never raises an exception on any code path (FUNC-MSE-014).

**Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path (FUNC-MSE-015).

**Requirements:** FUNC-MSE-005, FUNC-MSE-009, FUNC-MSE-010, FUNC-MSE-011, FUNC-MSE-013, FUNC-MSE-014, FUNC-MSE-015, FUNC-MSE-016

---

#### `Probe_Mouse_Protocols`

```ada
function Probe_Mouse_Protocols return Mouse_Capabilities;
```

Uncached variant of `Detect_Mouse_Protocols`. Runs the full five-guard cascade on every call without consulting or updating the protected-object cache. Intended for test harnesses that need a fresh probe result (e.g., after a terminal change or TMUX reattach) and for integration tests that must verify detection behaviour in isolation from the cache.

The cascade, timing, partial-result behaviour, and exception/termios contracts are identical to `Detect_Mouse_Protocols`.

**Requirements:** FUNC-MSE-009, FUNC-MSE-014, FUNC-MSE-015, FUNC-MSE-016

---

## Usage Examples

### Detect mouse protocol (typical usage)

```ada
with Termicap.Mouse.IO;  use Termicap.Mouse.IO;
with Termicap.Mouse;     use Termicap.Mouse;

declare
   Cap : constant Mouse_Capabilities := Detect_Mouse_Protocols;
begin
   if Cap.Win32_Console_Mouse then
      Put_Line ("Windows native console mouse.");
   elsif Cap.GPM_Available then
      Put_Line ("Linux/GPM mouse daemon available.");
   else
      case Cap.Best_Encoding is
         when SGR_Pixels =>
            Put_Line ("SGR pixel-precision mouse encoding.");
         when SGR =>
            Put_Line ("SGR decimal mouse encoding.");
         when URXVT =>
            Put_Line ("URXVT decimal mouse encoding.");
         when X10 =>
            Put_Line ("X10 button tracking (range limited to 222 cells).");
         when None =>
            Put_Line ("No mouse protocol recognised.");
         when Unknown =>
            Put_Line ("Not an interactive terminal or probe failed.");
      end case;
      if Cap.Supports_Button_Event then
         Put_Line ("  Drag tracking: supported (mode 1002).");
      end if;
      if Cap.Supports_Any_Event then
         Put_Line ("  Any-motion tracking: supported (mode 1003).");
      end if;
   end if;
end;
```

### Force a fresh probe (skip cache)

```ada
Cap : constant Mouse_Capabilities := Probe_Mouse_Protocols;
```

### Pure parser test (no terminal required)

```ada
with Termicap.Mouse; use Termicap.Mouse;

--  Well-formed DECRPM response for mode 1006 (SGR), status Set (Pm=1):
--  ESC [ ? 1 0 0 6 ; 1 $ y
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5B#, 16#3F#,                                --  ESC [ ?
      Character'Pos ('1'), Character'Pos ('0'),               --  1 0
      Character'Pos ('0'), Character'Pos ('6'),               --  0 6
      16#3B#,                                                 --  ;
      Character'Pos ('1'),                                    --  1  (Set)
      16#24#, Character'Pos ('y')];                           --  $ y
   Result : constant DECRPM_Parse_Result :=
     Parse_Mouse_DECRPM_Response (Raw, Raw'Length);
begin
   pragma Assert (Result.Valid = True);
   pragma Assert (Result.Mode = 1006);
   pragma Assert (Result.Status = Termicap.DECRPM.Set);
end;
```

---

## SPARK Notes

`Termicap.Mouse` (spec) targets SPARK Silver:

| Function | Key proof obligations | Discharged by |
|----------|-----------------------|---------------|
| `Parse_Mouse_DECRPM_Response` | Out-of-bounds access prevention; loop termination; `Mode = 0` when `Valid = False` | `Pre => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE`; postcondition; loop bounded by `Length` |
| `Resolve_Best_Encoding` | Correct result when `Probed = False`; top-two cascade steps | Partial postcondition; remaining steps validated by unit tests |

No manual lemmas, ghost code, or proof pragmas are required.

`Termicap.Mouse.IO` carries `pragma SPARK_Mode (Off)` on the spec, preventing SPARK-annotated callers from inadvertently calling `Detect_Mouse_Protocols` or `Probe_Mouse_Protocols` without a mode barrier.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-MSE-001 | `Mouse_Encoding` enumeration | Silver |
| FUNC-MSE-002 | `Mouse_Capabilities` record, `NO_MOUSE_CAPABILITIES` | Silver |
| FUNC-MSE-003 | `MODE_MOUSE_*` named constants | Silver |
| FUNC-MSE-004 | Six queries issued; responses matched by mode number, not position | Off |
| FUNC-MSE-005 | Single batched probe session (ADR-0022) | Off |
| FUNC-MSE-006 | `Pm in 1..4` → `Supports_* = True`; `Pm = 0` → `False`; missing → `False` | Off |
| FUNC-MSE-007 | `DECRPM_Parse_Result`, `Parse_Mouse_DECRPM_Response` | Silver |
| FUNC-MSE-008 | `Resolve_Best_Encoding` cascade | Silver (partial) |
| FUNC-MSE-009 | `Detect_Mouse_Protocols` / `Probe_Mouse_Protocols` five-guard cascade | Off |
| FUNC-MSE-010 | Windows `GetConsoleMode` gate (Windows body) | Off |
| FUNC-MSE-011 | Linux/GPM heuristic (POSIX body; ADR-0024) | Off |
| FUNC-MSE-012 | Multiplexer awareness; probe regardless of TMUX/STY | Off |
| FUNC-MSE-013 | `MOUSE_PROBE_TIMEOUT_MS`, `MAX_RESPONSE_SIZE`; partial-result preservation | Silver (constants) / Off (usage) |
| FUNC-MSE-014 | No-exception contract for `Detect_Mouse_Protocols` | Off |
| FUNC-MSE-015 | Termios restore via `Probe_Session` RAII | Off |
| FUNC-MSE-016 | One-probe-per-process cache; `Probe_Mouse_Protocols` bypass | Off |
| FUNC-MSE-017 | `Termicap.Mouse` (SPARK On spec) + `Termicap.Mouse.IO` (SPARK Off); platform dispatch via GPR `Source_Dirs` | Mixed |
| FUNC-MSE-018 | Integration into `Terminal_Capabilities` — **deferred** (ADR-0026) | N/A |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Mouse` and `Termicap.Mouse.IO` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 27: full mouse protocol detection cascade, Win32 fast-path, GPM heuristic, batched probe lifecycle, and cache behaviour
- **Tech Spec MOUSE** (`docs/tech-specs/mouse-protocol.md`) — design rationale, framework survey (tcell, crossterm, libvterm), batched sentinel probe, GPM heuristic, platform dispatch strategy
- **ADR-0022** (`docs/adr/0022-batched-single-sentinel-decrpm-mouse-probe.md`) — rationale for issuing all six queries in one session with a single DA1 sentinel
- **ADR-0023** (`docs/adr/0023-mouse-encoding-cascade-order.md`) — rationale for the `SGR_Pixels > SGR > URXVT > X10 > None` cascade order
- **ADR-0024** (`docs/adr/0024-gpm-detection-heuristic.md`) — rationale for the `TERM=linux` + `/dev/gpmctl` GPM detection heuristic
- **ADR-0025** (`docs/adr/0025-mouse-capability-record-shape.md`) — rationale for the `Mouse_Capabilities` record field layout and implicit invariants
- **ADR-0026** (`docs/adr/0026-defer-mouse-capability-integration.md`) — rationale for deferring `Mouse_Capabilities` integration into `Terminal_Capabilities`
- **Requirements** (`docs/requirements/mouse-protocol.sdoc`) — FUNC-MSE-001 through FUNC-MSE-018 (18 approved requirements)
- **[Termicap.DECRPM](decrpm.md)** — `Mode_Id`, `Mode_Status`, and `Parse_DECRPM_Response` infrastructure reused by `Termicap.Mouse`
- **[Termicap.OSC](osc.md)** — `Probe_Session` and `Sentinel_Query` infrastructure used by `Termicap.Mouse.IO`
- **[Termicap.DA1](da1.md)** — DA1 sentinel infrastructure reused as the mouse probe boundary
- **[Termicap.Keyboard](keyboard.md)** — sibling package with the same SPARK split pattern and platform dispatch strategy
