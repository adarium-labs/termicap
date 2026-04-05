# API Reference: `Termicap.OSC` and `Termicap.OSC.Parsing`

Package pair providing the OSC/DCS/CSI probe session lifecycle and pure SPARK DA1 parsing. `Termicap.OSC` is the FFI boundary for active terminal probing; `Termicap.OSC.Parsing` is its SPARK Silver child.

**Files:** `src/termicap-osc.ads`, `src/termicap-osc.adb`, `src/termicap-osc-parsing.ads`, `src/termicap-osc-parsing.adb`, `src/c/termicap_osc.c`
**SPARK_Mode:** `Termicap.OSC` — Off (spec and body); `Termicap.OSC.Parsing` — On (spec and body, Silver level)
**License:** Apache-2.0

---

## Overview

`Termicap.OSC` provides the complete infrastructure for sending escape sequence queries to a terminal and reading back responses in a controlled, restoring manner. The central abstraction is `Probe_Session`, a `Limited_Controlled` type that guarantees terminal state restoration on scope exit or exception propagation.

The **sentinel-bounded query pattern** drives response collection: each user query is followed by a DA1 request (`ESC [ c`). Response bytes are accumulated until the DA1 response (`ESC [ ? … c`) is detected or the timeout expires. This makes response boundaries unambiguous across heterogeneous terminals without side effects on cursor state.

All termios manipulation and POSIX I/O is delegated to a C helper (`termicap_osc.c`) exposing nine fixed-signature functions. `Termicap.OSC.Parsing` is the pure SPARK complement: it contains only side-effect-free functions that operate on `Byte_Array` values and carry machine-verified SPARK contracts.

---

## Package `Termicap.OSC`

### Types

#### `File_Descriptor`

```ada
type File_Descriptor is new Interfaces.C.int;
INVALID_FD : constant File_Descriptor := -1;
```

A distinct integer type for POSIX file descriptors. `INVALID_FD` is returned by `Open_Terminal` on failure and is the initial value of a session's FD field.

**Requirements:** FUNC-OSC-001

---

#### `Byte`

```ada
subtype Byte is Interfaces.C.unsigned_char;
```

A single byte of terminal I/O. Matches `unsigned char` in the C helper interface.

---

#### `Byte_Array`

```ada
type Byte_Array is array (Positive range <>) of Byte;
```

An unconstrained sequence of bytes. Used both as the type for arbitrary escape sequence queries (sent to the terminal) and for accumulated response bytes (read from it).

---

#### `Termios_State`

```ada
MAX_TERMIOS_SIZE : constant := 128;

type Termios_State is limited record
   Data : Byte_Array (1 .. MAX_TERMIOS_SIZE);
   Size : Natural;
end record;
```

Opaque buffer holding a saved `struct termios`. The C helper fills `Data` with the platform-specific struct bytes and records the actual `sizeof(struct termios)` in `Size`. Ada code treats this as an opaque value; no field inspection is needed.

`MAX_TERMIOS_SIZE = 128` provides headroom above all current platform sizes (Linux: 60 bytes, macOS: 72 bytes, FreeBSD: 44 bytes).

**Requirements:** FUNC-OSC-002

---

#### `Session_Status`

```ada
type Session_Status is
  (Session_OK,
   Session_Not_Foreground,
   Session_No_Terminal,
   Session_Save_Failed,
   Session_Raw_Failed,
   Session_Already_Active);
```

Outcome of an `Open` call. Each value identifies the exact step at which opening failed.

| Value | Meaning |
|-------|---------|
| `Session_OK` | Session opened successfully; queries may proceed |
| `Session_Not_Foreground` | Process is in a background process group; no query sent |
| `Session_No_Terminal` | `/dev/tty` could not be opened |
| `Session_Save_Failed` | `tcgetattr()` failed; cannot save termios |
| `Session_Raw_Failed` | `tcsetattr()` for raw mode failed |
| `Session_Already_Active` | Another `Probe_Session` is open in this process |

**Requirements:** FUNC-OSC-008

---

#### `Response_Buffer`

```ada
MAX_RESPONSE_SIZE : constant := 4_096;
subtype Response_Buffer is Byte_Array (1 .. MAX_RESPONSE_SIZE);
```

Fixed-size accumulation buffer for `Sentinel_Query` responses. Stack-allocated — no heap allocation occurs during probing. Overflow (more than `MAX_RESPONSE_SIZE` bytes) is treated as a timeout condition.

**Requirements:** FUNC-OSC-009

---

#### `Probe_Session`

```ada
type Probe_Session is new Ada.Finalization.Limited_Controlled with private;
```

RAII probe session encapsulating `/dev/tty` open, raw mode, and restore. The private part holds:

| Field | Type | Initial value |
|-------|------|--------------|
| `FD` | `File_Descriptor` | `INVALID_FD` |
| `Saved_State` | `Termios_State` | zero |
| `Is_Raw` | `Boolean` | `False` |

The type is limited: it cannot be copied or assigned. Only one `Probe_Session` may be open at any time; `Is_Raw = True` acts as the single-session guard (FUNC-OSC-012).

`Finalize` is declared `overriding` and calls `Close` unconditionally, ensuring terminal restoration even on exception propagation (FUNC-OSC-015).

**Requirements:** FUNC-OSC-008, FUNC-OSC-012, FUNC-OSC-015

---

### Session Lifecycle

#### `Open`

```ada
procedure Open
  (Session : in out Probe_Session; Status : out Session_Status);
```

Open a probe session. Performs the following steps in order, stopping at the first failure:

1. Foreground process group check (FUNC-OSC-007). Returns `Session_Not_Foreground` if the process is in the background.
2. Acquire the single-session guard (FUNC-OSC-012). Returns `Session_Already_Active` if `Is_Raw` is already `True`.
3. Open `/dev/tty` (FUNC-OSC-001). Returns `Session_No_Terminal` on failure.
4. Save termios state (FUNC-OSC-002). Returns `Session_Save_Failed` and closes the FD on failure.
5. Activate raw mode (FUNC-OSC-003). Returns `Session_Raw_Failed` and restores termios and closes the FD on failure.
6. Drain stale input (FUNC-OSC-011). Non-fatal; proceeds regardless of outcome.

On success, `Status = Session_OK` and `Is_Open` returns `True`.

**Requirements:** FUNC-OSC-001, FUNC-OSC-002, FUNC-OSC-003, FUNC-OSC-007, FUNC-OSC-008, FUNC-OSC-011, FUNC-OSC-012

---

#### `Is_Open`

```ada
function Is_Open (Session : Probe_Session) return Boolean;
```

Return `True` if the session was opened successfully and has not yet been closed.

**Requirements:** FUNC-OSC-008

---

#### `Close`

```ada
procedure Close (Session : in out Probe_Session);
```

Close the probe session: restore termios, close `/dev/tty`, release the single-session guard. Safe to call when not open (no-op). Also called automatically by `Finalize` on scope exit or exception propagation.

Ordered: termios is restored before the FD is closed.

**Requirements:** FUNC-OSC-008

---

### Query Operations

#### `Sentinel_Query`

```ada
procedure Sentinel_Query
  (Session     : Probe_Session;
   Query       : Byte_Array;
   Response    : out Response_Buffer;
   Resp_Length : out Natural;
   Timeout_Ms  : Natural;
   Timed_Out   : out Boolean;
   Retry       : Boolean := False);
```

Send `Query` followed by the DA1 sentinel (`ESC [ c`), then accumulate response bytes until the DA1 response (`ESC [ ? … c`) is detected or `Timeout_Ms` milliseconds elapse.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Session` | in | Open probe session providing the terminal FD |
| `Query` | in | Escape sequence bytes to send (e.g., `ESC ] 11 ; ? ESC \`) |
| `Response` | out | Buffer receiving the pre-sentinel response bytes |
| `Resp_Length` | out | Number of valid bytes written into `Response` |
| `Timeout_Ms` | in | Millisecond timeout for the read accumulation loop |
| `Timed_Out` | out | `True` if the DA1 response was not detected in time |
| `Retry` | in | When `True` and the first attempt timed out, retry once with `2 * Timeout_Ms` (default: `False`) |

On DA1 detection, `Response(1 .. Resp_Length)` contains the pre-sentinel bytes and `Timed_Out = False`. On timeout, `Timed_Out = True` and `Resp_Length = 0`.

The session must be open (`Is_Open = True`) before calling.

**Requirements:** FUNC-OSC-006, FUNC-OSC-009, FUNC-OSC-013

---

### Low-Level I/O

#### `Write_Query`

```ada
procedure Write_Query
  (Session : Probe_Session;
   Query   : Byte_Array;
   Written : out Natural;
   Success : out Boolean);
```

Write a byte sequence to the session's terminal FD via `write()`. `Success = False` on partial write or error. Does not retry partial writes.

**Requirements:** FUNC-OSC-005

---

#### `Timed_Read`

```ada
procedure Timed_Read
  (FD         : File_Descriptor;
   Buffer     : out Byte_Array;
   Bytes_Read : out Natural;
   Timeout_Ms : Natural;
   Timed_Out  : out Boolean);
```

Read bytes from a file descriptor with a millisecond timeout, using `select()` followed by `read()`. `Timed_Out = True` when `select()` returned 0 (no data within timeout). On `select()` or `read()` error, `Bytes_Read = 0` and `Timed_Out = False`. `Timeout_Ms = 0` performs a non-blocking poll.

**Requirements:** FUNC-OSC-004

---

#### `Is_Foreground_Process`

```ada
function Is_Foreground_Process (FD : File_Descriptor) return Boolean;
```

Return `True` if the calling process is in the terminal's foreground process group. Uses `ioctl(FD, TIOCGPGRP, &fg_pgrp)` and compares with `getpgrp()`. Returns `False` on `ioctl` failure.

**Requirements:** FUNC-OSC-007

---

### Internal Terminal Operations

These subprograms are called by `Open` and `Close`/`Finalize`. They are part of the public interface for testability and for callers that need finer-grained control.

#### `Open_Terminal`

```ada
function Open_Terminal return File_Descriptor;
```

Open `/dev/tty` for direct terminal I/O (`open("/dev/tty", O_RDWR)`). Returns `INVALID_FD` on failure.

**Requirements:** FUNC-OSC-001

---

#### `Close_Terminal`

```ada
procedure Close_Terminal (FD : in out File_Descriptor);
```

Close a terminal file descriptor (`close(FD)`). Sets `FD := INVALID_FD` on return. Safe to call with `INVALID_FD` (no-op).

**Requirements:** FUNC-OSC-001

---

#### `Save_Termios`

```ada
procedure Save_Termios
  (FD : File_Descriptor; State : out Termios_State; OK : out Boolean);
```

Save the current termios state via `tcgetattr()`. The raw struct bytes are copied into `State.Data`; `State.Size` records the actual platform `sizeof(struct termios)`.

**Requirements:** FUNC-OSC-002

---

#### `Restore_Termios`

```ada
procedure Restore_Termios
  (FD : File_Descriptor; State : Termios_State; OK : out Boolean);
```

Restore a previously saved termios state via `tcsetattr(FD, TCSANOW, …)`. Does not raise an exception on failure; `OK` reports the outcome.

**Requirements:** FUNC-OSC-002

---

#### `Set_Raw_Mode`

```ada
procedure Set_Raw_Mode
  (FD : File_Descriptor; State : Termios_State; OK : out Boolean);
```

Switch the terminal to raw mode by deriving a raw `struct termios` from `State` (clearing `ICANON`, `ECHO`, `ISIG`, `IXON`, `ICRNL`, `BRKINT`; setting `VMIN=0`, `VTIME=0`) and applying it via `tcsetattr(TCSANOW)`. Does not modify `State`. Must be called after a successful `Save_Termios`.

**Requirements:** FUNC-OSC-003

---

#### `Drain_Input`

```ada
procedure Drain_Input (FD : File_Descriptor);
```

Drain stale buffered bytes from a terminal FD by performing non-blocking `Timed_Read` calls (Timeout_Ms = 0) until a read returns 0 bytes. Bounded to at most `MAX_DRAIN_ITERATIONS` iterations to prevent an infinite loop against a continuously-streaming terminal.

**Requirements:** FUNC-OSC-011

---

### RAII Guarantee

`Probe_Session` is a `Limited_Controlled` type. The Ada runtime calls `Finalize` automatically when a session goes out of scope, whether by normal exit or exception propagation. `Finalize` calls `Close`, which:

1. Restores termios via `Restore_Termios`.
2. Closes the FD via `Close_Terminal`.
3. Sets `Is_Raw := False`, releasing the single-session guard.

No caller action is required for cleanup beyond declaring the session in an appropriate scope. Calling `Close` explicitly before scope exit is safe (idempotent — `Finalize` becomes a no-op).

---

## Package `Termicap.OSC.Parsing`

### Types

#### `DA1_Value_Array`

```ada
MAX_DA1_PARAMS : constant := 16;
type DA1_Value_Array is array (Positive range 1 .. MAX_DA1_PARAMS) of Natural;
```

Fixed-size array holding up to 16 decimal parameter values extracted from a DA1 response. Only indices `1 .. Count` are meaningful; the remainder are zero-initialised.

**Requirements:** FUNC-OSC-010

---

#### `DA1_Params`

```ada
type DA1_Params is record
   Count  : Natural range 0 .. MAX_DA1_PARAMS := 0;
   Values : DA1_Value_Array := [others => 0];
end record;
```

Aggregates the parsed DA1 parameters. `Count = 0` indicates no valid DA1 response was found or the input was empty.

**Requirements:** FUNC-OSC-010

---

#### `Passthrough_Mode`

```ada
type Passthrough_Mode is
  (No_Passthrough, Tmux_Passthrough, Screen_Passthrough);
```

Selects the DCS wrapping applied by `Wrap_For_Passthrough`. Callers derive the appropriate value from a `Termicap.Terminal_Id.Terminal_Identity` result.

| Value | Wrapping applied |
|-------|-----------------|
| `No_Passthrough` | Query sent as-is |
| `Tmux_Passthrough` | `ESC P tmux ; ESC <Query> ESC \` |
| `Screen_Passthrough` | `ESC P <Query> ESC \` |

**Requirements:** FUNC-OSC-014

---

### Functions

#### `Contains_DA1_Response`

```ada
function Contains_DA1_Response
  (Bytes : Byte_Array; Length : Natural) return Boolean
with Pre => Length <= Bytes'Length;
```

Return `True` if `Bytes(1 .. Length)` contains a complete DA1 response matching the pattern `ESC [ ? <digits/semicolons>+ c` (bytes `0x1B 0x5B 0x3F … 0x63`). Presence detection is sufficient for boundary determination in `Sentinel_Query`; full parsing is not required here.

**SPARK contract:** `Pre => Length <= Bytes'Length`

**Requirements:** FUNC-OSC-006

---

#### `DA1_Response_Start`

```ada
function DA1_Response_Start
  (Bytes : Byte_Array; Length : Natural) return Natural
with
  Pre  => Length <= Bytes'Length,
  Post => DA1_Response_Start'Result <= Length;
```

Return the 1-based index of the `ESC` byte (`0x1B`) that starts the DA1 response in `Bytes(1 .. Length)`. Returns `Length` (used as a sentinel "not found" value) when no DA1 response is present, allowing the caller to slice `Bytes(1 .. Result - 1)` as the pre-sentinel response.

**SPARK contract:** `Pre`; `Post => result <= Length` (GNATprove-dischargeable)

**Requirements:** FUNC-OSC-006

---

#### `Parse_DA1_Response`

```ada
function Parse_DA1_Response
  (Bytes : Byte_Array; Length : Natural) return DA1_Params
with
  Pre  => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE,
  Post => Parse_DA1_Response'Result.Count <= MAX_DA1_PARAMS;
```

Parse a DA1 response byte sequence and extract its numeric parameters. Verifies that `Bytes(1 .. Length)` matches `ESC [ ? <decimal-or-semicolons>* c`, then splits on semicolons and converts each segment to `Natural`.

Returns `Count = 0` if the pattern does not match, if `Length = 0`, or if no digit bytes are present between `?` and the terminating `c`.

**SPARK contract:** `Pre` (bounds); `Post => result.Count <= MAX_DA1_PARAMS` (GNATprove-dischargeable at Silver level)

**Requirements:** FUNC-OSC-010

---

#### `Wrap_For_Passthrough`

```ada
function Wrap_For_Passthrough
  (Query : Byte_Array; Passthrough : Passthrough_Mode) return Byte_Array;
```

Wrap a query byte sequence in the DCS passthrough syntax for the specified multiplexer.

| `Passthrough` | Encoding |
|--------------|----------|
| `No_Passthrough` | Returns `Query` unchanged |
| `Tmux_Passthrough` | `0x1B 0x50 "tmux;" 0x1B <Query bytes> 0x1B 0x5C` |
| `Screen_Passthrough` | `0x1B 0x50 <Query bytes> 0x1B 0x5C` |

The returned `Byte_Array` is a new value owned by the caller.

**Requirements:** FUNC-OSC-014

---

## Usage Pattern

```ada
with Termicap.OSC;         use Termicap.OSC;
with Termicap.OSC.Parsing; use Termicap.OSC.Parsing;

procedure Probe_Background_Color is
   --  OSC 11 background color query: ESC ] 11 ; ? ESC \
   Query : constant Byte_Array :=
     [16#1B#, 16#5D#, 16#31#, 16#31#, 16#3B#,
      16#3F#, 16#1B#, 16#5C#];

   Session     : Probe_Session;
   Status      : Session_Status;
   Response    : Response_Buffer;
   Resp_Length : Natural;
   Timed_Out   : Boolean;
begin
   Open (Session, Status);

   if Status /= Session_OK then
      return;  --  not interactive or background
   end if;

   Sentinel_Query
     (Session     => Session,
      Query       => Query,
      Response    => Response,
      Resp_Length => Resp_Length,
      Timeout_Ms  => 250,
      Timed_Out   => Timed_Out,
      Retry       => True);

   --  Session.Finalize is called here unconditionally.

   if not Timed_Out then
      --  Response(1 .. Resp_Length) contains the OSC 11 reply bytes.
      null;
   end if;
end Probe_Background_Color;
```

The session goes out of scope at the end of `Probe_Background_Color` and `Finalize` restores the terminal. No explicit `Close` call is needed.

---

## SPARK Notes

`Termicap.OSC` carries `pragma SPARK_Mode (Off)` throughout. `Ada.Finalization.Limited_Controlled` and the POSIX syscall FFI are outside the SPARK 2014 language subset.

`Termicap.OSC.Parsing` carries `pragma SPARK_Mode (On)`. All four functions are provable at Silver level without manual lemmas:

- `Contains_DA1_Response`: `Pre` prevents out-of-bounds access; the loop is bounded by `Length`.
- `DA1_Response_Start`: `Pre` + `Post` together prove the result is a valid index into `Bytes(1 .. Length)`.
- `Parse_DA1_Response`: `Pre` constrains `Length` to `MAX_RESPONSE_SIZE`; `Post` proves the count bound.
- `Wrap_For_Passthrough`: pure function; no contracts beyond the type system are needed.

---

## Requirements Traceability

| Requirement | Element |
|-------------|---------|
| FUNC-OSC-001 | `Open_Terminal`, `Close_Terminal`, `File_Descriptor`, `INVALID_FD` |
| FUNC-OSC-002 | `Save_Termios`, `Restore_Termios`, `Termios_State`, `MAX_TERMIOS_SIZE` |
| FUNC-OSC-003 | `Set_Raw_Mode` |
| FUNC-OSC-004 | `Timed_Read` |
| FUNC-OSC-005 | `Write_Query` |
| FUNC-OSC-006 | `Sentinel_Query`, `Contains_DA1_Response`, `DA1_Response_Start` |
| FUNC-OSC-007 | `Is_Foreground_Process` |
| FUNC-OSC-008 | `Probe_Session`, `Open`, `Is_Open`, `Close`, `Session_Status`, `Finalize` |
| FUNC-OSC-009 | `Response_Buffer`, `MAX_RESPONSE_SIZE` — overflow treated as timeout in `Sentinel_Query` |
| FUNC-OSC-010 | `Parse_DA1_Response`, `DA1_Params`, `DA1_Value_Array`, `MAX_DA1_PARAMS` |
| FUNC-OSC-011 | `Drain_Input` |
| FUNC-OSC-012 | `Probe_Session.Is_Raw` — single-session guard in `Open` and `Finalize`/`Close` |
| FUNC-OSC-013 | `Sentinel_Query (Retry => True)` — doubles timeout on retry |
| FUNC-OSC-014 | `Wrap_For_Passthrough`, `Passthrough_Mode` |
| FUNC-OSC-015 | `pragma SPARK_Mode (Off)` on `Termicap.OSC`; `pragma SPARK_Mode (On)` on `Termicap.OSC.Parsing` |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.OSC` and `Termicap.OSC.Parsing` descriptions
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 18: full probe session lifecycle, sentinel query accumulation, and RAII restore flow
- **Tech Spec OSC** (`docs/tech-specs/osc-query-infra.md`) — design rationale, framework survey, C helper design, and ADR-0014
- **[Termicap.Terminal_Id](terminal-id.md)** — source of `Multiplexer_Kind`; used to derive the `Passthrough_Mode` for `Wrap_For_Passthrough`
