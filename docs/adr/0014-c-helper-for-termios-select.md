# C helper approach for termios/select/fd_set instead of direct Ada struct mapping

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-04

## Context and Problem Statement

The OSC Query Infrastructure requires Ada code to call `tcgetattr()`, `tcsetattr()`, `select()`, and `ioctl(TIOCGPGRP)` for terminal raw mode, timed reads, and foreground process group checks. These POSIX interfaces involve `struct termios` (platform-specific size and field layout), `fd_set` (manipulated only through C macros), and the variadic `ioctl()` function. How should the Ada/SPARK library interact with these C constructs?

## Decision Drivers

* `struct termios` has different sizes and field layouts across Linux (~60 bytes), macOS (~72 bytes), and FreeBSD (~44 bytes). An Ada record representation clause would need platform-specific conditional compilation.
* `fd_set` is accessed exclusively through `FD_ZERO`, `FD_SET`, and `FD_ISSET` macros, which cannot be imported from Ada via `pragma Import`.
* `ioctl()` is variadic (same issue as ADR-0006).
* The project already has two working C helper files (`termicap_ioctl.c`, `termicap_sigwinch.c`) and the build system supports mixed Ada/C compilation.
* SPARK_Mode => Off boundary should contain the minimum necessary code; all decision logic must remain in Ada.

## Considered Options

* **Option A**: C helper file with fixed-signature wrappers for all termios/select/ioctl operations
* **Option B**: Direct Ada record mapping of `struct termios` with platform-specific representation clauses, plus a separate C helper only for `fd_set` macros
* **Option C**: Use GNAT's `Interfaces.C_Streams` or POSIX Ada bindings (e.g., Florist)

## Decision Outcome

Chosen option: **Option A** (C helper file), because it is consistent with the project's established pattern, avoids fragile platform-specific Ada struct layouts, and handles all three problem cases (struct termios, fd_set macros, variadic ioctl) uniformly in a single auditable C file.

### Positive Consequences

* Consistent with ADR-0006 and `termicap_sigwinch.c` -- same pattern, same review standards
* Platform portability: the C compiler handles struct layout differences automatically
* The C file contains no logic beyond syscall invocation and struct field access
* Ada-side code focuses on session management and error handling, not struct byte manipulation
* Easy to extend for future POSIX calls (e.g., `poll()` as an alternative to `select()`)

### Negative Consequences

* Adds another C source file (~120 lines) to maintain alongside Ada code
* The termios state is stored as an opaque byte buffer in Ada, which cannot be inspected by SPARK proofs (acceptable since the entire session package is SPARK_Mode => Off)

## Pros and Cons of the Options

### Option A: C helper file (chosen)

A C file `src/c/termicap_osc.c` provides fixed-signature functions for all termios/select/ioctl operations. Ada imports them via `pragma Import (C, ...)`. The termios state is passed between Ada and C as an opaque byte buffer.

* Good, because consistent with established project pattern (ADR-0006, `termicap_sigwinch.c`)
* Good, because handles struct termios, fd_set macros, and variadic ioctl uniformly
* Good, because the C compiler resolves platform-specific struct layouts automatically
* Good, because C code is trivially auditable (~120 lines, no logic, no heap allocation)
* Bad, because adds a C source file to the project

### Option B: Direct Ada struct mapping + partial C helper

Define `struct termios` as an Ada record with representation clauses per platform. Use a C helper only for `fd_set` macros and `ioctl`.

* Good, because termios state is visible to Ada code (could be inspected, though not SPARK-provable)
* Bad, because requires `#if` / preprocessor-style conditional compilation in Ada (GNAT-specific)
* Bad, because struct termios fields and sizes must be manually tracked across Linux, macOS, FreeBSD, and kept in sync with libc updates
* Bad, because mixed approach (some C, some Ada struct mapping) is less consistent and harder to audit
* Bad, because `c_cc` array size varies (20 on Linux, 20 on macOS but different offsets)

### Option C: POSIX Ada bindings (Florist)

Use an existing Ada POSIX binding library for termios and select.

* Good, because no custom C code needed
* Bad, because Florist is not in the Alire ecosystem and adds a heavyweight dependency
* Bad, because Florist's SPARK compatibility is unknown
* Bad, because adds a third-party dependency for functionality that is a ~120-line C file

## Links

* [ADR-0006](0006-c-wrapper-for-ioctl-tiocgwinsz.md) -- Established the C helper pattern for ioctl
* [Tech Spec](../tech-specs/osc-query-infra.md) -- OSC Query Infrastructure technical specification
* POSIX termios(3) -- documents struct termios
* POSIX select(2) -- documents fd_set and FD_SET/FD_ZERO macros
