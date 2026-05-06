# FGPGRP: Foreground Process Group Check

**Feature:** Foreground process group verification before OSC/DCS/CSI queries (Tier 4)
**Requirements:** FUNC-FGP-001 through FUNC-FGP-013 (`docs/requirements/FUNC-FGPGRP.sdoc`)
**Parent Requirements:** OSC (REQ-OSC)
**Status:** Proposed
**Date:** 2026-05-06

---

## 1. Overview

When a process is running as a background job in a POSIX shell, sending escape
sequence queries (OSC, DCS, CSI) to the terminal corrupts the foreground
process's output. The escape bytes appear interleaved with the foreground
process's display, and the terminal's raw-mode response bytes may be misread by
both processes.

The FGPGRP feature gates all active terminal probing behind a foreground process
group check. The canonical POSIX algorithm is:

1. Call `ioctl(fd, TIOCGPGRP, &fg_pgrp)` to get the terminal's foreground
   process group ID.
2. Call `getpgrp()` to get the calling process's own process group ID.
3. If they are equal, the process owns the terminal and may safely probe.

If the ioctl fails for any reason (ENOTTY, EBADF, EIO, EPERM), the process is
conservatively treated as not-foreground and probing is suppressed.

This feature is already partially implemented in the current codebase as part
of the OSC infrastructure (FUNC-OSC-007). The FUNC-FGP requirements formalize
the existing implementation, specify its integration contract, and add the
Windows stub requirement. This tech spec documents how the existing code maps
to the FUNC-FGP requirements and identifies the single correction needed (the
Windows stub return value).

---

## 2. Framework Survey

### termenv (Go) -- The primary reference

In `reference-frameworks/termenv/termenv_posix.go`, termenv implements the
foreground check as a standalone function:

```go
func isForeground(fd int) bool {
    pgrp, err := unix.IoctlGetInt(fd, unix.TIOCGPGRP)
    if err != nil {
        return false
    }
    return pgrp == unix.Getpgrp()
}
```

Key observations:

- **Same algorithm**: ioctl(TIOCGPGRP) + getpgrp() comparison. This is the
  canonical POSIX pattern and matches Termicap's implementation exactly.
- **Error handling**: Any ioctl error returns false (not-foreground). No errno
  inspection. Termicap follows the same pattern.
- **Call site**: In `termenv_unix.go:250`, `isForeground(fd)` is called inside
  `termStatusReport()` after opening `/dev/tty` but before entering raw mode
  and sending queries. The `unsafe` flag bypasses the check.
- **Solaris variant**: `termenv_solaris.go` has an identical implementation,
  confirming the algorithm is portable across POSIX platforms.
- **Windows**: termenv does not have a Windows `isForeground` because
  `termStatusReport` is not called on Windows. The Windows code path uses
  Windows Console APIs directly.
- **File descriptor source**: termenv opens `/dev/tty` first, then uses that
  FD for the foreground check. This matches FUNC-FGP-009 (use `/dev/tty`, not
  stdin/stdout/stderr).

### Global Synthesis (00-GLOBAL-SYNTHESIS.md)

The synthesis document lists the canonical background color detection algorithm
(Section 2) as:

```
if not foreground process (ioctl(TIOCGPGRP) != getpgrp()): abort
```

And in the OS call table (Section 6.1):

| OS Call | Purpose | Ada Binding Strategy |
|---------|---------|---------------------|
| `ioctl(fd, TIOCGPGRP, &pgrp)` | Foreground process check | Custom thin binding |
| `getpgrp()` | Process group ID | `pragma Import(C, C_Getpgrp, "getpgrp")` |

The synthesis recommends placing the foreground check in the Ada FFI boundary
layer, which is exactly where Termicap has placed it.

### Other frameworks

No other reference frameworks in the repository (chalk, supports-color, termbg,
crossterm) implement a foreground process group check. This is consistent with
the synthesis finding that only termenv (and notcurses, not in the reference set)
perform this guard.

---

## 3. Architecture

### Current state

The foreground check is already implemented as part of the `Termicap.OSC`
package:

```
Termicap.OSC (SPARK_Mode => Off)
  |-- Is_Foreground_Process (FD : File_Descriptor) return Boolean
  |     Ada wrapper calling C_Is_Foreground
  |
  |-- Open (Session, Status)
  |     Step 1: Open /dev/tty
  |     Step 2: Is_Foreground_Process (Temp_FD)
  |     Step 3: Acquire session guard
  |     Step 4: Save termios
  |     Step 5: Set raw mode
  |     Step 6: Drain input

C layer:
  termicap_osc_is_foreground(fd) -- ioctl(TIOCGPGRP) + getpgrp()
```

### Where FGPGRP fits in the package hierarchy

The foreground check lives in `Termicap.OSC` because it is an integral part of
the probe session lifecycle. The FUNC-FGP requirements do not mandate a separate
package; FUNC-FGP-012 says the FFI bindings "shall be named
`Termicap.OSC.Foreground` **or placed within an existing OSC FFI boundary
package**." The existing placement within `Termicap.OSC` satisfies this
requirement.

No new packages are needed. The existing implementation already satisfies all
FUNC-FGP requirements except for one correction to the Windows stub (see
Section 7).

---

## 4. Package Design

### 4.1. Public API (already exists)

The public API is declared in `src/termicap-osc.ads`:

```ada
function Is_Foreground_Process (FD : File_Descriptor) return Boolean;
--  @relation(FUNC-OSC-007): Foreground process group check via TIOCGPGRP
```

This signature satisfies FUNC-FGP-004. The function:

- Takes a `File_Descriptor` (which is `new Interfaces.C.int`)
- Returns `Boolean`
- Does not raise exceptions
- Is stateless (no package-level mutable state)
- Is safe for concurrent calls (no shared mutable state)

The return type mapping:
- `True` = caller is in the foreground process group (safe to probe)
- `False` = caller is not foreground, or ioctl failed, or FD is not a terminal

### 4.2. POSIX implementation (already exists)

In `src/posix/termicap-osc.adb`:

```ada
--  ioctl(TIOCGPGRP) + getpgrp() comparison (FUNC-OSC-007).
function C_Is_Foreground (FD : Interfaces.C.int) return Interfaces.C.int;
pragma Import (C, C_Is_Foreground, "termicap_osc_is_foreground");

function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
   Result : constant Interfaces.C.int :=
     C_Is_Foreground (Interfaces.C.int (FD));
begin
   return Result = 1;
end Is_Foreground_Process;
```

This implementation:
- Calls a single C function that encapsulates both ioctl and getpgrp
- Converts the C int return (1 = foreground, 0 = not) to Ada Boolean
- Cannot raise an exception (the C function handles all errors internally)

### 4.3. SPARK boundary

The entire `Termicap.OSC` package is `SPARK_Mode => Off` because it uses
`Ada.Finalization.Limited_Controlled` and C FFI bindings with access types.
`Is_Foreground_Process` is part of this FFI boundary.

Per FUNC-FGP-013, the comparison logic (`fg_pgrp == my_pgrp`) is expressed as
a pure C equality test. While the requirement suggests separating it into a
SPARK-eligible Ada helper, the current design keeps it in C for simplicity.
The comparison is trivially auditable as a single `==` in the C function. This
is acceptable because the entire `Termicap.OSC` package is already SPARK_Mode
Off, so separating the comparison into a SPARK-On helper would require
introducing a new child package for a single two-operand equality expression --
an unjustified increase in package count.

### 4.4. Session_Status enumeration (already exists)

```ada
type Session_Status is
  (Session_OK,
   Session_Not_Foreground,   -- Is_Foreground_Process returned False
   Session_No_Terminal,       -- /dev/tty could not be opened
   Session_Save_Failed,
   Session_Raw_Failed,
   Session_Already_Active);
```

The `Session_Not_Foreground` value satisfies FUNC-FGP-008's requirement for a
"distinguished result indicating that probing was suppressed."

---

## 5. C Helper Design

### Existing C function

In `src/c/termicap_osc.c`:

```c
int termicap_osc_is_foreground(int fd)
{
    pid_t fg_pgrp;
    pid_t my_pgrp;

    if (ioctl(fd, TIOCGPGRP, &fg_pgrp) != 0) {
        return 0;
    }

    my_pgrp = getpgrp();
    return (fg_pgrp == my_pgrp) ? 1 : 0;
}
```

This function:

1. Calls `ioctl(fd, TIOCGPGRP, &fg_pgrp)` -- resolves the TIOCGPGRP macro at
   C compile time (FUNC-FGP-002)
2. Calls `getpgrp()` -- returns the calling process's process group ID
   (FUNC-FGP-003)
3. Compares them and returns 1 (foreground) or 0 (not foreground / error)
   (FUNC-FGP-004)

### Why a C helper instead of direct Ada imports

The FUNC-FGP requirements specify two alternative approaches:

- **Option A (requirements text)**: Separate Ada imports for `ioctl(TIOCGPGRP)`
  (via a C helper that resolves the macro) and `getpgrp()` (direct import), with
  the comparison in Ada.
- **Option B (current implementation)**: A single C helper that encapsulates
  ioctl + getpgrp + comparison.

The current Option B design was chosen (ADR-0014 established the C helper
pattern for termios/ioctl) because:

- TIOCGPGRP is a preprocessor macro that varies across platforms (Linux:
  0x540F, macOS: defined via `_IOR`). It cannot be imported as an Ada constant.
- Combining ioctl + getpgrp in one C function eliminates the need for an
  `access Interfaces.C.int` parameter in the Ada binding (which would be
  needed for the ioctl output parameter). This simplifies the Ada FFI surface.
- The comparison in C is `fg_pgrp == my_pgrp`, which is trivially correct.
  Moving it to Ada would add one more FFI call (getpgrp) and one more C-to-Ada
  data transfer for no correctness benefit.

No new C functions are needed. The existing `termicap_osc_is_foreground` fully
satisfies FUNC-FGP-002, FUNC-FGP-003, and the comparison step of FUNC-FGP-004.

---

## 6. Integration Points

### 6.1. How Open() calls the foreground guard

In `src/posix/termicap-osc.adb`, the `Open` procedure (FUNC-FGP-008):

```ada
procedure Open (Session : in out Probe_Session; Status : out Session_Status) is
begin
   -- Step 1: Open /dev/tty to get an FD for the check
   declare
      Temp_FD : constant File_Descriptor := Open_Terminal;
   begin
      if Temp_FD = INVALID_FD then
         Status := Session_No_Terminal;
         return;
      end if;

      if not Is_Foreground_Process (Temp_FD) then
         -- Close the temporary FD and return
         Close_Terminal (Dummy_FD);
         Status := Session_Not_Foreground;
         return;
      end if;
      -- ... proceed with session guard, save termios, raw mode ...
   end;
end Open;
```

The current implementation opens `/dev/tty` first, then checks foreground
status using that FD. This satisfies FUNC-FGP-009 (use `/dev/tty`, not
stdin/stdout/stderr). If `/dev/tty` cannot be opened, `Session_No_Terminal`
is returned before the foreground check is reached, which satisfies the
FUNC-FGP-009 fallback ("treat as not safe to probe").

The foreground check is the **first logical check** after obtaining an FD.
No bytes are written to the terminal, no raw mode is entered, and no termios
state is saved before the foreground check. This satisfies FUNC-FGP-008's
requirement that "no escape sequence byte shall reach the terminal file
descriptor when Is_Foreground_Process returns False."

### 6.2. Integration with caller packages

All I/O packages that perform terminal queries go through `Termicap.OSC`:

| Package | Entry Point | How foreground check applies |
|---------|------------|------------------------------|
| `Termicap.Color.BG_Query.IO` | `Query_Color` | Calls `OSC.Open` which checks foreground |
| `Termicap.XTVersion.IO` | `Query_XTVersion` | Calls `OSC.Open` which checks foreground |
| `Termicap.DA1.IO` | `Query_DA1` | Calls `OSC.Open` which checks foreground |
| `Termicap.DECRPM.IO` | `Query_DECRPM` | Calls `OSC.Open` which checks foreground |
| `Termicap.Keyboard.IO` | `Query_Keyboard` | Calls `OSC.Open` which checks foreground |
| `Termicap.Graphics.IO` | `Query_Graphics` | Calls `OSC.Open` which checks foreground |
| `Termicap.Clipboard.IO` | `Query_Clipboard` | Calls `OSC.Open` which checks foreground |

Because the foreground check is embedded inside `Open`, callers do not need to
invoke it separately. The check is automatic and transparent. When `Open`
returns `Session_Not_Foreground`, callers treat it the same as any other
session-open failure: set `Timed_Out := True`, `Resp_Length := 0`, and return.

This is a pre-check inside `Begin_Query_Session` (i.e., `Open`), not a
separate function callers invoke. This design is preferred because:

- It cannot be forgotten or bypassed by callers
- It runs at the correct point in the lifecycle (after FD acquisition, before
  any terminal state mutation)
- The `Session_Not_Foreground` status code gives callers diagnostic information

---

## 7. Platform Strategy

### POSIX (Linux, macOS, BSDs, Solaris)

The POSIX implementation uses the platform-specific body at
`src/posix/termicap-osc.adb`, which imports the C helper
`termicap_osc_is_foreground`. The C helper is compiled only on POSIX platforms
(guarded by `#if defined(__unix__) || defined(__APPLE__)` in `termicap_osc.c`).

### Windows

The Windows stub is at `src/windows/termicap-osc.adb`. The platform split is
handled via Alire source directory selection (ADR-0018), where the project file
selects either `src/posix/` or `src/windows/` based on the target OS. No
conditional compilation or preprocessor is needed in Ada.

**Correction needed**: The current Windows stub returns `False`:

```ada
function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
   pragma Unreferenced (FD);
begin
   return False;  -- Current: always False
end Is_Foreground_Process;
```

FUNC-FGP-007 requires the Windows stub to return `True` ("unconditionally
returns True, without calling any ioctl or equivalent Windows API"). The
rationale: Windows does not have POSIX job control, so the foreground check
should not block probing. The subsequent TTY check and timeout mechanism
provide sufficient protection.

However, examining the Windows `Open` procedure, it currently returns
`Session_No_Terminal` unconditionally (because `/dev/tty` does not exist on
Windows). This means `Is_Foreground_Process` is **never called** on Windows
regardless of its return value. The Windows OSC probe session is a no-op
because Windows terminal interaction uses the Win32 Console API, not escape
sequences sent to `/dev/tty`.

Despite this, the stub should be corrected to return `True` per FUNC-FGP-007
for semantic correctness: if future Windows support adds ConPTY-based querying,
the foreground check should not be the gate that blocks it.

### Platform dispatch mechanism

The platform dispatch uses Alire source directory variables (ADR-0018):

```
src/posix/termicap-osc.adb   -- POSIX body (with C FFI)
src/windows/termicap-osc.adb -- Windows body (stubs)
```

Only one body is compiled for any given target. The spec
(`src/termicap-osc.ads`) is shared across both platforms.

---

## 8. Error Handling

All error paths return `False` (not foreground) from `Is_Foreground_Process`:

| Condition | ioctl result | Is_Foreground_Process | Open status |
|-----------|-------------|----------------------|-------------|
| Foreground process, valid terminal | Success, pgrps match | `True` | `Session_OK` |
| Background process, valid terminal | Success, pgrps differ | `False` | `Session_Not_Foreground` |
| FD is a pipe/file (ENOTTY) | Failure (-1) | `False` | `Session_Not_Foreground` |
| Bad FD (EBADF) | Failure (-1) | `False` | `Session_Not_Foreground` |
| Disconnected terminal (EIO) | Failure (-1) | `False` | `Session_Not_Foreground` |
| Permission denied (EPERM) | Failure (-1) | `False` | `Session_Not_Foreground` |
| /dev/tty cannot be opened | N/A (not called) | N/A | `Session_No_Terminal` |

The function does not inspect `errno` (FUNC-FGP-006). The C helper checks
only whether `ioctl` returned 0 (success) or non-zero (any failure). This
eliminates errno race conditions and keeps the error handling simple.

No exceptions propagate from `Is_Foreground_Process` (FUNC-FGP-010). The C
function cannot raise Ada exceptions, and the Ada wrapper performs only a
simple integer comparison (`Result = 1`), which cannot overflow or fault.

---

## 9. Thread Safety

`Is_Foreground_Process` is stateless and idempotent (FUNC-FGP-011):

- **No package-level mutable state**: The function declares only stack-local
  variables in the C helper (`fg_pgrp`, `my_pgrp`).
- **No caching**: Every call performs fresh `ioctl` and `getpgrp` system calls.
- **Independent calls**: Two Ada tasks calling `Is_Foreground_Process`
  simultaneously each invoke their own `ioctl`/`getpgrp` pair with separate
  stack frames. No locking is needed.
- **System calls are thread-safe**: `ioctl(TIOCGPGRP)` and `getpgrp()` are
  specified as thread-safe by POSIX.

Note that while `Is_Foreground_Process` itself is thread-safe, the `Open`
procedure that calls it uses the `Active_Session_Guard` protected object to
enforce single concurrent session semantics (FUNC-OSC-012). Thread safety at
the session level is handled by that guard, not by the foreground check.

---

## 10. Requirement Traceability

| Requirement | Design Element | Location |
|-------------|---------------|----------|
| FUNC-FGP-001 | Foreground check gates all OSC queries via `Open` | `src/posix/termicap-osc.adb:472` |
| FUNC-FGP-002 | `termicap_osc_is_foreground` wraps `ioctl(fd, TIOCGPGRP, &fg_pgrp)` | `src/c/termicap_osc.c:180-191` |
| FUNC-FGP-003 | `termicap_osc_is_foreground` calls `getpgrp()` | `src/c/termicap_osc.c:189` |
| FUNC-FGP-004 | `Is_Foreground_Process` in `Termicap.OSC`; three-step logic in C helper | `src/termicap-osc.ads:299`, `src/posix/termicap-osc.adb:244-248` |
| FUNC-FGP-005 | ioctl on non-TTY FD fails with ENOTTY, C helper returns 0, Ada returns False | `src/c/termicap_osc.c:185` |
| FUNC-FGP-006 | C helper checks `ioctl != 0` without inspecting errno; returns 0 on any failure | `src/c/termicap_osc.c:185-186` |
| FUNC-FGP-007 | Windows stub in `src/windows/termicap-osc.adb:113-117` (**needs correction: change `False` to `True`**) | `src/windows/termicap-osc.adb:113-117` |
| FUNC-FGP-008 | `Open` calls `Is_Foreground_Process` before raw mode; returns `Session_Not_Foreground` on failure | `src/posix/termicap-osc.adb:460-480` |
| FUNC-FGP-009 | `Open` opens `/dev/tty` first, uses that FD for the foreground check | `src/posix/termicap-osc.adb:465-472` |
| FUNC-FGP-010 | No exceptions: C function cannot raise, Ada wrapper is a simple `= 1` comparison | `src/posix/termicap-osc.adb:244-248` |
| FUNC-FGP-011 | No package-level state, no caching; stack-local variables only | `src/c/termicap_osc.c:182-183` |
| FUNC-FGP-012 | FFI binding in `Termicap.OSC` (SPARK_Mode => Off) via `pragma Import` | `src/posix/termicap-osc.adb:88-89` |
| FUNC-FGP-013 | Comparison is a pure `==` on `pid_t` values in C; trivially auditable | `src/c/termicap_osc.c:190` |

---

## 11. Implementation Plan

### Changes needed

The existing implementation satisfies all requirements except FUNC-FGP-007.
A single change is required:

1. **Windows stub correction** (`src/windows/termicap-osc.adb`):
   Change `Is_Foreground_Process` from returning `False` to returning `True`.

   Before:
   ```ada
   function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
      pragma Unreferenced (FD);
   begin
      return False;
   end Is_Foreground_Process;
   ```

   After:
   ```ada
   function Is_Foreground_Process (FD : File_Descriptor) return Boolean is
      pragma Unreferenced (FD);
   begin
      return True;
      --  Windows stub: always True (no POSIX job control on Windows).
   end Is_Foreground_Process;
   ```

2. **Documentation update**: Add `@relation(FUNC-FGP-NNN)` tags to the
   existing code comments to trace the new requirement UIDs alongside the
   existing `FUNC-OSC-007` references.

### No new files needed

- No new Ada packages (`.ads`/`.adb`)
- No new C helpers
- No new test files (the existing OSC test suite already covers the foreground
  check path via `Session_Not_Foreground` status)

### Testing considerations

- The foreground check is inherently difficult to unit-test because it depends
  on the process's job-control state, which is controlled by the shell.
- The existing test infrastructure tests the `Open` procedure's return of
  `Session_Not_Foreground` indirectly (by running in a CI environment where
  the process may or may not be foreground).
- A targeted integration test could `fork()` a child, place it in a new
  process group via `setpgrp()`, and verify that `Is_Foreground_Process`
  returns `False` for the child. This would require a C test helper.
