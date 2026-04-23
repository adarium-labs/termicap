# API Reference: `Termicap.Keyboard` and `Termicap.Keyboard.IO`

Package pair providing SPARK Silver-provable response parsing and an I/O boundary for active keyboard protocol detection. Detects which of four keyboard input protocols the controlling terminal supports: `Win32`, `Kitty`, `XTerm_CSI`, `Legacy`, or `Unknown`.

**Files:**
- `src/termicap-keyboard.ads`, `src/termicap-keyboard.adb`
- `src/termicap-keyboard-io.ads`
- `src/posix/termicap-keyboard-io.adb` (POSIX)
- `src/windows/termicap-keyboard-io.adb` (Windows)

**SPARK_Mode:** `Termicap.Keyboard` — On (spec and body, Silver level); `Termicap.Keyboard.IO` — Off (spec and both bodies)
**License:** Apache-2.0

---

## Overview

The Keyboard feature detects which keyboard input encoding protocol the controlling terminal supports by sending two CSI escape sequences — a Kitty protocol query (`CSI ? u`) and an XTerm modifyOtherKeys query (`CSI ? 4 m`) — each bounded by a DA1 sentinel, and observing which response (if any) arrives before the sentinel. The four-level priority cascade is:

**Win32 > Kitty probe > XTerm probe > Legacy**

The cascade short-circuits as soon as a result is determined:
- **Windows native console:** `GetConsoleMode (STD_INPUT_HANDLE)` succeeds → `Win32` without a probe.
- **Kitty protocol:** `CSI ? u` response arrives before the DA1 sentinel → `Kitty` with parsed flags.
- **XTerm modifyOtherKeys:** `CSI ? 4 m` response arrives before the DA1 sentinel → `XTerm_CSI`.
- **Otherwise:** → `Legacy` (probed but no modern protocol detected).
- **Non-interactive / error:** non-TTY stdin, background process, probe failure → `Unknown` (`NO_KEYBOARD_CAPABILITY`, `Probed => False`).

`Termicap.Keyboard` contains all SPARK-provable building blocks: the `Keyboard_Protocol` enumeration, `Kitty_Flags` and `Keyboard_Capability` record types, CSI query byte constants, and three pure parsing functions. These functions carry `Global => null` contracts and are verifiable at SPARK Silver level without manual lemmas.

`Termicap.Keyboard.IO` contains the I/O boundary: `Detect_Keyboard_Protocol` drives the cascade and caches the result; `Probe_Keyboard_Protocol` is the uncached variant. The result is cached in a package-level protected object for the process lifetime.

---

## Package `Termicap.Keyboard`

### Types

#### `Keyboard_Protocol`

```ada
type Keyboard_Protocol is (Unknown, Legacy, XTerm_CSI, Kitty, Win32);
```

Five-value enumeration representing the detected keyboard input encoding.

| Value | Meaning |
|-------|---------|
| `Unknown` | No probe was executed (non-TTY, background process, or probe failure). `Probed = False`. |
| `Legacy` | Both probes timed out or returned no recognised response. Terminal uses classic VT/ANSI encoding. `Probed = True`. |
| `XTerm_CSI` | The XTerm modifyOtherKeys query produced a recognised response before the DA1 sentinel. `Probed = True`. |
| `Kitty` | The Kitty keyboard protocol query produced a recognised response before the DA1 sentinel. `Probed = True`. |
| `Win32` | Native Windows console detected via `GetConsoleMode`. No probe was executed. `Probed = False`. |

**Requirements:** FUNC-KKB-001

---

#### `Kitty_Flags`

```ada
type Kitty_Flags is record
   Disambiguate_Escape_Codes : Boolean := False;
   Report_Event_Types        : Boolean := False;
   Report_Alternate_Keys     : Boolean := False;
   Report_All_Keys_As_Escape : Boolean := False;
   Report_Associated_Text    : Boolean := False;
end record;
```

Kitty keyboard protocol capability flags (bits 0..4 of the flags integer in the `CSI ? <n> u` response). All fields default to `False`. Bits >= 5 are silently ignored.

**Requirements:** FUNC-KKB-002

---

#### `Keyboard_Capability`

```ada
type Keyboard_Capability is record
   Protocol : Keyboard_Protocol := Unknown;
   Flags    : Kitty_Flags       := NO_KITTY_FLAGS;
   Probed   : Boolean           := False;
end record;
```

The result of a keyboard protocol detection. `Flags` is only meaningful when `Protocol = Kitty`; it is `NO_KITTY_FLAGS` for all other protocol values. `Probed = False` means the result was determined without a terminal probe (cache hit, Win32 gate, non-TTY guard, or probe failure).

**Requirements:** FUNC-KKB-003

---

#### `Parse_Result`

```ada
type Parse_Result (Found : Boolean := False) is record
   case Found is
      when True  => Flags : Kitty_Flags;
      when False => null;
   end case;
end record;
```

Discriminated return type for `Parse_Kitty_Response`.

| Discriminant | Fields available | Description |
|-------------|-----------------|-------------|
| `True` | `Flags` | A valid Kitty response was found; `Flags` contains the parsed capability bits. |
| `False` | (none) | No valid Kitty response found in the buffer. |

**Requirements:** FUNC-KKB-006

---

### Constants

#### `NO_KITTY_FLAGS`

```ada
NO_KITTY_FLAGS : constant Kitty_Flags := (others => False);
```

Canonical zero `Kitty_Flags` value with all capability bits unset. Used as the `Flags` field value for all non-Kitty results.

---

#### `NO_KEYBOARD_CAPABILITY`

```ada
NO_KEYBOARD_CAPABILITY : constant Keyboard_Capability :=
  (Protocol => Unknown, Flags => NO_KITTY_FLAGS, Probed => False);
```

Canonical "no result" capability. Returned on non-TTY stdin, background process, and probe failure paths (FUNC-KKB-011, FUNC-KKB-014).

---

#### `CSI_KITTY_QUERY`

```ada
CSI_KITTY_QUERY : constant Byte_Array :=
  [16#1B#, 16#5B#, 16#3F#, Character'Pos ('u')];
```

Four-byte encoding of `ESC [ ? u` — the Kitty keyboard protocol detection query (FUNC-KKB-004).

---

#### `CSI_XTERM_KBD_QUERY`

```ada
CSI_XTERM_KBD_QUERY : constant Byte_Array :=
  [16#1B#, 16#5B#, 16#3F#, Character'Pos ('4'), Character'Pos ('m')];
```

Five-byte encoding of `ESC [ ? 4 m` — the XTerm modifyOtherKeys detection query (FUNC-KKB-007).

---

#### `KITTY_PROBE_TIMEOUT_MS`

```ada
KITTY_PROBE_TIMEOUT_MS : constant := 1_000;
```

Millisecond timeout for the Kitty probe. Per-probe timeout; the XTerm probe uses its own independent timeout (FUNC-KKB-013).

---

#### `XTERM_KBD_PROBE_TIMEOUT_MS`

```ada
XTERM_KBD_PROBE_TIMEOUT_MS : constant := 1_000;
```

Millisecond timeout for the XTerm modifyOtherKeys probe (FUNC-KKB-013).

---

#### `MAX_RESPONSE_SIZE`

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
```

Maximum number of response bytes accumulated per probe. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Bounds all parsing loops for SPARK provability.

---

### Functions

#### `Parse_Kitty_Flags`

```ada
function Parse_Kitty_Flags (Flags_Int : Natural) return Kitty_Flags
with Global => null;
```

Convert the raw integer flags field from a Kitty `CSI ? <n> u` response into a `Kitty_Flags` record by extracting bits 0 through 4. Bits >= 5 are ignored.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Flags_Int` | in | Raw flags integer from the parsed Kitty response. |

**Returns:** `Kitty_Flags` with Boolean fields corresponding to bits 0..4.

**SPARK contract:** `Global => null` — pure bit manipulation, no state, no I/O.

**Requirements:** FUNC-KKB-005

---

#### `Parse_Kitty_Response`

```ada
function Parse_Kitty_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Parse_Result
with
  Global => null,
  Pre    => Length <= Bytes'Length
              and then Length <= MAX_RESPONSE_SIZE;
```

Scan `Bytes(1 .. Length)` for a well-formed Kitty keyboard response envelope `ESC [ ? <digits>* u`. The digits field (`<n>`) may be empty (bare `CSI ? u`), in which case flags = 0 and `Parse_Kitty_Flags (0)` produces all-`False` flags.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | Raw pre-sentinel response byte buffer. |
| `Length` | in | Number of valid bytes to examine. |

**Returns:** `Parse_Result'(Found => True, Flags => …)` if a valid response is present; `Parse_Result'(Found => False)` otherwise.

**SPARK contract:** `Pre` bounds `Length` within `Bytes` and within `MAX_RESPONSE_SIZE` — prevents out-of-bounds access; loop bounded by `Length`.

**Requirements:** FUNC-KKB-006, FUNC-KKB-016

---

#### `Parse_XTerm_Keyboard_Response`

```ada
function Parse_XTerm_Keyboard_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Boolean
with
  Global => null,
  Pre    => Length <= Bytes'Length;
```

Return `True` if `Bytes(1 .. Length)` contains a well-formed XTerm modifyOtherKeys response `ESC [ ? 4 ; <value> m`, where `<value>` is at least one decimal digit.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | Raw pre-sentinel response byte buffer. |
| `Length` | in | Number of valid bytes to examine. |

**Returns:** `True` when the response matches the XTerm modifyOtherKeys pattern; `False` otherwise.

**SPARK contract:** `Pre => Length <= Bytes'Length` — prevents out-of-bounds access.

**Requirements:** FUNC-KKB-008

---

## Package `Termicap.Keyboard.IO`

### Functions

#### `Detect_Keyboard_Protocol`

```ada
function Detect_Keyboard_Protocol return Keyboard_Capability;
```

Return the keyboard protocol capability for the controlling terminal. On the first call the full cascade is executed and the result is stored in a package-level protected object. All subsequent calls return the cached value directly (< 1 µs, no I/O).

**Cascade (in priority order):**

1. Cache hit → return cached result.
2. *(Windows only)* `GetConsoleMode (STD_INPUT_HANDLE)` succeeds → return `(Win32, NO_KITTY_FLAGS, Probed => False)`.
3. Non-TTY stdin or background process → return `NO_KEYBOARD_CAPABILITY`.
4. `Probe_Session.Open` fails → return `NO_KEYBOARD_CAPABILITY`.
5. Kitty `Sentinel_Query` (`CSI ? u` + DA1 sentinel, 1 s timeout) → `Parse_Kitty_Response`:
   - Match → return `(Kitty, parsed flags, Probed => True)`.
6. XTerm `Sentinel_Query` (`CSI ? 4 m` + DA1 sentinel, 1 s timeout) → `Parse_XTerm_Keyboard_Response`:
   - Match → return `(XTerm_CSI, NO_KITTY_FLAGS, Probed => True)`.
7. Fallback → return `(Legacy, NO_KITTY_FLAGS, Probed => True)`.

**Timing:** worst-case 2 s (both probes time out); typical < 100 ms when the terminal responds.

**Exception safety:** Never raises an exception on any code path (FUNC-KKB-014).

**Termios safety:** `Probe_Session.Finalize` is called unconditionally on every exit path (FUNC-KKB-015).

**Requirements:** FUNC-KKB-009, FUNC-KKB-010, FUNC-KKB-011, FUNC-KKB-012, FUNC-KKB-013, FUNC-KKB-014, FUNC-KKB-015, FUNC-KKB-017

---

#### `Probe_Keyboard_Protocol`

```ada
function Probe_Keyboard_Protocol return Keyboard_Capability;
```

Uncached variant of `Detect_Keyboard_Protocol`. Runs the full cascade on every call without consulting or updating the protected-object cache. Useful for testing, or when a fresh probe is required after terminal reconfiguration.

The cascade, timing, and exception/termios contracts are identical to `Detect_Keyboard_Protocol`.

**Requirements:** FUNC-KKB-009, FUNC-KKB-010, FUNC-KKB-011, FUNC-KKB-012, FUNC-KKB-013, FUNC-KKB-014, FUNC-KKB-015

---

## Usage Examples

### Detect keyboard protocol (typical usage)

```ada
with Termicap.Keyboard.IO;  use Termicap.Keyboard.IO;
with Termicap.Keyboard;     use Termicap.Keyboard;

declare
   Cap : constant Keyboard_Capability := Detect_Keyboard_Protocol;
begin
   case Cap.Protocol is
      when Win32 =>
         Put_Line ("Windows native console.");
      when Kitty =>
         Put_Line ("Kitty keyboard protocol.");
         if Cap.Flags.Disambiguate_Escape_Codes then
            Put_Line ("  Disambiguate escape codes: supported.");
         end if;
      when XTerm_CSI =>
         Put_Line ("XTerm modifyOtherKeys detected.");
      when Legacy =>
         Put_Line ("Legacy VT/ANSI encoding.");
      when Unknown =>
         Put_Line ("Not an interactive terminal or probe failed.");
   end case;
end;
```

### Force a fresh probe (skip cache)

```ada
Cap : constant Keyboard_Capability := Probe_Keyboard_Protocol;
```

### Pure parser test (no terminal required)

```ada
with Termicap.Keyboard; use Termicap.Keyboard;

--  Kitty response "ESC [ ? 31 u" (flags = 16#1F# = all five bits set)
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#5B#, 16#3F#,                   --  ESC [ ?
      Character'Pos ('3'), Character'Pos ('1'),  --  3 1
      Character'Pos ('u')];                      --  u
   Result : constant Parse_Result :=
     Parse_Kitty_Response (Raw, Raw'Length);
begin
   pragma Assert (Result.Found = True);
   pragma Assert (Result.Flags.Disambiguate_Escape_Codes = True);
   pragma Assert (Result.Flags.Report_Event_Types = True);
end;
```

### Pointer to full demo

See `examples/keyboard_protocol_demo/` for a three-scenario runnable example: cached detect, uncached probe, and pure parser demonstration.

---

## SPARK Notes

`Termicap.Keyboard` targets SPARK Silver:

| Function | Key proof obligations | Discharged by |
|----------|-----------------------|---------------|
| `Parse_Kitty_Flags` | Bit-extraction within bounds | `Global => null`; pure arithmetic on a `Natural` |
| `Parse_Kitty_Response` | Out-of-bounds access prevention; loop termination | `Pre => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE`; loop bounded by `Length` |
| `Parse_XTerm_Keyboard_Response` | Out-of-bounds access prevention | `Pre => Length <= Bytes'Length`; loop bounded by `Length` |

No manual lemmas, ghost code, or proof pragmas are required for any of the three functions.

`Termicap.Keyboard.IO` carries `pragma SPARK_Mode (Off)` on the spec, preventing SPARK-annotated callers from inadvertently calling `Detect_Keyboard_Protocol` or `Probe_Keyboard_Protocol` without a mode barrier.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-KKB-001 | `Keyboard_Protocol` enumeration | Silver |
| FUNC-KKB-002 | `Kitty_Flags` record | Silver |
| FUNC-KKB-003 | `Keyboard_Capability` record, `NO_KEYBOARD_CAPABILITY` | Silver |
| FUNC-KKB-004 | `CSI_KITTY_QUERY` constant | Silver |
| FUNC-KKB-005 | `Parse_Kitty_Flags` | Silver |
| FUNC-KKB-006 | `Parse_Kitty_Response`, `Parse_Result` | Silver |
| FUNC-KKB-007 | `CSI_XTERM_KBD_QUERY` constant | Silver |
| FUNC-KKB-008 | `Parse_XTerm_Keyboard_Response` | Silver |
| FUNC-KKB-009 | `Detect_Keyboard_Protocol` / `Probe_Keyboard_Protocol` cascade order | Off |
| FUNC-KKB-010 | Windows `GetConsoleMode` gate (Windows body) | Off |
| FUNC-KKB-011 | Non-TTY and foreground guards | Off |
| FUNC-KKB-012 | Probe I/O exclusively via `Termicap.OSC.Sentinel_Query` | Off |
| FUNC-KKB-013 | `KITTY_PROBE_TIMEOUT_MS`, `XTERM_KBD_PROBE_TIMEOUT_MS` (1 000 ms each) | Silver (constants) / Off (usage) |
| FUNC-KKB-014 | No-exception contract for `Detect_Keyboard_Protocol` | Off |
| FUNC-KKB-015 | Termios restore via `Probe_Session` RAII | Off |
| FUNC-KKB-016 | `Parse_Kitty_Response` handles partial/garbled responses | Silver |
| FUNC-KKB-017 | One-probe-per-process cache via protected object | Off |
| FUNC-KKB-018 | `Termicap.Keyboard` (SPARK On) + `Termicap.Keyboard.IO` (SPARK Off) split; platform dispatch via GPR `Source_Dirs` | Mixed |
| FUNC-KKB-019 | Integration into `Terminal_Capabilities` — **deferred** (ADR-0021) | N/A |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Keyboard` and `Termicap.Keyboard.IO` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 26: full keyboard protocol detection cascade, Win32 fast-path, probe lifecycle, and cache behaviour
- **Tech Spec KITTY-KB** (`docs/tech-specs/kitty-keyboard.md`) — design rationale, framework survey (tcell, crossterm, notcurses), DA1 sentinel reuse, platform dispatch strategy
- **ADR-0021** (`docs/adr/0021-defer-keyboard-capability-integration.md`) — rationale for deferring `Keyboard_Capability` integration into `Terminal_Capabilities` and the migration path
- **Requirements** (`docs/requirements/kitty-keyboard.sdoc`) — FUNC-KKB-001 through FUNC-KKB-019 (19 approved requirements)
- **[Termicap.OSC](osc.md)** — `Probe_Session` and `Sentinel_Query` infrastructure used by `Termicap.Keyboard.IO`
- **[Termicap.DA1](da1.md)** — DA1 sentinel infrastructure reused as the keyboard probe boundary
- **Example** (`examples/keyboard_protocol_demo/`) — runnable demo: cached detect, uncached probe, pure parser
