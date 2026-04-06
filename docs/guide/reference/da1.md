# API Reference: `Termicap.DA1` and `Termicap.DA1.IO`

Package pair providing SPARK Silver-provable DA1 response interpretation and an I/O boundary for active terminal capability detection via the Primary Device Attributes protocol (`CSI c` / `ESC [ ? Ps ; Ps ; ... c`).

**Files:**
- `src/termicap-da1.ads`, `src/termicap-da1.adb`
- `src/termicap-da1-io.ads`, `src/termicap-da1-io.adb`

**SPARK_Mode:** `Termicap.DA1` — On (spec and body, Silver level); `Termicap.DA1.IO` — Off (spec and body)
**License:** Apache-2.0

---

## Overview

The DA1 feature queries the terminal for its Primary Device Attributes by sending the `CSI c` (`ESC [ c`) escape sequence and parsing the response `ESC [ ? Ps ; Ps ; ... c`. The first `Ps` encodes the VT conformance level; subsequent `Ps` values advertise specific capabilities such as Sixel graphics, ANSI color, or rectangular editing.

`Termicap.DA1` contains all SPARK-provable building blocks: the `DA1_Capability` enumeration, the `VT_Level` enumeration, the `DA1_Capabilities` aggregate record, the `DA1_QUERY` constant, and three pure interpretation functions (`Interpret_DA1`, `Has_Capability`, `VT_Level_Of`). All functions carry `Global => null` and are verifiable at SPARK Silver level.

`Termicap.DA1.IO` contains the I/O boundary: `Query_DA1` drives the probe session using a timeout-only read loop, while `Detect_DA1` combines I/O, parsing, and interpretation into a single call. It carries `pragma SPARK_Mode (Off)` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O.

**Key distinction from other active probes:** unlike XTVERSION and BG-COLOR, `Termicap.DA1.IO` calls `Timeout_Query` rather than `Sentinel_Query`. Appending a DA1 sentinel (`CSI c`) after the DA1 query would produce two overlapping DA1 responses in the accumulation buffer, making boundary detection ambiguous (ADR-0017). The read loop exits when `Contains_DA1_Response` returns `True` for the accumulated bytes or the timeout elapses.

The typical call patterns are:

- **Single call, default timeout:** `Detect_DA1` — returns `DA1_Capabilities` directly.
- **Custom timeout or separate I/O and interpretation steps:** call `Query_DA1` then `Parse_DA1_Response` then `Interpret_DA1`.
- **Via aggregated record:** `Termicap.Capabilities.Detect` or `Get` — the `DA1` field of `Terminal_Capabilities` is populated automatically.

---

## Package `Termicap.DA1`

### Types

#### `DA1_Capability`

```ada
type DA1_Capability is
  (Printer,              --  Ps =  2
   ReGIS_Graphics,       --  Ps =  3
   Sixel_Graphics,       --  Ps =  4
   Selective_Erase,      --  Ps =  6
   User_Defined_Keys,    --  Ps =  8
   Windowing,            --  Ps = 18
   ANSI_Color,           --  Ps = 22
   Rectangular_Editing); --  Ps = 28
```

Curated subset of DA1 `Ps` parameter values relevant to terminal capability detection. Each literal corresponds to a specific `Ps` value in the Primary Device Attributes response. Unrecognised `Ps` values are silently ignored by `Interpret_DA1`.

| Literal | `Ps` | Meaning |
|---------|-----|---------|
| `Printer` | 2 | Printer port capability |
| `ReGIS_Graphics` | 3 | ReGIS vector graphics |
| `Sixel_Graphics` | 4 | Sixel bitmap graphics |
| `Selective_Erase` | 6 | Selective (protected) character erase |
| `User_Defined_Keys` | 8 | Programmable function keys (UDK) |
| `Windowing` | 18 | Window manipulation capability |
| `ANSI_Color` | 22 | ANSI colour (VT525 extension) |
| `Rectangular_Editing` | 28 | Rectangular area operations (DECCRA, DECFRA, etc.) |

**Requirements:** FUNC-DA1-001

---

#### `VT_Level`

```ada
type VT_Level is
  (Unknown,  --  No DA1 response or unrecognised first Ps
   VT100,    --  Ps = 1 (reserved; no modern terminal sends this)
   VT200,    --  Ps = 62
   VT300,    --  Ps = 63
   VT400,    --  Ps = 64
   VT500);   --  Ps = 65
```

VT conformance level encoded in the first `Ps` parameter of the DA1 response. `Unknown` is placed first so that default-initialised records carry `Unknown` as their `VT_Level`.

| Value | `Ps` | Description |
|-------|-----|-------------|
| `Unknown` | any other | No response received, or first `Ps` not in the recognised set. Also the value when `Supported = False`. |
| `VT100` | 1 | Reserved for completeness; no modern terminal emulator sends `Ps = 1` as its conformance class. |
| `VT200` | 62 | VT220-class conformance (most common for modern terminals). |
| `VT300` | 63 | VT320-class conformance. |
| `VT400` | 64 | VT420-class conformance. |
| `VT500` | 65 | VT520/525-class conformance. |

**Requirements:** FUNC-DA1-002

---

#### `Capability_Flags`

```ada
type Capability_Flags is array (DA1_Capability) of Boolean;
```

Boolean flag array indexed by `DA1_Capability`. Each element is `True` when the corresponding `Ps` value appeared in the DA1 response. Enables O(1) capability access by enumeration index and ensures future enumeration additions default to `False` automatically.

**Requirements:** FUNC-DA1-003

---

#### `DA1_Capabilities`

```ada
type DA1_Capabilities is record
   Supported : Boolean          := False;
   Level     : VT_Level         := Unknown;
   Flags     : Capability_Flags := [others => False];
end record;
```

Aggregated result of a DA1 response interpretation.

| Field | Default | Description |
|-------|---------|-------------|
| `Supported` | `False` | Semantic guard. `False` means no DA1 response was received or the response was empty. When `False`, `Level = Unknown` and all `Flags` entries are `False`. |
| `Level` | `Unknown` | VT conformance level decoded from the first `Ps` parameter. Always `Unknown` when `Supported = False`. |
| `Flags` | `[others => False]` | Capability presence flags indexed by `DA1_Capability`. All `False` when `Supported = False`. |

Default initialisation produces a safe "no DA1 response" value without requiring a named aggregate. This is the value returned by `Detect_DA1` when the query times out or the probe session cannot be opened.

**Requirements:** FUNC-DA1-003

---

### Constants

#### `DA1_QUERY`

```ada
DA1_QUERY : constant Byte_Array :=
  [16#1B#,   --  ESC
   16#5B#,   --  [   (CSI introducer)
   16#63#];  --  c   (Primary Device Attributes)
```

Three-byte `Byte_Array` encoding the DA1 query `ESC [ c` (`0x1B 0x5B 0x63`). The canonical Primary Device Attributes request.

Defined in the SPARK On package so that both `Termicap.DA1.IO` and test code can reference it without introducing a `SPARK_Mode` boundary violation.

**Note on dual use:** the same byte sequence `ESC [ c` is also used as the DA1 sentinel appended after every OSC query in `Sentinel_Query`. In that context it is a boundary marker. Here, `DA1_QUERY` is the primary query — the terminal's response is the capability advertisement.

**Requirements:** FUNC-DA1-007

---

### Functions

#### `Interpret_DA1`

```ada
function Interpret_DA1
  (Params : Termicap.OSC.Parsing.DA1_Params) return DA1_Capabilities
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    (if Params.Count = 0
     then not Interpret_DA1'Result.Supported
            and then Interpret_DA1'Result.Level = Unknown)
    and then
    (if Params.Count > 0
     then Interpret_DA1'Result.Supported);
```

Interpret a parsed DA1 response into a `DA1_Capabilities` record.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Params` | in | Parsed DA1 parameter array from `Parse_DA1_Response` (in `Termicap.OSC.Parsing`). |

**Returns:** A `DA1_Capabilities` record reflecting the parsed response.

**Algorithm:**
1. If `Params.Count = 0`, return a zeroed record (`Supported => False`, `Level => Unknown`, `Flags => [others => False]`).
2. Set `Supported := True`.
3. Decode `Params.Values(1)` as the VT conformance level: `62 => VT200`, `63 => VT300`, `64 => VT400`, `65 => VT500`, `others => Unknown`.
4. Scan `Params.Values(2 .. Params.Count)`; for each recognised value, set the corresponding `Flags` entry to `True`. Unrecognised values are silently ignored.

**SPARK contract:**
- `Count = 0` implies `Supported = False` and `Level = Unknown` (machine-verified).
- `Count > 0` implies `Supported = True` (machine-verified).

**Requirements:** FUNC-DA1-004

---

#### `Has_Capability`

```ada
function Has_Capability
  (Caps : DA1_Capabilities; Cap : DA1_Capability) return Boolean
is (Caps.Supported and then Caps.Flags (Cap))
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    Has_Capability'Result = (Caps.Supported and then Caps.Flags (Cap));
```

Return `True` if and only if `Cap` is present in the DA1 capabilities record.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Caps` | in | The `DA1_Capabilities` record to query. |
| `Cap` | in | The specific capability to test. |

**Returns:** `True` when `Caps.Supported = True` and `Caps.Flags (Cap) = True`. Short-circuit evaluation ensures `False` is returned whenever `Supported = False`, regardless of the flag array state.

**Example:**
```ada
if Has_Capability (Caps, Sixel_Graphics) then
   --  Terminal advertises Sixel graphics support
end if;
```

**Requirements:** FUNC-DA1-005

---

#### `VT_Level_Of`

```ada
function VT_Level_Of
  (Caps : DA1_Capabilities) return VT_Level
is (Caps.Level)
with
  SPARK_Mode => On,
  Global     => null,
  Post       =>
    VT_Level_Of'Result = Caps.Level
    and then (if not Caps.Supported
              then VT_Level_Of'Result = Unknown);
```

Return the VT conformance level from a `DA1_Capabilities` record.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Caps` | in | The `DA1_Capabilities` record to query. |

**Returns:** `Caps.Level`. When `Caps.Supported = False`, this is always `Unknown` by construction of `Interpret_DA1` and the default initialisation of `DA1_Capabilities`. The postcondition gives SPARK-annotated callers a provable fact: any call site that knows `Caps.Supported = False` may substitute `Unknown` directly.

**Requirements:** FUNC-DA1-006

---

## Package `Termicap.DA1.IO`

### Overview

`Termicap.DA1.IO` is the I/O boundary for the DA1 feature. It has `pragma SPARK_Mode (Off)` throughout because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O.

The key architectural difference from other IO packages is the use of `Timeout_Query` rather than `Sentinel_Query`. Because the DA1 response (`ESC [ ? Ps ; ... c`) contains the same terminating `c` byte as the sentinel query (`ESC [ c`), appending a sentinel would create two overlapping DA1 sequences in the buffer with ambiguous boundaries. `Timeout_Query` instead exits when `Contains_DA1_Response` returns `True` for the accumulated bytes, or when the timeout elapses (ADR-0017).

---

### Procedures and Functions

#### `Query_DA1`

```ada
procedure Query_DA1
  (Timeout_Ms  :     Natural;
   Response    : out Termicap.OSC.Response_Buffer;
   Resp_Length : out Natural;
   Timed_Out   : out Boolean)
with Pre => Response'Length >= Termicap.OSC.MAX_RESPONSE_SIZE;
```

Send a `CSI c` DA1 query to the terminal and return the raw response bytes.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Timeout_Ms` | in | Millisecond timeout for the response accumulation loop. |
| `Response` | out | Buffer receiving the raw DA1 response bytes. Must have at least `MAX_RESPONSE_SIZE` elements (enforced by precondition). |
| `Resp_Length` | out | Number of valid bytes written into `Response`. `0` on timeout or session failure. |
| `Timed_Out` | out | `True` if no complete DA1 response was detected within `Timeout_Ms`, or if the `Probe_Session` failed to open. |

**Execution steps:**
1. Capture environment snapshot and detect terminal identity via `Detect_Terminal_Identity`. Derive multiplexer passthrough mode from `Identity.Kind`.
2. Wrap `DA1_QUERY` using `Wrap_For_Passthrough` if a multiplexer is active.
3. Open a `Probe_Session`. On any failure (`Session_Not_Foreground`, `Session_No_Terminal`, etc.), set `Timed_Out := True`, `Resp_Length := 0`, and return immediately.
4. Write the (possibly wrapped) query bytes via `Write_Query`. On failure, set `Timed_Out := True`, `Resp_Length := 0`, and return.
5. Call `Timeout_Query`: accumulate bytes until `Contains_DA1_Response` returns `True` or `Timeout_Ms` elapses.
6. On DA1 detection: set `Resp_Length` to the accumulated byte count, `Timed_Out := False`.
7. On timeout: set `Timed_Out := True`, `Resp_Length := 0`.
8. `Probe_Session.Finalize` restores terminal state unconditionally.

Never raises an exception on any code path.

**Requirements:** FUNC-DA1-008, FUNC-DA1-010, FUNC-DA1-011, FUNC-DA1-012

---

#### `Detect_DA1`

```ada
function Detect_DA1
  (Timeout_Ms : Natural := 100) return DA1_Capabilities;
```

Combine DA1 I/O, parsing, and interpretation into a single call.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Timeout_Ms` | in | Millisecond timeout for the DA1 query (default: 100 ms). |

**Returns:** A `DA1_Capabilities` record. `Supported = False` when no response was received within the timeout or the session could not be opened.

**Execution steps:**
1. Call `Query_DA1` with `Timeout_Ms` to obtain raw response bytes.
2. If `Timed_Out = True`, return a default `DA1_Capabilities` record (`Supported => False`).
3. Call `Parse_DA1_Response` (from `Termicap.OSC.Parsing`) on the response buffer.
4. Call `Interpret_DA1` on the parsed `DA1_Params`.
5. Return the resulting `DA1_Capabilities` record.

The default timeout of 100 ms is consistent with `Query_And_Identify` (XTVERSION) and is appropriate for local terminal sessions. Callers operating over high-latency links (SSH, serial) may pass a larger value.

Never raises an exception on any code path.

**Requirements:** FUNC-DA1-009

---

## Usage Examples

### Check for Sixel graphics support

```ada
with Termicap.DA1;
with Termicap.DA1.IO;

procedure Check_Sixel is
   Caps : constant Termicap.DA1.DA1_Capabilities :=
     Termicap.DA1.IO.Detect_DA1;
begin
   if Termicap.DA1.Has_Capability (Caps, Termicap.DA1.Sixel_Graphics) then
      --  Terminal supports Sixel graphics
   end if;
end Check_Sixel;
```

### Query VT conformance level

```ada
with Termicap.DA1;
with Termicap.DA1.IO;

procedure Check_VT_Level is
   Caps  : constant Termicap.DA1.DA1_Capabilities :=
     Termicap.DA1.IO.Detect_DA1;
   Level : constant Termicap.DA1.VT_Level :=
     Termicap.DA1.VT_Level_Of (Caps);
begin
   if Level >= Termicap.DA1.VT200 then
      --  Terminal declares at least VT220-class conformance
   end if;
end Check_VT_Level;
```

### Via aggregated capabilities record (recommended)

```ada
with Termicap.Capabilities;
with Termicap.DA1;

procedure Check_Via_Caps is
   Caps : constant Termicap.Capabilities.Terminal_Capabilities :=
     Termicap.Capabilities.Get;
begin
   if Termicap.DA1.Has_Capability
        (Caps.DA1, Termicap.DA1.ANSI_Color)
   then
      --  Terminal advertises ANSI colour capability (VT525 Ps=22)
   end if;
end Check_Via_Caps;
```

---

## Design Notes

### Timeout-only read loop

Other active probes in Termicap (`Termicap.XTVERSION.IO`, `Termicap.Color.BG_Query.IO`) use `Sentinel_Query`, which appends a DA1 query (`CSI c`) after the user query and exits the accumulation loop when the DA1 response is detected. This is possible because the user query and the DA1 sentinel produce distinct response patterns.

For the DA1 feature, the user query *is* `CSI c`, and the response `ESC [ ? Ps ; ... c` *is* the DA1 response. Appending a second `CSI c` sentinel would produce two DA1 responses in the buffer, with the accumulation loop unable to determine which `c` byte terminates the first response and which terminates the second. `Query_DA1` therefore calls `Timeout_Query`, which writes the query without a sentinel and terminates the loop on `Contains_DA1_Response` detection or timeout (ADR-0017).

### SPARK split

`Termicap.DA1` follows the same SPARK split pattern as `Termicap.XTVERSION` and `Termicap.Color.BG_Query`:

- `Termicap.DA1` (both spec and body): SPARK Silver — all provable building blocks isolated here, `Global => null` on all subprograms.
- `Termicap.DA1.IO` (both spec and body): `SPARK_Mode => Off` — session management and terminal I/O only.

`Termicap.DA1` re-declares `Byte` and `Byte_Array` from `Interfaces.C.unsigned_char` rather than depending on `Termicap.OSC` (which is `SPARK_Mode => Off`). It depends on `Termicap.OSC.Parsing` (SPARK Silver) for the `DA1_Params` type used by `Interpret_DA1`. This preserves full SPARK provability in the parent package while maintaining representation compatibility at the I/O boundary in the child package.

---

## Related

- **`Termicap.OSC`** (`docs/guide/reference/osc.md`): `Timeout_Query` and `Probe_Session` used by `Termicap.DA1.IO`
- **`Termicap.Capabilities`** (`docs/guide/reference/termicap-capabilities.md`): `Terminal_Capabilities.DA1` field
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`): Rationale for the timeout-only read loop
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`): Full design rationale
- **Requirements** (`docs/requirements/functional/da1.sdoc`): FUNC-DA1-001 through FUNC-DA1-015
