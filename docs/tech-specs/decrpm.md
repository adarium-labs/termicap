# Technical Specification: DECRPM Private Mode Queries

**Feature:** DECRPM (DEC Private Mode Report) Queries
**Requirements:** `docs/requirements/functional/decrpm.sdoc` (FUNC-RPM-001 through FUNC-RPM-017)
**Date:** 2026-04-07

---

## 1. Overview

DECRPM (DEC Private Mode Report) is a terminal protocol that allows a program to query whether a specific DEC private mode is supported and what its current state is. The query sends `CSI ? <mode> $ p` and the terminal responds with `CSI ? <mode> ; <status> $ y`, where `<status>` is a numeric code: 0 (not recognized), 1 (set/enabled), 2 (reset/disabled), 3 (permanently set), or 4 (permanently reset).

This feature matters for terminal capability detection because it provides runtime answers to questions that environment variables and terminal identification cannot answer definitively:

- **Mouse support:** Does this terminal support X11 mouse tracking (mode 1000) or SGR mouse encoding (mode 1006)?
- **Bracketed paste:** Is mode 2004 available, preventing paste injection attacks?
- **Synchronized output:** Does mode 2026 exist, enabling flicker-free rendering?
- **Alternate screen:** Is mode 1049 available for full-screen TUI applications?

Unlike passive detection (environment variables, TERM database), DECRPM provides ground truth from the terminal itself. Unlike DA1 (which advertises hardware capabilities), DECRPM queries individual feature modes and reports their current activation state.

**Dependencies on existing features:**

- `Termicap.OSC` -- `Probe_Session`, `Sentinel_Query`, `Byte`, `Byte_Array`, `Response_Buffer`, `MAX_RESPONSE_SIZE`, `Session_Status` (Tier 3, SPARK Off)
- `Termicap.OSC.Parsing` -- `Wrap_For_Passthrough`, `Passthrough_Mode` (Tier 3, SPARK Silver)
- `Termicap.Terminal_Id` -- `Terminal_Identity`, `Detect_Terminal_Identity` for multiplexer detection (Tier 2)
- `Termicap.Environment` / `Termicap.Environment.Capture` -- environment snapshot for terminal identity detection (Tier 1)

---

## 2. Framework Survey

### tcell (Go)

tcell provides the most complete DECRPM integration among the reference frameworks.

1. **Type system:** `vt/mode.go` defines `PrivateMode` as a named integer type with 22 named constants covering modes 1 (AppCursor) through 9001 (Win32Input). `ModeStatus` is a separate named integer type. This parallels the Termicap `Mode_Id` subtype and `Mode_Status` enumeration.

2. **Query construction:** The `Query()` method on `PrivateMode` constructs the `CSI ? <mode> $ p` sequence via `fmt.Sprintf("\x1b[?%d$p", pm)` (`vt/mode.go` line 66). This is the same byte pattern that `DECRPM_Query` (FUNC-RPM-005) produces.

3. **Response generation:** The `Reply()` method constructs `CSI ? <mode> ; <status> $ y` via `fmt.Sprintf("\x1b[?%d;%d$y", pm, status)` (`vt/mode.go` line 71). tcell's VT emulator uses this in `processRequestPrivateMode` (`vt/emulate.go` line 1237) to respond to DECRQM queries from hosted applications.

4. **Sentinel pattern:** tcell uses DA1 (`CSI c`) as a sentinel for mode detection: "send keyboard query + DA1; if DA1 response arrives first, keyboard protocol is unsupported" (global synthesis section 2.7). This is identical to Termicap's `Sentinel_Query` pattern.

5. **Mode constants:** tcell tracks 22 private modes including `PmMouseButton` (1000), `PmMouseSgr` (1006), `PmAltScreen` (1049), `PmBracketedPaste` (2004), `PmSyncOutput` (2026), and `PmGraphemeClusters` (2027). Termicap's initial six constants (FUNC-RPM-001) are a strict subset.

### blessed (Python)

blessed provides the most user-facing DECRPM API among the reference frameworks.

1. **Response type:** `blessed/dec_modes.py` defines `DecModeResponse` with numeric constants `NOT_QUERIED` (-2), `NO_RESPONSE` (-1), `NOT_RECOGNIZED` (0), `SET` (1), `RESET` (2), `PERMANENTLY_SET` (3), `PERMANENTLY_RESET` (4). Helper properties (`supported`, `enabled`, `disabled`, `permanent`, `failed`) provide semantic access. This maps directly to Termicap's `Mode_Status` enumeration.

2. **Query mechanism:** `terminal.py` line 1289 constructs the query as `f'\x1b[?{int(mode):d}$p'` and matches responses against `re.compile(f'\x1b\\[\\?{int(mode):d};([0-4])\\$y')`. The regex-based approach validates the mode number echo and extracts the status digit.

3. **Caching:** blessed caches DECRPM results per mode number (`_dec_mode_cache` dict) and short-circuits all queries after the first timeout (`_dec_first_query_failed`). Termicap v1 does not implement caching for DECRPM (caching is a `Termicap.Capabilities` concern), but the "first timeout means all timeouts" heuristic is a useful pattern for callers.

4. **Boundary detection:** blessed uses `_query_with_boundary()` which sends a CPR (Cursor Position Report) request as a sentinel after the DECRQM query, similar to Termicap's DA1 sentinel pattern.

### WezTerm / termwiz (Rust)

WezTerm implements DECRPM on the terminal emulator side rather than the client side.

1. **Type system:** `wezterm-escape-parser/src/csi.rs` defines `DecPrivateMode` as an enum with `Code(DecPrivateModeCode)` and `Unspecified(u16)` variants. `DecPrivateModeCode` is a comprehensive enumeration of ~30 named modes. This is a more typed approach than tcell's integer type.

2. **Response handling:** WezTerm's escape parser recognises `CSI ? Ps ; Pm $ y` responses and dispatches them through the terminal state machine. The changelog notes bug fixes for DECRPM/DECRQM handling, confirming this is actively maintained.

3. **Relevance:** WezTerm validates that the `$ y` suffix is unique to DECRPM responses (no other CSI sequence uses it), which supports the recognition strategy in `Contains_DECRPM_Response`.

### notcurses (C)

notcurses does not use DECRPM queries directly. It relies on DA1 for capability detection and XTSMGRAPHICS for graphics capabilities. However, notcurses's DA1 sentinel pattern (all other queries are bounded by the DA1 response) is the same pattern that Termicap uses for DECRPM queries via `Sentinel_Query`.

### Key differences for Termicap

| Aspect | tcell (Go) | blessed (Python) | WezTerm (Rust) | Termicap (Ada) |
|--------|-----------|------------------|----------------|----------------|
| Query construction | `fmt.Sprintf` | f-string | Parser (emulator side) | Pure SPARK function |
| Response parsing | Event loop dispatch | Regex match | Escape parser state machine | Pure SPARK byte scan |
| Status type | Named int | Int constants + properties | Enum variants | Ada enumeration |
| Sentinel | DA1 | CPR | N/A (emulator) | DA1 via `Sentinel_Query` |
| Caching | Per-session | Per-terminal instance | N/A | External (`Capabilities`) |
| Batch queries | Sequential in session | Individual with cache | N/A | Single `Probe_Session` (FUNC-RPM-011) |
| SPARK provability | N/A | N/A | N/A | Silver for parsing |

### Patterns borrowed

| Pattern | Source | Adaptation |
|---------|--------|------------|
| Integer mode type + named constants | tcell `PrivateMode` | `Mode_Id` subtype + `MODE_*` constants |
| Five-value status enumeration | DEC spec, blessed `DecModeResponse`, tcell `ModeStatus` | `Mode_Status` enumeration with identical semantics |
| DA1 sentinel for response boundary | tcell keyboard detection, Termicap `Sentinel_Query` | Reuse existing `Sentinel_Query` unchanged |
| First-timeout-kills-all heuristic | blessed `_dec_first_query_failed` | Not in v1; documented for callers |
| Batch queries in single session | tcell sequential queries | `Detect_Modes` with per-query DA1 sentinel |

---

## 3. Package Architecture

### Package tree

```
Termicap                                  (existing root namespace)
├── Termicap.DECRPM                       [SPARK_Mode => On]  -- types, constants, parsing
│   └── Termicap.DECRPM.IO              [SPARK_Mode => Off] -- Query_Mode, Detect_Mode, Detect_Modes
```

### SPARK boundary rationale

| Package | SPARK_Mode | Reason |
|---------|------------|--------|
| `Termicap.DECRPM` | On | Pure types (`Mode_Id`, `Mode_Status`, `Mode_Report`, `Mode_Id_Array`, `Mode_Report_Array`), the `DECRPM_Query` function, `Contains_DECRPM_Response`, and `Parse_DECRPM_Response`. No FFI, no controlled types, no global state. All functions carry Silver-level contracts with `Global => null`. Re-declares compatible `Byte`/`Byte_Array` types using `Interfaces.C.unsigned_char` (same pattern as `Termicap.XTVERSION` and `Termicap.DA1`). |
| `Termicap.DECRPM.IO` | Off | Contains `Query_Error` enumeration, `Mode_Query_Result` and `Batch_Query_Result` discriminated records, `Query_Mode` procedure, `Detect_Mode` function, and `Detect_Modes` batch function. Calls `Termicap.OSC.Probe_Session` (controlled type) and `Sentinel_Query`. Accesses `Termicap.Terminal_Id` for multiplexer detection. |

### SPARK dependency note

`Termicap.DECRPM` (SPARK On) does not depend on `Termicap.OSC` (SPARK Off) or `Termicap.OSC.Parsing` (SPARK On). Unlike `Termicap.DA1`, which needs `DA1_Params` from `Termicap.OSC.Parsing`, the DECRPM parsing functions operate directly on raw `Byte_Array` buffers. The `Byte` and `Byte_Array` types are re-declared in `Termicap.DECRPM` using `Interfaces.C.unsigned_char`, following the same pattern as `Termicap.XTVERSION` (`src/termicap-xtversion.ads` lines 52-57). The I/O layer (`Termicap.DECRPM.IO`) converts between the two `Byte_Array` types at the boundary, just as `Termicap.XTVERSION.IO` does (`src/termicap-xtversion-io.adb` lines 73-75).

### No new C source file

All terminal I/O is performed through the existing `Termicap.OSC.Probe_Session` and `Sentinel_Query` infrastructure. DECRPM queries use standard CSI sequences, which do not require multiplexer passthrough wrapping in practice (CSI sequences are forwarded by tmux and screen without wrapping, unlike DCS/OSC sequences). No new system calls, C wrappers, or FFI bindings are introduced.

### File layout

| File | Purpose |
|------|---------|
| `src/termicap-decrpm.ads` | `Mode_Id` subtype, `MODE_*` constants, `Mode_Status` enum, `Mode_Report` record, `Mode_Id_Array`/`Mode_Report_Array` types, `MAX_BATCH_MODES` constant, `MAX_RESPONSE_SIZE` constant, `Byte`/`Byte_Array` types, `DECRPM_Query`, `Contains_DECRPM_Response`, `Parse_DECRPM_Response` function specs |
| `src/termicap-decrpm.adb` | `DECRPM_Query`, `Contains_DECRPM_Response`, `Parse_DECRPM_Response` function bodies |
| `src/termicap-decrpm-io.ads` | `Query_Error` enum, `Mode_Query_Result`/`Batch_Query_Result` discriminated records, `Query_Mode` procedure spec, `Detect_Mode`/`Detect_Modes` function specs |
| `src/termicap-decrpm-io.adb` | `Query_Mode` body: probe session + sentinel query; `Detect_Mode` body; `Detect_Modes` body |

---

## 4. Type Design

All types in sections 4.1 through 4.6 are declared in `Termicap.DECRPM` (SPARK_Mode => On). Types in sections 4.7 through 4.9 are declared in `Termicap.DECRPM.IO` (SPARK_Mode => Off).

### 4.1 Byte Types

```ada
subtype Byte is Interfaces.C.unsigned_char;

type Byte_Array is array (Positive range <>) of Byte;
```

Re-declared independently of `Termicap.OSC` to maintain SPARK On status. Representation-compatible with `Termicap.OSC.Byte_Array`, `Termicap.XTVERSION.Byte_Array`, and `Termicap.DA1.Byte_Array`. Follows the pattern at `src/termicap-xtversion.ads` lines 52-57 and `src/termicap-da1.ads` lines 55-61.

### 4.2 Capacity Constant

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
```

Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Used in the precondition of `Parse_DECRPM_Response` to bound parsing loops for SPARK provability. Same pattern as `Termicap.XTVERSION.MAX_RESPONSE_SIZE` (`src/termicap-xtversion.ads` line 67).

### 4.3 Mode_Id Subtype and Named Constants (FUNC-RPM-001)

```ada
subtype Mode_Id is Natural;

MODE_CURSOR_VISIBILITY : constant Mode_Id := 25;
MODE_MOUSE_X11         : constant Mode_Id := 1000;
MODE_MOUSE_SGR         : constant Mode_Id := 1006;
MODE_ALT_SCREEN        : constant Mode_Id := 1049;
MODE_BRACKETED_PASTE   : constant Mode_Id := 2004;
MODE_SYNC_OUTPUT       : constant Mode_Id := 2026;
```

Using a `Natural` subtype rather than a distinct integer type allows callers to pass literal integers for vendor-specific modes without type conversion. The six named constants cover the modes with broadest practical impact: cursor visibility (DECTCEM), X11 mouse tracking, SGR mouse encoding, alternate screen buffer, bracketed paste, and synchronized output. Named constants follow `ALL_CAPS_WITH_UNDERSCORES` per the coding standard.

### 4.4 Mode_Status Enumeration (FUNC-RPM-002)

```ada
type Mode_Status is
  (Not_Recognized,
   Set,
   Reset,
   Permanently_Set,
   Permanently_Reset);
```

Maps the five DECRPM response codes (Pm = 0..4) to named literals. Ordering places `Not_Recognized` first so that a default-initialized `Mode_Status` value is the safest default. Any Pm value outside 0..4 is mapped to `Not_Recognized`. Naming follows DEC terminology (`Set`/`Reset` rather than `Enabled`/`Disabled`).

**Pm-to-Mode_Status mapping:**

| Pm | Mode_Status | Meaning |
|----|-------------|---------|
| 0 | `Not_Recognized` | Terminal does not implement this mode |
| 1 | `Set` | Mode is currently enabled |
| 2 | `Reset` | Mode is currently disabled |
| 3 | `Permanently_Set` | Mode is always enabled, cannot be changed |
| 4 | `Permanently_Reset` | Mode is always disabled, cannot be changed |
| Other | `Not_Recognized` | Unknown status code; treated as unrecognized |

### 4.5 Mode_Report Record (FUNC-RPM-003)

```ada
type Mode_Report is record
   Mode   : Mode_Id     := 0;
   Status : Mode_Status := Not_Recognized;
end record;
```

Pairs the queried mode number with its decoded status. Default initialization produces `(Mode => 0, Status => Not_Recognized)`, which is clearly "empty" because mode 0 is not a valid DEC private mode. This record is used both in single-mode results (`Mode_Query_Result`) and batch results (`Mode_Report_Array`).

### 4.6 Batch Array Types (FUNC-RPM-010)

```ada
MAX_BATCH_MODES : constant := 16;

type Mode_Id_Array is
  array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Id;

type Mode_Report_Array is
  array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Report;
```

Fixed-size arrays for batch queries. SPARK Silver prohibits heap allocation, so dynamic sizing is not available. The bound of 16 covers the six standard modes with headroom for vendor extensions. Stack footprint: `16 * 4 = 64` bytes for `Mode_Id_Array`, `16 * 8 = 128` bytes for `Mode_Report_Array`.

### 4.7 Query_Error Enumeration (FUNC-RPM-004)

Declared in `Termicap.DECRPM.IO` (SPARK_Mode => Off).

```ada
type Query_Error is
  (Not_A_Terminal, Not_Foreground, Query_Timeout, Parse_Failed);
```

| Value | Meaning | Probe_Session mapping |
|-------|---------|----------------------|
| `Not_A_Terminal` | No controlling terminal (`/dev/tty` unavailable) | `Session_No_Terminal` |
| `Not_Foreground` | Process not in foreground process group | `Session_Not_Foreground` |
| `Query_Timeout` | No response within `Timeout_Ms` | `Timed_Out = True` from `Sentinel_Query` |
| `Parse_Failed` | Response received but not valid DECRPM | `Parse_DECRPM_Response` returns `Mode => 0` |

### 4.8 Mode_Query_Result Discriminated Record (FUNC-RPM-004)

Declared in `Termicap.DECRPM.IO` (SPARK_Mode => Off).

```ada
type Mode_Query_Result (Success : Boolean := False) is record
   case Success is
      when True  =>
         Report : Mode_Report;
      when False =>
         Error  : Query_Error;
   end case;
end record;
```

Default discriminant `False` ensures uninitialized values are in the failure state. Accessing `Report` when `Success = False` raises `Constraint_Error`, preventing use of invalid data. Mirrors the `XTVERSION_Result` pattern (`src/termicap-xtversion.ads` lines 91-99).

### 4.9 Batch_Query_Result Discriminated Record (FUNC-RPM-011)

Declared in `Termicap.DECRPM.IO` (SPARK_Mode => Off).

```ada
type Batch_Query_Result (Success : Boolean := False) is record
   case Success is
      when True  =>
         Reports : Mode_Report_Array;
         Count   : Positive;
      when False =>
         Error   : Query_Error;
   end case;
end record;
```

When `Success = True`, `Reports(1 .. Count)` holds the `Mode_Report` for each queried mode in input order. Modes that timed out individually within the batch have `Status => Not_Recognized` rather than causing the entire batch to fail.

---

## 5. Query Construction (FUNC-RPM-005)

### Function signature

```ada
function DECRPM_Query (Mode : Mode_Id) return Byte_Array
with
  SPARK_Mode => On,
  Global     => null,
  Post       => DECRPM_Query'Result'Length >= 6;
```

### Byte sequence structure

The output encodes `CSI ? <digits> $ p`:

| Position | Byte(s) | Value | Description |
|----------|---------|-------|-------------|
| 1 | ESC | `16#1B#` | Escape |
| 2 | `[` | `16#5B#` | CSI introducer |
| 3 | `?` | `16#3F#` | DEC private parameter prefix |
| 4..N | digits | `16#30#..16#39#` | ASCII decimal encoding of Mode |
| N+1 | `$` | `16#24#` | DECRPM command prefix |
| N+2 | `p` | `16#70#` | DECRPM command suffix |

### Digit encoding algorithm

```
1. result_prefix := [ESC, '[', '?']     -- 3 bytes
2. result_suffix := ['$', 'p']          -- 2 bytes
3. If Mode = 0:
      digits := ['0']                    -- single digit
4. Else:
      temp   := Mode
      digits := []
      while temp > 0:
         digits := [Character'Pos ('0') + (temp mod 10)] & digits
         temp   := temp / 10
5. return result_prefix & digits & result_suffix
```

The digit encoding produces ASCII characters (0x30..0x39) with no leading zeros, except `Mode = 0` which produces a single `'0'`. This is the same digit-to-ASCII conversion used throughout terminal escape sequences.

### Length bounds

- Minimum: Mode in 0..9 produces 1 digit, total = 3 + 1 + 2 = 6 bytes.
- Maximum: Mode = `Natural'Last` (2^31 - 1 = 2147483647) produces 10 digits, total = 3 + 10 + 2 = 15 bytes.
- The postcondition `Result'Length >= 6` is trivially provable.

### Examples

| Mode | Digits | Full sequence |
|------|--------|---------------|
| 25 | `"25"` | `ESC [ ? 2 5 $ p` (7 bytes) |
| 1000 | `"1000"` | `ESC [ ? 1 0 0 0 $ p` (8 bytes) |
| 2004 | `"2004"` | `ESC [ ? 2 0 0 4 $ p` (8 bytes) |
| 0 | `"0"` | `ESC [ ? 0 $ p` (6 bytes) |

### Implementation approach

The function builds the result in a local fixed-size `Byte_Array` (maximum 15 bytes) and returns a slice. The digit extraction loop divides `Mode` by 10 repeatedly, storing digits in reverse order, then reverses them. This avoids dynamic allocation and is fully SPARK-provable with bounded loop iteration (at most 10 iterations for a 32-bit Natural).

---

## 6. Response Parsing

### 6.1 Contains_DECRPM_Response (FUNC-RPM-006)

**Signature:**

```ada
function Contains_DECRPM_Response
  (Bytes : Byte_Array; Length : Natural) return Boolean
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Bytes'Length;
```

**Algorithm:**

```
1. If Length < 7: return False
   (minimum valid response: ESC [ ? <1 digit> ; <1 digit> $ y = 7 bytes)

2. Check prefix: Bytes(1) = 0x1B (ESC)
                 Bytes(2) = 0x5B ('[')
                 Bytes(3) = 0x3F ('?')
   If any mismatch: return False

3. Scan from position 4 for mode number digits (0x30..0x39):
   digit_count := 0
   I := 4
   while I <= Length and Bytes(I) in 0x30..0x39:
      digit_count := digit_count + 1
      I := I + 1
   If digit_count = 0: return False     -- no mode number

4. Check semicolon at position I:
   If I > Length or Bytes(I) /= 0x3B (';'): return False
   I := I + 1

5. Scan for status digits (0x30..0x39):
   status_digit_count := 0
   while I <= Length and Bytes(I) in 0x30..0x39:
      status_digit_count := status_digit_count + 1
      I := I + 1
   If status_digit_count = 0: return False     -- no status code

6. Check suffix: remaining bytes must be '$' (0x24) and 'y' (0x79)
   If I + 1 > Length: return False
   If Bytes(I) /= 0x24 or Bytes(I + 1) /= 0x79: return False

7. return True
```

**Key properties:**

- The `$ y` suffix is unique to DECRPM responses; no other standard CSI sequence uses it.
- The `?` prefix distinguishes DEC private mode reports from ANSI mode reports (which use `$ y` without `?`).
- Conservative: requires at least one digit before and after the semicolon.

### 6.2 Parse_DECRPM_Response (FUNC-RPM-007)

**Signature:**

```ada
function Parse_DECRPM_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Mode_Report
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Bytes'Length
                  and then Length <= MAX_RESPONSE_SIZE,
  Post       =>
    (if Contains_DECRPM_Response (Bytes, Length)
     then Parse_DECRPM_Response'Result.Mode > 0);
```

**Algorithm:**

```
1. If Length = 0 or not Contains_DECRPM_Response (Bytes, Length):
      return Mode_Report'(Mode => 0, Status => Not_Recognized)

2. Extract mode number (Ps):
      I := 4            -- first digit position after "ESC [ ?"
      Ps := 0
      while Bytes(I) in 0x30..0x39:
         Ps := Ps * 10 + (Natural(Bytes(I)) - 16#30#)
         I := I + 1
      -- I now points to the semicolon

3. Skip semicolon:
      I := I + 1

4. Extract status code (Pm):
      Pm := 0
      while Bytes(I) in 0x30..0x39:
         Pm := Pm * 10 + (Natural(Bytes(I)) - 16#30#)
         I := I + 1

5. Map Pm to Mode_Status:
      Status := (case Pm is
                    when 0 => Not_Recognized,
                    when 1 => Set,
                    when 2 => Reset,
                    when 3 => Permanently_Set,
                    when 4 => Permanently_Reset,
                    when others => Not_Recognized)

6. return Mode_Report'(Mode => Ps, Status => Status)
```

**SPARK provability notes:**

- The digit accumulation loops are bounded by `Length <= MAX_RESPONSE_SIZE` (4096), ensuring termination without manual loop invariants.
- The postcondition `Mode > 0` is provable because step 1 guards against invalid input (where `Contains_DECRPM_Response` requires at least one digit), and any valid decimal number with at least one digit is >= 0. Since the mode digits follow `?` and valid DEC private modes are positive, mode 0 would only occur from a degenerate `ESC [ ? 0 ; ... $ y` response, which is technically parseable but semantically invalid. The postcondition is maintained because `Contains_DECRPM_Response` guarantees at least one mode digit, and the smallest mode number with one digit is 0. However, in practice, the only way `Ps = 0` can occur is if the terminal echoes back mode 0, which no known terminal does. The postcondition as written in FUNC-RPM-007 states `Mode > 0` when `Contains_DECRPM_Response` is True. To satisfy this, the implementation should verify `Ps > 0` after extraction and return the default `Mode_Report` if `Ps = 0`.
- Overflow protection: `Ps` is accumulated as a `Natural`. With a maximum of `MAX_RESPONSE_SIZE` (4096) digits (practically impossible but theoretically bounded), overflow is prevented by checking `Ps <= (Natural'Last - 9) / 10` before each multiply-add step, returning the default on overflow.

---

## 7. I/O Integration

### 7.1 Query_Mode Procedure (FUNC-RPM-008)

**Signature (in `Termicap.DECRPM.IO`):**

```ada
procedure Query_Mode
  (Mode        :     Mode_Id;
   Timeout_Ms  :     Natural;
   Response    : out Termicap.OSC.Response_Buffer;
   Resp_Length : out Natural;
   Timed_Out   : out Boolean)
with Pre => Timeout_Ms > 0;
```

**Algorithm:**

```
1. Initialize outputs:
      Response    := [others => 0]
      Resp_Length := 0
      Timed_Out   := True

2. Capture environment and detect terminal identity:
      Capture_Current (Env)
      Identity := Detect_Terminal_Identity (Env)

3. Derive passthrough mode (CSI sequences generally do not need
   multiplexer passthrough, but the infrastructure is available):
      If not Identity.Is_Multiplexer:
         Passthrough := No_Passthrough
      Elsif Identity.Kind = Tmux:
         Passthrough := Tmux_Passthrough
      Elsif Identity.Kind = Screen:
         Passthrough := Screen_Passthrough
      Else:
         Passthrough := Tmux_Passthrough  -- safe default

4. Construct query bytes:
      Query := DECRPM_Query (Mode)
      Wrapped := Wrap_For_Passthrough (Query, Passthrough)

5. Open Probe_Session:
      Open (Session, Status)
      If Status /= Session_OK:
         return   -- outputs already set to error defaults

6. Send query with DA1 sentinel:
      Sentinel_Query
        (Session     => Session,
         Query       => Wrapped,
         Response    => Response,
         Resp_Length => Resp_Length,
         Timeout_Ms  => Timeout_Ms,
         Timed_Out   => Timed_Out,
         Retry       => False)

7. Probe_Session closes via RAII Finalize.
```

**Implementation note:** This follows the same pattern as `Query_XTVERSION` (`src/termicap-xtversion-io.adb` lines 18-77). The key difference is that `Query_Mode` uses `Sentinel_Query` (with DA1 sentinel) rather than `Timeout_Query`, because the DECRPM response is distinct from the DA1 response and the sentinel pattern works correctly.

**Multiplexer passthrough note:** FUNC-RPM-008 states that multiplexer passthrough is "deliberately omitted" because CSI sequences are generally forwarded by multiplexers without wrapping. However, the implementation includes the passthrough infrastructure for defensive completeness, matching the `Query_XTVERSION` pattern. If a specific multiplexer is found to require wrapping for DECRPM, the passthrough mode selection logic is already in place.

### 7.2 Detect_Mode Function (FUNC-RPM-009)

**Signature (in `Termicap.DECRPM.IO`):**

```ada
function Detect_Mode
  (Mode       : Mode_Id;
   Timeout_Ms : Natural := 100) return Mode_Query_Result;
```

**Algorithm:**

```
1. Declare local variables:
      Resp_Buffer : Response_Buffer
      Resp_Length : Natural
      Timed_Out   : Boolean
      Report      : Mode_Report

2. Call Query_Mode:
      Query_Mode (Mode, Timeout_Ms, Resp_Buffer, Resp_Length, Timed_Out)

3. If Timed_Out:
      return Mode_Query_Result'(Success => False,
                                 Error   => Query_Timeout)
   -- Note: FUNC-RPM-009 step 2 discusses distinguishing Not_A_Terminal
   -- from Not_Foreground via the Timed_Out path. For v1, both are
   -- reported as Query_Timeout, matching the Query_And_Identify pattern.
   -- An extended API may expose Session_Status in a future revision.

4. Parse response:
      Report := Parse_DECRPM_Response
                  (Byte_Array(Resp_Buffer), Resp_Length)
   -- Type conversion from Termicap.OSC.Byte_Array to
   -- Termicap.DECRPM.Byte_Array is safe because both are
   -- arrays of Interfaces.C.unsigned_char.

5. If Report.Mode = 0:
      return Mode_Query_Result'(Success => False,
                                 Error   => Parse_Failed)

6. return Mode_Query_Result'(Success => True, Report => Report)
```

**Default timeout:** 100 ms, consistent with `Query_And_Identify` (FUNC-XTV-013) and `Detect_DA1` (`src/termicap-da1-io.ads` line 116).

### 7.3 Detect_Modes Batch Function (FUNC-RPM-011)

**Signature (in `Termicap.DECRPM.IO`):**

```ada
function Detect_Modes
  (Modes      : Mode_Id_Array;
   Count      : Positive;
   Timeout_Ms : Natural := 200) return Batch_Query_Result
with Pre => Count <= MAX_BATCH_MODES;
```

**Algorithm:**

```
1. Declare local variables:
      Results     : Mode_Report_Array := [others => (Mode => 0,
                                                       Status => Not_Recognized)]
      Per_Timeout : Natural
      Env         : Environment
      Identity    : Terminal_Identity
      Passthrough : Passthrough_Mode

2. Capture environment and detect terminal identity.

3. Derive passthrough mode.

4. Open a single Probe_Session:
      Open (Session, Status)
      If Status /= Session_OK:
         return Batch_Query_Result'(Success => False,
                                     Error   => Not_A_Terminal)

5. Calculate per-query timeout:
      Per_Timeout := Natural'Max (50, Timeout_Ms / Count)

6. For I in 1 .. Count:
      a. Query := DECRPM_Query (Modes(I))
         Wrapped := Wrap_For_Passthrough (Query, Passthrough)

      b. Sentinel_Query
           (Session     => Session,
            Query       => Wrapped,
            Response    => Resp_Buffer,
            Resp_Length => Resp_Length,
            Timeout_Ms  => Per_Timeout,
            Timed_Out   => Timed_Out,
            Retry       => False)

      c. If not Timed_Out:
            Report := Parse_DECRPM_Response
                        (Byte_Array(Resp_Buffer), Resp_Length)
            If Report.Mode > 0:
               Results(I) := Report
            Else:
               Results(I) := (Mode => Modes(I),
                               Status => Not_Recognized)
         Else:
            Results(I) := (Mode => Modes(I),
                            Status => Not_Recognized)

7. Probe_Session closes via RAII Finalize.

8. return Batch_Query_Result'(Success => True,
                               Reports => Results,
                               Count   => Count)
```

**Key design decisions:**

- **Single session:** Opening `Probe_Session` once amortizes the overhead of opening `/dev/tty`, saving termios, and entering raw mode across all queries.
- **Per-query sentinel:** Each `Sentinel_Query` call within the session appends its own DA1 sentinel, providing per-mode response boundaries. This is correct because `Sentinel_Query` writes the query + DA1, reads until DA1 is detected, and returns the pre-sentinel bytes -- all within the already-open session.
- **Per-query timeout:** `Timeout_Ms / Count` with a minimum of 50 ms prevents the total blocking time from scaling linearly and prevents zero-timeout queries from trivial timeouts.
- **Partial success:** Individual mode timeouts produce `Status => Not_Recognized` for that mode rather than failing the entire batch. The batch returns `Success => True` as long as the session opened successfully.

---

## 8. Error Handling

### Error taxonomy

| Error Scenario | Query_Mode behavior | Detect_Mode result | Detect_Modes result |
|---------------|--------------------|--------------------|---------------------|
| No controlling terminal | `Timed_Out := True`, `Resp_Length := 0` | `(Success => False, Error => Query_Timeout)` | `(Success => False, Error => Not_A_Terminal)` |
| Not foreground process | `Timed_Out := True`, `Resp_Length := 0` | `(Success => False, Error => Query_Timeout)` | `(Success => False, Error => Not_A_Terminal)` |
| Terminal does not support DECRPM | `Timed_Out := True`, `Resp_Length := 0` | `(Success => False, Error => Query_Timeout)` | Individual mode: `Status => Not_Recognized` |
| Terminal supports DECRPM, mode not recognized | Response with `Pm = 0` | `(Success => True, Report => (Mode, Not_Recognized))` | `Reports(I) => (Mode, Not_Recognized)` |
| Malformed response | Bytes present but not valid DECRPM | `(Success => False, Error => Parse_Failed)` | Individual mode: `Status => Not_Recognized` |
| Mode is set | Response with `Pm = 1` | `(Success => True, Report => (Mode, Set))` | `Reports(I) => (Mode, Set)` |
| Mode is reset | Response with `Pm = 2` | `(Success => True, Report => (Mode, Reset))` | `Reports(I) => (Mode, Reset)` |

### Timeout semantics (FUNC-RPM-016)

A timeout is **not an error condition**. Terminals that do not implement DECRPM (Linux kernel console, dumb terminals, many older emulators) produce no response to `CSI ? Ps $ p`. This is the expected common case in CI, scripted, and legacy environments. Callers should treat `Query_Timeout` as "mode status unknown" and fall back to passive detection or conservative defaults.

### Distinguishing "not recognized" from "no DECRPM support"

Callers that need this distinction use a two-level check:

```ada
Result := Detect_Mode (MODE_BRACKETED_PASTE);
if Result.Success then
   --  Terminal speaks DECRPM
   if Result.Report.Status /= Not_Recognized then
      --  Mode is known to the terminal (Set, Reset, Permanently_Set, or Permanently_Reset)
   else
      --  Terminal speaks DECRPM but does not know mode 2004
   end if;
else
   --  Result.Error = Query_Timeout => terminal does not speak DECRPM at all
   --  Result.Error = Parse_Failed  => terminal sent something but it was garbled
end if;
```

### No exceptions

No subprogram in `Termicap.DECRPM` or `Termicap.DECRPM.IO` raises an exception on any code path. All error conditions are represented in the return types. This follows the library-wide convention (`.claude/ada-style-guide.md`: "No exceptions in library code -- use Result types").

---

## 9. SPARK Boundary

### SPARK Silver package: `Termicap.DECRPM`

| Element | SPARK Status | Contracts |
|---------|-------------|-----------|
| `Mode_Id` subtype | SPARK On | N/A (subtype) |
| `MODE_*` constants | SPARK On | N/A (constants) |
| `Mode_Status` enum | SPARK On | N/A (type) |
| `Mode_Report` record | SPARK On | N/A (type) |
| `Mode_Id_Array` type | SPARK On | N/A (type) |
| `Mode_Report_Array` type | SPARK On | N/A (type) |
| `MAX_BATCH_MODES` constant | SPARK On | N/A (constant) |
| `MAX_RESPONSE_SIZE` constant | SPARK On | N/A (constant) |
| `DECRPM_Query` function | SPARK On | `Global => null`, `Post => Result'Length >= 6` |
| `Contains_DECRPM_Response` function | SPARK On | `Global => null`, `Pre => Length <= Bytes'Length` |
| `Parse_DECRPM_Response` function | SPARK On | `Global => null`, `Pre => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE`, `Post => (if Contains_DECRPM_Response then Result.Mode > 0)` |

All functions in `Termicap.DECRPM` carry `Global => null` contracts, confirming no side effects. No dynamic allocation, no OS calls, no unbounded loops. The SPARK prover should discharge all proof obligations at Silver level without manual lemmas.

### SPARK Off package: `Termicap.DECRPM.IO`

| Element | SPARK Status | Reason |
|---------|-------------|--------|
| `Query_Error` enum | Off | Only meaningful in I/O context |
| `Mode_Query_Result` record | Off | References `Query_Error` |
| `Batch_Query_Result` record | Off | References `Query_Error` |
| `Query_Mode` procedure | Off | Calls `Probe_Session` (controlled type), `Sentinel_Query` |
| `Detect_Mode` function | Off | Calls `Query_Mode` |
| `Detect_Modes` function | Off | Calls `Probe_Session`, `Sentinel_Query` |

The `pragma SPARK_Mode (Off)` annotation is placed at the package level in both the spec and body of `Termicap.DECRPM.IO`, matching the pattern in `src/termicap-xtversion-io.ads` line 39 and `src/termicap-da1-io.ads` line 43. This ensures callers in SPARK-annotated packages receive a compile error if they attempt to call these subprograms without a SPARK mode barrier.

---

## 10. File Inventory

### Files to create

| File | Package | SPARK | Purpose |
|------|---------|-------|---------|
| `src/termicap-decrpm.ads` | `Termicap.DECRPM` | On | Types, constants, pure function specs |
| `src/termicap-decrpm.adb` | `Termicap.DECRPM` | On | `DECRPM_Query`, `Contains_DECRPM_Response`, `Parse_DECRPM_Response` bodies |
| `src/termicap-decrpm-io.ads` | `Termicap.DECRPM.IO` | Off | I/O types, `Query_Mode`, `Detect_Mode`, `Detect_Modes` specs |
| `src/termicap-decrpm-io.adb` | `Termicap.DECRPM.IO` | Off | I/O procedure and function bodies |
| `tests/src/termicap-decrpm-tests.ads` | Test package | Off | DECRPM test suite spec |
| `tests/src/termicap-decrpm-tests.adb` | Test package | Off | DECRPM test suite body |

### Files to modify

| File | Change |
|------|--------|
| `termicap.gpr` | Add `src/termicap-decrpm.ads`, `src/termicap-decrpm.adb`, `src/termicap-decrpm-io.ads`, `src/termicap-decrpm-io.adb` to source files (if not auto-discovered via `src/` directory) |
| `tests/termicap_tests.gpr` | Add test source files (if not auto-discovered) |
| `docs/architecture/03-building-blocks.md` | Add `Termicap.DECRPM` and `Termicap.DECRPM.IO` to the package tree |
| `docs/architecture/04-runtime-view.md` | Add DECRPM query flow scenario |

---

## 11. Requirement Traceability

| Requirement | Code Element | Package | Location |
|-------------|-------------|---------|----------|
| FUNC-RPM-001 | `Mode_Id` subtype, `MODE_*` constants | `Termicap.DECRPM` | `src/termicap-decrpm.ads` |
| FUNC-RPM-002 | `Mode_Status` enumeration | `Termicap.DECRPM` | `src/termicap-decrpm.ads` |
| FUNC-RPM-003 | `Mode_Report` record | `Termicap.DECRPM` | `src/termicap-decrpm.ads` |
| FUNC-RPM-004 | `Query_Error` enum, `Mode_Query_Result` record | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.ads` |
| FUNC-RPM-005 | `DECRPM_Query` function | `Termicap.DECRPM` | `src/termicap-decrpm.ads` (spec), `src/termicap-decrpm.adb` (body) |
| FUNC-RPM-006 | `Contains_DECRPM_Response` function | `Termicap.DECRPM` | `src/termicap-decrpm.ads` (spec), `src/termicap-decrpm.adb` (body) |
| FUNC-RPM-007 | `Parse_DECRPM_Response` function | `Termicap.DECRPM` | `src/termicap-decrpm.ads` (spec), `src/termicap-decrpm.adb` (body) |
| FUNC-RPM-008 | `Query_Mode` procedure | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.ads` (spec), `src/termicap-decrpm-io.adb` (body) |
| FUNC-RPM-009 | `Detect_Mode` function | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.ads` (spec), `src/termicap-decrpm-io.adb` (body) |
| FUNC-RPM-010 | `MAX_BATCH_MODES` constant, `Mode_Id_Array` type, `Mode_Report_Array` type | `Termicap.DECRPM` | `src/termicap-decrpm.ads` |
| FUNC-RPM-011 | `Batch_Query_Result` record, `Detect_Modes` function | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.ads` (spec), `src/termicap-decrpm-io.adb` (body) |
| FUNC-RPM-012 | `Sentinel_Query` usage in `Query_Mode` (Retry => False) | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.adb` (body, step 6 of `Query_Mode`) |
| FUNC-RPM-013 | Not-a-TTY guard via `Probe_Session.Open` returning `Session_No_Terminal` | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.adb` (body, step 5 of `Query_Mode`) |
| FUNC-RPM-014 | Foreground guard via `Probe_Session.Open` returning `Session_Not_Foreground` | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.adb` (body, step 5 of `Query_Mode`) |
| FUNC-RPM-015 | Package-level `SPARK_Mode` annotations on both packages | `Termicap.DECRPM`, `Termicap.DECRPM.IO` | `src/termicap-decrpm.ads`, `src/termicap-decrpm-io.ads` |
| FUNC-RPM-016 | `Query_Timeout` handling in `Detect_Mode` step 3 | `Termicap.DECRPM.IO` | `src/termicap-decrpm-io.adb` |
| FUNC-RPM-017 | Test cases for `Contains_DECRPM_Response`, `Parse_DECRPM_Response`, `DECRPM_Query` | Test package | `tests/src/termicap-decrpm-tests.adb` |
