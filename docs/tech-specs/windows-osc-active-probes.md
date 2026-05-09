# Technical Specification: Windows OSC Active Probes (and Adjacent Fixes)

**Feature:** Windows console implementation of the OSC probe session, plus the
ConPTY-aware active-probe gate refinement and the Unicode `OS` env-var fix.
**Requirements:** `docs/requirements/osc-query-infra.sdoc`
(FUNC-OSC-008 amended, FUNC-OSC-016, FUNC-OSC-017, FUNC-OSC-018, FUNC-OSC-019);
`docs/requirements/unicode-support.sdoc` (FUNC-UNI-005 revised);
`docs/requirements/windows-console.sdoc` (FUNC-WIN-014 new).
**Date:** 2026-05-08

---

## A. Overview

Termicap currently ships a Windows OSC body
(`src/windows/termicap-osc.adb`) that is a deliberate stub: every operation
returns failure, and `Probe_Session.Open` always reports
`Session_No_Terminal`. The cross-language conformance harness on
`win32`-flavoured terminals (PowerShell, Windows Terminal, Warp, cmd) shows the
consequence: termicap reports `unicode=none`, `hyperlinks=unknown`,
`sixel=false`, and missing `da1_attributes`/`xtversion` even on terminals where
the `blessed`, `rich`, and `prompt_toolkit` shims demonstrate that the replies
are actually emitted by the host. This tech-spec replaces the stub with a
working ConPTY-aware implementation, fixes a one-line typo in the Unicode
detector that prevents the Windows heuristic branch from ever being taken, and
refines the Win32 console gate in `termicap-graphics-io.adb` so that ConPTY
sessions are no longer mistaken for legacy `conhost` and skipped.

The design preserves the shared `Termicap.OSC` package surface verbatim. All
Windows-specific machinery lives in the body
(`src/windows/termicap-osc.adb`), with the Win32 mode-bit constants and the
gate-classifier helper extracted into `Termicap.Win32_VT` so that other
Windows bodies (graphics, clipboard, keyboard, mouse) can reuse them. The
foreground-process check on Windows degrades to a "do we have a usable console
handle pair" probe, since Windows has no `tcgetpgrp` analogue.

The result is symmetric with POSIX: a `Probe_Session` is a
`Limited_Controlled` RAII object whose `Open` acquires console handles, snaps
the input/output console-mode DWORDs, switches them into VT raw mode, drains
stale input, and whose `Finalize` unconditionally restores the saved DWORDs
and closes any handles the body owns. The same `Sentinel_Query` /
`Timeout_Query` / `Write_Query` / `Timed_Read` / `Drain_Input` semantics
apply, just over `WaitForSingleObject + ReadFile + WriteFile` instead of
`select + read + write`.

### Requirement coverage

| Requirement | Where addressed | Section |
|-------------|-----------------|---------|
| FUNC-OSC-008 (amended) | Windows lifecycle in `Open`/`Finalize` | D.1, D.6 |
| FUNC-OSC-016 | Console handle acquisition (GetStdHandle + CONIN$/CONOUT$) | D.2 |
| FUNC-OSC-017 | Console mode save/raw/restore | D.3 |
| FUNC-OSC-018 | `WaitForSingleObject` + `ReadFile` timed read | D.4 |
| FUNC-OSC-019 | Foreground check on Windows | D.5 |
| FUNC-WIN-014 | ConPTY-aware active-probe gate helper | E |
| FUNC-UNI-005 | `OS_TYPE` -> `OS` env-var fix | F |

---

## B. Framework Survey

### crossterm (Rust) -- pure raw-mode toggle, no VT input bit

`reference-frameworks/crossterm/src/terminal/sys/windows.rs:18-53` defines:

```rust
const NOT_RAW_MODE_MASK: DWORD =
    ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT;

pub(crate) fn enable_raw_mode() -> std::io::Result<()> {
    let console_mode = ConsoleMode::from(Handle::current_in_handle()?);
    let dw_mode = console_mode.mode()?;
    let new_mode = dw_mode & !NOT_RAW_MODE_MASK;
    console_mode.set_mode(new_mode)?;
    Ok(())
}
```

crossterm clears the three line-discipline bits and **does not** set
`ENABLE_VIRTUAL_TERMINAL_INPUT`. That is consistent with its read path:
`event/sys/windows/poll.rs` waits via `WaitForMultipleObjects` and the parser
in `event/sys/windows/parse.rs` reads `INPUT_RECORD` structures with
`ReadConsoleInputW`. INPUT_RECORDs deliver synthesised key events with
modifier metadata, so crossterm gets escape information from the host's key
translation rather than from a byte stream.

Termicap diverges. We are not building an event loop; we are sending an
escape-sequence query and reading the terminal's escape-sequence reply. Going
through INPUT_RECORDs would force us to re-synthesise the bytes from
`KeyEventRecord.uChar.UnicodeChar` plus the `dwControlKeyState`, which is
exactly the lossy round-trip that `ENABLE_VIRTUAL_TERMINAL_INPUT` was added to
avoid in Windows 10 1809+. With VT input enabled, the host delivers the same
byte sequence the program would see on a Unix terminal, so a `ReadFile`
returns the response bytes directly. ADR-0039 captures the trade-off.

crossterm's mask is also incomplete for our case: we additionally OR
`ENABLE_VIRTUAL_TERMINAL_INPUT` into the input mode and OR
`ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN` into the
output mode. Setting the output bits at probe time is not strictly required
for the response cycle (the terminal's reply does not pass through our output
mode) but it ensures the query bytes we `WriteFile` are not transformed by the
host (e.g., a stray CR injection).

### blessed (Python) -- POSIX shim that degrades on Windows

`reference-frameworks/blessed/blessed/terminal.py` exposes `_query_response()`
and `get_device_attributes()` which call `tty.setcbreak` /
`termios.tcgetattr` / `termios.tcsetattr`. On Windows these imports succeed in
recent Python releases (the `tty` and `termios` modules raise `ImportError`
under cpython on Windows; some shim libraries provide stubs). The blessed
shim used by our conformance harness falls back to non-raw, blocking reads
with a generous timeout, which still works on Windows Terminal because
`ENABLE_LINE_INPUT` defaults to off in PowerShell since Windows Terminal
1.x. The behaviour is correct but fragile and the timeouts are longer than
they need to be.

Lesson: do not try to share POSIX termios shims with Windows. Implement raw
mode via the native `SetConsoleMode` and use `WaitForSingleObject` for
millisecond-precision timeouts. blessed proves the responses exist on
Windows; it does not prove that POSIX-shaped code is a viable port target.

### termenv (Go) -- no Windows active probe

`reference-frameworks/termenv/termenv_windows.go` does not perform OSC
active probing. Its color/background detection on Windows reads
`COLORTERM`, `WT_SESSION`, the registry `HKCU\Console` palette, and the
build number; it never sends an OSC 11 query. termenv documents this
explicitly: "Windows has its own colour APIs". This is a deliberate design
choice, not an oversight: termenv gives up some accuracy on terminals that
honour OSC queries (Windows Terminal, Warp, mintty) in exchange for
implementation simplicity.

Termicap diverges: we keep the OSC active-probe path because the conformance
harness shows it produces strictly better results on the modern Windows
terminal landscape (Windows Terminal answers DA1, XTVERSION, OSC 11, OSC 8;
Warp answers OSC 11, OSC 8, OSC 52). The cost is the implementation in this
spec; the benefit is symmetric capability detection across platforms.

### win32ada -- what we have and what we must add

Verified by reading `reference-frameworks/win32ada/src/win32-winbase.ads` and
`win32-wincon.ads`:

| Symbol | Status |
|--------|--------|
| `Win32.Winbase.GetStdHandle` | Provided (line 1862) |
| `Win32.Winbase.WaitForSingleObject` | Provided (line 1769) |
| `Win32.Winbase.ReadFile` | Provided (line 1879) |
| `Win32.Winbase.WriteFile` | Provided (line 1871) |
| `Win32.Winbase.CloseHandle` | Provided (line 1925) |
| `Win32.Winbase.CreateFileW` | Provided (line 3667) |
| `Win32.Winbase.STD_INPUT_HANDLE`, `STD_OUTPUT_HANDLE` | Provided |
| `Win32.Winbase.WAIT_OBJECT_0` (= 0) | Provided (line 36 rename) |
| `Win32.Winbase.WAIT_TIMEOUT` (= 0x102) | Provided (line 42 rename) |
| `Win32.Winbase.WAIT_FAILED` (= 0xFFFFFFFF) | Provided (line 35) |
| `Win32.Winbase.INVALID_HANDLE_VALUE` | Provided |
| `Win32.Winbase.OPEN_EXISTING` | Provided |
| `Win32.Wincon.GetConsoleMode` | Provided |
| `Win32.Wincon.SetConsoleMode` | Provided |
| `Win32.Wincon.ENABLE_PROCESSED_INPUT` (=1) | Provided (line 59) |
| `Win32.Wincon.ENABLE_LINE_INPUT` (=2) | Provided (line 60) |
| `Win32.Wincon.ENABLE_ECHO_INPUT` (=4) | Provided (line 61) |
| `Win32.Wincon.ENABLE_PROCESSED_OUTPUT` (=1) | Provided (line 64) |
| `ENABLE_VIRTUAL_TERMINAL_PROCESSING` (=4) | Already in `Termicap.Win32_VT` |
| **`ENABLE_VIRTUAL_TERMINAL_INPUT` (=0x200)** | **Missing — declare in `Termicap.Win32_VT`** |
| **`DISABLE_NEWLINE_AUTO_RETURN` (=0x8)** | **Missing — declare in `Termicap.Win32_VT`** |
| `Win32.Winnt.GENERIC_READ`, `GENERIC_WRITE` | Provided |
| `Win32.Winnt.FILE_SHARE_READ`, `FILE_SHARE_WRITE` | Provided |

Conclusion: every primitive we need is reachable through win32ada and
`Termicap.Win32_VT`. Two new constants must be added to `Win32_VT`. No new
binding crate or hand-written FFI is required. ADR-0019 already establishes
win32ada as the FFI layer; we are inside that envelope.

### Patterns adopted

| Pattern | Source | Adaptation |
|---------|--------|------------|
| Two-DWORD save/raw/restore | crossterm + Microsoft VT docs | Save both input and output modes; clear the three NOT_RAW bits on input, OR `ENABLE_VIRTUAL_TERMINAL_INPUT`; OR VT_PROCESSING + DISABLE_NEWLINE_AUTO_RETURN onto output |
| Stage-1 `GetStdHandle` -> stage-2 `CreateFileW("CONIN$"/"CONOUT$")` | termenv / blessed / FUNC-WIN-004 | Reuse the existing `Termicap.Win32_VT.Open_Console_Input/Output` helpers; track per-handle origin (Borrowed/Owned) so `Finalize` doesn't `CloseHandle` on a borrowed STD handle |
| `WaitForSingleObject(h, ms)` + `ReadFile` | Win32 standard timed-wait + crossterm event poll inverted | Single waitable -> `WaitForSingleObject`; single `ReadFile` after `WAIT_OBJECT_0`; partial reads handled by the caller's accumulation loop |
| ConPTY classifier (`is the console host translating VT?`) | Microsoft ConPTY docs + observed conformance behaviour | Classify into `Legacy_Conhost` / `ConPTY_VT_Enabled` / `Not_A_Console` and let call sites decide whether to skip active probes |

---

## C. API Surface

### Shared `Termicap.OSC` spec — unchanged

The package spec at `src/termicap-osc.ads` carries every operation that the
Windows body must realise:

| Public op | POSIX body | Windows body |
|-----------|------------|--------------|
| `Open` | foreground -> `/dev/tty` -> tcgetattr -> raw -> drain | foreground (FUNC-OSC-019) -> handle acquisition (FUNC-OSC-016) -> mode save (FUNC-OSC-017) -> raw (FUNC-OSC-017) -> drain (FUNC-OSC-018) |
| `Is_Open` | `FD /= INVALID_FD and Is_Raw` | same fields, same predicate |
| `Close` | restore termios; close FD; release guard | restore mode; CloseHandle owned handles; release guard |
| `Finalize` | `Close` | `Close` |
| `Sentinel_Query` | unchanged loop | unchanged loop (pure caller of `Write_Query` + `Timed_Read`) |
| `Timeout_Query` | unchanged loop | unchanged loop |
| `Write_Query` | `write()` C helper | `WriteFile` on output handle |
| `Timed_Read` | `select()+read()` C helper | `WaitForSingleObject + ReadFile` on input handle |
| `Is_Foreground_Process` | `ioctl(TIOCGPGRP) + getpgrp()` | acquire-and-discard handle pair; True iff at least one acquired |
| `Open_Terminal` | `open("/dev/tty", O_RDWR)` | acquire input handle pair; return a synthetic FD that indexes a body-private state slot |
| `Close_Terminal` | `close(fd)` | close the body-private state's owned handles |
| `Save_Termios` | `tcgetattr` into `Termios_State.Data` | `GetConsoleMode` x 2 into `Termios_State.Data` |
| `Restore_Termios` | `tcsetattr(TCSANOW)` | `SetConsoleMode` x 2 |
| `Set_Raw_Mode` | clear ICANON/ECHO/ISIG/IXON/ICRNL/BRKINT, VMIN=0/VTIME=0 | clear ENABLE_LINE/ECHO/PROCESSED_INPUT, OR ENABLE_VIRTUAL_TERMINAL_INPUT; OR ENABLE_VIRTUAL_TERMINAL_PROCESSING|DISABLE_NEWLINE_AUTO_RETURN onto output |
| `Drain_Input` | `Timed_Read(timeout=0)` x 16 max | same algorithm, native primitive |

**No additions to the spec are needed.** The `Termios_State.Data : Byte_Array
(1 .. MAX_TERMIOS_SIZE)` field with `MAX_TERMIOS_SIZE = 128` is more than
enough to hold the Windows console-mode payload. The Windows layout is:

```
Offset 0  : 4 bytes  Input_Mode  (Win32.DWORD, native byte order)
Offset 4  : 4 bytes  Output_Mode (Win32.DWORD, native byte order)
Offset 8  : 1 byte   Input_Saved (0 or 1)
Offset 9  : 1 byte   Output_Saved (0 or 1)
Total     : 10 bytes
```

`Termios_State.Size` is set to 10 on Windows save success. The byte layout is
opaque to the shared spec; only the Windows body interprets it. ADR-0040
records the decision to overlay rather than introduce a Windows-specific
record.

### Where the per-handle state lives

The `Probe_Session` shared record has three fields: `FD`, `Saved_State`,
`Is_Raw`. It is shared between platforms via the OSC spec. To carry two
HANDLEs and two `Console_Handle_Origin` values without breaking POSIX, the
Windows body keeps a body-private static array keyed by a synthetic
`File_Descriptor` value (an integer index, not an OS FD). The
`Probe_Session.FD` field stores the index; everything else lives in the body.
This is detailed in section D and rationalised in ADR-0040.

The alternative — extending `Probe_Session` with platform-conditional fields
gated on `Alire_Host_OS` — was rejected because it would require either
preprocessing or a discriminant, and would force every consumer of
`Termicap.OSC` to handle the extra fields even on POSIX.

---

## D. Implementation Strategy

### D.1 Body file structure

```
src/windows/termicap-osc.adb
├── Constants               -- DA1_SENTINEL, MAX_DRAIN_ITERATIONS, MAX_SLOTS
├── Slot table              -- private static array indexed by File_Descriptor
├── Active_Session_Guard    -- protected; same shape as POSIX
├── Internal helpers        -- Acquire_Handles, Slot operations
├── Open_Terminal           -- allocate slot, acquire handles
├── Close_Terminal          -- release slot, close owned handles
├── Save_Termios            -- pack two DWORDs into Termios_State.Data
├── Restore_Termios         -- unpack and SetConsoleMode x2
├── Set_Raw_Mode            -- read input/output modes from Data, mutate, apply
├── Timed_Read              -- WaitForSingleObject + ReadFile on input handle
├── Write_Query             -- WriteFile on output handle (or input if no output)
├── Drain_Input             -- 16 x Timed_Read(0)
├── Is_Foreground_Process   -- True iff at least one handle acquired
├── Sentinel_Query          -- copy of POSIX algorithm, parameterised on FD
├── Timeout_Query           -- copy of POSIX algorithm
├── Open / Is_Open / Close  -- session lifecycle
└── Finalize                -- override; calls Close
```

Both `Sentinel_Query` and `Timeout_Query` are byte-for-byte ports of the
POSIX bodies (sections "Query Operations" of `posix/termicap-osc.adb`). They
do not touch any OS primitive directly; they call `Write_Query` and
`Timed_Read`. Keeping them duplicated rather than hoisting them to the spec
is consistent with the existing repo organisation (the POSIX body has them
inline). A future refactor can move them up after both platforms are stable.

### D.2 FUNC-OSC-016 — Console handle acquisition

`Termicap.Win32_VT` already exposes `Open_Console_Input`,
`Open_Console_Output`, `Is_Valid_Handle`, and `Close_Handle`. The Windows
OSC body uses these for the stage-2 fallback and adds a stage-1 wrapper for
`GetStdHandle + GetConsoleMode`.

```text
Acquire_Handles (out Slot):

   --  Stage 1: standard handles
   In_Std  := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_INPUT_HANDLE)
   Out_Std := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE)

   --  Stage 1 validation: GetConsoleMode() succeeds iff handle is a console
   if Is_Valid_Handle (In_Std) and then GetConsoleMode (In_Std, Mode) /= FALSE then
      Slot.In_Handle := In_Std
      Slot.In_Origin := Borrowed_From_Std
   end if

   if Is_Valid_Handle (Out_Std) and then GetConsoleMode (Out_Std, Mode) /= FALSE then
      Slot.Out_Handle := Out_Std
      Slot.Out_Origin := Borrowed_From_Std
   end if

   --  Stage 2: CONIN$/CONOUT$ fallback for redirected handles
   if Slot.In_Origin = Not_Acquired then
      H := Open_Console_Input
      if Is_Valid_Handle (H) then
         Slot.In_Handle := H
         Slot.In_Origin := Owned_From_CreateFile
      end if
   end if

   if Slot.Out_Origin = Not_Acquired then
      H := Open_Console_Output
      if Is_Valid_Handle (H) then
         Slot.Out_Handle := H
         Slot.Out_Origin := Owned_From_CreateFile
      end if
   end if
```

`Open_Terminal` allocates the next free slot, calls `Acquire_Handles`, and
returns the slot index as a `File_Descriptor`. If both
`Slot.In_Origin = Not_Acquired` **and** `Slot.Out_Origin = Not_Acquired`, the
slot is freed immediately and `INVALID_FD` is returned (the caller in `Open`
maps that to `Session_No_Terminal`, matching POSIX `/dev/tty` failure).

`Close_Terminal` reads the slot, calls `Win32.Winbase.CloseHandle` on each
handle whose `Origin = Owned_From_CreateFile`, leaves
`Borrowed_From_Std` handles alone (Microsoft documents that calling
`CloseHandle` on a `GetStdHandle` result invalidates it for the rest of the
process), and frees the slot.

#### Handle origin enum (body-private)

```ada
type Console_Handle_Origin is
  (Not_Acquired,
   Borrowed_From_Std,
   Owned_From_CreateFile);
```

#### Slot table (body-private)

```ada
type Console_Slot is record
   In_Use     : Boolean := False;
   In_Handle  : Win32.Winnt.HANDLE := Win32.Winbase.INVALID_HANDLE_VALUE;
   In_Origin  : Console_Handle_Origin := Not_Acquired;
   Out_Handle : Win32.Winnt.HANDLE := Win32.Winbase.INVALID_HANDLE_VALUE;
   Out_Origin : Console_Handle_Origin := Not_Acquired;
end record;

MAX_SLOTS : constant := 4;          --  FUNC-OSC-012 caps active sessions to 1
type Slot_Array is array (1 .. MAX_SLOTS) of Console_Slot;
Slots : Slot_Array;                 --  body-private; access serialised by
                                    --  Active_Session_Guard
```

`MAX_SLOTS = 4` is a defensive over-allocation: only one session is ever
active (FUNC-OSC-012), but a few slots tolerate races during tests where
finalisation is delayed by GNAT's runtime.

The `File_Descriptor` returned by `Open_Terminal` is the slot index
(1..MAX_SLOTS). `INVALID_FD = -1` from the spec works unchanged because the
`Probe_Session.FD` field is a `File_Descriptor` (a distinct integer type).
No FD value collides with a real POSIX FD because this code only runs on
Windows.

#### Error handling

| GetStdHandle returns | GetConsoleMode result | Outcome |
|----------------------|----------------------|---------|
| `INVALID_HANDLE_VALUE` or null | n/a (skipped by `Is_Valid_Handle`) | go to stage 2 |
| valid handle | `FALSE` (errno = `ERROR_INVALID_HANDLE` or pipe) | discard, go to stage 2 |
| valid handle | `TRUE` | accept as borrowed |

| CreateFileW result | Outcome |
|--------------------|---------|
| `INVALID_HANDLE_VALUE` | side considered unacquired |
| any other handle | accept as owned |

If both sides are unacquired, return `INVALID_FD`; `Open` translates that to
`Session_No_Terminal`.

### D.3 FUNC-OSC-017 — Save / raw / restore

`Save_Termios` writes the two DWORDs and two flags into the `Data` byte
array using little-endian packing (Win32 is always LE on supported hardware,
and Ada's `Stream` would add tags; raw byte packing keeps the layout
SPARK-friendly even if the package itself is `SPARK_Mode => Off`):

```text
Save_Termios (FD, State, OK):
   Slot := Slots (Natural (FD))
   In_OK  := False
   Out_OK := False

   if Slot.In_Origin /= Not_Acquired then
      if GetConsoleMode (Slot.In_Handle, Tmp) /= FALSE then
         Pack_DWORD (State.Data, offset => 1, value => Tmp)
         In_OK := True
      end if
   end if

   if Slot.Out_Origin /= Not_Acquired then
      if GetConsoleMode (Slot.Out_Handle, Tmp) /= FALSE then
         Pack_DWORD (State.Data, offset => 5, value => Tmp)
         Out_OK := True
      end if
   end if

   State.Data (9)  := (if In_OK  then 1 else 0)
   State.Data (10) := (if Out_OK then 1 else 0)
   State.Size := 10
   OK := In_OK or Out_OK   --  FUNC-OSC-017 step 3: partial save permitted
                           --  but at least one side must succeed.
```

`Set_Raw_Mode` reads `State.Data` rather than calling `GetConsoleMode` again,
so it operates on the same snapshot that `Restore_Termios` will roll back to:

```text
Set_Raw_Mode (FD, State, OK):
   In_Mode  := Unpack_DWORD (State.Data, offset => 1)
   Out_Mode := Unpack_DWORD (State.Data, offset => 5)
   In_Saved  := State.Data (9)  /= 0
   Out_Saved := State.Data (10) /= 0

   New_In  := (In_Mode and not (ENABLE_LINE_INPUT
                              or ENABLE_ECHO_INPUT
                              or ENABLE_PROCESSED_INPUT))
              or ENABLE_VIRTUAL_TERMINAL_INPUT

   New_Out := Out_Mode
              or ENABLE_VIRTUAL_TERMINAL_PROCESSING
              or DISABLE_NEWLINE_AUTO_RETURN

   In_OK  := True
   Out_OK := True
   if In_Saved then
      In_OK := SetConsoleMode (Slot.In_Handle, New_In) /= FALSE
   end if
   if Out_Saved then
      Out_OK := SetConsoleMode (Slot.Out_Handle, New_Out) /= FALSE
   end if

   OK := (not In_Saved or In_OK) and (not Out_Saved or Out_OK)
```

`Restore_Termios` mirrors the save, reading the saved DWORDs back and
calling `SetConsoleMode`. Failures are ignored (the Finalize path must not
raise):

```text
Restore_Termios (FD, State, OK):
   In_Mode   := Unpack_DWORD (State.Data, offset => 1)
   Out_Mode  := Unpack_DWORD (State.Data, offset => 5)
   In_Saved  := State.Data (9)  /= 0
   Out_Saved := State.Data (10) /= 0

   In_OK  := True
   Out_OK := True
   if In_Saved then
      In_OK := SetConsoleMode (Slot.In_Handle, In_Mode) /= FALSE
   end if
   if Out_Saved then
      Out_OK := SetConsoleMode (Slot.Out_Handle, Out_Mode) /= FALSE
   end if

   OK := In_OK and Out_OK
```

### D.4 FUNC-OSC-018 — Timed read

```text
Timed_Read (FD, Buffer, Bytes_Read, Timeout_Ms, Timed_Out):
   Buffer     := zero
   Bytes_Read := 0
   Timed_Out  := False

   if Buffer'Length = 0 then return end if
   Slot := Slots (Natural (FD))
   if Slot.In_Origin = Not_Acquired then return end if

   Wait := WaitForSingleObject (Slot.In_Handle, DWORD (Timeout_Ms))

   if Wait = WAIT_TIMEOUT then
      Timed_Out := True; return
   end if
   if Wait /= WAIT_OBJECT_0 then
      --  WAIT_FAILED, WAIT_ABANDONED, WAIT_IO_COMPLETION:
      --  surface as I/O error: Bytes_Read=0, Timed_Out=False
      return
   end if

   Got : aliased Win32.DWORD := 0
   OK  := ReadFile (Slot.In_Handle,
                    Buffer (Buffer'First)'Address,
                    DWORD (Buffer'Length),
                    Got'Access,
                    null) /= FALSE
   if not OK then return end if         --  I/O error, surface as 0/0

   Bytes_Read := Natural (Got)          --  partial reads OK; caller re-reads
```

The signature in the spec passes `FD : File_Descriptor`, not a HANDLE. The
Windows body looks up the slot. The spec is unchanged.

`MAX_SLOTS = 4` plus the active-session guard means the slot lookup is
constant-time and never fails for a `Probe_Session` returned by `Open`.

`Drain_Input` calls `Timed_Read` with `Timeout_Ms => 0` up to
`MAX_DRAIN_ITERATIONS = 16` (FUNC-OSC-011 — value already set on POSIX, used
unchanged on Windows since the iteration bound is platform-agnostic). When
`WaitForSingleObject` is called with `dwMilliseconds = 0`, it returns
immediately with `WAIT_TIMEOUT` if the handle is not signalled, giving the
same non-blocking-poll semantics as `select` with a zero timeval.

### D.5 FUNC-OSC-019 — Foreground check

```ada
function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
begin
   if FD = INVALID_FD then
      return False;
   end if;
   --  After Open_Terminal succeeds, the slot is allocated and at least one
   --  handle was acquired (otherwise INVALID_FD would have been returned).
   --  By FUNC-OSC-019 that suffices: Windows has no foreground concept.
   return Slots (Natural (FD)).In_Use
      and then (Slots (Natural (FD)).In_Origin /= Not_Acquired
                or else Slots (Natural (FD)).Out_Origin /= Not_Acquired);
end Is_Foreground_Process;
```

`Open` calls `Is_Foreground_Process` only **after** `Open_Terminal`. On
POSIX the order is the opposite (foreground check uses a freshly-opened
`/dev/tty`), but the spec is permissive: it just requires the check to be
performed. On Windows the check is meaningful only in the post-acquisition
sense ("did we get a console"). The shared `Probe_Session.Open` body is
platform-specific (one body per platform), so the order can differ between
platforms without changing the spec.

### D.6 Session lifecycle (FUNC-OSC-008 amended)

The Windows `Open` orders the steps as follows, matching the requirement
text for the Windows mapping:

```text
Open (Session, Status):
   --  Step 1: acquire handles (FUNC-OSC-016).  If neither side, no terminal.
   Session.FD := Open_Terminal
   if Session.FD = INVALID_FD then
      Status := Session_No_Terminal; return
   end if

   --  Step 2: foreground check (FUNC-OSC-019).  Windows reduces to
   --  "do we have a usable console", which Open_Terminal already verified.
   --  Kept as an explicit step for symmetry with POSIX and for future
   --  changes (e.g., Job-object based gating).
   if not Is_Foreground_Process (Session.FD) then
      Close_Terminal (Session.FD)
      Status := Session_Not_Foreground; return
   end if

   --  Step 3: single-session guard (FUNC-OSC-012)
   Active_Session_Guard.Acquire (Acquired)
   if not Acquired then
      Close_Terminal (Session.FD)
      Status := Session_Already_Active; return
   end if

   --  Step 4: save console mode (FUNC-OSC-017 save sequence)
   Save_Termios (Session.FD, Session.Saved_State, OK)
   if not OK then
      Close_Terminal (Session.FD); Active_Session_Guard.Release
      Status := Session_Save_Failed; return
   end if

   --  Step 5: raw mode (FUNC-OSC-017 raw sequence)
   Set_Raw_Mode (Session.FD, Session.Saved_State, OK)
   if not OK then
      Restore_Termios (Session.FD, Session.Saved_State, _)
      Close_Terminal (Session.FD); Active_Session_Guard.Release
      Status := Session_Raw_Failed; return
   end if
   Session.Is_Raw := True

   --  Step 6: drain (FUNC-OSC-011 implemented per FUNC-OSC-018)
   Drain_Input (Session.FD)

   Status := Session_OK
```

`Close` and `Finalize` are byte-for-byte the same shape as POSIX: restore
mode, close handles, release guard. `Finalize` overrides
`Limited_Controlled.Finalize` and calls `Close`; failures are silently
swallowed.

### D.7 The C-helper question

POSIX has a C helper because `select`/`tcgetattr`/`tcsetattr`/`ioctl` deal
with platform-variant struct layouts and macros that have no Ada equivalent.

Win32 is different. Every primitive we need has a fixed, stdcall, non-variadic
signature with simple types (`HANDLE`, `DWORD`, `BOOL`, `LPVOID`,
`LPDWORD`, `LPCSTR`, `LPCWSTR`). win32ada already provides the bindings.
There is no struct unmarshalling and no macro to expand. ADR-0019 (win32ada
as the FFI layer) covers exactly this case.

**Decision: no C helper for the Windows OSC body.** Everything is direct
Ada calls into win32ada plus the two new constants. This is consistent with
all other Windows bodies in `src/windows/`.

A separate C file would also break the build: `src/c/termicap_osc.c`
unconditionally includes `<termios.h>` and `<sys/select.h>`, neither of
which exists on MSYS2/MSVC. Splitting the file into `_posix.c` and
`_windows.c` was considered and rejected because the Windows side has no
content beyond what the Ada body already does.

### D.8 What POSIX behaviour must not regress

| Concern | Verification |
|---------|--------------|
| Shared spec unchanged | `git diff src/termicap-osc.ads` empty |
| POSIX body unchanged | `git diff src/posix/termicap-osc.adb` empty |
| C helper unchanged | `git diff src/c/termicap_osc.c` empty |
| `Termios_State.Data` size 128 bytes is enough on POSIX | already true (struct termios <= 80 bytes everywhere we support); 10 bytes used on Windows |
| `Active_Session_Guard` semantics platform-agnostic | both bodies declare the same protected object |
| `Limited_Controlled` semantics platform-agnostic | yes; only the Finalize body differs |

The only file in `src/` that this work edits and that POSIX consumes is
`src/termicap-unicode.adb` (the `OS_TYPE` -> `OS` fix). That fix is a strict
no-op on POSIX because the `OS` env var is not exported by POSIX shells; the
Windows-heuristic branch is taken only when `OS=Windows_NT`, and the
preceding locale check still wins on any Linux/macOS host.

---

## E. ConPTY VT Gate Refinement (FUNC-WIN-014)

### Problem

`src/windows/termicap-graphics-io.adb:245-254` currently does:

```ada
H := Win32.Winbase.GetStdHandle (Win32.Winbase.STD_OUTPUT_HANDLE);
if Termicap.Win32_VT.Is_Valid_Handle (H) then
   Res := Win32.Wincon.GetConsoleMode (H, Mode'Unchecked_Access);
   if Res /= Win32.FALSE then
      --  Native Windows Console confirmed; no escape probe.
      return Caps;
   end if;
end if;
```

This is too aggressive on ConPTY-managed sessions. Windows Terminal,
PowerShell hosting in VS Code, Warp, and any program that ConPTY-wraps a
child all expose a console handle to the child for which `GetConsoleMode`
succeeds, even though the *user-facing* terminal is not the legacy
`conhost.exe` and does honour Sixel, Kitty graphics, OSC 8, etc. The current
gate skips active probing in exactly the cases where it would succeed.

### Fix

Add a classifier helper to `Termicap.Win32_VT`:

```ada
type Console_VT_Status is
  (Not_A_Console,
   Legacy_Conhost,
   ConPTY_VT_Enabled);

--  @summary Classify the current console host for the purpose of deciding
--           whether to send VT-based active probes.
--  @return  Not_A_Console      — STD_OUTPUT_HANDLE is not a console handle
--                                (redirected to file/pipe; classic
--                                MSYS2/Cygwin path).  Caller may still try
--                                CONOUT$ or POSIX-like behaviour.
--           Legacy_Conhost     — STD_OUTPUT_HANDLE is a console AND
--                                ENABLE_VIRTUAL_TERMINAL_PROCESSING is
--                                neither set nor settable.  Sixel/OSC
--                                queries will not work.
--           ConPTY_VT_Enabled  — STD_OUTPUT_HANDLE is a console AND
--                                ENABLE_VIRTUAL_TERMINAL_PROCESSING is
--                                already set, OR can be set without error.
--                                Active probes are appropriate.
function Console_VT_Status return Console_VT_Status;

--  @summary Convenience predicate: "should Tier-3 active probing skip on
--           the basis of console-host detection?"
--  @return  True iff Console_VT_Status returns Legacy_Conhost.
function Should_Skip_Active_Probes return Boolean;
```

Implementation:

```text
Console_VT_Status:
   H := GetStdHandle (STD_OUTPUT_HANDLE)
   if not Is_Valid_Handle (H) then
      return Not_A_Console
   end if
   if GetConsoleMode (H, Mode) = FALSE then
      return Not_A_Console
   end if
   if (Mode and ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= 0 then
      return ConPTY_VT_Enabled
   end if
   --  ConPTY enables VT processing automatically.  conhost.exe sometimes
   --  does too on recent builds.  Probe by attempting to set the bit:
   if SetConsoleMode (H, Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= FALSE then
      return ConPTY_VT_Enabled  --  the host accepted the bit
   end if
   return Legacy_Conhost
```

Note: when `Console_VT_Status` returns `ConPTY_VT_Enabled` after a successful
`SetConsoleMode` probe, the bit is left enabled. That is intentional and
matches `Termicap.Win32_VT.Enable_VT_Processing` behaviour (FUNC-WIN-011).

### Call sites to update

```
src/windows/termicap-graphics-io.adb:245-254     -- Sixel/Kitty gate
src/windows/termicap-clipboard-io.adb:243-253    -- OSC 52 gate
src/windows/termicap-keyboard-io.adb:108-122     -- Kitty keyboard gate
src/windows/termicap-mouse-io.adb:273-285        -- mouse mode probe gate
```

Each site currently does `if GetConsoleMode succeeds then return passive`.
After the refactor each call becomes:

```ada
case Termicap.Win32_VT.Console_VT_Status is
   when Termicap.Win32_VT.Legacy_Conhost =>
      return Caps;  -- passive only; conhost cannot answer
   when Termicap.Win32_VT.Not_A_Console =>
      null;         -- fall through to MSYS2/Cygwin/POSIX-like path
   when Termicap.Win32_VT.ConPTY_VT_Enabled =>
      null;         -- fall through to TTY guard and active probes
end case;
```

`Termicap.OSC.Open` itself should not consult the gate: the OSC layer is
host-agnostic by design (the protocol is the same on legacy conhost and
ConPTY; legacy conhost just doesn't reply, which is what the timeout exists
for). The gate is a **performance** optimisation on top of the OSC layer:
on confirmed legacy hosts we save a 1-second timeout per query. ADR-0041
captures this separation.

---

## F. Unicode Env-Var Fix (FUNC-UNI-005)

`src/termicap-unicode.adb:212` currently reads:

```ada
if Equal_Insensitive (Value (Env, "OS_TYPE"), "Windows_NT") then
   Floor := Unicode_Level'Max (Floor, Detect_Windows_Unicode (Env));
end if;
```

The Windows shell exports `OS=Windows_NT`, not `OS_TYPE`. The original
requirement text was wrong, the implementation matched the wrong text, and
the Windows branch was therefore never entered.

**Change:** replace `"OS_TYPE"` with `"OS"`. One-line edit. No test
infrastructure changes required because the existing
`Termicap.Environment.Insert` builder lets unit tests compose any env-var
snapshot.

`Termicap.Environment.Capture` uses `Ada.Environment_Variables.Iterate`
(`src/termicap-environment-capture.adb:27`) which captures every env var
defined by the OS, including `OS=Windows_NT` on Windows. No
allowlist gate exists; no addition is required.

The `Equal_Insensitive` value comparison is already case-insensitive (it's
defined that way in `Termicap.Environment.Equal_Case_Insensitive`). No
further changes.

### Test impact

Existing unit tests for `Detect_Unicode_Level` did not cover the Windows
branch (it was unreachable). Adding tests is in section H.

---

## G. Cross-Platform Impact Assessment

| File | Edit | POSIX impact |
|------|------|--------------|
| `src/termicap-osc.ads` | none | none |
| `src/termicap-osc-parsing.ads/.adb` | none | none |
| `src/posix/termicap-osc.adb` | none | none |
| `src/c/termicap_osc.c` | none | none |
| `src/windows/termicap-osc.adb` | full rewrite | none — POSIX builds do not include this file |
| `src/windows/termicap-win32_vt.ads` | add `ENABLE_VIRTUAL_TERMINAL_INPUT`, `DISABLE_NEWLINE_AUTO_RETURN`, `Console_VT_Status` enum, `Console_VT_Status` function, `Should_Skip_Active_Probes` function | none — file not in POSIX source dirs |
| `src/windows/termicap-win32_vt.adb` | implement the new helpers | none |
| `src/windows/termicap-graphics-io.adb` | replace inlined GetConsoleMode block with `Should_Skip_Active_Probes` | none |
| `src/windows/termicap-clipboard-io.adb` | same refactor | none |
| `src/windows/termicap-keyboard-io.adb` | same refactor | none |
| `src/windows/termicap-mouse-io.adb` | same refactor | none |
| `src/termicap-unicode.adb` | `"OS_TYPE"` -> `"OS"` | strictly none on POSIX (no shell exports `OS=Windows_NT`); strictly positive on Windows (the branch becomes reachable) |
| `src/termicap-environment.ads/.adb` | none | none |
| `src/termicap-environment-capture.adb` | none — `Iterate` already captures `OS` | none |

The build system is already platform-dispatched
(ADR-0018, `src/posix/` vs `src/windows/`). `alr build` on Linux/macOS picks
up zero of the rewritten files.

---

## H. Test Plan

All tests live in `tests/src/`. The existing test framework
(`tests/src/tests.adb` + per-module driver units) is reused without
extension.

### H.1 Unicode env-var fix — unit test

`tests/src/test_unicode_windows.adb` (new file):

```text
Test 1: Windows_Terminal_Sets_Basic
   Env := EMPTY_ENVIRONMENT
   Insert (Env, "OS",         "Windows_NT")
   Insert (Env, "WT_SESSION", "abc-123")
   assert Detect_Unicode_Level (Env) = Basic

Test 2: Windows_Vscode_Sets_Basic
   Env := EMPTY_ENVIRONMENT
   Insert (Env, "OS",           "Windows_NT")
   Insert (Env, "TERM_PROGRAM", "vscode")
   assert Detect_Unicode_Level (Env) = Basic

Test 3: Windows_No_Heuristic_Returns_None
   Env := EMPTY_ENVIRONMENT
   Insert (Env, "OS", "Windows_NT")
   --  no WT_SESSION, no TERM_PROGRAM, no TERM, no JediTerm
   assert Detect_Unicode_Level (Env) = None

Test 4: OS_TYPE_Alone_Does_Not_Trigger
   --  Regression: the old typo `OS_TYPE` must no longer match.
   Env := EMPTY_ENVIRONMENT
   Insert (Env, "OS_TYPE",    "Windows_NT")
   Insert (Env, "WT_SESSION", "abc-123")
   assert Detect_Unicode_Level (Env) = None  --  Windows branch not entered

Test 5: Locale_Wins_Over_Windows_Heuristic
   Env := EMPTY_ENVIRONMENT
   Insert (Env, "OS",     "Windows_NT")
   Insert (Env, "LC_ALL", "en_US.UTF-8")
   assert Detect_Unicode_Level (Env) = Basic  --  via locale, not heuristic
```

These are pure SPARK-mode tests; no tasking, no I/O.

### H.2 Win32_VT helper unit tests

`tests/src/test_win32_vt_classifier.adb` (new file, `@platform=windows`):

The classifier is an OS-call wrapper, so unit-testing requires either a
dependency-injection seam or a real console. We pick the second route: the
test runs only on Windows hosts and requires the test binary to be invoked
under a real console (i.e., the existing `tests/bin/termicap_tests`
invocation).

```text
Test 1: Classifier_Returns_Sane_Value
   --  Whatever the host is, the result must be one of the three enum values.
   Status := Console_VT_Status
   assert Status in (Not_A_Console | Legacy_Conhost | ConPTY_VT_Enabled)

Test 2: Should_Skip_Iff_Legacy_Conhost
   --  Should_Skip_Active_Probes is the predicate form.
   assert Should_Skip_Active_Probes = (Console_VT_Status = Legacy_Conhost)

Test 3: VT_Bit_Set_After_ConPTY_Probe
   --  When the classifier returns ConPTY_VT_Enabled, the VT processing bit
   --  must be set on STD_OUTPUT_HANDLE (post-condition of a successful
   --  SetConsoleMode probe).
   if Console_VT_Status = ConPTY_VT_Enabled then
      H := GetStdHandle (STD_OUTPUT_HANDLE)
      Result := GetConsoleMode (H, Mode)
      assert Result /= FALSE
      assert (Mode and ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= 0
   end if
```

These tests are skipped on POSIX via the `@platform=windows` runner tag
(existing infrastructure; see `tests/src/runner.adb`).

### H.3 OSC Probe Session integration test on Windows

`tests/src/test_osc_session_windows.adb` (new file, `@platform=windows`):

```text
Test 1: Open_Returns_OK_Or_Documented_Status
   declare
      Session : Termicap.OSC.Probe_Session;
      Status  : Termicap.OSC.Session_Status;
   begin
      Termicap.OSC.Open (Session, Status);
      --  In a Windows console session the status MUST be one of:
      --    Session_OK            (we have a console)
      --    Session_No_Terminal   (the test binary is being run with stdin AND
      --                           stdout redirected to non-console; CONIN$/
      --                           CONOUT$ also unavailable — rare)
      assert Status in (Session_OK | Session_No_Terminal);
      --  Save_Failed / Raw_Failed must NOT occur on a healthy WT session;
      --  if they do, this test catches the regression.
      assert Status not in (Session_Save_Failed | Session_Raw_Failed);
   end;

Test 2: DA1_Roundtrip_Under_Sentinel_Query
   --  Send DA1 itself as the query; the response must contain the DA1
   --  pattern; Sentinel_Query must return Resp_Length = 0 (the pre-sentinel
   --  bytes are empty because the response IS the sentinel).
   if Status = Session_OK then
      Termicap.OSC.Sentinel_Query
        (Session, DA1_QUERY, Response, Resp_Length, 1000, Timed_Out);
      assert not Timed_Out;
      assert Resp_Length = 0;
   end if;

Test 3: Finalize_Restores_Mode
   declare
      H        : Win32.Winnt.HANDLE;
      Mode_Pre : Win32.DWORD := 0;
      Mode_Post: Win32.DWORD := 0;
   begin
      H := GetStdHandle (STD_INPUT_HANDLE);
      GetConsoleMode (H, Mode_Pre'Access);

      declare
         Session : Termicap.OSC.Probe_Session;
         Status  : Termicap.OSC.Session_Status;
      begin
         Termicap.OSC.Open (Session, Status);
         --  Session goes out of scope at end of declare — Finalize must run
      end;

      GetConsoleMode (H, Mode_Post'Access);
      assert Mode_Pre = Mode_Post;
   end;
```

### H.4 Conformance harness regression

The existing harness
(`tools/conformance/run.py --emulator <id>`) is not changed; we add the
following expected outputs to `tools/conformance/manifest.json` (Windows
emulator profiles only):

| Emulator | Field | Expected after fix |
|----------|-------|---------------------|
| windows-terminal | unicode | extended (was: none) |
| windows-terminal | sixel | true (was: false) |
| windows-terminal | da1_attributes | non-empty (was: missing) |
| windows-terminal | xtversion | non-empty (was: missing) |
| warp | unicode | extended (was: none) |
| warp | hyperlinks | supported (was: unknown) |
| warp | da1_attributes | non-empty (was: missing) |
| powershell-conhost | unicode | none (legacy host; unchanged) |
| powershell-conhost | sixel | false (legacy host; unchanged) |

The harness compares against `blessed`/`rich`/`prompt_toolkit` shims and was
the original reporter of the regression; running it after the implementation
phase is the acceptance criterion.

### H.5 Coverage targets

| Module | New lines | Test coverage target |
|--------|-----------|----------------------|
| `src/windows/termicap-osc.adb` | ~250 | 90% (some error paths only reachable with synthetic fault injection) |
| `src/windows/termicap-win32_vt.adb` (additions) | ~30 | 100% |
| `src/termicap-unicode.adb` (one line) | 1 | 100% (all four heuristic branches covered) |

---

## I. Risks and Open Questions

### I.1 `Probe_Session` shared type

**Chosen:** body-private slot table indexed by a synthetic `File_Descriptor`.
**Alternative considered:** extend `Probe_Session` with platform-conditional
fields (HANDLEs and origins). Rejected because it pollutes the spec with
Windows-specific symbols, requires `with Win32.Winnt` from the shared spec,
and breaks the `src/posix` vs `src/windows` build dispatch (the spec would
need to choose one set of fields). The slot-table approach keeps the spec
identical on both platforms; the cost is one extra indirection per OSC call,
which is negligible compared to the syscall cost. ADR-0040 documents this.

### I.2 Concurrency and the active-session guard

The `Active_Session_Guard` protected object in the POSIX body is a literal
copy in the Windows body. Both bodies have their own instance because Ada
protected objects cannot live in a `SPARK_Mode => Off` shared spec without
forcing the spec off as well (it already is, but moving the guard there
would require `with Ada.Synchronous_Task_Control` etc. in the spec). The
duplication is small (15 lines) and the semantics are identical. A future
refactor could hoist the protected object to a shared private child package
`Termicap.OSC.Internal_Guard` if the duplication becomes a concern.

### I.3 `Termios_State.Data` size

10 bytes used out of 128. No bump required. POSIX uses up to ~80 bytes on
some BSDs but well below 128. If a future platform exceeds 128, the
constant in `src/termicap-osc.ads` is bumped — POSIX-only impact.

### I.4 `WAIT_FAILED` / `WAIT_ABANDONED` on disconnected handles

Both surface as `Bytes_Read = 0, Timed_Out = False`. The `Sentinel_Query`
caller's accumulation loop interprets that as an I/O error and returns
`Timed_Out = True, Resp_Length = 0`. This is conservative: a closed handle
behaves identically to an unresponsive terminal, which is the desired
outcome (the next layer up will fall back to passive heuristics).

A more sophisticated implementation could return a distinct
`Session_IO_Error` status, but that would require a spec change for a case
that is essentially unreachable on a session that just successfully
completed `Open`. Deferred.

### I.5 `Drain_Input` iteration bound on Windows

`MAX_DRAIN_ITERATIONS = 16` is platform-agnostic and reused unchanged. Each
iteration is `WaitForSingleObject(0)` + at most one `ReadFile`. With the
0 ms wait, an iteration costs <1 microsecond; the bound is so far above the
practical drain need (typically 0–2 reads) that it is purely defensive.

### I.6 `WriteFile` to which handle?

`Write_Query` writes to the **output** handle when one is acquired,
otherwise to the input handle. Most terminal hosts forward writes from any
console handle to the same underlying buffer, but on programs that have
stdout redirected and use CONIN$ for input, writing to CONOUT$ is the
correct path. The body chooses output-first, falling back to input.

### I.7 Open question for review

- **Should we extend `Session_Status` with `Session_IO_Error`** to
  distinguish a transient `WAIT_FAILED` from a flat-out missing console?
  The spec currently has neither value, and Sentinel_Query's
  `Timed_Out = True` is the catch-all. Recommend: defer; keep the spec
  unchanged.
- **Should `Drain_Input` log when it hits the iteration bound on Windows?**
  The POSIX side does not log either. The existing `Termicap.Logging`
  abstraction is opt-in. Recommend: no.
- **Stage-2 fallback on Windows Sandbox / restricted token processes:**
  `CreateFileW("CONIN$", ...)` may return `ERROR_ACCESS_DENIED` in
  containerised environments. The body returns `Session_No_Terminal` in
  that case, which is correct (no usable console) but worth mentioning in
  user-facing docs.

---

## J. Implementation Order (suggested)

1. **FUNC-UNI-005 fix.** One line in `src/termicap-unicode.adb`. Add
   `tests/src/test_unicode_windows.adb` with the five tests in H.1.
   `alr build && tests/bin/termicap_tests`. Lowest risk, highest value
   (unblocks the conformance regression on Windows Terminal).

2. **`Termicap.Win32_VT` extensions.**
   - Add `ENABLE_VIRTUAL_TERMINAL_INPUT` and `DISABLE_NEWLINE_AUTO_RETURN`
     constants.
   - Add `Console_VT_Status` enum + `Console_VT_Status` function +
     `Should_Skip_Active_Probes` predicate.
   - Add `tests/src/test_win32_vt_classifier.adb`.

3. **Refactor four call sites** in `src/windows/`:
   `graphics-io`, `clipboard-io`, `keyboard-io`, `mouse-io`. Each reduces
   to a `case Console_VT_Status` block. No behavioural change on legacy
   conhost; positive change on ConPTY hosts (active probes now run).

4. **Windows OSC body rewrite.** Replace `src/windows/termicap-osc.adb`
   with the implementation per sections D.1–D.6. Build, then run the
   integration test from H.3.

5. **Sentinel/Timeout query parity check.** Confirm the Windows body's
   `Sentinel_Query` and `Timeout_Query` produce byte-identical output to
   the POSIX body on a known mock input (unit test or
   side-by-side review).

6. **Conformance harness re-run.** Update
   `tools/conformance/manifest.json` with the new expected outputs from
   H.4. Run on Windows Terminal, Warp, and PowerShell-conhost. Diff with
   the cross-language reference shims to confirm parity.

7. **Documentation pass.** Update `docs/architecture/05-building-block.md`
   (existing file) to mention the slot table, and add a one-line entry to
   `docs/adr/README.md` for ADRs 0039–0041.

---

## K. ADRs

Three ADRs are filed alongside this tech spec:

1. **ADR-0039**: Windows OSC uses `ReadFile` + `ENABLE_VIRTUAL_TERMINAL_INPUT`,
   not `ReadConsoleInputW`.
   `docs/adr/0039-windows-osc-uses-readfile-not-readconsoleinput.md`

2. **ADR-0040**: Windows console mode state stuffed into the existing
   `Termios_State.Data` byte array; per-handle metadata in a body-private
   slot table.
   `docs/adr/0040-windows-osc-state-in-termios-state-data.md`

3. **ADR-0041**: ConPTY VT classifier extracted as a helper in
   `Termicap.Win32_VT`; gate refinement is a per-call-site decision and
   does not live in the OSC layer itself.
   `docs/adr/0041-conpty-vt-gate-helper-in-win32-vt.md`

---

## L. Open Items for Phase 3

- Confirm `MAX_SLOTS = 4` is acceptable, or reduce to 1 (matching
  FUNC-OSC-012's "single concurrent session" rule). Recommend 1; the
  defensive over-allocation in section D.2 is unnecessary now that the
  active-session guard is reused on Windows.
- Confirm we are willing to leave the `Should_Skip_Active_Probes`
  side-effect (it sets `ENABLE_VIRTUAL_TERMINAL_PROCESSING` when probing
  ConPTY) inside the classifier rather than splitting "classify" from
  "enable". Recommend: keep, because every call site that currently
  calls `Enable_VT_Processing` would otherwise need to call it again.
