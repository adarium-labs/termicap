# Technical Specification: OSC Query Infrastructure

**Feature:** OSC Query Infrastructure (Tier 3 Foundation)
**Requirements:** `docs/requirements/osc-query-infra.sdoc` (FUNC-OSC-001 through FUNC-OSC-015)
**Date:** 2026-04-04

---

## 1. Overview

The OSC Query Infrastructure provides the low-level machinery that every active terminal probing feature in Termicap depends on: background/foreground color queries, XTVERSION, DA1 parsing, and DECRPM mode queries. None of these features can exist without a reliable way to send escape sequences to the terminal, read back responses with a timeout, and guarantee terminal state restoration.

This feature delivers:

- **Terminal file descriptor management** -- open/close `/dev/tty` for direct terminal I/O independent of stdin/stdout/stderr redirection
- **Termios save/restore and raw mode** -- switch the terminal to raw mode for escape sequence I/O, with guaranteed restoration
- **select()-based timed reads** -- non-blocking reads with millisecond-precision timeouts
- **Sentinel-bounded query pattern** -- send query + DA1 as a boundary marker, accumulate response bytes until the DA1 response is detected or timeout expires
- **Foreground process group check** -- prevent queries from background processes
- **Probe session lifecycle** -- RAII-style controlled type that encapsulates the full open/raw/query/restore/close sequence
- **DA1 response parsing** -- pure SPARK function extracting device attribute parameters
- **Multiplexer passthrough wrapping** -- wrap queries for tmux/screen passthrough

**Dependencies on existing features:**

- `Termicap.TTY` -- TTY detection (Tier 1); the probe session can verify TTY status before opening `/dev/tty`
- `Termicap.Terminal_Id` -- terminal identity detection (Tier 2); provides `Multiplexer_Kind` for passthrough wrapping

---

## 2. Framework Survey

### termenv (Go)

termenv implements the sentinel pattern in `termenv_unix.go`:

1. `termStatusReport()` checks foreground status via `ioctl(TIOCGPGRP)` + `getpgrp()` comparison
2. Saves termios via `IoctlGetTermios`, modifies to clear `ECHO` and `ICANON`, restores via `defer`
3. Sends OSC query (e.g., `\x1b]11;?\x1b\\`) followed by cursor position query (`CSI 6n`) as the sentinel
4. Reads response byte-by-byte with `select()` timeout, classifying responses as OSC or CSI based on the second byte (`]` vs `[`)
5. Uses CPR (Cursor Position Report) as the sentinel instead of DA1

**Key differences for Termicap:** termenv uses CPR (`CSI 6n` / response ending in `R`) as the sentinel. Termicap uses DA1 (`CSI c` / response matching `CSI ? ... c`), which is more universally supported and avoids side effects on cursor state. DA1 is the approach recommended by the global synthesis.

### termbg (Rust)

termbg uses crossterm's raw mode abstraction with `scopeguard::defer` for RAII cleanup. It sends the OSC 11 query with multiplexer-specific wrapping (tmux DCS passthrough, screen DCS passthrough). Response reading uses crossterm's event polling with timeout.

**Key differences for Termicap:** termbg delegates raw mode and event reading to crossterm. Termicap must implement these directly since there is no equivalent Ada framework. termbg's multiplexer passthrough wrapping strings are directly reusable as byte sequences.

### blessed (Node.js)

blessed uses DA1 as the sentinel boundary (same choice as Termicap). It batches multiple queries before a single DA1 sentinel, reducing round trips.

**Key differences for Termicap:** Termicap's initial implementation sends one query + one sentinel per call. Batching is a future optimization.

### Patterns borrowed

| Pattern | Source | Adaptation |
|---------|--------|------------|
| Sentinel-bounded query | termenv, blessed | DA1 instead of CPR as sentinel |
| Foreground process group check | termenv | Direct port: `ioctl(TIOCGPGRP)` + `getpgrp()` |
| Raw mode RAII via defer/scope guard | termenv, termbg | Ada `Limited_Controlled` with `Finalize` |
| Multiplexer passthrough wrapping | termbg, termenv | Pure function, same DCS byte sequences |
| select()-based timed read | termenv | Direct port via C helper for `fd_set` macros |
| Input drain before query | termbg | Non-blocking reads with iteration bound |

### Ada/SPARK constraints affecting design

- **No variadic C imports**: `select()` itself is not variadic, but `fd_set` manipulation uses macros (`FD_ZERO`, `FD_SET`, `FD_ISSET`). These require a C helper file, following the pattern established by ADR-0006 (ioctl wrapper).
- **No controlled types in SPARK**: `Limited_Controlled` requires `SPARK_Mode => Off` for the session package.
- **struct termios layout is platform-specific**: Rather than mapping the full struct layout in Ada (fragile across platforms), a C helper manages termios manipulation and exposes a fixed-signature API. See ADR-0014.

---

## 3. Package Design

### Package tree

```
Termicap                              (existing root namespace)
├── Termicap.OSC                      [SPARK_Mode => Off] — probe session, I/O operations
│   └── Termicap.OSC.Parsing          [SPARK_Mode => On]  — DA1 parsing, sentinel detection, passthrough wrapping
```

### SPARK boundary rationale

| Package | SPARK_Mode | Reason |
|---------|------------|--------|
| `Termicap.OSC` | Off | Uses `Ada.Finalization.Limited_Controlled`, C FFI for termios/select/ioctl/read/write/open/close |
| `Termicap.OSC.Parsing` | On | Pure functions: `Parse_DA1_Response`, `Contains_DA1_Response`, `Wrap_For_Passthrough`. No FFI, no state. |

### C source file

A new C source file `src/c/termicap_osc.c` provides helper functions for:

- `fd_set` manipulation (macros cannot be imported from Ada)
- `termios` save/restore/raw-mode (struct layout is platform-specific)
- `select()` wrapper with fixed-signature parameters
- Foreground process group check (`ioctl(TIOCGPGRP)` is variadic)

This follows the established pattern of `src/c/termicap_ioctl.c` (ADR-0006) and `src/c/termicap_sigwinch.c`. The `.gpr` file already includes `src/c/` in `Source_Dirs` and lists `"C"` in `Languages`.

### File layout

| File | Purpose |
|------|---------|
| `src/termicap-osc.ads` | Probe session type, I/O API, public types |
| `src/termicap-osc.adb` | Session lifecycle, C FFI bindings, sentinel query loop |
| `src/termicap-osc-parsing.ads` | Pure SPARK parsing API |
| `src/termicap-osc-parsing.adb` | DA1 parser, sentinel detector, passthrough wrapper |
| `src/c/termicap_osc.c` | C helpers for termios, select, foreground check |

---

## 4. Type Design

### File_Descriptor

```ada
type File_Descriptor is new Interfaces.C.int;
INVALID_FD : constant File_Descriptor := -1;
```

A distinct integer type for file descriptors. Declared in `Termicap.OSC`.

### Termios_State

```ada
type Termios_State is limited private;
```

An opaque type wrapping the C-side termios state. The actual data is stored on the C side as a static `struct termios`; the Ada type holds an identifier or is a thin wrapper around the C helper's state management. See section 6 for the C helper approach (ADR-0014).

Alternative: the Ada type is a fixed-size byte array large enough to hold `struct termios` on any supported platform (typically 60 bytes on Linux, 72 bytes on macOS). The C helper fills this array via `tcgetattr` and reads it back via `tcsetattr`.

Chosen approach: **opaque byte buffer** sized to `MAX_TERMIOS_SIZE` (128 bytes, conservative upper bound). This avoids C-side static state and supports future concurrent sessions on different FDs.

```ada
MAX_TERMIOS_SIZE : constant := 128;
type Termios_State is record
   Data : Byte_Array (1 .. MAX_TERMIOS_SIZE);
   Size : Natural;  --  actual size on this platform, set by C helper
end record;
```

### Session_Status

```ada
type Session_Status is
  (Session_OK,
   Session_Not_Foreground,
   Session_No_Terminal,
   Session_Save_Failed,
   Session_Raw_Failed,
   Session_Already_Active);
```

### Probe_Session

```ada
type Probe_Session is new Ada.Finalization.Limited_Controlled with private;
```

Private components:

```ada
type Probe_Session is new Ada.Finalization.Limited_Controlled with record
   FD           : File_Descriptor := INVALID_FD;
   Saved_State  : Termios_State;
   Is_Open      : Boolean := False;
end record;
```

`Finalize` restores termios and closes the FD. `Initialize` is a no-op (actual opening happens via `Open`).

### DA1_Params

Declared in `Termicap.OSC.Parsing` (SPARK_Mode => On):

```ada
MAX_DA1_PARAMS : constant := 16;

type DA1_Value_Array is array (Positive range 1 .. MAX_DA1_PARAMS) of Natural;

type DA1_Params is record
   Count  : Natural range 0 .. MAX_DA1_PARAMS := 0;
   Values : DA1_Value_Array := [others => 0];
end record;
```

### Byte_Array and Response_Buffer

```ada
subtype Byte is Interfaces.C.unsigned_char;
type Byte_Array is array (Positive range <>) of Byte;

MAX_RESPONSE_SIZE : constant := 4_096;
subtype Response_Buffer is Byte_Array (1 .. MAX_RESPONSE_SIZE);
```

### Multiplexer_Kind

Declared in `Termicap.OSC.Parsing` (SPARK_Mode => On):

```ada
type Multiplexer_Kind is (None, Tmux, Screen);
```

---

## 5. API Design

### Termicap.OSC (SPARK_Mode => Off)

#### Session lifecycle

```ada
procedure Open
  (Session : in out Probe_Session;
   Status  :    out Session_Status);
--  @relation(FUNC-OSC-008): Full open sequence
--  Steps: foreground check -> open /dev/tty -> save termios -> raw mode -> drain
--  On failure at any step, cleans up and sets Status accordingly.
--  Precondition: not Session.Is_Open (informal; not SPARK-provable)

function Is_Open (Session : Probe_Session) return Boolean;
--  @return True if Open completed successfully and Close has not been called.

procedure Close (Session : in out Probe_Session);
--  @relation(FUNC-OSC-008): Restore termios and close FD.
--  Safe to call when not open (no-op).
--  Called automatically by Finalize.
```

#### Query operations

```ada
procedure Sentinel_Query
  (Session    :     Probe_Session;
   Query      :     Byte_Array;
   Response   : out Response_Buffer;
   Resp_Length : out Natural;
   Timeout_Ms :     Natural;
   Timed_Out  : out Boolean;
   Retry      :     Boolean := False);
--  @relation(FUNC-OSC-006): Send query + DA1 sentinel, accumulate until DA1 detected.
--  @relation(FUNC-OSC-013): Optional retry with doubled timeout.
--  @param Query     The escape sequence to send (e.g., OSC 11 query bytes).
--  @param Response  Buffer receiving pre-sentinel response bytes.
--  @param Resp_Length Number of valid bytes in Response.
--  @param Timeout_Ms Read timeout in milliseconds.
--  @param Timed_Out  True if no DA1 response detected within timeout.
--  @param Retry      If True and first attempt times out, retry once with 2*Timeout_Ms.

procedure Write_Query
  (Session :     Probe_Session;
   Query   :     Byte_Array;
   Written : out Natural;
   Success : out Boolean);
--  @relation(FUNC-OSC-005): Write bytes to session's terminal FD.
```

#### Low-level I/O (internal, but documented for completeness)

```ada
procedure Timed_Read
  (FD         :     File_Descriptor;
   Buffer     : out Byte_Array;
   Bytes_Read : out Natural;
   Timeout_Ms :     Natural;
   Timed_Out  : out Boolean);
--  @relation(FUNC-OSC-004): select() + read() with timeout.

function Is_Foreground_Process (FD : File_Descriptor) return Boolean;
--  @relation(FUNC-OSC-007): ioctl(TIOCGPGRP) + getpgrp() comparison.

procedure Drain_Input (FD : File_Descriptor);
--  @relation(FUNC-OSC-011): Non-blocking drain with iteration bound.
```

#### File descriptor management (internal)

```ada
function Open_Terminal return File_Descriptor;
--  @relation(FUNC-OSC-001): open("/dev/tty", O_RDWR). Returns INVALID_FD on failure.

procedure Close_Terminal (FD : in out File_Descriptor);
--  @relation(FUNC-OSC-001): close(fd). Sets FD to INVALID_FD.

procedure Save_Termios
  (FD    :     File_Descriptor;
   State :    out Termios_State;
   OK    :    out Boolean);
--  @relation(FUNC-OSC-002): tcgetattr wrapper.

procedure Restore_Termios
  (FD    :     File_Descriptor;
   State :     Termios_State;
   OK    :    out Boolean);
--  @relation(FUNC-OSC-002): tcsetattr(TCSANOW) wrapper.

procedure Set_Raw_Mode
  (FD    :     File_Descriptor;
   State :     Termios_State;
   OK    :    out Boolean);
--  @relation(FUNC-OSC-003): Modify saved state for raw mode and apply.
```

### Termicap.OSC.Parsing (SPARK_Mode => On)

```ada
function Parse_DA1_Response
  (Bytes  : Byte_Array;
   Length : Natural) return DA1_Params
  with Pre  => Length <= Bytes'Length,
       Post => Parse_DA1_Response'Result.Count <= MAX_DA1_PARAMS;
--  @relation(FUNC-OSC-010): Pure DA1 response parser.
--  Returns Count = 0 if the sequence does not match CSI ? <digits/semicolons> c.

function Contains_DA1_Response
  (Bytes  : Byte_Array;
   Length : Natural) return Boolean
  with Pre => Length <= Bytes'Length;
--  @relation(FUNC-OSC-006): Sentinel detection predicate.
--  Returns True if the byte sequence contains a complete DA1 response
--  (ESC [ ? ... c pattern).

function DA1_Response_Start
  (Bytes  : Byte_Array;
   Length : Natural) return Natural
  with Pre  => Length <= Bytes'Length,
       Post => DA1_Response_Start'Result <= Length;
--  Returns the index where the DA1 response begins (ESC [ ?), or Length
--  if no DA1 response is found. Used by Sentinel_Query to extract the
--  pre-sentinel bytes.

function Wrap_For_Passthrough
  (Query       : Byte_Array;
   Multiplexer : Multiplexer_Kind) return Byte_Array;
--  @relation(FUNC-OSC-014): Pure passthrough wrapping.
--  When Multiplexer = None, returns Query unchanged.
--  When Tmux: ESC P tmux ; ESC <Query> ESC \
--  When Screen: ESC P <Query> ESC \
```

---

## 6. C FFI Layer

### C helper file: `src/c/termicap_osc.c`

Following the pattern established by `termicap_ioctl.c` and `termicap_sigwinch.c`, all C helpers have fixed (non-variadic) signatures and contain no decision logic beyond the syscall invocation.

#### Required C helper functions

| C Function | Purpose | Why a C helper is needed |
|-----------|---------|--------------------------|
| `termicap_osc_open_tty()` | `open("/dev/tty", O_RDWR)` | `open()` is variadic when `O_CREAT` is used; although `O_RDWR` alone does not require a third arg, a C wrapper provides a clean fixed signature |
| `termicap_osc_close_fd(int fd)` | `close(fd)` | Thin wrapper for consistency; could be imported directly, but grouped for uniformity |
| `termicap_osc_save_termios(int fd, void *buf, int buf_size, int *actual_size)` | `tcgetattr(fd, &termios)`, copy to caller buffer | struct termios layout is platform-specific; C helper copies raw bytes to Ada-side buffer |
| `termicap_osc_restore_termios(int fd, const void *buf, int size)` | `tcsetattr(fd, TCSANOW, &termios)` | Reverse of save: copy from Ada buffer to struct, call tcsetattr |
| `termicap_osc_set_raw(int fd, const void *saved_buf, int size)` | Modify termios for raw mode, apply via `tcsetattr` | Clears ICANON, ECHO, ISIG, IXON, ICRNL, BRKINT; sets VMIN=0, VTIME=0 |
| `termicap_osc_timed_read(int fd, void *buf, int buf_size, int timeout_ms, int *bytes_read, int *timed_out)` | `select()` + `read()` | `fd_set` manipulation requires `FD_ZERO`/`FD_SET`/`FD_ISSET` macros, which are not callable from Ada |
| `termicap_osc_write(int fd, const void *buf, int len, int *written)` | `write(fd, buf, len)` | Thin wrapper for type safety; returns 0 on success, -1 on error |
| `termicap_osc_is_foreground(int fd)` | `ioctl(fd, TIOCGPGRP, &pgrp)` + `getpgrp()` | `ioctl` is variadic (same reason as ADR-0006) |
| `termicap_osc_termios_size()` | Returns `sizeof(struct termios)` | Ada needs to know the actual size on this platform for the byte buffer |

#### Ada-side bindings (in `Termicap.OSC` body)

Each C function gets a `pragma Import (C, ...)` binding in the package body, following the exact pattern from `termicap-sigwinch.adb`:

```ada
function C_Open_TTY return Interfaces.C.int;
pragma Import (C, C_Open_TTY, "termicap_osc_open_tty");

function C_Close_FD (FD : Interfaces.C.int) return Interfaces.C.int;
pragma Import (C, C_Close_FD, "termicap_osc_close_fd");

function C_Save_Termios
  (FD          : Interfaces.C.int;
   Buf         : System.Address;
   Buf_Size    : Interfaces.C.int;
   Actual_Size : access Interfaces.C.int) return Interfaces.C.int;
pragma Import (C, C_Save_Termios, "termicap_osc_save_termios");
-- ... etc.
```

### Why C helpers instead of direct Ada struct mapping

See ADR-0014 for the full decision. In summary:

- `struct termios` has different sizes and field layouts across Linux (60 bytes), macOS (72 bytes), and FreeBSD (44 bytes)
- `fd_set` is manipulated via macros (`FD_ZERO`, `FD_SET`, `FD_ISSET`) that are not importable from Ada
- `ioctl` is variadic and requires a C wrapper (same rationale as ADR-0006)
- The C helper approach is already established in this project and proven to work

---

## 7. Sentinel Pattern Detail

### Algorithm: `Sentinel_Query`

**Step 1: Write query + sentinel**

```
Write to FD: <Query bytes>
Write to FD: ESC [ c            (DA1 request -- 3 bytes: 0x1B 0x5B 0x63)
```

**Step 2: Accumulate response**

```
Buffer := empty (Response_Buffer, Length := 0)
Start_Time := now

loop:
   Remaining_Ms := Timeout_Ms - elapsed_since(Start_Time)
   if Remaining_Ms <= 0 then
      -- Total timeout expired
      Timed_Out := True; Resp_Length := 0; return
   end if

   Timed_Read (FD, Chunk, Chunk_Len, Remaining_Ms, Chunk_Timed_Out)

   if Chunk_Timed_Out or Chunk_Len = 0 then
      Timed_Out := True; Resp_Length := 0; return
   end if

   Append Chunk(1..Chunk_Len) to Buffer
   Length := Length + Chunk_Len

   if Length >= MAX_RESPONSE_SIZE then
      -- Buffer overflow protection (FUNC-OSC-009)
      Timed_Out := True; Resp_Length := 0; return
   end if

   if Contains_DA1_Response (Buffer, Length) then
      -- DA1 detected: extract pre-sentinel bytes
      Boundary := DA1_Response_Start (Buffer, Length)
      Resp_Length := Boundary - 1
      Response (1 .. Resp_Length) := Buffer (1 .. Resp_Length)
      Timed_Out := False
      return
   end if
end loop
```

**Step 3: Optional retry (FUNC-OSC-013)**

If `Retry = True` and the first attempt sets `Timed_Out = True`, repeat steps 1-2 with `Timeout_Ms * 2`.

### Byte-level example: OSC 11 background color query

**Sent:**

```
Bytes sent to terminal:
  1B 5D 31 31 3B 3F 1B 5C     -- ESC ] 1 1 ; ? ESC \   (OSC 11 query)
  1B 5B 63                     -- ESC [ c               (DA1 sentinel)
```

**Expected response (xterm):**

```
Terminal responds with:
  1B 5D 31 31 3B 72 67 62 3A   -- ESC ] 1 1 ; r g b :
  30 30 30 30 2F 30 30 30 30   -- 0 0 0 0 / 0 0 0 0
  2F 30 30 30 30 1B 5C         -- / 0 0 0 0 ESC \       (OSC response)
  1B 5B 3F 36 34 3B 31 63     -- ESC [ ? 6 4 ; 1 c     (DA1 response)
```

**Detection:** The accumulator scans for the pattern `ESC [ ?` followed by digits/semicolons terminated by `c` (0x63). Once `0x63` is found after `ESC [ ?`, the DA1 boundary is identified at the position of the `ESC` byte that starts `ESC [ ?`. All bytes before that position are the query response.

### DA1 detection predicate

`Contains_DA1_Response` scans the buffer for the sequence:

1. `0x1B` (ESC)
2. `0x5B` (`[`)
3. `0x3F` (`?`)
4. One or more bytes in the set `{0x30..0x39, 0x3B}` (digits and semicolons)
5. `0x63` (`c`)

The scan is a simple linear pass. The function returns `True` as soon as step 5 is matched. `DA1_Response_Start` returns the index of the `ESC` byte from step 1.

---

## 8. Error Handling

### Error propagation strategy

All FFI operations return error indicators (integer return codes or Boolean `OK` parameters). No exceptions are raised from FFI calls. This follows the Termicap convention established in `Termicap.TTY` and `Termicap.Dimensions`.

### Session error reporting

`Open` reports errors via the `Session_Status` out parameter. Each failure case performs cleanup of any resources allocated before the failure:

| Failure | Status | Cleanup |
|---------|--------|---------|
| Not foreground | `Session_Not_Foreground` | None (nothing opened yet) |
| `/dev/tty` open fails | `Session_No_Terminal` | None |
| `tcgetattr` fails | `Session_Save_Failed` | Close FD |
| Raw mode fails | `Session_Raw_Failed` | Restore termios, close FD |
| Already active | `Session_Already_Active` | None |

### Finalize guarantees

`Finalize` (called automatically on scope exit or exception propagation):

1. If `Is_Open`, calls `Restore_Termios` (ignores failure -- best effort)
2. If `FD /= INVALID_FD`, calls `Close_Terminal`
3. Releases the active-session guard

`Finalize` never raises an exception. If `Restore_Termios` or `Close_Terminal` fails, the failure is silently ignored. This matches the Ada convention for `Finalize` (the runtime already handles exception propagation from `Finalize` specially).

### Single-session enforcement (FUNC-OSC-012)

A protected variable `Active_Session_Guard` in the `Termicap.OSC` body tracks whether a session is currently open. `Open` checks this guard atomically; `Close` (and `Finalize`) releases it. This prevents interleaved byte sequences from concurrent sessions.

```ada
protected Active_Session_Guard is
   procedure Acquire (Acquired : out Boolean);
   procedure Release;
   function Is_Active return Boolean;
private
   Active : Boolean := False;
end Active_Session_Guard;
```

---

## 9. SPARK Annotations

### SPARK_Mode assignments

| Package | Spec | Body | Rationale |
|---------|------|------|-----------|
| `Termicap.OSC` | Off | Off | Uses `Ada.Finalization.Limited_Controlled`, protected object, C FFI |
| `Termicap.OSC.Parsing` | On | On | Pure functions, no FFI, no controlled types |

### Provable contracts in `Termicap.OSC.Parsing`

| Subprogram | Contract | Proof level |
|-----------|----------|-------------|
| `Parse_DA1_Response` | `Post => Result.Count <= MAX_DA1_PARAMS` | Silver (loop bound analysis) |
| `Contains_DA1_Response` | `Pre => Length <= Bytes'Length` | Silver (simple range check) |
| `DA1_Response_Start` | `Post => Result <= Length` | Silver (bounded by scan range) |
| `Wrap_For_Passthrough` | `Post => (if Multiplexer = None then Result'Length = Query'Length)` | Silver |

### Target proof level

- `Termicap.OSC.Parsing`: **SPARK Silver** -- all postconditions provable by GNATprove without manual lemmas
- `Termicap.OSC`: **SPARK_Mode => Off** -- not provable due to controlled types and FFI

---

## 10. ADRs

Two ADRs are filed alongside this tech spec:

1. **ADR-0014**: C helper approach for termios/select/fd_set instead of direct Ada struct mapping
   - Location: `docs/adr/0014-c-helper-for-termios-select.md`
   - Decides to use C helpers for `struct termios` manipulation and `select()` with `fd_set`, rather than mapping the C structures directly in Ada

2. **ADR-0015**: Probe session using `Limited_Controlled` for RAII instead of explicit open/close
   - Location: `docs/adr/0015-probe-session-limited-controlled.md`
   - Decides to use `Ada.Finalization.Limited_Controlled` for the probe session type, accepting `SPARK_Mode => Off` as the cost of guaranteed cleanup
