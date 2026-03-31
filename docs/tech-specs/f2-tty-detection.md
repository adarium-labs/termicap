# F2: TTY Detection

**Feature:** TTY (Terminal Teletype) Detection
**Requirements:** FUNC-TTY-001 through FUNC-TTY-006
**Status:** Approved
**Date:** 2026-03-31

---

## A. Framework Survey

### How reference libraries handle TTY detection

#### go-isatty (Go) -- Dedicated TTY detection library

go-isatty provides a single `IsTerminal(fd uintptr) bool` function with platform-specific implementations:

- **BSD/macOS**: `unix.IoctlGetTermios(int(fd), unix.TIOCGETA)` -- returns `err == nil`
- **Linux**: `unix.IoctlGetTermios(int(fd), unix.TCGETS)` -- returns `err == nil`
- **Windows**: `GetConsoleMode(handle, &mode)` -- returns success boolean
- **Cygwin**: Inspects pipe name via `GetFileInformationByHandleEx` for `\cygwin-*-pty*` or `\msys-*-pty*` patterns

The pattern is consistent: attempt a terminal-specific ioctl, and return whether it succeeded. No error propagation -- failure means "not a TTY".

**Strengths:**
- Exhaustive platform coverage (Linux, macOS, FreeBSD, OpenBSD, NetBSD, DragonFly, Solaris, AIX, Plan 9, Windows, Cygwin/MSYS2).
- Clean error-to-boolean mapping: any error means "not a TTY".
- Separate `IsCygwinTerminal` function for the Windows edge case.

**Weaknesses:**
- Takes a raw `uintptr` fd -- no type safety for stream identification.
- Callers must know the correct fd numbers (0, 1, 2).

#### crossterm (Rust) -- Trait-based IsTty

crossterm defines an `IsTty` trait with blanket implementations:

```rust
#[cfg(unix)]
impl<S: AsRawFd> IsTty for S {
    fn is_tty(&self) -> bool {
        let fd = self.as_raw_fd();
        unsafe { libc::isatty(fd) == 1 }
    }
}
```

On Windows, it uses `GetConsoleMode` instead. The trait approach allows `stdout().is_tty()` syntax.

**Strengths:**
- Type-safe: only types with file descriptors can be queried.
- `libc::isatty(fd) == 1` is the simplest possible POSIX implementation.

**Weaknesses:**
- Trait dispatch adds complexity unnecessary for our use case.

#### termwiz (Rust, from WezTerm) -- Same pattern

Identical to crossterm: `libc::isatty(fd) == 1` on Unix, `GetConsoleMode` on Windows.

#### supports-color (Rust) -- Inline isatty in detection flow

rust-supports-color uses `is-terminal` crate (which wraps `libc::isatty`) as a gate in its color detection algorithm. TTY status is checked per-stream (`Stream::Stdout`, `Stream::Stderr`) and used as a disqualifier: if the stream is not a TTY and no force-color override is active, color support is `None`.

**Strengths:**
- Stream enum (`Stdout`, `Stderr`) gives type safety over raw fd numbers.
- TTY check is integrated into the detection priority chain.

#### termenv (Go) -- isatty as TTY gate

termenv uses go-isatty internally via `o.isTTY()` as the first check in `ColorProfile()`:

```go
func (o *Output) ColorProfile() Profile {
    if !o.isTTY() {
        return Ascii
    }
    // ... env var detection follows
}
```

### What Termicap should adopt and why

Termicap should adopt the following patterns:

1. **POSIX `isatty()` via `pragma Import (C, ...)`**: The universal POSIX approach. All reference frameworks ultimately call `isatty(fd)` on Unix. This is simpler and more portable than ioctl-based approaches (go-isatty uses ioctl internally, but `isatty()` wraps the same logic in the C library).

2. **Stream_Kind enumeration** (inspired by rust-supports-color's `Stream` enum): Provides type safety over raw file descriptor numbers. Callers never need to know that stdout is fd 1.

3. **Error-to-False mapping** (universal pattern): All reference frameworks treat any error from the TTY query as "not a TTY". Termicap follows suit -- `Is_TTY` returns `False` on error, never raises exceptions.

4. **Independent package** (not a child of `Termicap.Environment`): TTY detection is an OS syscall, not an environment variable query. The reference frameworks keep these concerns separate (go-isatty is a standalone package, supports-color's `Stream` enum is separate from env var handling).

See [ADR-0003](../adr/0003-tty-detection-package-structure.md) for the package structure rationale.

---

## B. Package Design

### Package hierarchy

```
Termicap                          (root namespace -- no types or subprograms)
├── Termicap.Environment          [SPARK Silver] -- environment snapshot (F1)
│   └── Termicap.Environment.Capture  [SPARK_Mode => Off] -- OS FFI boundary
└── Termicap.TTY                  [spec: SPARK, body: SPARK_Mode => Off] -- TTY detection
```

### SPARK boundaries

| Package | SPARK_Mode (spec) | SPARK_Mode (body) | Rationale |
|---------|------------------|------------------|-----------|
| `Termicap.TTY` | On | Off | Spec declares pure types and function signatures (SPARK-provable). Body calls C `isatty()` via FFI (not provable). |

### Why a single package, not a parent/child split

Unlike `Termicap.Environment` which has a SPARK-provable body (pure map operations) and a separate `Capture` child for FFI, `Termicap.TTY` has no pure logic to prove in the body. Every public function ultimately calls `isatty()`. Splitting into `Termicap.TTY` (spec only) + `Termicap.TTY.Binding` (body) would add a package boundary for zero verification benefit.

The pattern is: **SPARK spec for type safety and contract documentation, Ada body for the FFI call.** This is the simplest correct boundary.

### Relationship to other packages

`Termicap.TTY` has **no dependency** on `Termicap.Environment`. They are independent foundational building blocks. Downstream detection packages (e.g., `Termicap.Detection`) will use both:

- `Termicap.Environment` for env var queries (NO_COLOR, TERM, COLORTERM, etc.)
- `Termicap.TTY` for the TTY gate in color detection

---

## C. Type Design

### Stream_Kind enumeration (FUNC-TTY-001)

```ada
type Stream_Kind is (Stdin, Stdout, Stderr);
```

This is a simple enumeration with three values matching the POSIX standard streams. The mapping to file descriptors is an internal implementation detail:

| Stream_Kind | File Descriptor |
|-------------|----------------|
| `Stdin`     | 0              |
| `Stdout`    | 1              |
| `Stderr`    | 2              |

The fd mapping is encapsulated in the package body via a lookup array, not exposed in the spec.

### TTY_Status record type (FUNC-TTY-006)

For the bulk query function, a record type indexed by the three streams:

```ada
type TTY_Status is record
   Stdin  : Boolean;
   Stdout : Boolean;
   Stderr : Boolean;
end record;
```

**Why a record, not an array indexed by Stream_Kind:**

An `array (Stream_Kind) of Boolean` was considered. While slightly more concise, the record type offers clearer named access at call sites (`Status.Stdout` vs `Status (Stdout)`) and is marginally more readable in documentation and assertions. Both are SPARK-compatible; the record was chosen for readability.

See [ADR-0003](../adr/0003-tty-detection-package-structure.md) for this decision.

---

## D. SPARK Strategy

### SPARK_Mode placement

```ada
package Termicap.TTY
   with SPARK_Mode
is
   --  All type declarations and function signatures are SPARK-visible.
   --  Contracts are documented but cannot be machine-verified for Is_TTY
   --  because the implementation calls C code.
end Termicap.TTY;

package body Termicap.TTY
   with SPARK_Mode => Off
is
   --  Contains pragma Import (C, ...) for isatty().
   --  Not verifiable by GNATprove.
end Termicap.TTY;
```

### What is provable

| Element | SPARK Provable | Reason |
|---------|---------------|--------|
| `Stream_Kind` type | Yes | Enumeration type, fully SPARK |
| `TTY_Status` type | Yes | Record of Booleans, fully SPARK |
| `Is_TTY` signature | Yes | Function signature with contract is SPARK-visible |
| `Is_TTY` body | No | Calls C `isatty()` via FFI |
| `Query_All` signature | Yes | Function signature with contract is SPARK-visible |
| `Query_All` body | No | Calls `Is_TTY` which calls C FFI |

### Global contracts

Since `Is_TTY` reads external OS state (the file descriptor table), it cannot have `Global => null`. The spec does not declare a `Global` contract for `Is_TTY` because:

1. The body is `SPARK_Mode => Off`, so GNATprove does not analyze it.
2. Declaring `Global => null` would be a lie -- `isatty()` reads kernel state.
3. Downstream SPARK packages that call `Is_TTY` will themselves need `SPARK_Mode => Off` at the call site, or will call it from an Ada-only region.

This is the same pattern used by `Termicap.Environment.Capture`: the FFI boundary is explicitly outside the SPARK verification perimeter.

### How downstream packages use Is_TTY

Downstream detection logic (e.g., color level detection) will capture the TTY status once and pass it as a Boolean parameter to SPARK-provable detection functions:

```ada
--  In application code or detection init (SPARK_Mode => Off region):
Is_Interactive : constant Boolean := Termicap.TTY.Is_TTY (Stdout);

--  In SPARK-provable detection function:
function Detect_Color_Level
   (Env            : Termicap.Environment.Environment;
    Is_Interactive : Boolean) return Color_Level
   with Global => null;
```

This preserves the SPARK boundary: the `Is_TTY` call happens once in an Ada-only region, and the result flows as a plain `Boolean` into the provable detection chain.

---

## E. API Signatures

```ada
-------------------------------------------------------------------------------
--  Termicap.TTY - Terminal Teletype Detection
--
--  Copyright (c) 2026 Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  Detects whether standard I/O streams are connected to an interactive
--  terminal (TTY).
--
--  @description
--  Provides per-stream TTY detection using the POSIX isatty() system call.
--  The package spec is SPARK-annotated for type safety; the body uses
--  SPARK_Mode => Off for the C FFI binding.
--
--  All detection functions are safe and non-destructive: they return False
--  on error and never raise exceptions or modify terminal state.
--
--  Requirements Coverage:
--    - @relation(FUNC-TTY-001): Stream_Kind enumeration type
--    - @relation(FUNC-TTY-002): Per-stream TTY detection
--    - @relation(FUNC-TTY-003): POSIX isatty() binding
--    - @relation(FUNC-TTY-004): Safe, non-destructive query
--    - @relation(FUNC-TTY-005): SPARK boundary
--    - @relation(FUNC-TTY-006): Bulk TTY status query

package Termicap.TTY
   with SPARK_Mode
is

   ---------------------------------------------------------------------------
   --  Types (FUNC-TTY-001)
   ---------------------------------------------------------------------------

   --  @summary Identifies a standard I/O stream.
   --  @relation(FUNC-TTY-001): Stream kind enumeration
   type Stream_Kind is (Stdin, Stdout, Stderr);

   --  @summary TTY status for all three standard streams.
   --  @relation(FUNC-TTY-006): Bulk query result type
   type TTY_Status is record
      Stdin  : Boolean;
      Stdout : Boolean;
      Stderr : Boolean;
   end record;

   ---------------------------------------------------------------------------
   --  Per-Stream Detection (FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004)
   ---------------------------------------------------------------------------

   --  @summary Check whether a standard stream is connected to a terminal.
   --  @param Stream The stream to query.
   --  @return True if the stream is connected to an interactive terminal,
   --          False otherwise (including when the stream handle is invalid
   --          or the query fails for any reason).
   --  @relation(FUNC-TTY-002): Per-stream TTY detection
   --  @relation(FUNC-TTY-003): Uses POSIX isatty() internally
   --  @relation(FUNC-TTY-004): Returns False on error, never raises
   function Is_TTY (Stream : Stream_Kind) return Boolean;

   ---------------------------------------------------------------------------
   --  Bulk Query (FUNC-TTY-006)
   ---------------------------------------------------------------------------

   --  @summary Query TTY status for all three streams at once.
   --  @return A record containing the TTY status of Stdin, Stdout, and Stderr.
   --  @relation(FUNC-TTY-006): Convenience function reducing FFI calls
   function Query_All return TTY_Status;

end Termicap.TTY;
```

---

## F. Error Handling

### Analysis: Is error handling needed?

The POSIX `isatty()` function has a well-defined error model:

- Returns `1` if the file descriptor refers to a terminal.
- Returns `0` and sets `errno` if not (common errors: `EBADF` for invalid fd, `ENOTTY` for non-terminal fd).

All reference frameworks follow the same pattern: **map any non-1 return to `False`**. This is correct because:

1. `isatty()` is a read-only query -- it cannot corrupt state.
2. The only meaningful distinction is "is a TTY" vs "is not a TTY". The specific reason for "not a TTY" (bad fd, pipe, file, etc.) is irrelevant for terminal capability detection.
3. FUNC-TTY-004 explicitly requires: "return False rather than raising an exception if the stream handle is invalid or unavailable."

**Conclusion: No Result types or exception handling needed.** The `Is_TTY` function returns `Boolean` directly. Any C-level error is absorbed into `False`.

The implementation maps the return value as:

```ada
function Is_TTY (Stream : Stream_Kind) return Boolean is
begin
   return C_Isatty (FD_MAP (Stream)) = 1;
end Is_TTY;
```

If `C_Isatty` returns 0 (or any value other than 1), `Is_TTY` returns `False`. No exception can propagate from a `pragma Import (C, ...)` function that returns `int`.

---

## G. Platform Considerations

### Current scope: POSIX only

Termicap targets POSIX systems (Linux, macOS, FreeBSD) for the initial release. The `isatty()` function is available on all POSIX-compliant systems and is part of the C standard library (`<unistd.h>`).

### Windows future work

Windows TTY detection requires a different mechanism:

- **Console**: `GetConsoleMode(handle, &mode)` succeeds if the handle is a console.
- **Cygwin/MSYS2 PTYs**: Pipe name inspection via `GetFileInformationByHandleEx` (as implemented by go-isatty).
- **Windows Terminal**: `WT_SESSION` env var indicates Windows Terminal, but this is a color capability hint, not a TTY check.

When Windows support is added, the approach will be:

1. The `.ads` spec remains unchanged (SPARK, platform-independent).
2. A platform-specific body selection mechanism (e.g., separate `.adb` files with GPR `case` on `Target`) will provide the Windows implementation.
3. The Windows body will use `pragma Import (Stdcall, ...)` for Win32 API calls.

This is a future concern and does not affect the current design.

### macOS-specific note

go-isatty on macOS uses `TIOCGETA` ioctl instead of `TCGETS`. However, since Termicap uses `isatty()` from the C library (not raw ioctls), the C library handles the platform-specific ioctl selection internally. No special handling is needed.

---

## H. Dependencies

### From `functional` crate

Nothing. This package does not use Result types (see Section F).

### From `sparklib` crate

Nothing. This package uses only basic Ada types (`Boolean`, enumerations, records).

### From the Ada standard library

- `Interfaces.C` -- for the `int` type used by the `isatty()` C binding.

### External C library dependency

- `isatty()` from `<unistd.h>` (POSIX) -- linked automatically by the GNAT runtime on POSIX systems. No additional linker flags are needed.

### New dependencies

None required. This is a zero-dependency package (beyond the GNAT runtime and C library).

---

## I. File Layout

| File | SPARK | Description |
|------|-------|-------------|
| `src/termicap-tty.ads` | Yes | Stream_Kind type, TTY_Status type, Is_TTY, Query_All |
| `src/termicap-tty.adb` | No (SPARK_Mode => Off) | C binding via pragma Import, fd mapping, implementation |

### File naming rationale

File names follow the Ada convention of lowercase with dashes matching the package hierarchy:
- `Termicap.TTY` maps to `termicap-tty.ads` / `.adb`

No changes to `termicap.gpr` are needed since all files are in the existing `src/` source directory.

---

## J. Testing Strategy

### Challenge: automated testing of isatty()

TTY detection is inherently difficult to test in automated environments:

- **CI pipelines** (GitHub Actions, GitLab CI, etc.) run without a TTY. `Is_TTY` will return `False` for all streams.
- **Redirected output** in test runners similarly produces `False`.
- There is no portable way to create a pseudo-TTY from Ada without OS-specific `posix_openpt`/`openpty` calls.

### What can be tested

#### 1. Stream_Kind type properties

Verify the enumeration has exactly three values and the expected representation:

```ada
pragma Assert (Stream_Kind'First = Stdin);
pragma Assert (Stream_Kind'Last  = Stderr);
pragma Assert (Stream_Kind'Pos (Stdin)  = 0);
pragma Assert (Stream_Kind'Pos (Stdout) = 1);
pragma Assert (Stream_Kind'Pos (Stderr) = 2);
```

#### 2. TTY_Status record structure

Verify the bulk result type stores three independent Boolean values:

```ada
declare
   Status : TTY_Status := (Stdin => True, Stdout => False, Stderr => True);
begin
   pragma Assert (Status.Stdin  = True);
   pragma Assert (Status.Stdout = False);
   pragma Assert (Status.Stderr = True);
end;
```

#### 3. Is_TTY returns Boolean without raising

Call `Is_TTY` for all three streams and verify no exception is raised. In a CI environment, all three are expected to return `False`:

```ada
declare
   Result_In  : constant Boolean := Is_TTY (Stdin);
   Result_Out : constant Boolean := Is_TTY (Stdout);
   Result_Err : constant Boolean := Is_TTY (Stderr);
begin
   --  In CI, all should be False. The key assertion is that
   --  no exception was raised and all returned valid Booleans.
   null;
end;
```

#### 4. Query_All consistency

Verify that `Query_All` returns the same results as three individual `Is_TTY` calls:

```ada
declare
   Status : constant TTY_Status := Query_All;
begin
   pragma Assert (Status.Stdin  = Is_TTY (Stdin));
   pragma Assert (Status.Stdout = Is_TTY (Stdout));
   pragma Assert (Status.Stderr = Is_TTY (Stderr));
end;
```

#### 5. CI-specific expectation test

In CI environments, document that all streams are expected to be non-TTY:

```ada
--  This test documents expected CI behavior.
--  When run in an interactive terminal, these assertions will fail,
--  which is correct and expected.
if Ada.Environment_Variables.Exists ("CI") then
   pragma Assert (not Is_TTY (Stdout));
   pragma Assert (not Is_TTY (Stderr));
end if;
```

#### 6. Manual/interactive testing

For interactive terminal testing, an example program (not part of the automated test suite) can be provided:

```ada
with Ada.Text_IO;
with Termicap.TTY;

procedure TTY_Demo is
   use Termicap.TTY;
   Status : constant TTY_Status := Query_All;
begin
   Ada.Text_IO.Put_Line ("Stdin  is TTY: " & Status.Stdin'Image);
   Ada.Text_IO.Put_Line ("Stdout is TTY: " & Status.Stdout'Image);
   Ada.Text_IO.Put_Line ("Stderr is TTY: " & Status.Stderr'Image);
end TTY_Demo;
```

Running this interactively vs with redirected output validates the detection:

```bash
# Interactive -- expect True/True/True
./tty_demo

# Piped stdout -- expect True/False/True
./tty_demo | cat

# Piped all -- expect False/False/False
echo "" | ./tty_demo | cat 2>&1
```

### Test file location

| File | Description |
|------|-------------|
| `tests/src/test_tty.adb` | Unit tests for Stream_Kind, TTY_Status, Is_TTY safety, Query_All consistency |
| `examples/src/tty_demo.adb` | Interactive demonstration program (not run in CI) |

---

## Appendix: Implementation Notes

### File descriptor mapping

The body uses a constant array to map `Stream_Kind` to C file descriptors:

```ada
with Interfaces.C;

package body Termicap.TTY
   with SPARK_Mode => Off
is

   use type Interfaces.C.int;

   ---------------------------------------------------------------------------
   --  C Binding
   ---------------------------------------------------------------------------

   function C_Isatty (Fd : Interfaces.C.int) return Interfaces.C.int;
   pragma Import (C, C_Isatty, "isatty");

   ---------------------------------------------------------------------------
   --  File descriptor mapping
   ---------------------------------------------------------------------------

   FD_MAP : constant array (Stream_Kind) of Interfaces.C.int :=
      (Stdin  => 0,
       Stdout => 1,
       Stderr => 2);

   ---------------------------------------------------------------------------
   --  Is_TTY (FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004)
   ---------------------------------------------------------------------------

   function Is_TTY (Stream : Stream_Kind) return Boolean is
   begin
      return C_Isatty (FD_MAP (Stream)) = 1;
   end Is_TTY;

   ---------------------------------------------------------------------------
   --  Query_All (FUNC-TTY-006)
   ---------------------------------------------------------------------------

   function Query_All return TTY_Status is
   begin
      return (Stdin  => Is_TTY (Stdin),
              Stdout => Is_TTY (Stdout),
              Stderr => Is_TTY (Stderr));
   end Query_All;

end Termicap.TTY;
```

### Why pragma Import, not Interfaces.C.Extensions

GNAT provides `Interfaces.C` with the standard C types. The `isatty` function is declared as:

```c
int isatty(int fd);
```

The binding maps directly:

```ada
function C_Isatty (Fd : Interfaces.C.int) return Interfaces.C.int;
pragma Import (C, C_Isatty, "isatty");
```

No additional C wrapper, header inclusion, or linker configuration is needed. The `isatty` symbol is available in the default C library linked by the GNAT runtime.

### POSIX file descriptor constants

The constants 0, 1, 2 for stdin, stdout, stderr are defined by POSIX and are universal across all POSIX-compliant systems. They are not platform-specific and do not need conditional compilation.

---

## Appendix: Requirements Traceability

| Requirement | API Element | SPARK |
|-------------|-------------|-------|
| FUNC-TTY-001 | `Stream_Kind` enumeration type | Silver (spec) |
| FUNC-TTY-002 | `Is_TTY` function | Spec: Silver, Body: Off |
| FUNC-TTY-003 | `C_Isatty` pragma Import, `FD_MAP` array | Off (body only) |
| FUNC-TTY-004 | `Is_TTY` returns False on error (C_Isatty /= 1) | Off (body only) |
| FUNC-TTY-005 | Spec: SPARK_Mode, Body: SPARK_Mode => Off | Silver / Off |
| FUNC-TTY-006 | `TTY_Status` record, `Query_All` function | Spec: Silver, Body: Off |
