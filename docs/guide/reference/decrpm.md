# API Reference: `Termicap.DECRPM` and `Termicap.DECRPM.IO`

Package pair providing SPARK Silver-provable DECRPM query construction and response parsing, and an I/O boundary for active terminal mode detection via the DEC Private Mode Report protocol (`CSI ? Ps $ p` / `CSI ? Ps ; Pm $ y`).

**Files:**
- `src/termicap-decrpm.ads`, `src/termicap-decrpm.adb`
- `src/termicap-decrpm-io.ads`, `src/termicap-decrpm-io.adb`

**SPARK_Mode:** `Termicap.DECRPM` — On (spec and body, Silver level); `Termicap.DECRPM.IO` — Off (spec and body)
**License:** Apache-2.0

---

## Overview

The DECRPM feature queries the terminal for the current state of a DEC private mode by sending the `CSI ? Ps $ p` escape sequence and parsing the response `CSI ? Ps ; Pm $ y`. The response carries the mode number (`Ps`) back and a status code (`Pm`) encoding whether the mode is set, reset, permanently set, permanently reset, or not recognised by the terminal.

`Termicap.DECRPM` contains all SPARK-provable building blocks: the `Mode_Id` subtype, six named mode constants, the `Mode_Status` enumeration, the `Mode_Report` record, fixed-size batch array types, the `DECRPM_Query` construction function, and two pure parsing functions (`Contains_DECRPM_Response`, `Parse_DECRPM_Response`). All subprograms carry `Global => null` and are verifiable at SPARK Silver level.

`Termicap.DECRPM.IO` contains the I/O boundary: `Query_Mode` drives the probe session using `Sentinel_Query`, while `Detect_Mode` combines I/O and parsing into a single call, and `Detect_Modes` performs a batch of queries within a single `Probe_Session` for lower overhead. It carries `pragma SPARK_Mode (Off)` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O.

**Key distinction from `Termicap.DA1.IO`:** unlike DA1 queries, DECRPM uses `Sentinel_Query` (not `Timeout_Query`). DECRPM responses (`CSI ? Ps ; Pm $ y`) are structurally distinct from the DA1 sentinel (`ESC [ c`), so the sentinel pattern safely bounds the accumulation loop without ambiguity.

The typical call patterns are:

- **Single call, default timeout:** `Detect_Mode (MODE_BRACKETED_PASTE)` — returns `Mode_Query_Result` directly.
- **Batch query, single session:** `Detect_Modes (Modes, Count)` — returns `Batch_Query_Result` with `Reports(1..Count)`.
- **Custom timeout or separate I/O and parsing steps:** call `Query_Mode` then `Parse_DECRPM_Response`.

---

## Package `Termicap.DECRPM`

### Types

#### `Byte`

```ada
subtype Byte is Interfaces.C.unsigned_char;
```

A single byte of terminal I/O, matching `Interfaces.C.unsigned_char`. Defined independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to keep this package SPARK On. The underlying type is identical, so `Termicap.DECRPM.IO` can convert between the two without a copy.

---

#### `Byte_Array`

```ada
type Byte_Array is array (Positive range <>) of Byte;
```

An unconstrained sequence of bytes for escape sequence data. Used for the `DECRPM_Query` function return type and raw response buffers passed to the parsing functions. Representation-compatible with `Termicap.OSC.Byte_Array`, `Termicap.XTVERSION.Byte_Array`, and `Termicap.DA1.Byte_Array`.

---

#### `Mode_Id`

```ada
subtype Mode_Id is Natural;
```

DEC private mode number. Using a subtype of `Natural` rather than a new integer type allows callers to pass literal integers for vendor-specific modes without type conversion. The six named constants cover the modes with the broadest practical impact on terminal UI libraries.

**Requirements:** FUNC-RPM-001

---

#### `Mode_Status`

```ada
type Mode_Status is
  (Not_Recognized,      --  Pm = 0: mode not implemented by terminal
   Set,                 --  Pm = 1: mode is currently enabled
   Reset,               --  Pm = 2: mode is currently disabled
   Permanently_Set,     --  Pm = 3: mode is always enabled, cannot be changed
   Permanently_Reset);  --  Pm = 4: mode is always disabled, cannot be changed
```

Five-value enumeration mapping DECRPM response status codes (`Pm` parameter).

| Literal | `Pm` | Meaning |
|---------|-----|---------|
| `Not_Recognized` | 0 | Mode not implemented by this terminal. |
| `Set` | 1 | Mode is currently enabled. |
| `Reset` | 2 | Mode is currently disabled. |
| `Permanently_Set` | 3 | Mode is always enabled; cannot be changed by `DECSET`/`DECRST`. |
| `Permanently_Reset` | 4 | Mode is always disabled; cannot be changed by `DECSET`/`DECRST`. |

`Not_Recognized` appears first so that default-initialised values carry the safest state. Any `Pm` value outside `0..4` is mapped to `Not_Recognized`.

**Requirements:** FUNC-RPM-002

---

#### `Mode_Report`

```ada
type Mode_Report is record
   Mode   : Mode_Id     := 0;
   Status : Mode_Status := Not_Recognized;
end record;
```

Record pairing a mode number with its decoded DECRPM status.

| Field | Default | Description |
|-------|---------|-------------|
| `Mode` | `0` | The DEC private mode number echoed back by the terminal. `0` in the default indicates "empty" — mode 0 is not a valid DEC private mode number. |
| `Status` | `Not_Recognized` | The decoded `Pm` status value for this mode. |

Default initialisation produces `(Mode => 0, Status => Not_Recognized)`, which is unambiguously the "no response" value. Used in both single-mode results (`Mode_Query_Result` in `Termicap.DECRPM.IO`) and batch results (`Mode_Report_Array`).

**Requirements:** FUNC-RPM-003

---

#### `Mode_Id_Array`

```ada
type Mode_Id_Array is
  array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Id;
```

Fixed-size array of mode identifiers for batch query input. Callers populate elements `1 .. Count` with the mode numbers to query; elements beyond `Count` are ignored. Fixed size is required for SPARK Silver mode (no heap allocation).

**Requirements:** FUNC-RPM-010

---

#### `Mode_Report_Array`

```ada
type Mode_Report_Array is
  array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Report;
```

Fixed-size array of mode reports for batch query output. The `I`-th element corresponds to the `I`-th mode in the `Mode_Id_Array` input, regardless of whether a response was received. Modes that timed out individually have `Status => Not_Recognized`.

**Requirements:** FUNC-RPM-010

---

### Constants

#### `MAX_RESPONSE_SIZE`

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
```

Maximum number of response bytes accumulated by `Query_Mode`. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Used in preconditions to bound all parsing loops for SPARK provability.

**Requirements:** FUNC-RPM-007

---

#### `MAX_BATCH_MODES`

```ada
MAX_BATCH_MODES : constant := 16;
```

Maximum number of modes that may be queried in a single batch. Covers the six standard constants with headroom for vendor extensions, while remaining within a reasonable stack footprint (`16 * 8 = 128` bytes for `Mode_Report_Array`).

**Requirements:** FUNC-RPM-010

---

#### Mode Constants

```ada
MODE_CURSOR_VISIBILITY : constant Mode_Id := 25;
MODE_MOUSE_X11         : constant Mode_Id := 1000;
MODE_MOUSE_SGR         : constant Mode_Id := 1006;
MODE_ALT_SCREEN        : constant Mode_Id := 1049;
MODE_BRACKETED_PASTE   : constant Mode_Id := 2004;
MODE_SYNC_OUTPUT       : constant Mode_Id := 2026;
```

Named constants for the six DEC private modes with the broadest practical impact on terminal UI libraries.

| Constant | Value | Description |
|----------|-------|-------------|
| `MODE_CURSOR_VISIBILITY` | 25 | DECTCEM — cursor visible. |
| `MODE_MOUSE_X11` | 1000 | X11 mouse button tracking. |
| `MODE_MOUSE_SGR` | 1006 | SGR mouse coordinate encoding (extends X11 to large terminals). |
| `MODE_ALT_SCREEN` | 1049 | Alternate screen buffer (save/restore cursor, clear screen). |
| `MODE_BRACKETED_PASTE` | 2004 | Bracketed paste mode (pastes wrapped in `ESC[200~`/`ESC[201~`). |
| `MODE_SYNC_OUTPUT` | 2026 | Synchronized output (suppress partial renders during updates). |

**Requirements:** FUNC-RPM-001

---

### Functions

#### `DECRPM_Query`

```ada
function DECRPM_Query (Mode : Mode_Id) return Byte_Array
with
  SPARK_Mode => On,
  Global     => null,
  Post       => DECRPM_Query'Result'Length >= 6;
```

Construct the DECRPM query byte sequence for a given mode number.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Mode` | in | The DEC private mode number to query. |

**Returns:** A `Byte_Array` encoding `CSI ? Ps $ p` (`ESC [ ? <digits> $ p`). The sequence is: `0x1B 0x5B 0x3F <ASCII decimal digits> 0x24 0x70`.

**Length bounds:**
- Minimum: 6 bytes (mode in `0..9` — 3-byte prefix + 1 digit + 2-byte suffix).
- Maximum: 15 bytes (`Natural'Last` has 10 digits — 3 + 10 + 2).

**Examples:**
```ada
--  MODE_CURSOR_VISIBILITY = 25 => ESC [ ? 2 5 $ p   (7 bytes)
--  MODE_MOUSE_X11 = 1000       => ESC [ ? 1 0 0 0 $ p (8 bytes)
--  MODE_BRACKETED_PASTE = 2004 => ESC [ ? 2 0 0 4 $ p (8 bytes)
```

Digit encoding uses ASCII (`0x30..0x39`) with no leading zeros, except `Mode = 0` which produces the single digit `'0'`. Fully side-effect-free (`Global => null`), as required by `SPARK_Mode => On`.

**SPARK contract:** `Post => Result'Length >= 6` (machine-verified).

**Requirements:** FUNC-RPM-005

---

#### `Contains_DECRPM_Response`

```ada
function Contains_DECRPM_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Boolean
with
  SPARK_Mode => On,
  Global     => null,
  Pre        => Length <= Bytes'Length;
```

Return `True` if `Bytes(1..Length)` contains a syntactically valid DECRPM response.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | The raw response byte buffer. |
| `Length` | in | Number of valid bytes in `Bytes` to examine. |

**Returns:** `True` if and only if:
- `Length >= 7` (minimum: `ESC [ ? d ; d $ y`)
- `Bytes` starts with `ESC [ ?` (`0x1B 0x5B 0x3F`)
- At least one decimal digit follows `?` before a semicolon (`0x3B`)
- A semicolon is present
- At least one decimal digit follows the semicolon
- The sequence ends with `$ y` (`0x24 0x79`)

Returns `False` for any shorter or malformed input. The `$ y` suffix is unique to DECRPM responses; the `?` prefix distinguishes DEC private mode reports from ANSI mode reports.

**Requirements:** FUNC-RPM-006

---

#### `Parse_DECRPM_Response`

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

Parse a byte buffer containing a DECRPM response into a `Mode_Report`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | The raw response byte buffer. |
| `Length` | in | Number of valid bytes in `Bytes` (`0 <= Length <= MAX_RESPONSE_SIZE`). |

**Returns:** A `Mode_Report` with `Mode > 0` and the decoded `Mode_Status` on success; `Mode_Report'(Mode => 0, Status => Not_Recognized)` on failure.

**Algorithm:**
1. If `Length = 0` or `Contains_DECRPM_Response (Bytes, Length)` is `False`, return the default `Mode_Report`.
2. Scan from position 4 (after `ESC [ ?`) to extract the decimal `Ps` value (mode number) by accumulating ASCII digits until the semicolon.
3. Skip the semicolon and extract the decimal `Pm` value (status code) by accumulating ASCII digits until `$`.
4. Map `Pm` to `Mode_Status`: `0 => Not_Recognized`, `1 => Set`, `2 => Reset`, `3 => Permanently_Set`, `4 => Permanently_Reset`, `others => Not_Recognized`.
5. If `Ps = 0` after extraction, return the default `Mode_Report`.
6. Return `Mode_Report'(Mode => Ps, Status => <decoded status>)`.

**SPARK contract:** `Post => (if Contains_DECRPM_Response then Result.Mode > 0)` (machine-verified). No exception is raised on any code path.

**Requirements:** FUNC-RPM-007

---

## Package `Termicap.DECRPM.IO`

### Overview

`Termicap.DECRPM.IO` is the I/O boundary for the DECRPM feature. It has `pragma SPARK_Mode (Off)` throughout because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O.

Unlike `Termicap.DA1.IO`, this package uses `Sentinel_Query` rather than `Timeout_Query`. DECRPM responses (`CSI ? Ps ; Pm $ y`) are structurally distinct from the DA1 sentinel (`ESC [ c`), so the sentinel pattern safely bounds the accumulation loop — there is no risk of the terminal's DECRPM response being confused with the boundary marker.

---

### Types

#### `Query_Error`

```ada
type Query_Error is
  (Not_A_Terminal,   --  No controlling terminal (/dev/tty unavailable)
   Not_Foreground,   --  Process not in terminal foreground process group
   Query_Timeout,    --  No response within Timeout_Ms
   Parse_Failed);    --  Response received but could not be parsed
```

Four-value enumeration for DECRPM query failure reasons.

| Literal | Description |
|---------|-------------|
| `Not_A_Terminal` | No controlling terminal — `/dev/tty` is unavailable. |
| `Not_Foreground` | The process is not in the terminal's foreground process group. |
| `Query_Timeout` | No DA1 sentinel was detected within `Timeout_Ms`. |
| `Parse_Failed` | A response was received but `Parse_DECRPM_Response` returned `Mode => 0`. |

Values correspond to the `Probe_Session` error vocabulary for consistency across all active probing features.

**Requirements:** FUNC-RPM-004

---

#### `Mode_Query_Result`

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

Discriminated record carrying the outcome of a single-mode query.

| Discriminant / Field | Description |
|----------------------|-------------|
| `Success` | `True` when a valid response was received and parsed. Default `False` ensures uninitialised values are in the failure state — accessing `Report` on an uninitialised record raises `Constraint_Error`. |
| `Report` (`Success = True`) | The `Mode_Report` returned by the terminal (mode number plus decoded `Mode_Status`). |
| `Error` (`Success = False`) | A `Query_Error` value explaining the failure. |

Mirrors `XTVERSION_Result` (FUNC-XTV-001) and the BG-COLOR result pattern.

**Requirements:** FUNC-RPM-004

---

#### `Batch_Query_Result`

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

Discriminated record carrying the outcome of a batch mode query.

| Discriminant / Field | Description |
|----------------------|-------------|
| `Success` | `True` when the `Probe_Session` opened successfully and all `Count` queries were attempted. |
| `Reports` (`Success = True`) | `Mode_Report_Array` with valid entries at indices `1 .. Count`. Modes that timed out individually have `Status => Not_Recognized`. |
| `Count` (`Success = True`) | Number of valid entries in `Reports`. Equals the `Count` parameter passed to `Detect_Modes` on success. |
| `Error` (`Success = False`) | A `Query_Error` value explaining the session-open failure. |

The default discriminant `False` ensures uninitialised values are in the failure state.

**Requirements:** FUNC-RPM-011

---

### Procedures and Functions

#### `Query_Mode`

```ada
procedure Query_Mode
  (Mode        :     Mode_Id;
   Timeout_Ms  :     Natural;
   Response    : out Termicap.OSC.Response_Buffer;
   Resp_Length : out Natural;
   Timed_Out   : out Boolean)
with Pre => Timeout_Ms > 0;
```

Send a single DECRPM query and return the raw response bytes.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Mode` | in | The DEC private mode number to query. |
| `Timeout_Ms` | in | Millisecond timeout for the sentinel query. Must be `> 0` (enforced by precondition). |
| `Response` | out | Buffer receiving the raw pre-sentinel response bytes. |
| `Resp_Length` | out | Number of valid bytes written into `Response`. `0` on timeout or session failure. |
| `Timed_Out` | out | `True` if no DA1 sentinel was detected within `Timeout_Ms`, or if the `Probe_Session` failed to open. |

**Execution steps:**
1. Construct the query bytes via `DECRPM_Query (Mode)`: `CSI ? Ps $ p`.
2. Capture environment snapshot and detect terminal identity via `Detect_Terminal_Identity`. Derive the passthrough mode from `Identity.Kind`.
3. Wrap the query via `Wrap_For_Passthrough` if a multiplexer is active.
4. Open a `Probe_Session`. On any failure (`Session_No_Terminal`, `Session_Not_Foreground`, etc.), set `Timed_Out := True`, `Resp_Length := 0`, and return immediately.
5. Call `Sentinel_Query` with the (possibly wrapped) query, `Timeout_Ms`, and `Retry => False`.
6. Allow the `Probe_Session` to close unconditionally via RAII `Finalize`.
7. Populate `Response` with the pre-sentinel response bytes, `Resp_Length` with the valid byte count, and `Timed_Out` with the sentinel-detection outcome.

Never raises an exception on any code path.

**Requirements:** FUNC-RPM-008

---

#### `Detect_Mode`

```ada
function Detect_Mode
  (Mode       : Mode_Id;
   Timeout_Ms : Natural := 100) return Mode_Query_Result;
```

Combine a DECRPM query with response parsing into a single call.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Mode` | in | The DEC private mode number to query. |
| `Timeout_Ms` | in | Millisecond timeout for `Query_Mode` (default: 100 ms). |

**Returns:** A `Mode_Query_Result`. `Success = True` with the parsed `Mode_Report` on success; `Success = False` with a `Query_Error` on failure.

**Execution steps:**
1. Call `Query_Mode` with `Mode` and `Timeout_Ms` to obtain `Response`, `Resp_Length`, and `Timed_Out`.
2. If `Timed_Out = True`, return `Mode_Query_Result'(Success => False, Error => Query_Timeout)`. (Both `Not_A_Terminal` and `Not_Foreground` arrive via `Timed_Out = True` in this API version.)
3. Call `Parse_DECRPM_Response` on the response buffer.
4. If `Parse_DECRPM_Response` returns `Mode => 0` (parse failure), return `Mode_Query_Result'(Success => False, Error => Parse_Failed)`.
5. Return `Mode_Query_Result'(Success => True, Report => <parsed report>)`.

Never raises an exception on any code path.

**Requirements:** FUNC-RPM-009

---

#### `Detect_Modes`

```ada
function Detect_Modes
  (Modes      : Mode_Id_Array;
   Count      : Positive;
   Timeout_Ms : Natural := 200) return Batch_Query_Result
with Pre => Count <= MAX_BATCH_MODES;
```

Query multiple DEC private modes within a single `Probe_Session`.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Modes` | in | Array of DEC private mode numbers to query. |
| `Count` | in | Number of valid entries in `Modes` (`1 .. MAX_BATCH_MODES`), enforced by precondition. |
| `Timeout_Ms` | in | Total millisecond budget for the batch (default: 200 ms). |

**Returns:** A `Batch_Query_Result`. `Success = True` with `Reports(1..Count)` on success; `Success = False` with a `Query_Error` on session-open failure.

**Execution steps:**
1. Capture environment and derive passthrough mode (as in `Query_Mode`).
2. Open a single `Probe_Session`. If opening fails, return `Batch_Query_Result'(Success => False, Error => Not_A_Terminal)`.
3. For each index `I` in `1 .. Count`:
   - Construct the DECRPM query for `Modes(I)` via `DECRPM_Query`.
   - Call `Sentinel_Query` with a per-query timeout of `max(50, Timeout_Ms / Count)` milliseconds.
   - Call `Parse_DECRPM_Response` on the response bytes.
   - Accumulate the resulting `Mode_Report` (`Status => Not_Recognized` for individual timeouts).
4. Close the `Probe_Session` via RAII `Finalize`.
5. Return `Batch_Query_Result'(Success => True, Reports => <accumulated reports>, Count => Count)`.

Modes that time out individually within the batch receive `Status => Not_Recognized` rather than causing the entire batch to fail. The default `Timeout_Ms` of 200 ms allocates approximately 12 ms per mode for a 16-mode batch, sufficient for local terminals.

Never raises an exception on any code path.

**Requirements:** FUNC-RPM-011

---

## Usage Examples

### Query a single mode

```ada
with Termicap.DECRPM;
with Termicap.DECRPM.IO;

procedure Check_Bracketed_Paste is
   use Termicap.DECRPM;
   Result : constant Mode_Query_Result :=
     Termicap.DECRPM.IO.Detect_Mode (MODE_BRACKETED_PASTE);
begin
   if Result.Success then
      case Result.Report.Status is
         when Set | Permanently_Set =>
            --  Bracketed paste is active
         when Reset | Permanently_Reset =>
            --  Bracketed paste is inactive
         when Not_Recognized =>
            --  Terminal does not implement this mode
      end case;
   end if;
end Check_Bracketed_Paste;
```

### Query multiple modes in a single session

```ada
with Termicap.DECRPM;
with Termicap.DECRPM.IO;

procedure Check_Multiple_Modes is
   use Termicap.DECRPM;
   Modes  : Mode_Id_Array := [others => 0];
   Result : Batch_Query_Result;
begin
   Modes (1) := MODE_BRACKETED_PASTE;
   Modes (2) := MODE_SYNC_OUTPUT;
   Modes (3) := MODE_ALT_SCREEN;

   Result := Termicap.DECRPM.IO.Detect_Modes
     (Modes => Modes, Count => 3);

   if Result.Success then
      for I in 1 .. Result.Count loop
         --  Result.Reports(I).Mode   — mode number queried
         --  Result.Reports(I).Status — Set / Reset / etc.
         null;
      end loop;
   end if;
end Check_Multiple_Modes;
```

### Construct and inspect a query byte sequence

```ada
with Termicap.DECRPM;

procedure Show_Query is
   use Termicap.DECRPM;
   Query : constant Byte_Array := DECRPM_Query (MODE_CURSOR_VISIBILITY);
begin
   --  Query contains ESC [ ? 2 5 $ p  (7 bytes)
   --  Query'Length >= 6 is guaranteed by the postcondition
   null;
end Show_Query;
```

---

## Design Notes

### Sentinel vs. timeout strategy

Other active probes that send a non-DA1 query (`Termicap.XTVERSION.IO`, `Termicap.Color.BG_Query.IO`) use `Sentinel_Query`, which appends a DA1 query (`CSI c`) after the user query. The accumulation loop exits when `Contains_DA1_Response` returns `True`, signalling that the terminal has processed everything up to and including the sentinel.

For the DA1 feature, this strategy is unavailable — the user query *is* `CSI c`, and appending a second `CSI c` sentinel would interleave two DA1 responses in the buffer (ADR-0017). `Termicap.DA1.IO` therefore calls `Timeout_Query`.

For DECRPM, `Sentinel_Query` is safe. The DECRPM response (`CSI ? Ps ; Pm $ y`, ending with `$ y`) is unambiguously different from the DA1 sentinel response (`ESC [ ? Ps ; ... c`, ending with `c`). The accumulation loop in `Sentinel_Query` exits when the DA1 sentinel response is detected — at that point all DECRPM response bytes are already in the buffer, and `Parse_DECRPM_Response` can process them cleanly.

### Batch query design

`Detect_Modes` reuses a single `Probe_Session` across all queries in the batch. Each mode is queried in sequence using `Sentinel_Query` with a per-mode timeout derived from the total budget. This amortises the cost of opening and closing `/dev/tty` and restoring terminal settings across all modes in the batch — particularly beneficial when checking several modes as part of terminal capability discovery at startup.

### SPARK split

`Termicap.DECRPM` follows the same SPARK split pattern as `Termicap.XTVERSION`, `Termicap.Color.BG_Query`, and `Termicap.DA1`:

- `Termicap.DECRPM` (both spec and body): SPARK Silver — all provable building blocks isolated here, `Global => null` on all subprograms.
- `Termicap.DECRPM.IO` (both spec and body): `SPARK_Mode => Off` — session management and terminal I/O only.

`Termicap.DECRPM` re-declares `Byte` and `Byte_Array` from `Interfaces.C.unsigned_char` rather than depending on `Termicap.OSC` (which is `SPARK_Mode => Off`). This preserves full SPARK provability in the parent package while maintaining representation compatibility at the I/O boundary in the child package.

---

## Related

- **`Termicap.OSC`** (`docs/guide/reference/osc.md`): `Sentinel_Query`, `Probe_Session`, and `Response_Buffer` used by `Termicap.DECRPM.IO`
- **`Termicap.OSC.Parsing`** (`docs/guide/reference/osc.md`): `Wrap_For_Passthrough` used for multiplexer passthrough in `Query_Mode` and `Detect_Modes`
- **`Termicap.DA1.IO`** (`docs/guide/reference/da1.md`): Contrast — uses `Timeout_Query` instead of `Sentinel_Query`
- **Tech Spec DECRPM** (`docs/tech-specs/decrpm.md`): Full design rationale
- **Requirements** (`docs/requirements/functional/decrpm.sdoc`): FUNC-RPM-001 through FUNC-RPM-017
