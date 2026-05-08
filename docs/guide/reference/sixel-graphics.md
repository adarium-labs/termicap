# API Reference: `Termicap.Graphics` and `Termicap.Graphics.IO`

Package pair providing SPARK Silver-provable response parsing and an I/O boundary for active Sixel and Kitty graphics protocol detection. Detects whether the controlling terminal supports Sixel graphics, the Kitty graphics protocol, or neither.

**Files:**
- `src/termicap-graphics.ads`, `src/termicap-graphics.adb`
- `src/termicap-graphics-io.ads`
- `src/posix/termicap-graphics-io.adb` (POSIX)
- `src/windows/termicap-graphics-io.adb` (Windows)

**SPARK_Mode:** `Termicap.Graphics` — On (spec and body, Silver level); `Termicap.Graphics.IO` — Off (spec and both bodies)
**License:** Apache-2.0

---

## Overview

The Graphics feature detects Sixel and Kitty graphics protocol support in the controlling terminal using a six-step cascade:

1. **Passive Kitty env-var harvest** — `KITTY_WINDOW_ID`, `TERM=xterm-kitty`, `TERM_PROGRAM=WezTerm`. No terminal I/O; runs before TTY guard.
2. **Passive Sixel env-var harvest** — `TERM_PROGRAM=WezTerm` (case-insensitive) plus `TERM` exact match (case-insensitive) for `foot`, `foot-extra`, `mlterm`, `mlterm-256color`, `yaft`. No terminal I/O. The legacy `TERM` prefix `xterm` rule and `TERM = xterm-kitty` exact match were removed (FUNC-SXL-008, conformance B2a): the `xterm` prefix matches every modern terminal that ships with `TERM=xterm-256color`, and kitty intentionally rejects sixel.
3. **DA1 active probe for Sixel Ps=4** — reuses `Termicap.DA1.IO.Detect_DA1`; sets `Sixel_Via_DA1 = True` when `Has_Capability (DA1_Result, Sixel_Graphics)` is true. A valid DA1 response **without** Ps=4 is **authoritative-negative**: the cascade clears any over-eager passive `Sixel_Supported` flag and sets `Probed = True` (FUNC-SXL-005, FUNC-SXL-006, conformance B2b). Runs in an independent `Probe_Session`.
4. **XTVERSION name-substring fallback for Sixel** — case-insensitive name match for "kitty" or "WezTerm" in the XTVERSION response. Skipped when `Sixel_Via_DA1 = True` and also when DA1 produced an authoritative-negative response (`Probed = True` and `Sixel_Supported = False`), so the XTVERSION-name match cannot re-promote a terminal that DA1 just cleared (conformance B2c).
5. **Optional Kitty APC active probe** — sends `KITTY_APC_QUERY` (`ESC _ G i=1,a=q ESC \`) followed by a DA1 sentinel; parses the response with `Parse_Kitty_APC_Response`. Runs in a second independent `Probe_Session`. Skipped when `Kitty_Graphics_Supported` is already `True` from the passive harvest.
6. **XTVERSION-driven Kitty graphics refinement** — when the APC probe is inconclusive (timeout, `Error` reply, or Apple Terminal skip), `Refine_Kitty_With_XTVERSION` consults a curated `KNOWN_GOOD_KITTY` allowlist (iterm2 ≥ 3.6.0, kitty ≥ 0.20.0, wezterm any, ghostty any, konsole ≥ 22.4.0). A match promotes `Kitty_Graphics_Supported` to `True` while leaving `Kitty_Via_Active_Probe = False` (provenance is XTVERSION). Mirrors `Termicap.Hyperlinks.Refine_With_XTVERSION` (FUNC-HYP-011). Upgrade-only — never demotes a passive positive (FUNC-SXL-009, FUNC-SXL-010, conformance B3a).

Platform fast-paths short-circuit before any active probe:
- **Windows native console:** `GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → passive env-var harvest only (`Probed = False`).
- **Non-interactive / error:** non-TTY stdout, background process, probe failure → passive env-var harvest only or `NO_GRAPHICS_CAPABILITIES`.

Unlike the Mouse batched-probe design (ADR-0022), each active probe uses an **independent session** with its own 1 000 ms budget (ADR-0028). Worst-case cold-start latency is 2 s (both probes time out). Typical cold-start latency is < 200 ms when the terminal responds.

`Termicap.Graphics` contains all SPARK-provable building blocks: the `Graphics_Capabilities` record, the `APC_Parse_Result` enumeration, 11 named terminal identifier constants, the `KITTY_APC_QUERY` byte array, the `GRAPHICS_PROBE_TIMEOUT_MS` constant, and the pure `Parse_Kitty_APC_Response` function. All functions carry `Global => null` contracts and are verifiable at SPARK Silver level.

`Termicap.Graphics.IO` contains the I/O boundary: `Detect_Graphics` drives the full cascade and caches the result; `Detect_Graphics_Uncached` is the cache-bypass variant for test harnesses.

---

## Package `Termicap.Graphics`

### Types

#### `Graphics_Capabilities`

```ada
type Graphics_Capabilities is record
   Sixel_Supported          : Boolean := False;
   Kitty_Graphics_Supported : Boolean := False;
   Sixel_Via_DA1            : Boolean := False;
   Kitty_Via_Active_Probe   : Boolean := False;
   Probed                   : Boolean := False;
   Sixel_Color_Registers    : Natural := 0;
   Kitty_Graphics_Version   : Natural := 0;
end record;
```

Aggregate result of Sixel and Kitty graphics protocol detection.

| Field | Description |
|-------|-------------|
| `Sixel_Supported` | `True` when Sixel graphics are available on the controlling terminal, established by any of the three detection paths: DA1 active probe (FUNC-SXL-005), XTVERSION name match (FUNC-SXL-007), or env-var heuristic (FUNC-SXL-008). `False` by default (safe: unsupported Sixel renders as visible garbage). |
| `Kitty_Graphics_Supported` | `True` when the Kitty graphics protocol is available, established by passive env-var heuristics (FUNC-SXL-009) or the optional APC active probe (FUNC-SXL-010). `False` by default. |
| `Sixel_Via_DA1` | `True` when `Sixel_Supported` was set via a successful DA1 probe (Ps=4 present). `False` when set via passive heuristics only, or when `Sixel_Supported` is `False`. |
| `Kitty_Via_Active_Probe` | `True` when `Kitty_Graphics_Supported` was confirmed via the APC active probe (FUNC-SXL-010). `False` when set via passive env-var heuristics only, or when `Kitty_Graphics_Supported` is `False`. |
| `Probed` | `True` when at least one active probe (DA1 or APC) was attempted. `False` when the result was determined entirely by passive env-var heuristics (no TTY, not foreground, `/dev/tty` unopenable, or Win32 Console gate). |
| `Sixel_Color_Registers` | Number of simultaneous colors available for Sixel rendering, or `0` when unknown. Common values: 256 (most terminals), 1024, 65536 (WezTerm). Defaults to `0` in v1; XTSMGRAPHICS probing is deferred. |
| `Kitty_Graphics_Version` | Kitty graphics protocol version, or `0` when not determinable. kitty advertises its version via XTVERSION; version-string parsing is deferred. Defaults to `0` in v1. |

**Implicit invariants** (enforced by construction, not by `Type_Invariant`):
- I1. `Sixel_Via_DA1 = True` ⟹ `Sixel_Supported = True` and `Probed = True`.
- I2. `Kitty_Via_Active_Probe = True` ⟹ `Kitty_Graphics_Supported = True` and `Probed = True`.
- I3. `Probed = False` ⟹ `Sixel_Via_DA1 = False` and `Kitty_Via_Active_Probe = False`.
- I4. `Sixel_Color_Registers > 0` ⟹ `Sixel_Supported = True`.

**Canonical interpretations:**

| State | Meaning |
|-------|---------|
| `Sixel_Supported = False, Kitty_Graphics_Supported = False, Probed = False` | Detection was not performed or all guards suppressed probing (non-TTY, foreground guard, `/dev/tty` open failure, Win32 Console gate). |
| `Sixel_Supported = True, Sixel_Via_DA1 = True, Probed = True` | Sixel confirmed by DA1 Ps=4 active probe (highest confidence). |
| `Sixel_Supported = True, Sixel_Via_DA1 = False` | Sixel inferred by XTVERSION name match or env-var heuristic (lower confidence). |
| `Kitty_Graphics_Supported = True, Kitty_Via_Active_Probe = True, Probed = True` | Kitty graphics confirmed by APC active probe. |
| `Kitty_Graphics_Supported = True, Kitty_Via_Active_Probe = False` | Kitty graphics inferred by env-var heuristics (`KITTY_WINDOW_ID`, `TERM=xterm-kitty`, or `TERM_PROGRAM=WezTerm`). |

**Requirements:** FUNC-SXL-001, FUNC-SXL-002, FUNC-SXL-003

---

#### `APC_Parse_Result`

```ada
type APC_Parse_Result is (Not_Present, OK, Error);
```

Three-way result of the Kitty graphics APC response parser.

| Value | Meaning |
|-------|---------|
| `Not_Present` | No APC G response envelope found in the buffer. The DA1 sentinel arrived first (terminal does not implement the Kitty graphics query). Treated as "not supported". |
| `OK` | APC G response found and its params contain "OK". Terminal confirmed Kitty graphics protocol support. |
| `Error` | APC G response found but params contain "EINVAL". Terminal answered but reported a protocol error. Treated as "not supported". |

Both `Not_Present` and `Error` map to `Kitty_Graphics_Supported = False` for the purpose of FUNC-SXL-010. The distinction is preserved for debugging and test assertions.

**Requirements:** FUNC-SXL-011

---

### Constants

#### `NO_GRAPHICS_CAPABILITIES`

```ada
NO_GRAPHICS_CAPABILITIES : constant Graphics_Capabilities :=
  (Sixel_Supported          => False,
   Kitty_Graphics_Supported => False,
   Sixel_Via_DA1            => False,
   Kitty_Via_Active_Probe   => False,
   Probed                   => False,
   Sixel_Color_Registers    => 0,
   Kitty_Graphics_Version   => 0);
```

Canonical "no result" value. Used as the cache initial value and as the fallback on every error path of `Detect_Graphics`. A `Graphics_Capabilities` declared without an explicit aggregate is equivalent to this value via default initialisation.

**Requirements:** FUNC-SXL-001

---

#### `KITTY_APC_QUERY`

```ada
KITTY_APC_QUERY : constant Byte_Array :=
  [16#1B#,                  --  ESC      (0x1B)
   16#5F#,                  --  _        (0x5F, APC introducer)
   Character'Pos ('G'),     --  G        (0x47)
   Character'Pos ('i'),     --  i        (0x69)
   Character'Pos ('='),     --  =        (0x3D)
   Character'Pos ('1'),     --  1        (0x31)
   Character'Pos (','),     --  ,        (0x2C)
   Character'Pos ('a'),     --  a        (0x61)
   Character'Pos ('='),     --  =        (0x3D)
   Character'Pos ('q'),     --  q        (0x71)
   16#1B#,                  --  ESC      (0x1B)
   16#5C#];                 --  \        (0x5C, ST terminator)
```

12-byte APC Kitty graphics query sequence. Encodes `ESC _ G i=1,a=q ESC \` (APC introducer + `"Gi=1,a=q"` payload + ST terminator). Adopted from the notcurses `KITTYQUERY` macro. A DA1 sentinel (`ESC [ c`) is appended by the caller as a response boundary marker.

**Requirements:** FUNC-SXL-010

---

#### `GRAPHICS_PROBE_TIMEOUT_MS`

```ada
GRAPHICS_PROBE_TIMEOUT_MS : constant Natural := 1_000;
```

Millisecond timeout for each active probe session (DA1 or APC). Each session has its own independent 1 000 ms budget (ADR-0028). Consistent with `MOUSE_PROBE_TIMEOUT_MS` (FUNC-MSE-013), `KITTY_PROBE_TIMEOUT_MS` (FUNC-KKB-013), and the OSC-INFRA default (FUNC-OSC-004). Implementations may use a shorter timeout (minimum 100 ms) on local PTYs.

**Requirements:** FUNC-SXL-015

---

#### Named Terminal Identifier Constants (FUNC-SXL-004)

All 11 constants are of type `String`. They centralise terminal identifier values used in passive detection to avoid scattered string literals.

| Constant | Value | Detection Use |
|----------|-------|---------------|
| `TERM_XTERM_KITTY` | `"xterm-kitty"` | Exact `TERM` match — kitty terminal (Kitty graphics passive harvest, FUNC-SXL-009). Note: kitty does **not** implement Sixel; the constant is no longer consulted by the passive Sixel harvest (FUNC-SXL-008, conformance B2a). |
| `TERM_FOOT` | `"foot"` | Exact `TERM` match — foot Wayland terminal (Sixel, FUNC-SXL-008). |
| `TERM_FOOT_EXTRA` | `"foot-extra"` | Exact `TERM` match — foot with extra capabilities (Sixel, FUNC-SXL-008). |
| `TERM_XTERM` | `"xterm"` | Reserved for future use. The legacy `TERM` prefix `xterm` rule was removed from the passive Sixel harvest in conformance B2a (FUNC-SXL-008): every modern terminal sets `TERM=xterm-256color` and the prefix has no positive predictive value. DA1 (FUNC-SXL-005) is the authoritative source for xterm-family Sixel support. |
| `TERM_MLTERM` | `"mlterm"` | Exact `TERM` match — MLterm (Sixel, FUNC-SXL-008). |
| `TERM_YAFT` | `"yaft"` | Exact `TERM` match — yaft framebuffer terminal (Sixel, FUNC-SXL-008). |
| `TERM_PROGRAM_WEZTERM` | `"WezTerm"` | Case-insensitive `TERM_PROGRAM` match — WezTerm (Sixel + Kitty graphics, FUNC-SXL-008, FUNC-SXL-009). |
| `TERM_PROGRAM_ITERM2` | `"iTerm.app"` | Exact `TERM_PROGRAM` match — iTerm2 for macOS. Reserved for future use; the passive Sixel harvest no longer consults this constant in conformance B2a (FUNC-SXL-008). DA1 (FUNC-SXL-005) is the authoritative source for iTerm2 Sixel support (only iTerm2 ≥ 3.5 implements sixel and DA1 reports Ps=4). |
| `ENV_KITTY_WINDOW_ID` | `"KITTY_WINDOW_ID"` | Env-var name — kitty sets this for every window it manages; highest-confidence passive Kitty indicator (FUNC-SXL-009). |
| `XTVERSION_NAME_KITTY` | `"kitty"` | Case-insensitive XTVERSION name token — kitty reports "kitty x.y.z" (FUNC-SXL-007). |
| `XTVERSION_NAME_WEZTERM` | `"WezTerm"` | Case-insensitive XTVERSION name token — WezTerm reports "WezTerm x.y.z" (FUNC-SXL-007). |

**Requirements:** FUNC-SXL-004

---

### Functions

#### `Parse_Kitty_APC_Response`

```ada
function Parse_Kitty_APC_Response
  (Buffer : Byte_Array;
   Length : Natural) return APC_Parse_Result
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Buffer'Length,
  Post       => True;
```

Parse a Kitty graphics APC response from a raw byte buffer. Scans `Buffer (Buffer'First .. Buffer'First + Length - 1)` for an APC G response envelope of the form:

```
ESC _ G <params> ESC \
```

where the APC introducer is `0x1B 0x5F` and the string terminator is `ESC \` (`0x1B 0x5C`) or `BEL` (`0x07`).

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Buffer` | in | Raw response byte buffer. |
| `Length` | in | Number of valid bytes in `Buffer` to examine (0 .. `Buffer'Length`). |

**Returns:** `APC_Parse_Result` per the rules:
- `OK` — APC G envelope found and `<params>` contains `"OK"`.
- `Error` — APC G envelope found and `<params>` contains `"EINVAL"`.
- `Not_Present` — No APC G envelope found in the buffer (DA1 sentinel arrived first).

The function never raises for any buffer content; stray or out-of-range bytes are skipped. `BEL` (`0x07`) is treated as an alternate APC terminator alongside `ESC \`.

**SPARK contract:** `Global => null` — pure buffer scan, no state, no I/O. `Pre` bounds `Length` within `Buffer` to prevent out-of-bounds access. No loop termination or invariant proof obligations beyond the precondition.

**Note:** This parser mirrors the tri-state design of `Parse_Kitty_Response` in `Termicap.Keyboard` (FUNC-KKB-006), preserving the `Not_Present`/`OK`/`Error` distinction for debugging even though both `Not_Present` and `Error` map to "not supported".

**Example:**

```ada
--  APC G response with "OK" payload: ESC _ G OK ESC \
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5F#,                          --  ESC _
      Character'Pos ('G'),                      --  G
      Character'Pos ('O'), Character'Pos ('K'), --  OK
      16#1B#, 16#5C#];                          --  ESC \
   Result : constant APC_Parse_Result :=
     Parse_Kitty_APC_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = OK);
end;
```

**Requirements:** FUNC-SXL-011

---

## Package `Termicap.Graphics.IO`

### Functions

#### `Detect_Graphics`

```ada
function Detect_Graphics return Graphics_Capabilities;
```

Return the Sixel and Kitty graphics protocol capabilities for the controlling terminal. On the first call, the full detection cascade is executed and the result is stored in a package-level protected object. All subsequent calls return the cached value directly (< 1 µs, no I/O).

**Detection cascade (in order):**

1. Cache hit → return cached result immediately.
2. *(Windows only)* `GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → run passive harvests (Steps 3–4) and return with `Probed = False`.
3. Passive Kitty env-var harvest: `KITTY_WINDOW_ID` present → `Kitty_Graphics_Supported = True`; `TERM = "xterm-kitty"` → `Kitty_Graphics_Supported = True`; `TERM_PROGRAM = "WezTerm"` (case-insensitive) → `Kitty_Graphics_Supported = True`.
4. Passive Sixel env-var harvest (`Has_Sixel_From_Env`): `TERM_PROGRAM = "WezTerm"` (case-insensitive); or `TERM` (case-insensitive) in `{"foot", "foot-extra", "mlterm", "mlterm-256color", "yaft"}` → `Sixel_Supported = True` (heuristic; overridden by DA1). The legacy `TERM` prefix `"xterm"` rule and `TERM = "xterm-kitty"` exact match are intentionally absent (conformance B2a).
5. Non-TTY guard: `Is_TTY (Stdout) = False` → return passive results only (`Probed = False`).
6. DA1 active probe (independent session, 1 000 ms budget): calls `Termicap.DA1.IO.Detect_DA1`; if `Has_Capability (DA1_Result, Sixel_Graphics)` → `Sixel_Supported = True`, `Sixel_Via_DA1 = True`, `Probed = True`. If DA1 returned a valid response **without** Ps=4 → authoritative-negative: `Sixel_Supported = False`, `Sixel_Via_DA1 = False`, `Probed = True` (overrides any over-eager passive flag, conformance B2b).
7. XTVERSION name-substring fallback (skipped when `Sixel_Via_DA1 = True` **and** when DA1 produced an authoritative-negative response, conformance B2c): case-insensitive match for `"kitty"` or `"WezTerm"` in XTVERSION name → `Sixel_Supported = True`.
8. Optional Kitty APC active probe (independent session, 1 000 ms budget; skipped when `Kitty_Graphics_Supported = True`): sends `KITTY_APC_QUERY` + DA1 sentinel; calls `Parse_Kitty_APC_Response`; `OK` → `Kitty_Graphics_Supported = True`, `Kitty_Via_Active_Probe = True`, `Probed = True`.
9. XTVERSION-driven Kitty graphics refinement (`Refine_Kitty_With_XTVERSION`, conformance B3a; skipped when `Kitty_Graphics_Supported = True`): consults `KNOWN_GOOD_KITTY` allowlist; on a match promotes `Kitty_Graphics_Supported = True` (provenance is XTVERSION — `Kitty_Via_Active_Probe` stays `False`).

**Timing:** worst-case 2 s cold-start (DA1 probe + APC probe, both timing out at 1 s each); the XTVERSION refinement reuses any cached XTVERSION result. Typical < 200 ms when the terminal responds. Cached calls < 1 µs.

**Partial results:** If a probe session fails after passive harvests have already produced results, the passive results are preserved and returned. `Probed = True` is only set when an active probe was actually attempted.

**Exception safety:** Never raises an exception on any code path (FUNC-SXL-016).

**Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path of each session (FUNC-SXL-014).

**Requirements:** FUNC-SXL-005, FUNC-SXL-006, FUNC-SXL-007, FUNC-SXL-008, FUNC-SXL-009, FUNC-SXL-010, FUNC-SXL-012, FUNC-SXL-013, FUNC-SXL-014, FUNC-SXL-015, FUNC-SXL-016, FUNC-SXL-017

---

#### `Detect_Graphics_Uncached`

```ada
function Detect_Graphics_Uncached return Graphics_Capabilities;
```

Cache-bypass variant of `Detect_Graphics`. Runs the identical detection cascade (all guards + passive harvests + DA1 probe + XTVERSION fallback + optional APC probe) without consulting or updating the process-lifetime protected-object cache. Intended for test harnesses that need a fresh probe result (e.g., after a terminal change) and for integration tests that must verify detection behaviour in isolation from the cache.

The cascade, timing, partial-result behaviour, and exception/termios contracts are identical to `Detect_Graphics`.

**Requirements:** FUNC-SXL-016, FUNC-SXL-017

---

#### `Has_Sixel_From_Env`

```ada
function Has_Sixel_From_Env
  (Env : Termicap.Environment.Environment) return Boolean;
```

Pure inspection of a captured `Environment` snapshot returning the passive Sixel verdict used by `Detect_Graphics` Step 4. No terminal I/O, no global state, no exceptions.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | Captured environment snapshot (typically built via `Termicap.Environment.Capture.Capture_Current`). |

**Returns:** `True` when one of the high-signal env-var heuristics fires:

1. `TERM_PROGRAM = "WezTerm"` (case-insensitive); or
2. `TERM` (case-insensitive) equals one of `"foot"`, `"foot-extra"`, `"mlterm"`, `"mlterm-256color"`, `"yaft"`.

Otherwise `False`. The function reflects the post-B2a allowlist: the legacy `TERM` prefix `"xterm"` rule and `TERM = "xterm-kitty"` exact match were removed because the prefix matches every modern terminal that ships with `TERM=xterm-256color`, and kitty intentionally rejects sixel.

**When to call it.** Most callers should not — `Detect_Graphics` already invokes `Has_Sixel_From_Env` as Step 4 of the cascade and combines the result with the DA1 active probe. The function is exposed publicly to support deterministic regression tests of the passive harvest in isolation from DA1, XTVERSION, and the APC probe (conformance B2 test scaffolding).

**SPARK contract:** none — `Termicap.Graphics.IO` is `SPARK_Mode => Off` package-wide. The body performs only string comparisons via `Termicap.Environment` (which is SPARK Silver) and never raises.

**Requirements:** FUNC-SXL-008

---

#### `Refine_Kitty_With_XTVERSION`

```ada
function Refine_Kitty_With_XTVERSION
  (Passive : Graphics_Capabilities;
   XTV     : Termicap.XTVERSION.XTVERSION_Result) return Graphics_Capabilities;
```

Value-to-value promoter for Kitty graphics support that mirrors `Termicap.Hyperlinks.Refine_With_XTVERSION` (FUNC-HYP-011). Used as cascade Step 9 when the APC active probe is inconclusive (timeout, `Error` reply, or Apple Terminal skip). No terminal I/O is performed; the caller supplies the previously-collected `XTVERSION_Result`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Passive` | in | The `Graphics_Capabilities` value collected by the cascade up to this point (typically with `Kitty_Graphics_Supported = False`). |
| `XTV` | in | The `XTVERSION_Result` from `Termicap.XTVERSION.IO.Query_And_Identify`. |

**Returns:** A copy of `Passive` with `Kitty_Graphics_Supported := True` when the known-good check passes; `Passive` unchanged otherwise. On promotion, `Kitty_Via_Active_Probe` is left at `False` because the provenance is XTVERSION, not the APC probe.

**Algorithm:**

| Condition | Result |
|-----------|--------|
| `XTV.Status /= Success` | `Passive` unchanged |
| Terminal name (case-insensitive) not in `KNOWN_GOOD_KITTY` | `Passive` unchanged |
| Name found, `Treat_Any` entry | promoted (name match alone) |
| Name found, strict entry, version ≥ minimum | promoted |
| Name found, strict entry, version < minimum or unparseable | `Passive` unchanged |

**`KNOWN_GOOD_KITTY` table (body-private constants, 5 entries):**

| Terminal name token (case-insensitive) | Minimum version | Treat_Any |
|----------------------------------------|-----------------|-----------|
| `iterm2` | 3.6.0 | No |
| `kitty` | 0.20.0 | No |
| `wezterm` | — | Yes |
| `ghostty` | — | Yes |
| `konsole` | 22.4.0 | No |

**Upgrade-only.** The function never demotes a passive positive: a name absent from the table or a too-low version simply leaves the existing `Kitty_Graphics_Supported` flag (typically `False` on entry) in place. Demotion is reserved for the APC active probe.

**Exception safety.** An outer `when others => return Passive` handler guarantees no exception propagation (defence in depth; the body performs no I/O and `Termicap.Version.Compare` is total).

**When to call it.** Most callers should not — `Detect_Graphics` already invokes it as cascade Step 9. The function is exposed publicly so unit tests can verify the allowlist semantics without driving the full cascade (conformance B3a test scaffolding).

**Requirements:** FUNC-SXL-009, FUNC-SXL-010

---

## Usage Examples

### Detect graphics capabilities (typical usage)

```ada
with Termicap.Graphics.IO;  use Termicap.Graphics.IO;
with Termicap.Graphics;     use Termicap.Graphics;

declare
   Cap : constant Graphics_Capabilities := Detect_Graphics;
begin
   if Cap.Sixel_Supported then
      if Cap.Sixel_Via_DA1 then
         Put_Line ("Sixel confirmed by DA1 probe (Ps=4).");
      else
         Put_Line ("Sixel inferred by env-var heuristic or XTVERSION name.");
      end if;
      if Cap.Sixel_Color_Registers > 0 then
         Put_Line ("  Color registers: " & Cap.Sixel_Color_Registers'Image);
      end if;
   else
      Put_Line ("Sixel not supported.");
   end if;

   if Cap.Kitty_Graphics_Supported then
      if Cap.Kitty_Via_Active_Probe then
         Put_Line ("Kitty graphics confirmed by APC active probe.");
      else
         Put_Line ("Kitty graphics inferred by env-var heuristic.");
      end if;
   else
      Put_Line ("Kitty graphics protocol not supported.");
   end if;

   if not Cap.Probed then
      Put_Line ("(No active probe performed — non-TTY or Windows console.)");
   end if;
end;
```

### Force a fresh probe (skip cache)

```ada
Cap : constant Graphics_Capabilities := Detect_Graphics_Uncached;
```

### Pure APC parser test (no terminal required)

```ada
with Termicap.Graphics;  use Termicap.Graphics;

--  APC G response containing "OK" payload: ESC _ G OK ESC \
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5F#,
      Character'Pos ('G'),
      Character'Pos ('O'), Character'Pos ('K'),
      16#1B#, 16#5C#];
   Result : constant APC_Parse_Result :=
     Parse_Kitty_APC_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = OK);
end;

--  Buffer with no APC G envelope (DA1 sentinel only):
declare
   Raw    : constant Byte_Array := [16#1B#, 16#5B#, 16#3F#, 16#63#];  --  ESC [ ? c
   Result : constant APC_Parse_Result :=
     Parse_Kitty_APC_Response (Raw, Raw'Length);
begin
   pragma Assert (Result = Not_Present);
end;
```

### Check whether a specific capability source is available

```ada
--  Distinguish between DA1-confirmed Sixel and heuristic Sixel:
if Cap.Sixel_Supported and then not Cap.Sixel_Via_DA1 then
   --  Heuristic only: use with caution; DA1 is the authoritative source.
   null;
end if;
```

---

## SPARK Notes

`Termicap.Graphics` (spec and body) targets SPARK Silver:

| Function | Key proof obligations | Discharged by |
|----------|-----------------------|---------------|
| `Parse_Kitty_APC_Response` | Out-of-bounds access prevention; loop termination; no exception on any input | `Pre => Length <= Buffer'Length`; loop bounded by `Length`; stray bytes skipped |

No manual lemmas, ghost code, or proof pragmas are required.

`Termicap.Graphics.IO` carries `pragma SPARK_Mode (Off)` on the spec, preventing SPARK-annotated callers from inadvertently calling `Detect_Graphics` or `Detect_Graphics_Uncached` without a mode barrier.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-SXL-001 | `Graphics_Capabilities` record, `NO_GRAPHICS_CAPABILITIES` | Silver |
| FUNC-SXL-002 | `Sixel_Color_Registers` field | Silver |
| FUNC-SXL-003 | `Kitty_Graphics_Version` field | Silver |
| FUNC-SXL-004 | 11 named terminal identifier constants (`TERM_*`, `TERM_PROGRAM_*`, `ENV_*`, `XTVERSION_*`) | Silver |
| FUNC-SXL-005 | DA1 active probe for Sixel Ps=4 via `Detect_DA1` | Off |
| FUNC-SXL-006 | DA1 probe session via OSC-INFRA (`Probe_Session`) | Off |
| FUNC-SXL-007 | XTVERSION name-substring Sixel fallback | Off |
| FUNC-SXL-008 | Passive Sixel env-var heuristics | Off |
| FUNC-SXL-009 | Passive Kitty env-var heuristics | Off |
| FUNC-SXL-010 | Optional Kitty APC active probe; `KITTY_APC_QUERY` constant | Silver (constant) / Off (probe) |
| FUNC-SXL-011 | `APC_Parse_Result` enumeration; `Parse_Kitty_APC_Response` function | Silver |
| FUNC-SXL-012 | Pre-condition guards and TTY guards (full cascade) | Off |
| FUNC-SXL-013 | Non-TTY passive fallback | Off |
| FUNC-SXL-014 | Termios restore on all exit paths via `Probe_Session` RAII | Off |
| FUNC-SXL-015 | `GRAPHICS_PROBE_TIMEOUT_MS`; independent per-session budget (ADR-0028) | Silver (constant) / Off (usage) |
| FUNC-SXL-016 | No-exception contract for `Detect_Graphics` and `Detect_Graphics_Uncached` | Off |
| FUNC-SXL-017 | One-probe-per-process cache; `Detect_Graphics_Uncached` cache-bypass | Off |
| FUNC-SXL-018 | `Termicap.Graphics` (SPARK On spec + body) + `Termicap.Graphics.IO` (SPARK Off); platform dispatch via GPR `Source_Dirs` | Mixed |
| FUNC-SXL-019 | Integration into `Terminal_Capabilities` — **deferred** (ADR-0029) | N/A |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Graphics` and `Termicap.Graphics.IO` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 28: full graphics detection cascade, independent probe sessions, passive harvest ordering, APC skip condition, and cache behaviour
- **Tech Spec SIXEL** (`docs/tech-specs/sixel-graphics.md`) — design rationale, detection cascade strategy, framework survey, independent session vs. batched design, SPARK boundary
- **ADR-0027** (`docs/adr/0027-da1-reuse-vs-fresh-probe.md`) — rationale for reusing `Termicap.DA1.IO.Detect_DA1` rather than issuing a fresh low-level probe
- **ADR-0028** (`docs/adr/0028-graphics-independent-probe-sessions.md`) — rationale for independent sessions (one per probe) over the batched approach used for mouse
- **ADR-0029** (`docs/adr/0029-graphics-package-naming.md`) — rationale for the `Termicap.Graphics` / `Termicap.Graphics.IO` naming and the deferred integration into `Terminal_Capabilities`
- **Requirements** (`docs/requirements/sixel-graphics.sdoc`) — FUNC-SXL-001 through FUNC-SXL-019 (19 approved requirements)
- **[Termicap.DA1](da1.md)** — `DA1_Capabilities`, `Has_Capability`, and `Detect_DA1` infrastructure reused by `Termicap.Graphics.IO` for the Sixel DA1 probe
- **[Termicap.XTVERSION](xtversion.md)** — `Query_And_Identify` infrastructure reused by `Termicap.Graphics.IO` for the XTVERSION name-substring fallback
- **[Termicap.OSC](osc.md)** — `Probe_Session`, `Write_Query`, and `Sentinel_Query` infrastructure used by `Termicap.Graphics.IO`
- **[Termicap.Mouse](mouse-protocol.md)** — sibling package with the same SPARK split pattern and platform dispatch strategy; uses batched probe (contrast with graphics independent sessions)
- **[Termicap.Keyboard](keyboard.md)** — sibling package illustrating the independent-session pattern for Kitty keyboard vs. XTerm keyboard probes
