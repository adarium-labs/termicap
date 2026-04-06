# API Reference: `Termicap.XTVERSION` and `Termicap.XTVERSION.IO`

Package pair providing SPARK Silver-provable DCS response parsing and an I/O boundary for active terminal identification via the XTVERSION protocol (`CSI > q` / `DCS >| response`).

**Files:**
- `src/termicap-xtversion.ads`, `src/termicap-xtversion.adb`
- `src/termicap-xtversion-io.ads`, `src/termicap-xtversion-io.adb`

**SPARK_Mode:** `Termicap.XTVERSION` — On (spec and body, Silver level); `Termicap.XTVERSION.IO` — Off (spec and body)
**License:** Apache-2.0

---

## Overview

The XTVERSION feature identifies the active terminal emulator by sending the `CSI > q` escape sequence and parsing the `DCS >| <name> <version> ST` response. This is an active probing method — the library writes a byte sequence to the terminal and reads the response — in contrast to passive methods that inspect environment variables.

`Termicap.XTVERSION` contains all SPARK-provable building blocks: the CSI query constant, four pure parsing functions (DCS response recognition, payload extraction, name/version tokenisation, and top-level parse orchestration), and the result types. These functions carry `Global => null` contracts and are verifiable at SPARK Silver level without manual lemmas.

`Termicap.XTVERSION.IO` contains the I/O boundary: `Query_XTVERSION` drives the probe session and returns raw response bytes, while `Query_And_Identify` combines I/O and parsing into a single call. It carries `pragma SPARK_Mode (Off)` throughout because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O.

The two payload formats handled are:

- **Format B (parenthesised):** `xterm(388)` → Name = `"xterm"`, Version = `"388"`. Used by xterm, mlterm, foot.
- **Format A (space-separated):** `WezTerm 20240203` → Name = `"WezTerm"`, Version = `"20240203"`. Used by tmux, WezTerm, kitty.

Format B takes priority in `Split_XTV_Payload`: `(` is checked before space.

The typical call pattern is:

- **Single call, default timeout:** `Query_And_Identify` — returns `XTVERSION_Result` directly.
- **Custom timeout or separate I/O and parse steps:** call `Query_XTVERSION` then `Parse_XTVERSION_Response`.

---

## Package `Termicap.XTVERSION`

### Types

#### `XTVERSION_Status`

```ada
type XTVERSION_Status is (Success, Timeout, Parse_Error);
```

Three-way outcome discriminant for an XTVERSION query.

| Value | Meaning |
|-------|---------|
| `Success` | A valid DCS XTVERSION response was received and parsed; `Terminal_Name` and `Terminal_Version` fields are populated. |
| `Timeout` | The terminal did not respond with a DA1 sentinel within the allowed time. |
| `Parse_Error` | A response was received but could not be parsed as a valid DCS XTVERSION envelope, or the name token was empty. |

**Requirements:** FUNC-XTV-001

---

#### `XTVERSION_Result`

```ada
type XTVERSION_Result (Status : XTVERSION_Status := Timeout) is record
   case Status is
      when Success =>
         Terminal_Name    : Ada.Strings.Unbounded.Unbounded_String;
         Terminal_Version : Ada.Strings.Unbounded.Unbounded_String;
      when Timeout | Parse_Error =>
         null;
   end case;
end record;
```

Discriminated record carrying the outcome of an XTVERSION query.

| Discriminant | Fields available | Description |
|-------------|-----------------|-------------|
| `Success` | `Terminal_Name`, `Terminal_Version` | Name and version tokens extracted from the DCS response. Both are trimmed of leading and trailing whitespace. `Terminal_Name` is guaranteed non-empty (enforced by `Parse_XTVERSION_Response` postcondition). `Terminal_Version` may be empty for name-only payloads. |
| `Timeout` | (none) | Terminal did not respond. Accessing `Terminal_Name` or `Terminal_Version` raises `Constraint_Error`. |
| `Parse_Error` | (none) | Response received but malformed. Accessing `Terminal_Name` or `Terminal_Version` raises `Constraint_Error`. |

The default discriminant is `Timeout` (the most common non-success case), allowing unconstrained variable declarations without an explicit initial value.

**Requirements:** FUNC-XTV-001

---

#### `Payload_Slice`

```ada
type Payload_Slice is record
   Offset : Positive;
   Length : Natural;
end record;
```

Zero-copy positional reference into the raw response byte buffer. `Offset` is the index of the first payload byte (immediately after the `ESC P > |` prefix); `Length` is the number of payload bytes (excluding the `ST` or `BEL` terminator). No copy of the payload bytes is made during extraction.

Used as the return type of `Extract_XTV_Payload` and as the input bounds to `Split_XTV_Payload`.

**Requirements:** FUNC-XTV-004

---

#### `Token_Pair`

```ada
type Token_Pair is record
   Name    : Ada.Strings.Unbounded.Unbounded_String;
   Version : Ada.Strings.Unbounded.Unbounded_String;
end record;
```

Intermediate tokenisation result from `Split_XTV_Payload`. `Name` holds the terminal name (e.g., `"xterm"`, `"WezTerm"`). `Version` holds the version string (e.g., `"388"`, `"20240203"`), or the empty string if no delimiter was found in the payload.

Both strings are trimmed of leading and trailing ASCII space bytes (`0x20`).

**Requirements:** FUNC-XTV-005

---

### Constants

#### `MAX_RESPONSE_SIZE`

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
```

Maximum number of response bytes that `Query_XTVERSION` accumulates. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Used in the precondition of `Parse_XTVERSION_Response` to bound all parsing loops and guarantee termination.

**Requirements:** FUNC-XTV-006

---

#### `CSI_XTVERSION_QUERY`

```ada
CSI_XTVERSION_QUERY : constant Byte_Array :=
  [16#1B#, 16#5B#,                       --  ESC [   (CSI introducer)
   Character'Pos ('>'),                   --  >
   Character'Pos ('q')];                  --  q
```

Four-byte `Byte_Array` encoding the XTVERSION query `ESC [ > q` (`0x1B 0x5B 0x3E 0x71`). This is the canonical query sequence used by xterm, WezTerm, and tcell.

Defined in the SPARK On package so that both `Termicap.XTVERSION.IO` and test code can reference it without introducing a `SPARK_Mode` boundary violation.

**Requirements:** FUNC-XTV-002

---

### Functions

#### `Contains_XTVERSION_Response`

```ada
function Contains_XTVERSION_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Boolean
with
  Global => null,
  Pre    => Length <= Bytes'Length;
```

Return `True` if `Bytes(1 .. Length)` contains a well-formed DCS XTVERSION response envelope.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | Raw response byte buffer. |
| `Length` | in | Number of valid bytes to examine (`0 <= Length <= Bytes'Length`). |

**Returns:** `True` when all of the following hold:
1. `Length >= 6` (4-byte prefix + at least 1 payload byte + terminator).
2. `Bytes(1..4) = 0x1B 0x50 0x3E 0x7C` (`ESC P > |`).
3. A `ST` terminator (`0x1B 0x5C`) or `BEL` terminator (`0x07`) is present after the prefix.

Returns `False` for any input shorter than 6 bytes, any input not starting with `ESC P > |`, or any input lacking a valid terminator.

**SPARK contract:** `Pre => Length <= Bytes'Length` — prevents out-of-bounds access; loop bounded by `Length`.

**Requirements:** FUNC-XTV-003

---

#### `Extract_XTV_Payload`

```ada
function Extract_XTV_Payload
  (Bytes  : Byte_Array;
   Length : Natural) return Payload_Slice
with
  Global => null,
  Pre    => Length <= Bytes'Length
              and then Contains_XTVERSION_Response (Bytes, Length),
  Post   => Extract_XTV_Payload'Result.Length > 0
              and then Extract_XTV_Payload'Result.Offset >= Bytes'First + 4
              and then Extract_XTV_Payload'Result.Offset
                         + Extract_XTV_Payload'Result.Length - 1
                       < Bytes'First + Length;
```

Extract the payload region from a confirmed DCS XTVERSION response.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | Raw response byte buffer, already confirmed to contain a valid DCS XTVERSION envelope. |
| `Length` | in | Number of valid bytes. |

**Returns:** A `Payload_Slice` with:
- `Offset` — index of the first byte after the `ESC P > |` prefix (`>= Bytes'First + 4`).
- `Length` — count of payload bytes before the `ST` or `BEL` terminator (`> 0`).

The precondition requires `Contains_XTVERSION_Response` to have returned `True`, so this function need not handle invalid input. The postcondition machine-verifies that the slice lies entirely within the valid byte range.

**SPARK contract:** `Pre` requires `Contains_XTVERSION_Response`; `Post` guarantees non-empty payload within bounds — both dischargeable at Silver level.

**Requirements:** FUNC-XTV-004

---

#### `Split_XTV_Payload`

```ada
function Split_XTV_Payload
  (Bytes  : Byte_Array;
   Offset : Positive;
   Length : Natural) return Token_Pair
with
  Global => null,
  Pre    => Length > 0
              and then Offset >= Bytes'First
              and then Offset + Length - 1 <= Bytes'Last;
```

Split the XTVERSION payload bytes into a terminal name and version.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | The byte buffer containing the payload span. |
| `Offset` | in | Index of the first payload byte (from `Extract_XTV_Payload`). |
| `Length` | in | Number of payload bytes (must be `> 0`). |

**Returns:** A `Token_Pair` with `Name` and `Version` as `Unbounded_String` values.

**Format handling (in priority order):**

| Format | Example payload | `Name` | `Version` |
|--------|----------------|--------|-----------|
| B — parenthesised | `xterm(388)` | `"xterm"` | `"388"` |
| A — space-separated | `WezTerm 20240203` | `"WezTerm"` | `"20240203"` |
| Name-only | `SomeTerminal` | `"SomeTerminal"` | `""` |

Format B (parenthesised) takes priority: `(` is checked before space. This matches the WezTerm/termwiz reference implementation.

Both tokens are trimmed of leading and trailing ASCII space bytes (`0x20`).

**SPARK contract:** `Pre` bounds `Offset` and `Length` within `Bytes` — dischargeable at Silver level.

**Requirements:** FUNC-XTV-005

---

#### `Parse_XTVERSION_Response`

```ada
function Parse_XTVERSION_Response
  (Bytes  : Byte_Array;
   Length : Natural) return XTVERSION_Result
with
  Global => null,
  Pre    => Length <= Bytes'Length
              and then Length <= MAX_RESPONSE_SIZE,
  Post   =>
    (if Parse_XTVERSION_Response'Result.Status = Success
     then Ada.Strings.Unbounded.Length
            (Parse_XTVERSION_Response'Result.Terminal_Name) > 0);
```

Orchestrate DCS recognition, payload extraction, and tokenisation end-to-end.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Bytes` | in | Raw Sentinel_Query response byte buffer. |
| `Length` | in | Number of valid bytes in `Bytes` (`0 <= Length <= MAX_RESPONSE_SIZE`). |

**Returns:** `XTVERSION_Result` with status and (on success) name and version fields.

**Algorithm:**

1. If `Length = 0` or `Contains_XTVERSION_Response` returns `False`: return `(Status => Parse_Error)`.
2. Call `Extract_XTV_Payload` to obtain the payload slice.
3. Call `Split_XTV_Payload` on the slice to obtain name and version tokens.
4. If `Name` is non-empty: return `(Status => Success, Terminal_Name => Name, Terminal_Version => Version)`.
5. If `Name` is empty: return `(Status => Parse_Error)`.

No exception is raised on any code path.

**SPARK contract:** `Pre` bounds the buffer length; `Post` guarantees `Terminal_Name` is non-empty when `Status = Success` — machine-verified by GNATprove at Silver level.

**Requirements:** FUNC-XTV-006, FUNC-XTV-016

---

## Package `Termicap.XTVERSION.IO`

### Procedures and Functions

#### `Query_XTVERSION`

```ada
procedure Query_XTVERSION
  (Timeout_Ms  :     Natural;
   Response    : out XTVERSION.Byte_Array;
   Resp_Length : out Natural;
   Timed_Out   : out Boolean)
with Pre => Response'Length >= XTVERSION.MAX_RESPONSE_SIZE;
```

Send a `CSI > q` XTVERSION query to the terminal and return the raw DCS response bytes.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Timeout_Ms` | in | Millisecond timeout passed to `Sentinel_Query`. |
| `Response` | out | Buffer receiving the pre-sentinel response bytes. Must have length `>= XTVERSION.MAX_RESPONSE_SIZE`. |
| `Resp_Length` | out | Number of valid bytes written into `Response`. `0` on timeout or session failure. |
| `Timed_Out` | out | `True` if the DA1 sentinel was not detected within `Timeout_Ms`, or if the `Probe_Session` failed to open. |

**Algorithm:**

1. Capture the current environment and call `Detect_Terminal_Identity`.
2. If the terminal is a multiplexer (`Is_Multiplexer = True`), wrap `CSI_XTVERSION_QUERY` via `Termicap.OSC.Parsing.Wrap_For_Passthrough`:
   - `Tmux` → `Tmux_Passthrough`; `Screen` → `Screen_Passthrough`; other multiplexers → `Tmux_Passthrough` (safe default).
3. Open a `Probe_Session`. On failure (not foreground, `/dev/tty` unavailable, raw mode error): set `Timed_Out := True`, `Resp_Length := 0`, return immediately.
4. Call `Sentinel_Query` with `Retry => False` (no automatic retry).
5. Allow `Probe_Session` to close unconditionally via RAII (`Finalize`).
6. Populate `Response`, `Resp_Length`, and `Timed_Out` from the query result.

**Exception safety:** Never raises an exception on any code path.

**Note:** `Retry => False` means a single timeout results in `Timed_Out = True` with no automatic second attempt. Callers requiring retry behaviour must call `Query_XTVERSION` again explicitly.

**Requirements:** FUNC-XTV-008, FUNC-XTV-009, FUNC-XTV-010, FUNC-XTV-011, FUNC-XTV-012

---

#### `Query_And_Identify`

```ada
function Query_And_Identify
  (Timeout_Ms : Natural := 100) return XTVERSION_Result;
```

Combine XTVERSION I/O and parsing into a single call.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Timeout_Ms` | in | Millisecond timeout for `Query_XTVERSION`. Default: `100` ms. |

**Returns:** `XTVERSION_Result` with:
- `Status = Timeout` — if `Query_XTVERSION` sets `Timed_Out = True`.
- `Status = Success` — if a valid DCS response was received and parsed; `Terminal_Name` and `Terminal_Version` are populated.
- `Status = Parse_Error` — if a response was received but could not be parsed.

**Algorithm:**

1. Call `Query_XTVERSION (Timeout_Ms, Response, Resp_Length, Timed_Out)`.
2. If `Timed_Out = True`: return `XTVERSION_Result'(Status => Timeout)`.
3. Call `Parse_XTVERSION_Response (Response, Resp_Length)`.
4. Return the `Parse_XTVERSION_Response` result directly.

The default timeout of 100 ms balances responsiveness with adequate time for slow or multiplexed terminals to deliver the DCS response.

**Exception safety:** Never raises an exception on any code path.

**Requirements:** FUNC-XTV-013, FUNC-XTV-015

---

## Usage Examples

### Simplest usage: identify the active terminal

```ada
with Termicap.XTVERSION.IO; use Termicap.XTVERSION.IO;
with Termicap.XTVERSION;    use Termicap.XTVERSION;

declare
   Result : constant XTVERSION_Result := Query_And_Identify;
begin
   case Result.Status is
      when Success =>
         --  Terminal_Name is guaranteed non-empty (SPARK Silver postcondition)
         Put_Line ("Terminal: " & To_String (Result.Terminal_Name));
         Put_Line ("Version:  " & To_String (Result.Terminal_Version));
      when Timeout =>
         Put_Line ("Terminal did not respond to XTVERSION query.");
      when Parse_Error =>
         Put_Line ("XTVERSION response received but could not be parsed.");
   end case;
end;
```

### Custom timeout

```ada
Result : constant XTVERSION_Result := Query_And_Identify (Timeout_Ms => 250);
```

### Separate I/O and parse steps

Use this pattern when you need access to the raw response bytes, or when you want to call `Parse_XTVERSION_Response` from a test without terminal I/O.

```ada
with Termicap.XTVERSION.IO; use Termicap.XTVERSION.IO;
with Termicap.XTVERSION;    use Termicap.XTVERSION;

declare
   Response    : Byte_Array (1 .. MAX_RESPONSE_SIZE);
   Resp_Length : Natural;
   Timed_Out   : Boolean;
   Result      : XTVERSION_Result;
begin
   Query_XTVERSION
     (Timeout_Ms  => 150,
      Response    => Response,
      Resp_Length => Resp_Length,
      Timed_Out   => Timed_Out);

   if Timed_Out then
      Result := (Status => Timeout);
   else
      Result := Parse_XTVERSION_Response (Response, Resp_Length);
   end if;

   --  Use Result as needed.
end;
```

### Pure parse from a known byte buffer (testing)

`Parse_XTVERSION_Response` is a pure SPARK Silver function and can be called from any context — no terminal I/O required.

```ada
with Termicap.XTVERSION; use Termicap.XTVERSION;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

--  DCS response for "xterm(388)": ESC P > | x t e r m ( 3 8 8 ) ESC \
declare
   Raw : constant Byte_Array :=
     [16#1B#, 16#50#, 16#3E#, 16#7C#,         --  ESC P > |
      Character'Pos ('x'), Character'Pos ('t'),
      Character'Pos ('e'), Character'Pos ('r'),
      Character'Pos ('m'), Character'Pos ('('),
      Character'Pos ('3'), Character'Pos ('8'),
      Character'Pos ('8'), Character'Pos (')'),
      16#1B#, 16#5C#];                          --  ESC \
   Result : constant XTVERSION_Result :=
     Parse_XTVERSION_Response (Raw, Raw'Length);
begin
   pragma Assert (Result.Status = Success);
   pragma Assert (To_String (Result.Terminal_Name) = "xterm");
   pragma Assert (To_String (Result.Terminal_Version) = "388");
end;
```

---

## SPARK Notes

`Termicap.XTVERSION` targets SPARK Silver:

| Function | Key proof obligations | Discharged by |
|----------|-----------------------|---------------|
| `Contains_XTVERSION_Response` | Out-of-bounds access prevention; loop termination | `Pre => Length <= Bytes'Length`; loop bounded by `Length` |
| `Extract_XTV_Payload` | Payload slice in valid range; `Length > 0` | `Pre` (requires `Contains_XTVERSION_Response`); `Post` bounds via precondition chain |
| `Split_XTV_Payload` | Offset + Length within `Bytes'Last` | `Pre` bounds expression; no unbounded search |
| `Parse_XTVERSION_Response` | `Terminal_Name` non-empty on `Success` | `Post` predicate; GNATprove traces through the call to `Split_XTV_Payload` |

No manual lemmas, ghost code, or proof pragmas are required for any of the four functions.

`Termicap.XTVERSION.IO` carries `pragma SPARK_Mode (Off)` on the spec, preventing SPARK-annotated callers from inadvertently calling `Query_XTVERSION` or `Query_And_Identify` without a mode barrier. The pure parsing logic in the parent package remains fully provable and callable from SPARK contexts.

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-XTV-001 | `XTVERSION_Status`, `XTVERSION_Result` | Silver |
| FUNC-XTV-002 | `CSI_XTVERSION_QUERY` constant | Silver |
| FUNC-XTV-003 | `Contains_XTVERSION_Response` | Silver |
| FUNC-XTV-004 | `Extract_XTV_Payload`, `Payload_Slice` | Silver |
| FUNC-XTV-005 | `Split_XTV_Payload`, `Token_Pair` (both formats) | Silver |
| FUNC-XTV-006 | `Parse_XTVERSION_Response`, `MAX_RESPONSE_SIZE` | Silver |
| FUNC-XTV-007 | `SPARK_Mode On`, `Global => null` on all four parse functions | Silver |
| FUNC-XTV-008 | `Query_XTVERSION` procedure | Off |
| FUNC-XTV-009 | `Sentinel_Query (Retry => False)` in `Query_XTVERSION` | Off |
| FUNC-XTV-010 | Foreground guard via `Probe_Session.Open` | Off |
| FUNC-XTV-011 | Not-a-TTY guard via `Probe_Session.Open` | Off |
| FUNC-XTV-012 | Multiplexer passthrough via `Wrap_For_Passthrough` | Off |
| FUNC-XTV-013 | `Query_And_Identify` convenience function | Off |
| FUNC-XTV-015 | `Timed_Out = True` maps to `Status = Timeout` in `Query_And_Identify` | Off |
| FUNC-XTV-016 | All malformed-input cases return `Parse_Error` in `Parse_XTVERSION_Response` | Silver |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.XTVERSION` and `Termicap.XTVERSION.IO` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 21: full XTVERSION probe lifecycle, multiplexer passthrough decision, and parse pipeline
- **Tech Spec XTVERSION** (`docs/tech-specs/xtversion.md`) — design rationale, framework survey (tcell, WezTerm/termwiz), DCS envelope format details, and tokenisation algorithm
- **[Termicap.OSC](osc.md)** — `Probe_Session` and `Sentinel_Query` infrastructure used by `Query_XTVERSION`
- **[Termicap.Terminal_Id](termicap-terminal-id.md)** — source of `Terminal_Identity`; used in `Query_XTVERSION` to determine whether multiplexer passthrough wrapping is needed
