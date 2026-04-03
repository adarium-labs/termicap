# F8: SIGWINCH Resize Notification

**Feature:** SIGWINCH Resize Notification
**Requirements:** FUNC-SWC-001 through FUNC-SWC-011
**Status:** Proposed
**Date:** 2026-04-03

---

## 1. Overview

This feature adds asynchronous terminal resize notification to Termicap via the POSIX SIGWINCH signal. When installed, a signal handler automatically re-queries terminal dimensions on each SIGWINCH delivery, caches the result in a thread-safe protected object, and writes a notification byte to a self-pipe for integration with I/O multiplexing event loops.

**Scope:**

- Explicit install/uninstall lifecycle (no automatic elaboration-time handler)
- Automatic ioctl(TIOCGWINSZ) re-query inside the signal handler
- Polling interface (Has_Resize / Acknowledge_Resize) for render-loop applications
- Self-pipe trick for select()/poll()/epoll() integration
- Graceful degradation to no-ops on non-Unix platforms

**SPARK level:** Ada FFI boundary -- `SPARK_Mode => Off` on both spec and body. Ada interrupt handlers on protected types and dynamic signal attachment are outside the SPARK 2014 language subset. The package uses `Ada.Interrupts`, C FFI bindings for pipe/fcntl/write/close/sigaction, and protected-object interrupt semantics, none of which GNATprove can verify (FUNC-SWC-011).

---

## 2. Framework Survey

### How reference libraries handle SIGWINCH / resize notification

#### crossterm (Rust) -- signal-hook + mio

crossterm uses the `signal-hook` crate to register a SIGWINCH handler and `signal-hook-mio` to integrate with the mio event loop. On signal receipt, the handler writes to an internal pipe (via the `signal-hook` self-pipe facility). The application's event loop polls the pipe FD alongside other I/O sources. When the pipe becomes readable, crossterm re-queries `ioctl(TIOCGWINSZ)` and emits a `Resize(cols, rows)` event through its unified event stream.

Key pattern: the ioctl re-query happens outside the signal handler (in the event-loop thread), not inside it. This is safe because mio serializes access.

#### termlib (Rust) -- raw self-pipe

termlib implements the self-pipe trick directly: `pipe2(O_NONBLOCK | O_CLOEXEC)`, then installs a `sigaction` handler that writes one byte to the write end. The read end is exposed for caller integration.

Key pattern: ioctl re-query inside the signal handler is avoided; the caller does it after draining the pipe.

#### termenv (Go) -- goroutine + signal.Notify

Go's `os/signal` package delivers signals to a channel. termenv spawns a goroutine that blocks on the channel, re-queries dimensions via `syscall.Syscall(SYS_IOCTL, ...)`, and updates a protected state variable.

Key pattern: channel-based notification replaces the self-pipe; Go's runtime handles the async-signal-safe conversion internally.

#### tcell (Go) -- SIGWINCH + in-band resize

tcell registers SIGWINCH via `signal.Notify` and also supports DEC Private Mode 2048 for in-band resize events. The SIGWINCH path re-queries ioctl and posts a ResizeEvent to the internal event queue.

### Key design decisions derived from the survey

1. **Re-query inside the handler vs. outside:** crossterm and termlib defer the ioctl to the event loop; termenv and tcell do it in the signal-handling context. For Ada, performing the ioctl inside the protected procedure called by the interrupt handler is the most natural fit. `ioctl` is on the POSIX async-signal-safe list, and Ada protected procedures provide the mutual exclusion needed for cache updates. This avoids a race between the signal and a caller reading the cached size.

2. **Self-pipe is universal:** All surveyed libraries that support event-loop integration use some form of the self-pipe trick (or its language-level equivalent like Go channels). The self-pipe is the correct POSIX idiom.

3. **Explicit install is standard:** No surveyed library auto-installs a SIGWINCH handler at import/elaboration time. All require an explicit call, consistent with FUNC-SWC-001.

4. **O_NONBLOCK on write end:** All implementations set the write end non-blocking. A full pipe buffer means there is already an unread notification; discarding the byte is correct (FUNC-SWC-004).

---

## 3. Ada Package Design

### Package name and hierarchy

`Termicap.Sigwinch` -- a direct child of `Termicap`, consistent with the existing flat hierarchy (`Termicap.TTY`, `Termicap.Dimensions`, etc.). It is not a child of `Termicap.Dimensions` because SIGWINCH handling is an independent lifecycle concern: it manages signal disposition, pipe resources, and a cached size, whereas `Termicap.Dimensions` is a stateless detection function.

### Protected object design

A single library-level protected object named `Handler` encapsulates all mutable state (FUNC-SWC-007). This is consistent with the Ada idiom for interrupt-handler state.

**Fields (private):**

| Field | Type | Initial Value | Purpose |
|-------|------|---------------|---------|
| `Installed` | `Boolean` | `False` | Whether the handler is currently active |
| `Pending_Resize` | `Boolean` | `False` | Set by signal, cleared by Acknowledge_Resize |
| `Cached_Size` | `Terminal_Size` | `DEFAULT_SIZE` | Last ioctl result (or default) |
| `Registered_FD` | `Interfaces.C.int` | `STDOUT_FILENO` | FD for ioctl queries |
| `Pipe_Read` | `Interfaces.C.int` | `-1` | Read end of self-pipe |
| `Pipe_Write` | `Interfaces.C.int` | `-1` | Write end of self-pipe (internal) |

`DEFAULT_SIZE` is `(Rows => 24, Columns => 80, Pixel_Width => 0, Pixel_Height => 0)`, matching the `Termicap.Dimensions` defaults (FUNC-SWC-006).

**Operations:**

| Operation | Kind | Description | Requirement |
|-----------|------|-------------|-------------|
| `Install` | Procedure | Create pipe, set O_NONBLOCK, query initial size, attach handler. FD parameter defaults to `STDOUT_FILENO`. Idempotent. | FUNC-SWC-001, FUNC-SWC-004, FUNC-SWC-009, FUNC-SWC-010 |
| `Uninstall` | Procedure | Detach handler, restore previous disposition, close pipe, reset state. Idempotent. | FUNC-SWC-001, FUNC-SWC-006 |
| `Has_Resize` | Function | Returns `Pending_Resize`. Non-blocking, no side effects. | FUNC-SWC-003 |
| `Acknowledge_Resize` | Procedure | Sets `Pending_Resize := False`. | FUNC-SWC-003 |
| `Get_Pipe_Read_FD` | Function | Returns `Pipe_Read` (-1 if not installed). | FUNC-SWC-005 |
| `Get_Cached_Size` | Function | Returns `Cached_Size`. | FUNC-SWC-010 |

The signal handler entry point is an internal protected procedure `Handle_Sigwinch` that performs the ioctl re-query, updates `Cached_Size`, sets `Pending_Resize := True`, and writes one byte to `Pipe_Write` (FUNC-SWC-002, FUNC-SWC-004).

### SPARK_Mode: Off rationale

The package spec carries `SPARK_Mode => Off` because:

- Ada interrupt handlers on protected types use `Ada.Interrupts` semantics outside the SPARK 2014 subset.
- The protected object contains `Interfaces.C.int` fields manipulated via C FFI calls.
- `sigaction`, `pipe`, `fcntl`, `write`, and `close` are bound via `pragma Import (C, ...)`.

This follows the convention established by `Termicap.TTY` and `Termicap.Dimensions` for Ada FFI boundaries (FUNC-SWC-011). Candidates for future SPARK extraction (if tooling supports it) include the pending-flag management logic and the cached-size update logic, which are pure state transitions.

---

## 4. C Binding Layer

### Required C functions

| C Function | POSIX Header | Ada Binding Name | Purpose |
|------------|-------------|-----------------|---------|
| `pipe()` | `<unistd.h>` | `C_Pipe` | Create self-pipe FD pair |
| `fcntl()` | `<fcntl.h>` | `C_Fcntl` | Set `O_NONBLOCK` on write end |
| `write()` | `<unistd.h>` | `C_Write` | Write notification byte in handler |
| `read()` | `<unistd.h>` | `C_Read` | (Not bound; caller drains pipe externally) |
| `close()` | `<unistd.h>` | `C_Close` | Close pipe FDs on uninstall |
| `ioctl(TIOCGWINSZ)` | `<sys/ioctl.h>` | `C_Get_Winsize` | Re-query dimensions (reuse existing binding) |
| `sigaction()` | `<signal.h>` | via C wrapper | Install/restore signal handler |

### Binding approach

Direct `pragma Import (C, ...)` for `pipe`, `fcntl`, `write`, and `close` -- these have fixed signatures unlike `ioctl`. The existing `termicap_get_winsize` C wrapper from `src/c/termicap_ioctl.c` is reused for the ioctl call.

For `sigaction`, a thin C wrapper is required because:
- The `struct sigaction` layout is platform-dependent and contains bitfield/union members that cannot be portably represented in Ada.
- The signal number `SIGWINCH` is a platform-specific constant (typically 28 on Linux, 28 on macOS, but not guaranteed).

The C wrapper provides two fixed-signature functions:

```c
/* termicap_sigwinch.c */

/* Install a SIGWINCH handler that calls the provided callback.
 * Returns 0 on success, -1 on error.
 * Saves the previous sigaction for later restoration. */
int termicap_sigwinch_install(void (*handler)(int));

/* Restore the previous SIGWINCH disposition saved by install.
 * Returns 0 on success, -1 on error. */
int termicap_sigwinch_restore(void);
```

### Signal handler approach: Ada protected procedure with C trampoline

**Recommended approach:** A C-level signal handler trampoline that calls back into Ada.

**Rationale (ADR-0010):**

The Ada RM provides `Ada.Interrupts.Attach_Handler` for binding interrupt handlers to protected procedures. However, SIGWINCH is not guaranteed to be in the set of reserved interrupts on all GNAT targets, and the mapping from POSIX signal numbers to `Ada.Interrupts.Interrupt_ID` is implementation-defined. Using `sigaction` via a C binding gives:

1. **Portability:** The C wrapper handles the platform-specific signal number and `struct sigaction` layout. No dependency on GNAT-specific interrupt ID mappings.
2. **Composability:** `sigaction` returns the previous handler disposition, enabling faithful restoration (FUNC-SWC-006). `Ada.Interrupts.Detach_Handler` restores to the default disposition, not to whatever was installed before Termicap.
3. **Consistency:** Matches the C-wrapper pattern already established in the project (ADR-0006, `termicap_ioctl.c`).

The C signal handler is a minimal trampoline that:
1. Calls `termicap_get_winsize(fd, &cols, &rows, &xpixel, &ypixel)` to re-query dimensions.
2. Writes one byte to the self-pipe write FD.
3. Calls back into Ada (via an exported procedure) to update the protected object state.

**Alternative considered:** Pure Ada `Ada.Interrupts.Attach_Handler`. Rejected because it cannot portably save/restore the previous signal disposition, and the interrupt ID for SIGWINCH is GNAT-implementation-specific.

**Alternative considered:** Performing the entire handler in C (ioctl + pipe write + state update in C global variables). Rejected because it would duplicate the protected-object thread safety that Ada provides natively, and would require manual locking in C.

### Revised C wrapper design

To keep the signal handler fully async-signal-safe, the C trampoline performs only async-signal-safe operations (ioctl, write) and stores results in C-side global variables. The Ada side reads these values when `Has_Resize` or `Get_Cached_Size` is called.

```c
/* termicap_sigwinch.c -- C wrapper for SIGWINCH handling */

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <errno.h>

static struct sigaction old_action;
static int registered_fd   = 1;
static int pipe_write_fd   = -1;

/* Volatile state updated by the signal handler, read by Ada */
static volatile sig_atomic_t resize_pending = 0;
static volatile unsigned short cached_cols   = 80;
static volatile unsigned short cached_rows   = 24;
static volatile unsigned short cached_xpixel = 0;
static volatile unsigned short cached_ypixel = 0;

static void sigwinch_handler(int sig) {
    (void)sig;
    struct winsize ws;
    if (ioctl(registered_fd, TIOCGWINSZ, &ws) == 0) {
        cached_cols   = ws.ws_col;
        cached_rows   = ws.ws_row;
        cached_xpixel = ws.ws_xpixel;
        cached_ypixel = ws.ws_ypixel;
    }
    resize_pending = 1;
    if (pipe_write_fd >= 0) {
        char byte = 1;
        int saved_errno = errno;
        write(pipe_write_fd, &byte, 1);  /* ignore EAGAIN */
        errno = saved_errno;
    }
}

int termicap_sigwinch_install(int fd, int write_fd) {
    struct sigaction sa;
    registered_fd = fd;
    pipe_write_fd = write_fd;
    resize_pending = 0;

    /* Initial dimension query */
    struct winsize ws;
    if (ioctl(fd, TIOCGWINSZ, &ws) == 0) {
        cached_cols   = ws.ws_col;
        cached_rows   = ws.ws_row;
        cached_xpixel = ws.ws_xpixel;
        cached_ypixel = ws.ws_ypixel;
    }

    sa.sa_handler = sigwinch_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    return sigaction(SIGWINCH, &sa, &old_action);
}

int termicap_sigwinch_restore(void) {
    pipe_write_fd = -1;
    resize_pending = 0;
    cached_cols   = 80;
    cached_rows   = 24;
    cached_xpixel = 0;
    cached_ypixel = 0;
    return sigaction(SIGWINCH, &old_action, NULL);
}

int termicap_sigwinch_pending(void) {
    return resize_pending;
}

void termicap_sigwinch_acknowledge(void) {
    resize_pending = 0;
}

void termicap_sigwinch_get_size(unsigned short *cols,
                                 unsigned short *rows,
                                 unsigned short *xpixel,
                                 unsigned short *ypixel) {
    *cols   = cached_cols;
    *rows   = cached_rows;
    *xpixel = cached_xpixel;
    *ypixel = cached_ypixel;
}
```

This design keeps all signal-handler logic in C (async-signal-safe) and exposes read-only query functions that the Ada protected object delegates to. The Ada protected object adds thread-safety serialization on top.

---

## 5. Self-Pipe Implementation Detail

### Pipe creation at install time

1. Call `pipe()` to create a pair of file descriptors: `Pipe_FDs(0)` (read) and `Pipe_FDs(1)` (write).
2. If `pipe()` returns -1, the install fails silently (the handler is installed without self-pipe capability; `Get_Pipe_Read_FD` returns -1).
3. Set `O_NONBLOCK` on the write end via `fcntl(Pipe_FDs(1), F_SETFL, O_NONBLOCK)`. This prevents the signal handler from blocking if the pipe buffer is full.
4. Optionally set `O_CLOEXEC` on both ends to prevent FD leakage to child processes (defense in depth; not required by the specification).
5. Store `Pipe_FDs(0)` as the read FD (exposed via `Get_Pipe_Read_FD`) and pass `Pipe_FDs(1)` to the C wrapper as the write FD.

### Signal handler body (in C)

The C signal handler (`sigwinch_handler`) performs exactly three async-signal-safe operations:

1. **ioctl re-query:** `ioctl(registered_fd, TIOCGWINSZ, &ws)`. On success, cache the result. On failure, retain previous values (FUNC-SWC-002).
2. **Set pending flag:** `resize_pending = 1` (sig_atomic_t write is atomic by POSIX definition).
3. **Pipe write:** `write(pipe_write_fd, &byte, 1)`. If the write returns -1 with `errno == EAGAIN`, the byte is silently discarded -- the pipe already contains unread data, so the read end is already readable (FUNC-SWC-004). `errno` is saved and restored around the write call.

### Drain contract for callers

When `Get_Pipe_Read_FD` returns a valid FD (>= 0) and the FD becomes readable (via `select`/`poll`/`epoll`), the caller must:

1. Read and discard all available bytes from the FD (loop `read()` until EAGAIN or 0).
2. Call `Get_Cached_Size` or `Has_Resize` / `Acknowledge_Resize` to consume the notification.

Failing to drain the pipe will cause the FD to remain permanently readable, which is harmless but wasteful -- subsequent SIGWINCH deliveries may find the pipe full and discard their notification bytes. The resize information is still available via `Has_Resize` and `Get_Cached_Size` regardless of pipe state.

---

## 6. Platform Portability

### Platform detection strategy

**Compile-time variant body selection** via the Alire/GPRbuild build system.

The package spec (`termicap-sigwinch.ads`) is identical across all platforms. Two body files exist:

| File | Platform | Content |
|------|----------|---------|
| `src/termicap-sigwinch.adb` | Unix (Linux, macOS, BSDs) | Full implementation with C bindings |
| `src/termicap-sigwinch__windows.adb` | Windows | Stub no-op body |

The GPR project file selects the body variant based on `System.OS_Constants` or a custom GPR scenario variable:

```
for Body ("Termicap.Sigwinch") use "termicap-sigwinch" & Platform_Suffix & ".adb";
```

Alternatively, a single body with compile-time `if` using GNAT `System.OS_Constants`:

```ada
if System.OS_Constants.Target_OS = System.OS_Constants.Windows then
   --  no-op stubs
else
   --  real implementation
end if;
```

The variant-body approach is preferred because it avoids dead code in the compiled binary and makes the platform boundary explicit.

### Stub body for non-Unix

On non-Unix platforms, all operations degrade gracefully (FUNC-SWC-008):

| Operation | Stub Behavior |
|-----------|---------------|
| `Install` | No-op, returns immediately |
| `Uninstall` | No-op, returns immediately |
| `Has_Resize` | Returns `False` |
| `Acknowledge_Resize` | No-op |
| `Get_Pipe_Read_FD` | Returns `-1` |
| `Get_Cached_Size` | Returns `DEFAULT_SIZE` (80x24, 0 pixels) |

The C file `termicap_sigwinch.c` is excluded from the Windows build via GPR source file filtering.

---

## 7. Ada Spec Sketch (`.ads`)

```ada
-------------------------------------------------------------------------------
--  Termicap.Sigwinch - SIGWINCH Resize Notification
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Provides asynchronous terminal resize notification via POSIX SIGWINCH,
--  with a self-pipe for I/O loop integration and a polling interface.
--
--  @description
--  This package manages a SIGWINCH signal handler lifecycle.  When installed,
--  the handler automatically re-queries terminal dimensions via
--  ioctl(TIOCGWINSZ) and caches the result.  Applications can poll for
--  resize events or integrate with select()/poll() via the self-pipe read FD.
--
--  This package is an Ada FFI boundary and does not carry SPARK provability.
--  Ada interrupt handlers on protected types and dynamic signal attachment
--  are outside the SPARK 2014 language subset.  Candidates for future SPARK
--  extraction: pending-flag management, cached-size update logic.
--
--  Requirements Coverage:
--    - @relation(FUNC-SWC-001): Signal handler installation and removal
--    - @relation(FUNC-SWC-002): Automatic dimension re-query on SIGWINCH
--    - @relation(FUNC-SWC-003): Resize event polling interface
--    - @relation(FUNC-SWC-004): Self-pipe write on SIGWINCH
--    - @relation(FUNC-SWC-005): Pipe read FD exposure
--    - @relation(FUNC-SWC-006): Handler cleanup and resource release
--    - @relation(FUNC-SWC-007): Thread safety via Ada protected object
--    - @relation(FUNC-SWC-008): Graceful degradation on non-Unix
--    - @relation(FUNC-SWC-009): Registered file descriptor at install time
--    - @relation(FUNC-SWC-010): Current cached dimensions retrieval
--    - @relation(FUNC-SWC-011): SPARK boundary declaration

with Termicap.Dimensions;
with Interfaces.C;

package Termicap.Sigwinch
   with SPARK_Mode => Off
is

   ---------------------------------------------------------------------------
   --  Constants
   ---------------------------------------------------------------------------

   --  @summary Default file descriptor used for ioctl queries when none
   --  is specified by the caller.
   STDOUT_FILENO : constant Interfaces.C.int := 1;

   --  @summary Default terminal size returned when the handler is not
   --  installed or on non-Unix platforms.
   DEFAULT_SIZE : constant Termicap.Dimensions.Terminal_Size :=
      (Rows         => Termicap.Dimensions.DEFAULT_ROWS,
       Columns      => Termicap.Dimensions.DEFAULT_COLUMNS,
       Pixel_Width  => 0,
       Pixel_Height => 0);

   --  @summary Sentinel value indicating no valid file descriptor.
   INVALID_FD : constant Interfaces.C.int := -1;

   ---------------------------------------------------------------------------
   --  Protected Object (FUNC-SWC-007)
   ---------------------------------------------------------------------------

   protected Handler is

      -----------------------------------------------------------------
      --  Lifecycle (FUNC-SWC-001, FUNC-SWC-006, FUNC-SWC-009)
      -----------------------------------------------------------------

      --  @summary Install the SIGWINCH handler and create the self-pipe.
      --  @param FD  File descriptor to use for ioctl(TIOCGWINSZ) queries.
      --             Defaults to STDOUT_FILENO.  Pass INVALID_FD to use the
      --             default.
      --  @relation(FUNC-SWC-001): Explicit installation, idempotent
      --  @relation(FUNC-SWC-004): Creates self-pipe with O_NONBLOCK
      --  @relation(FUNC-SWC-009): Accepts FD parameter
      --  @relation(FUNC-SWC-010): Performs initial ioctl query
      procedure Install (FD : Interfaces.C.int := STDOUT_FILENO);

      --  @summary Uninstall the SIGWINCH handler and release all resources.
      --  @relation(FUNC-SWC-001): Explicit removal, idempotent
      --  @relation(FUNC-SWC-006): Ordered cleanup steps
      procedure Uninstall;

      -----------------------------------------------------------------
      --  Polling Interface (FUNC-SWC-003)
      -----------------------------------------------------------------

      --  @summary Check whether a resize event is pending.
      --  @return True if at least one SIGWINCH has been received since
      --          installation or last acknowledgement.
      --  @relation(FUNC-SWC-003): Non-blocking polling
      function Has_Resize return Boolean;

      --  @summary Clear the pending-resize flag.
      --  @relation(FUNC-SWC-003): Acknowledgement clears flag
      procedure Acknowledge_Resize;

      -----------------------------------------------------------------
      --  Self-Pipe (FUNC-SWC-004, FUNC-SWC-005)
      -----------------------------------------------------------------

      --  @summary Return the read end of the self-pipe for I/O loop
      --           integration.
      --  @return A non-negative FD when installed; INVALID_FD (-1) when
      --          not installed or on non-Unix platforms.
      --  @relation(FUNC-SWC-005): Pipe read FD exposure
      function Get_Pipe_Read_FD return Interfaces.C.int;

      -----------------------------------------------------------------
      --  Cached Dimensions (FUNC-SWC-002, FUNC-SWC-010)
      -----------------------------------------------------------------

      --  @summary Return the most recently cached terminal dimensions.
      --  @return The dimensions from the last ioctl query (either at
      --          install time or triggered by SIGWINCH).  Returns
      --          DEFAULT_SIZE if the handler is not installed.
      --  @relation(FUNC-SWC-002): Reflects automatic re-query results
      --  @relation(FUNC-SWC-010): No new ioctl call; returns cached value
      function Get_Cached_Size return Termicap.Dimensions.Terminal_Size;

   private

      Installed      : Boolean                            := False;
      Pending_Resize : Boolean                            := False;
      Cached_Size    : Termicap.Dimensions.Terminal_Size  := DEFAULT_SIZE;
      Registered_FD  : Interfaces.C.int                   := STDOUT_FILENO;
      Pipe_Read      : Interfaces.C.int                   := INVALID_FD;
      Pipe_Write     : Interfaces.C.int                   := INVALID_FD;

   end Handler;

end Termicap.Sigwinch;
```

### Notes on the spec

- The protected object `Handler` is declared at library level, making it a singleton. This is intentional: there is exactly one SIGWINCH handler per process.
- `Install` and `Uninstall` are protected procedures (serialized, read-write access). `Has_Resize`, `Get_Pipe_Read_FD`, and `Get_Cached_Size` are protected functions (concurrent reads allowed).
- `Acknowledge_Resize` is a protected procedure because it modifies `Pending_Resize`.
- The `FD` parameter in `Install` defaults to `STDOUT_FILENO`. If the caller passes `INVALID_FD` (-1), the implementation treats it as `STDOUT_FILENO` (FUNC-SWC-009).
- The type `Terminal_Size` is reused from `Termicap.Dimensions` rather than redeclared, maintaining a single canonical type for terminal dimensions.

---

## 8. Traceability

| Requirement | Design Element |
|-------------|---------------|
| FUNC-SWC-001 | `Handler.Install` / `Handler.Uninstall` procedures with idempotency guards (`if Installed then return` / `if not Installed then return`) |
| FUNC-SWC-002 | C signal handler calls `ioctl(TIOCGWINSZ)` and stores result in `volatile` globals; Ada `Get_Cached_Size` reads via C query function |
| FUNC-SWC-003 | `Handler.Has_Resize` (protected function) and `Handler.Acknowledge_Resize` (protected procedure) |
| FUNC-SWC-004 | Pipe creation in `Install` with `fcntl(F_SETFL, O_NONBLOCK)` on write end; C handler writes one byte, ignores EAGAIN |
| FUNC-SWC-005 | `Handler.Get_Pipe_Read_FD` returns `Pipe_Read` field; returns `INVALID_FD` when not installed |
| FUNC-SWC-006 | `Handler.Uninstall` performs ordered cleanup: (1) `termicap_sigwinch_restore`, (2) close write FD, (3) close read FD, (4) reset `Pending_Resize`, (5) reset `Cached_Size` to `DEFAULT_SIZE` |
| FUNC-SWC-007 | All mutable state in a single `protected Handler` object; all public operations are protected functions/procedures |
| FUNC-SWC-008 | Variant body (`termicap-sigwinch__windows.adb`) provides no-op stubs; `Get_Pipe_Read_FD` returns -1; `Has_Resize` returns False |
| FUNC-SWC-009 | `Install (FD : Interfaces.C.int := STDOUT_FILENO)` parameter; stored in `Registered_FD`, passed to C install function |
| FUNC-SWC-010 | `Handler.Get_Cached_Size` returns cached value; initial ioctl query performed in `Install` via C `termicap_sigwinch_install` |
| FUNC-SWC-011 | `SPARK_Mode => Off` on package spec; comment in spec header documents FFI boundary status and SPARK extraction candidates |

---

## 9. ADR: Signal Handler Mechanism (ADR-0010)

**Title:** C trampoline signal handler vs. Ada.Interrupts.Attach_Handler for SIGWINCH

**Status:** Proposed

**Context:**

Termicap needs to install a SIGWINCH handler that re-queries terminal dimensions and writes a notification byte to a self-pipe. Ada provides `Ada.Interrupts.Attach_Handler` for binding interrupt handlers to protected procedures. Alternatively, the handler can be installed via `sigaction()` through a C binding, with the C handler performing the async-signal-safe operations directly.

**Decision:**

Use a C-level signal handler installed via `sigaction()`, with the handler performing the ioctl re-query and pipe write in C. The Ada protected object synchronizes access to the state by delegating reads to C query functions within its protected functions/procedures.

**Consequences:**

- (+) **Previous disposition restoration:** `sigaction` returns the previous `struct sigaction`, enabling faithful restoration on uninstall. `Ada.Interrupts.Detach_Handler` restores to SIG_DFL, losing any previous application handler.
- (+) **Portability:** No dependency on GNAT-specific `Interrupt_ID` mappings for SIGWINCH.
- (+) **Async-signal-safety:** The C handler performs only `ioctl` (async-signal-safe), `write` (async-signal-safe), and volatile writes. No Ada runtime calls from signal context.
- (+) **Consistency:** Follows the established C-wrapper pattern (ADR-0006).
- (-) State is split between C globals and the Ada protected object, adding a small amount of complexity.
- (-) The C file must be excluded from non-Unix builds.

**Recommendation:** Create `docs/adr/0010-sigwinch-c-trampoline-handler.md` with the full ADR when implementation begins.
