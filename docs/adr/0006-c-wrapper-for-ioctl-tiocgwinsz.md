# C wrapper for ioctl(TIOCGWINSZ) instead of direct Ada import

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-02

## Context and Problem Statement

Terminal dimensions detection requires calling `ioctl(fd, TIOCGWINSZ, &ws)` to read the kernel's knowledge of terminal geometry. How should the Ada/SPARK library invoke this POSIX system call, given that `ioctl` is a variadic C function (`int ioctl(int fd, unsigned long request, ...)`)?

## Decision Drivers

* Ada's `pragma Import (C, ...)` requires a fixed parameter signature -- it cannot bind variadic C functions
* SPARK_Mode => Off boundary should be as small as possible
* The solution must compile with Alire/GNAT on POSIX systems (Linux, macOS, FreeBSD)
* Minimal external surface -- the C code should contain no logic, only the syscall invocation

## Considered Options

* **Option A**: Thin C wrapper with fixed signature (`termicap_get_winsize`)
* **Option B**: Ada binding to a platform-specific non-variadic ioctl wrapper (e.g., `tcgetwinsize` from glibc 2.36+)
* **Option C**: Inline assembly or GNAT-specific variadic call mechanism

## Decision Outcome

Chosen option: **Option A** (thin C wrapper), because it is the standard approach used by virtually all Ada/SPARK projects that need ioctl access, is portable across all POSIX platforms, and keeps the C code minimal (no logic, just the syscall call and field extraction).

### Positive Consequences

* Works on all POSIX platforms regardless of glibc version
* The C wrapper is trivially auditable: ~15 lines, no logic, no memory allocation
* All decision-making (success criteria, fallback chain, defaults) stays in Ada where it can be tested
* Standard pattern -- follows GNATColl.Terminal and other Ada FFI projects
* Easy to extend for other ioctl requests in the future

### Negative Consequences

* Introduces a C source file into the build, requiring GPR changes (`Languages` attribute, `Source_Dirs`)
* The C file must be maintained alongside Ada code (minimal burden given its trivial size)

## Pros and Cons of the Options

### Option A: Thin C wrapper (chosen)

A C file `src/c/termicap_ioctl.c` provides `termicap_get_winsize(fd, cols, rows, xpixel, ypixel) -> int`, which Ada imports via `pragma Import (C, C_Get_Winsize, "termicap_get_winsize")`.

* Good, because portable across all POSIX platforms and glibc versions
* Good, because the C wrapper contains zero logic -- ioctl call + field extraction only
* Good, because standard, well-understood pattern in the Ada/SPARK ecosystem
* Good, because easy to add coverage for other ioctl requests later
* Bad, because adds a C source file to the project (minor build complexity)

### Option B: Ada binding to tcgetwinsize

POSIX.1-2024 introduces `tcgetwinsize()` as a non-variadic alternative to `ioctl(TIOCGWINSZ)`. glibc 2.36+ provides it.

* Good, because no C wrapper needed -- direct `pragma Import` is possible
* Bad, because requires glibc >= 2.36 (released June 2022), excluding older LTS distributions (e.g., Ubuntu 20.04, RHEL 8)
* Bad, because not available on macOS or FreeBSD at the time of writing
* Bad, because Ada would still need to define the `winsize` record layout, which is platform-specific

### Option C: Inline assembly or GNAT-specific mechanism

GNAT could potentially support variadic calls through machine code insertions or compiler-specific pragmas.

* Bad, because no standard GNAT mechanism exists for variadic C calls
* Bad, because inline assembly is non-portable and fragile
* Bad, because violates the project's principle of minimal, auditable FFI surface

## Links

* [Tech Spec F4](../tech-specs/terminal-dimensions.md) -- Terminal dimensions technical specification
* [ADR-0003](0003-tty-detection-package-structure.md) -- Related: TTY detection SPARK boundary pattern
* POSIX ioctl(2) man page -- documents the variadic signature
* POSIX.1-2024 `tcgetwinsize` -- future non-variadic alternative
