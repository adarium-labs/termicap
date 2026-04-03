# API Reference: `Termicap.Sigwinch`

Package providing asynchronous terminal resize notification via POSIX SIGWINCH, with a self-pipe for I/O multiplexer integration and a polling interface backed by a thread-safe protected object.

**File:** `src/termicap-sigwinch.ads`
**SPARK_Mode:** Off (spec and body)
**License:** Apache-2.0

---

## Overview

`Termicap.Sigwinch` manages the full lifecycle of a SIGWINCH signal handler. When installed, the handler automatically re-queries terminal dimensions via `ioctl(TIOCGWINSZ)` and caches the result in an internal Ada protected object. Applications may choose between two consumption patterns:

- **Polling pattern** — call `Has_Resize` in a loop and retrieve dimensions with `Get_Cached_Size`.
- **Self-pipe / event-loop pattern** — register the FD returned by `Get_Pipe_Read_FD` with `select()`, `poll()`, or `epoll()` and wake up only when a resize actually occurs.

All public operations are thin wrappers around a private protected singleton declared in the package body. The protected object serialises concurrent callers and holds three state items: `Installed`, `Pending`, and `Cached_Size`.

Signal-context work (ioctl re-query, pipe write) is delegated to a C trampoline (`src/c/termicap_sigwinch.c`) that is async-signal-safe by design — no heap allocation, no non-reentrant functions.

The entire package carries `SPARK_Mode => Off`. Ada protected objects with interrupt semantics and dynamic `sigaction` calls are outside the SPARK 2014 language subset. Future work may extract the pure flag-management logic into a SPARK-provable child package.

---

## Lifecycle

### `Install`

```ada
procedure Install (Terminal_FD : Integer := 1);
```

Install the SIGWINCH signal handler and create the self-pipe.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Terminal_FD` | in | File descriptor used for `ioctl(TIOCGWINSZ)` queries inside the signal handler. Defaults to `1` (stdout, consistent with `Termicap.Dimensions.Get_Size`). |

**Behaviour:**

1. Creates a pipe; the write end is set O_NONBLOCK so the C handler never stalls.
2. Performs an initial `ioctl(TIOCGWINSZ)` on `Terminal_FD` and stores the result as `Cached_Size`.
3. Registers the C-level handler via `sigaction()`, saving the previous disposition for `Uninstall`.
4. Sets `Installed := True`, `Pending := False`.

**Idempotent:** calling `Install` when the handler is already installed has no effect.

**Requirements:** FUNC-SWC-001, FUNC-SWC-004, FUNC-SWC-009, FUNC-SWC-010

---

### `Uninstall`

```ada
procedure Uninstall;
```

Uninstall the SIGWINCH signal handler and release all resources.

**Behaviour (ordered):**

1. Restores the previous signal disposition saved at install time via `sigaction()`.
2. Closes the write end of the self-pipe.
3. Closes the read end of the self-pipe.
4. Resets `Pending := False`.
5. Resets `Cached_Size` to the default (80 columns, 24 rows, 0 pixel dimensions).
6. Sets `Installed := False`.

**Idempotent:** calling `Uninstall` when the handler is not installed has no effect.

After this call the FD previously returned by `Get_Pipe_Read_FD` is closed and must not be used.

**Requirements:** FUNC-SWC-001, FUNC-SWC-006

---

## Polling Interface

### `Has_Resize`

```ada
function Has_Resize return Boolean;
```

Report whether a terminal resize event is pending.

**Returns:** `True` if at least one SIGWINCH has been received since `Install` or since the last `Acknowledge_Resize`. `False` when the handler is not installed.

**Non-blocking; no side effects.** Safe to call from multiple tasks concurrently.

**Requirements:** FUNC-SWC-003

---

### `Acknowledge_Resize`

```ada
procedure Acknowledge_Resize;
```

Clear the pending-resize flag.

After this call `Has_Resize` returns `False` until the next SIGWINCH delivery.

`Acknowledge_Resize` is intentionally separate from `Has_Resize`: a SIGWINCH arriving between a `Has_Resize` check and an acknowledgement is preserved by the protected object and will be visible in the next `Has_Resize` call. No-op when the handler is not installed.

**Requirements:** FUNC-SWC-003

---

## Self-Pipe

### `Get_Pipe_Read_FD`

```ada
function Get_Pipe_Read_FD return Integer;
```

Return the read end of the self-pipe for I/O multiplexing.

**Returns:** A non-negative file descriptor when the handler is installed. `-1` (invalid FD) when not installed or on non-Unix platforms.

Callers may register this FD with `select()`, `poll()`, `epoll_ctl()`, or any other I/O multiplexing interface. When the FD becomes readable:

1. Drain the pipe — read and discard all available bytes (loop until `EAGAIN`).
2. Call `Get_Cached_Size` to retrieve the updated dimensions.
3. Call `Acknowledge_Resize` to clear the pending flag.

The FD remains valid for the lifetime of the installed handler and is closed by `Uninstall`.

**Requirements:** FUNC-SWC-005, FUNC-SWC-008

---

## Cached Dimensions

### `Get_Cached_Size`

```ada
function Get_Cached_Size return Termicap.Dimensions.Terminal_Size;
```

Return the most recently cached terminal dimensions.

**Returns:** The `Terminal_Size` captured by the last `ioctl(TIOCGWINSZ)` call, which occurs either at `Install` time or inside the C handler on each SIGWINCH delivery. No new ioctl call is performed.

Returns the default size `(Columns => 80, Rows => 24, Pixel_Width => 0, Pixel_Height => 0)` when the handler is not installed.

Safe to call concurrently from multiple Ada tasks.

**Requirements:** FUNC-SWC-002, FUNC-SWC-010

---

## Usage Patterns

### Polling pattern

```ada
with Termicap.Sigwinch;   use Termicap.Sigwinch;
with Termicap.Dimensions; use Termicap.Dimensions;

procedure Main is
   Size : Terminal_Size;
begin
   Install;   --  handler installed; initial dimensions cached

   loop
      --  ... do application work ...

      if Has_Resize then
         Size := Get_Cached_Size;
         Acknowledge_Resize;
         --  Redraw at Size.Columns x Size.Rows
      end if;
   end loop;

   Uninstall;
end Main;
```

### Self-pipe / event-loop pattern

```ada
with Termicap.Sigwinch;   use Termicap.Sigwinch;
with Termicap.Dimensions; use Termicap.Dimensions;
with Interfaces.C;

procedure Main is
   FD   : constant Integer := -1;  --  placeholder; set after Install
   Size : Terminal_Size;
   Buf  : Character;
   N    : Integer;
begin
   Install;
   FD := Get_Pipe_Read_FD;   --  register with select()/poll()/epoll()

   --  Event loop (pseudocode — use appropriate POSIX binding):
   loop
      --  block in select()/poll()/epoll() watching FD and other FDs

      if FD_is_readable then
         --  Drain all bytes from the pipe before reading state
         loop
            N := C_Read (FD, Buf'Address, 1);
            exit when N < 0;   --  EAGAIN on non-blocking read
         end loop;

         Size := Get_Cached_Size;
         Acknowledge_Resize;
         --  Redraw at Size.Columns x Size.Rows
      end if;

      --  Handle other FDs ...
   end loop;

   Uninstall;
end Main;
```

---

## Platform Notes

On non-Unix platforms (including Windows), SIGWINCH does not exist. The package degrades gracefully:

| Operation | Behaviour on non-Unix |
|-----------|----------------------|
| `Install` | No-op |
| `Uninstall` | No-op |
| `Has_Resize` | Returns `False` |
| `Acknowledge_Resize` | No-op |
| `Get_Pipe_Read_FD` | Returns `-1` |
| `Get_Cached_Size` | Returns default size (80 × 24, 0 pixels) |

No exception is raised on any platform (FUNC-SWC-008).

---

## Thread Safety

All six public operations are safe to call from multiple Ada tasks concurrently. The internal protected singleton enforces mutual exclusion using Ada's built-in protected object semantics. The C signal handler is async-signal-safe: it uses only `ioctl(2)` and `write(2)`, both of which appear on the POSIX async-signal-safe function list (FUNC-SWC-007).

The pending flag and cached size are updated atomically from the perspective of Ada callers. A SIGWINCH that arrives between a `Has_Resize` call that returns `False` and a subsequent `Has_Resize` call will be visible in the later call — it is never silently discarded.

---

## Requirements Traceability

| Requirement | Element |
|-------------|---------|
| FUNC-SWC-001 | `Install` / `Uninstall` — explicit, idempotent lifecycle management |
| FUNC-SWC-002 | `Get_Cached_Size` — reflects automatic ioctl re-query on SIGWINCH |
| FUNC-SWC-003 | `Has_Resize` / `Acknowledge_Resize` — non-blocking polling interface |
| FUNC-SWC-004 | Self-pipe created in `Install`; C handler writes one byte per signal |
| FUNC-SWC-005 | `Get_Pipe_Read_FD` — exposes read end for I/O multiplexers |
| FUNC-SWC-006 | `Uninstall` — ordered cleanup: sigaction restore → pipe close → state reset |
| FUNC-SWC-007 | Protected singleton serialises all concurrent callers |
| FUNC-SWC-008 | No-op / `-1` / default-size degradation on non-Unix platforms |
| FUNC-SWC-009 | `Install (Terminal_FD)` — caller-supplied FD with default of `1` |
| FUNC-SWC-010 | `Get_Cached_Size` returns cached value without a new ioctl call |
| FUNC-SWC-011 | Entire package carries `SPARK_Mode => Off` — documented FFI boundary |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, SPARK boundary diagram, `Termicap.Sigwinch` description
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 15: full SIGWINCH signal flow, installation, delivery, consumption, and uninstallation
- **Tech Spec F8** (`docs/tech-specs/sigwinch.md`) — design rationale, self-pipe pattern, C trampoline decision
- **[Termicap.Dimensions](termicap-dimensions.md)** — source of the `Terminal_Size` type; `Get_Size` for one-shot dimension queries without signal handling
