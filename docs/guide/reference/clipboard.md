# API Reference: `Termicap.Clipboard` and `Termicap.Clipboard.IO`

Package pair providing SPARK Silver-provable response parsing and an I/O boundary for OSC 52 clipboard capability detection. Detects whether the controlling terminal supports clipboard write-only access, full read-write access via OSC 52, or neither.

**Files:**
- `src/termicap-clipboard.ads`, `src/termicap-clipboard.adb`
- `src/termicap-clipboard-io.ads`
- `src/posix/termicap-clipboard-io.adb` (POSIX)
- `src/windows/termicap-clipboard-io.adb` (Windows)

**SPARK_Mode:** `Termicap.Clipboard` — On (spec and body, Silver level); `Termicap.Clipboard.IO` — Off (spec and both bodies)
**License:** Apache-2.0

---

## Overview

The Clipboard feature detects OSC 52 clipboard support in the controlling terminal using a three-phase cascade:

1. **DA1 passive probe for Ps=52** — reuses `Termicap.DA1.IO.Detect_DA1`; sets `Via_DA1 = True` and `Support = Write_Only` when `Has_Capability (DA1_Result, Clipboard_Access)` is true. Runs in an independent `Probe_Session`.
2. **Active OSC 52 read-back probe** — sends `OSC52_QUERY` (`ESC ] 52 ; c ; ? BEL`) followed by a DA1 sentinel; parses the response with `Parse_OSC52_Response`; upgrades `Support` to `Read_Write` and sets `Via_Active_Probe = True` when `Valid_Response` is returned. Runs in a second independent `Probe_Session`. Skipped when `Support` is already `Read_Write`.
3. **Passive env-var heuristics** — applied when `Support = None` after Phases 1 and 2. `TERM_PROGRAM=WezTerm` or `iTerm.app` → `Read_Write`; `TERM_PROGRAM=vscode` or `WT_SESSION` present → `Write_Only`; `TERM=xterm-kitty` → `Read_Write`; `TERM` prefix `xterm` → `Write_Only`. Sets `Via_Env_Heuristic = True`.

Platform fast-paths short-circuit before any active probe:
- **Windows native console:** `GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → passive env-var heuristics only (`Probed = False`).
- **Non-interactive / error:** non-TTY stdout, background process, probe failure → passive env-var heuristics only or `NO_CLIPBOARD_CAPABILITIES`.

Unlike the Mouse batched-probe design (ADR-0022), each active probe uses an **independent session** with its own 1 000 ms budget (ADR-0028). Worst-case cold-start latency is 2 s (both probes time out). Typical cold-start latency is < 200 ms when the terminal responds.

Multiplexer passthrough: when `TMUX` or `STY` is set, the OSC 52 query is wrapped using `Termicap.OSC.Parsing.Wrap_For_Passthrough` before being sent (FUNC-C52-011). The DA1 probe (Phase 1) handles its own multiplexer wrapping independently via `Detect_DA1`.

`Termicap.Clipboard` contains all SPARK-provable building blocks: the `Clipboard_Support` enumeration, the `Clipboard_Capabilities` record, 9 named terminal identifier constants, the `OSC52_QUERY` byte array, the `CLIPBOARD_PROBE_TIMEOUT_MS` constant, the `OSC52_Parse_Result` enumeration, and the pure `Parse_OSC52_Response` function. All functions carry `Global => null` contracts and are verifiable at SPARK Silver level.

`Termicap.Clipboard.IO` contains the I/O boundary: `Detect_Clipboard` drives the full cascade and caches the result; `Detect_Clipboard_Uncached` is the cache-bypass variant for test harnesses.

---

## Package `Termicap.Clipboard`

### Types

#### `Clipboard_Support`

```ada
type Clipboard_Support is (None, Write_Only, Read_Write);
```

Three-level enumeration for clipboard access support via OSC 52.

| Value | Meaning |
|-------|---------|
| `None` | No clipboard access detected. Either the terminal does not support OSC 52, or detection was not performed (non-TTY, no DA1 Ps=52, no active probe response, no heuristic match). |
| `Write_Only` | Terminal accepts OSC 52 write sequences but does not respond to read queries. Established by DA1 Ps=52 without an active probe upgrade, or by env-var heuristics for write-capable-only terminals. |
| `Read_Write` | Terminal supports both writing and reading via OSC 52. Reading was confirmed by the active probe returning a valid OSC 52 response. |

Ordering: `None` < `Write_Only` < `Read_Write` (increasing capability level). Callers may compare with `>=`: `if Support >= Write_Only then emit OSC 52 writes`.

**Requirements:** FUNC-C52-001

---

#### `Clipboard_Capabilities`

```ada
type Clipboard_Capabilities is record
   Support           : Clipboard_Support := None;
   Via_DA1           : Boolean           := False;
   Via_Active_Probe  : Boolean           := False;
   Via_Env_Heuristic : Boolean           := False;
   Probed            : Boolean           := False;
end record;
```

Aggregate result of OSC 52 clipboard capability detection.

| Field | Description |
|-------|-------------|
| `Support` | The detected clipboard access level. Default: `None`. |
| `Via_DA1` | `True` when `Support` was set based on DA1 Ps=52 (FUNC-C52-006). `False` when `Support` was determined by active probe or env-var heuristic only. |
| `Via_Active_Probe` | `True` when `Support` was upgraded to `Read_Write` by the active OSC 52 read-back probe (FUNC-C52-007). |
| `Via_Env_Heuristic` | `True` when `Support` was set by env-var heuristics alone (FUNC-C52-009). `Via_DA1` and `Via_Active_Probe` are both `False` when this is `True`. |
| `Probed` | `True` when at least one active probe (DA1 or OSC 52) was attempted. `False` when the result was determined entirely by passive env-var heuristics (non-TTY, foreground guard failed, `/dev/tty` unopenable, or Win32 Console gate). |

**Implicit invariants** (enforced by construction, not by `Type_Invariant`):
- I1. `Via_DA1 = True` ⟹ `Support >= Write_Only` and `Probed = True`.
- I2. `Via_Active_Probe = True` ⟹ `Support = Read_Write` and `Probed = True`.
- I3. `Via_Env_Heuristic = True` ⟹ `Via_DA1 = False` and `Via_Active_Probe = False`.
- I4. `Probed = False` ⟹ `Via_DA1 = False` and `Via_Active_Probe = False`.

**Canonical interpretations:**

| State | Meaning |
|-------|---------|
| `Support = None, Probed = False` | Detection was not performed, or all guards suppressed probing (non-TTY, foreground guard, `/dev/tty` open failure, Win32 Console gate). No heuristic matched either. |
| `Support >= Write_Only, Via_DA1 = True, Probed = True` | DA1 Ps=52 was present; clipboard write capability confirmed (highest active-probe confidence). |
| `Support = Read_Write, Via_Active_Probe = True, Probed = True` | Active OSC 52 probe returned a valid response; full read-write confirmed. |
| `Support /= None, Via_Env_Heuristic = True, Probed = False` | Passive env-var heuristic matched; no active probe was performed. |

**Requirements:** FUNC-C52-002

---

#### `OSC52_Parse_Result`

```ada
type OSC52_Parse_Result is (Not_Present, Valid_Response, Malformed);
```

Three-way result of the OSC 52 response parser.

| Value | Meaning |
|-------|---------|
| `Not_Present` | No OSC 52 introducer (`ESC ] 52`) was found in the buffer. The DA1 sentinel arrived first, or the terminal did not respond to the read query. Treated as "read-back not available". |
| `Valid_Response` | A well-formed OSC 52 response was found: `ESC ] 52 ; <sel> ; <base64-or-empty>` present and terminated with `BEL` (`0x07`) or `ST` (`ESC \`). Indicates the terminal supports OSC 52 read-back (`Read_Write` upgrade in the cascade). |
| `Malformed` | An OSC 52 introducer was found but the response did not terminate correctly or lacked the required semicolon structure. Treated as "read-back not available". Distinguished from `Not_Present` for debugging and test assertions. |

Both `Not_Present` and `Malformed` map to "read-back not available" in the detection cascade.

**Requirements:** FUNC-C52-008

---

### Constants

#### `NO_CLIPBOARD_CAPABILITIES`

```ada
NO_CLIPBOARD_CAPABILITIES : constant Clipboard_Capabilities :=
  (Support           => None,
   Via_DA1           => False,
   Via_Active_Probe  => False,
   Via_Env_Heuristic => False,
   Probed            => False);
```

Canonical "no result" value. Used as the cache initial value and as the fallback on every error path of `Detect_Clipboard`. A `Clipboard_Capabilities` declared without an explicit aggregate is equivalent to this value via default initialisation.

**Requirements:** FUNC-C52-002

---

#### `OSC52_QUERY`

```ada
OSC52_QUERY : constant Byte_Array :=
  [16#1B#,                  --  ESC      (0x1B)
   16#5D#,                  --  ]        (0x5D, OSC introducer)
   Character'Pos ('5'),     --  5        (0x35)
   Character'Pos ('2'),     --  2        (0x32)
   Character'Pos (';'),     --  ;        (0x3B)
   Character'Pos ('c'),     --  c        (0x63, clipboard selection)
   Character'Pos (';'),     --  ;        (0x3B)
   Character'Pos ('?'),     --  ?        (0x3F, query)
   16#07#];                 --  BEL      (0x07, OSC terminator)
```

9-byte OSC 52 clipboard read query sequence. Encodes `ESC ] 52 ; c ; ? BEL` (OSC introducer + `"52;c;?"` + BEL terminator). A DA1 sentinel (`ESC [ c`) is appended by the caller as a response boundary marker via `Termicap.OSC.Sentinel_Query`.

**Requirements:** FUNC-C52-007

---

#### `CLIPBOARD_PROBE_TIMEOUT_MS`

```ada
CLIPBOARD_PROBE_TIMEOUT_MS : constant Natural := 1_000;
```

Millisecond timeout for each active probe session (DA1 or OSC 52). Each session has its own independent 1 000 ms budget (ADR-0028). Consistent with `MOUSE_PROBE_TIMEOUT_MS` (FUNC-MSE-013), `KITTY_PROBE_TIMEOUT_MS` (FUNC-KKB-013), `GRAPHICS_PROBE_TIMEOUT_MS` (FUNC-SXL-015), and the OSC-INFRA default (FUNC-OSC-004). Worst-case cold-start latency is 2 000 ms (both probes time out completely).

**Requirements:** FUNC-C52-015

---

#### Named Terminal Identifier Constants (FUNC-C52-005)

All 9 constants are of type `String`. They centralise terminal identifier values used in passive env-var heuristics to avoid scattered string literals.

| Constant | Value | Detection Use |
|----------|-------|---------------|
| `TERM_PROGRAM_WEZTERM` | `"WezTerm"` | Case-insensitive `TERM_PROGRAM` match — WezTerm; full OSC 52 read-write (FUNC-C52-009 step 1). |
| `TERM_PROGRAM_ITERM2` | `"iTerm.app"` | Case-insensitive `TERM_PROGRAM` match — iTerm2 macOS; full OSC 52 read-write (FUNC-C52-009 step 1). |
| `TERM_PROGRAM_VSCODE` | `"vscode"` | Case-insensitive `TERM_PROGRAM` match — VS Code integrated terminal; OSC 52 write-only (FUNC-C52-009 step 2). |
| `ENV_WT_SESSION` | `"WT_SESSION"` | Env-var name — Windows Terminal sets this for every hosted terminal; OSC 52 write-only (FUNC-C52-009 step 3). |
| `ENV_TMUX` | `"TMUX"` | Env-var name — tmux sets this when running inside a tmux session; used for multiplexer passthrough detection (FUNC-C52-011). Not a clipboard heuristic. |
| `ENV_STY` | `"STY"` | Env-var name — GNU screen sets this when running inside a screen session; used for multiplexer passthrough detection (FUNC-C52-011). Not a clipboard heuristic. |
| `TERM_XTERM_KITTY` | `"xterm-kitty"` | Exact `TERM` match — kitty GPU terminal; full OSC 52 read-write (FUNC-C52-009 step 4). |
| `TERM_XTERM` | `"xterm"` | `TERM` prefix match — xterm family; OSC 52 write-only (allowWindowOps disabled by default, FUNC-C52-009 step 4). |

**Requirements:** FUNC-C52-005

---

### Functions

#### `Parse_OSC52_Response`

```ada
function Parse_OSC52_Response
  (Buffer : Byte_Array;
   Length : Natural) return OSC52_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length,
  Post       => True;
```

Parse an OSC 52 read-back response from a raw byte buffer. Scans `Buffer (Buffer'First .. Buffer'First + Length - 1)` for an OSC 52 response matching the pattern:

```
ESC ] 52 ; <selection> ; <base64-or-empty> BEL
  or:
ESC ] 52 ; <selection> ; <base64-or-empty> ESC \
```

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Raw response byte buffer. |
| `Length` | in | Number of valid bytes in `Buffer` to examine (0 .. `Buffer'Length`). |

**Returns:** `OSC52_Parse_Result` per the rules:
- `Valid_Response` — A well-formed OSC 52 response envelope was found: `ESC ] 52` introduced the response, at least two semicolons were present, and the response terminated with `BEL` or `ST`. The base64 payload is not decoded; structural presence is sufficient for capability detection.
- `Not_Present` — No OSC 52 introducer found in the buffer. The terminal did not respond to the read query, or the DA1 sentinel arrived before any OSC 52 bytes.
- `Malformed` — An OSC 52 introducer was found but the response did not terminate with `BEL` or `ESC \`, or fewer than two semicolons were present before the terminator.

The function never raises for any buffer content; stray or out-of-range bytes are skipped. The scan is O(Length) worst-case.

**SPARK contract:** `Global => null` — pure buffer scan, no state, no I/O. `Pre` bounds `Length` within `Buffer` to prevent out-of-bounds access.

**Example:**

```ada
--  OSC 52 read-back response: ESC ] 52 ; c ; dGVzdA== BEL
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5D#,                          --  ESC ]
      Character'Pos ('5'), Character'Pos ('2'), --  52
      Character'Pos (';'), Character'Pos ('c'), --  ;c
      Character'Pos (';'),                      --  ;
      Character'Pos ('d'), Character'Pos ('G'), --  dG  (base64 payload)
      16#07#];                                  --  BEL
   Result : constant OSC52_Parse_Result :=
     Parse_OSC52_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = Valid_Response);
end;
```

**Requirements:** FUNC-C52-008

---

## Package `Termicap.Clipboard.IO`

### Functions

#### `Detect_Clipboard`

```ada
function Detect_Clipboard return Clipboard_Capabilities;
```

Return the OSC 52 clipboard capabilities for the controlling terminal. On the first call, the full detection cascade is executed and the result is stored in a package-level protected object. All subsequent calls return the cached value directly (< 1 µs, no I/O).

**Detection cascade (in order):**

1. Cache hit → return cached result immediately.
2. *(Windows only)* `GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → run passive env-var heuristics (Step 7) and return with `Probed = False`.
3. Non-TTY guard: `Is_TTY (Stdout) = False` → run passive env-var heuristics and return with `Probed = False` (FUNC-C52-013).
4. Open DA1 `Probe_Session` (independent session 1): `/dev/tty` open, foreground guard (`Is_Foreground_Process`), raw mode. Fails → run env-var heuristics and return with `Probed = False`.
5. DA1 active probe (independent session 1, 1 000 ms budget): calls `Termicap.DA1.IO.Detect_DA1`; if `Has_Capability (DA1_Result, Clipboard_Access)` → `Support = Write_Only`, `Via_DA1 = True`, `Probed = True`.
6. Active OSC 52 read-back probe (independent session 2, 1 000 ms budget; skipped when `Support = Read_Write`): sends `OSC52_QUERY` + DA1 sentinel via `Termicap.OSC.Sentinel_Query`; multiplexer wrapping applied when `TMUX` or `STY` is set (FUNC-C52-011); if `Parse_OSC52_Response` returns `Valid_Response` → `Support = Read_Write`, `Via_Active_Probe = True`, `Probed = True`.
7. Passive env-var heuristics (applied when `Support = None` after Phases 1 and 2): `TERM_PROGRAM` ∈ `{"WezTerm", "iTerm.app"}` → `Read_Write`; `TERM_PROGRAM = "vscode"` or `WT_SESSION` present → `Write_Only`; `TERM = "xterm-kitty"` → `Read_Write`; `TERM` prefix `"xterm"` → `Write_Only`. Sets `Via_Env_Heuristic = True`.

**Timing:** worst-case 2 s cold-start (DA1 probe + OSC 52 probe, both timing out). Typical < 200 ms when the terminal responds. Cached calls < 1 µs.

**Partial results:** If a probe session fails after Phase 1 has already produced a `Write_Only` result, that partial result is preserved and returned. `Probed = True` is only set when an active probe was actually attempted.

**Exception safety:** Never raises an exception on any code path (FUNC-C52-016).

**Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path of each session (FUNC-C52-014).

**Requirements:** FUNC-C52-006, FUNC-C52-007, FUNC-C52-009, FUNC-C52-010, FUNC-C52-011, FUNC-C52-012, FUNC-C52-013, FUNC-C52-014, FUNC-C52-015, FUNC-C52-016, FUNC-C52-017

---

#### `Detect_Clipboard_Uncached`

```ada
function Detect_Clipboard_Uncached return Clipboard_Capabilities;
```

Cache-bypass variant of `Detect_Clipboard`. Runs the identical detection cascade (all guards + DA1 phase + active OSC 52 probe phase + env-var heuristics phase) without consulting or updating the process-lifetime protected-object cache. Intended for test harnesses that need a fresh probe result (e.g., after a terminal change) and for integration tests that must verify detection behaviour in isolation from the cache.

The cascade, timing, partial-result behaviour, and exception/termios contracts are identical to `Detect_Clipboard`.

**Requirements:** FUNC-C52-016, FUNC-C52-017

---

## Usage Examples

### Detect clipboard capabilities (typical usage)

```ada
with Termicap.Clipboard.IO;  use Termicap.Clipboard.IO;
with Termicap.Clipboard;     use Termicap.Clipboard;

declare
   Cap : constant Clipboard_Capabilities := Detect_Clipboard;
begin
   if Cap.Support >= Write_Only then
      Put_Line ("Clipboard write via OSC 52 is available.");
      if Cap.Via_DA1 then
         Put_Line ("  (Confirmed by DA1 Ps=52 active probe.)");
      elsif Cap.Via_Env_Heuristic then
         Put_Line ("  (Inferred by env-var heuristic — lower confidence.)");
      end if;
   end if;

   if Cap.Support = Read_Write then
      Put_Line ("Clipboard read-back via OSC 52 is available.");
      if Cap.Via_Active_Probe then
         Put_Line ("  (Confirmed by active OSC 52 read-back probe.)");
      end if;
   else
      Put_Line ("Clipboard read-back is not available.");
   end if;

   if not Cap.Probed then
      Put_Line ("(No active probe performed — non-TTY or Windows console.)");
   end if;
end;
```

### Guard on write capability only

```ada
--  Gate any OSC 52 write sequence on >= Write_Only:
if Cap.Support >= Write_Only then
   --  Safe to emit: ESC ] 52 ; c ; <base64-encoded-data> BEL
   null;
end if;
```

### Force a fresh probe (skip cache)

```ada
Cap : constant Clipboard_Capabilities := Detect_Clipboard_Uncached;
```

### Pure OSC 52 parser test (no terminal required)

```ada
with Termicap.Clipboard;  use Termicap.Clipboard;

--  Valid OSC 52 response: ESC ] 52 ; c ; <payload> BEL
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5D#,
      Character'Pos ('5'), Character'Pos ('2'),
      Character'Pos (';'), Character'Pos ('c'),
      Character'Pos (';'),
      Character'Pos ('d'), Character'Pos ('G'),
      16#07#];
   Result : constant OSC52_Parse_Result :=
     Parse_OSC52_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = Valid_Response);
end;

--  Buffer with no OSC 52 introducer (DA1 sentinel only):
declare
   Raw    : constant Byte_Array := [16#1B#, 16#5B#, 16#3F#, 16#63#];  --  ESC [ ? c
   Result : constant OSC52_Parse_Result :=
     Parse_OSC52_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = Not_Present);
end;
```

### Distinguish probe source for logging

```ada
--  Distinguish between DA1-confirmed write-only and heuristic write-only:
if Cap.Support = Write_Only and then Cap.Via_Env_Heuristic then
   --  Heuristic only: emit OSC 52 writes with caution;
   --  DA1 or active probe is more authoritative.
   null;
end if;
```

---

## SPARK Notes

`Termicap.Clipboard` (spec and body) targets SPARK Silver:

| Function | Key proof obligations | Discharged by |
|----------|-----------------------|---------------|
| `Parse_OSC52_Response` | Out-of-bounds access prevention; loop termination; no exception on any input | `Pre => Length <= Buffer'Length`; loop bounded by `Length`; stray bytes skipped |

No manual lemmas, ghost code, or proof pragmas are required.

`Termicap.Clipboard.IO` carries `pragma SPARK_Mode (Off)` on the spec, preventing SPARK-annotated callers from inadvertently calling `Detect_Clipboard` or `Detect_Clipboard_Uncached` without a mode barrier.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-C52-001 | `Clipboard_Support` enumeration | Silver |
| FUNC-C52-002 | `Clipboard_Capabilities` record, `NO_CLIPBOARD_CAPABILITIES` | Silver |
| FUNC-C52-003 | `Clipboard_Access` literal in `Termicap.DA1.DA1_Capability`; `DA1_PS_CLIPBOARD_ACCESS` constant | Silver |
| FUNC-C52-005 | 9 named terminal identifier constants (`TERM_PROGRAM_*`, `ENV_*`, `TERM_*`) | Silver |
| FUNC-C52-006 | DA1 passive probe for Clipboard_Access Ps=52 via `Detect_DA1` | Off |
| FUNC-C52-007 | Active OSC 52 read-back probe; `OSC52_QUERY` constant | Silver (constant) / Off (probe) |
| FUNC-C52-008 | `OSC52_Parse_Result` enumeration; `Parse_OSC52_Response` function | Silver |
| FUNC-C52-009 | Passive env-var heuristics (TERM_PROGRAM, WT_SESSION, TERM) | Off |
| FUNC-C52-010 | Combined detection cascade (DA1 → OSC 52 probe → env-var heuristics) | Off |
| FUNC-C52-011 | tmux and screen OSC 52 query passthrough wrapping | Off |
| FUNC-C52-012 | Pre-condition guards and TTY guards (full cascade) | Off |
| FUNC-C52-013 | Non-TTY passive fallback | Off |
| FUNC-C52-014 | Termios restore on all exit paths via `Probe_Session` RAII | Off |
| FUNC-C52-015 | `CLIPBOARD_PROBE_TIMEOUT_MS`; independent per-session budget (ADR-0028) | Silver (constant) / Off (usage) |
| FUNC-C52-016 | No-exception contract for `Detect_Clipboard` and `Detect_Clipboard_Uncached` | Off |
| FUNC-C52-017 | One-probe-per-process cache; `Detect_Clipboard_Uncached` cache-bypass | Off |
| FUNC-C52-018 | `Termicap.Clipboard` (SPARK On spec + body) + `Termicap.Clipboard.IO` (SPARK Off); platform dispatch via GPR `Source_Dirs` | Mixed |
| FUNC-C52-019 | Integration into `Terminal_Capabilities` — **deferred** | N/A |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Clipboard` and `Termicap.Clipboard.IO` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 30: full clipboard detection cascade, independent probe sessions, multiplexer passthrough, and cache behaviour
- **Tech Spec OSC52** (`docs/tech-specs/osc52-clipboard.md`) — design rationale, detection cascade strategy, framework survey, independent session design, SPARK boundary
- **ADR-0031** (`docs/adr/0031-defer-clipboard-capability-integration.md`) — rationale for deferring integration of `Clipboard_Capabilities` into `Terminal_Capabilities`
- **Requirements** (`docs/requirements/osc52.sdoc`) — FUNC-C52-001 through FUNC-C52-019 (19 approved requirements)
- **[Termicap.DA1](da1.md)** — `DA1_Capabilities`, `Has_Capability`, and `Detect_DA1` infrastructure reused by `Termicap.Clipboard.IO` for the DA1 Ps=52 passive probe; `Clipboard_Access` literal added to `DA1_Capability`
- **[Termicap.OSC](osc.md)** — `Probe_Session`, `Sentinel_Query`, and `Wrap_For_Passthrough` infrastructure used by `Termicap.Clipboard.IO`
- **[Termicap.Graphics](sixel-graphics.md)** — sibling package with the same SPARK split pattern, independent-session design (ADR-0028), and DA1 reuse strategy (ADR-0027)
- **[Termicap.Mouse](mouse-protocol.md)** — sibling package with the same SPARK split pattern and platform dispatch strategy; uses batched probe (contrast with clipboard independent sessions)
- **[Termicap.Keyboard](keyboard.md)** — sibling package illustrating the independent-session pattern for Kitty keyboard vs. XTerm keyboard probes
