# Keep foreground process group check in Termicap.OSC rather than a new child package

* Status: Accepted
* Deciders: Heziode
* Date: 2026-05-06

## Context and Problem Statement

The FUNC-FGP requirements (FUNC-FGP-012) specify that the foreground process group FFI bindings "shall be named Termicap.OSC.Foreground or placed within an existing OSC FFI boundary package." The foreground check (`Is_Foreground_Process`) is already implemented in `Termicap.OSC` as part of the probe session lifecycle. Should it be extracted into a separate `Termicap.OSC.Foreground` child package, or should it remain in the existing `Termicap.OSC` package?

## Decision Drivers

* FUNC-FGP-012 explicitly allows either placement
* The foreground check is tightly coupled to the probe session `Open` procedure: it is called as step 2 of `Open`, using the `/dev/tty` file descriptor that `Open` just acquired
* The C FFI binding (`C_Is_Foreground`) is declared in the same `pragma Import` block as all other OSC C bindings (`C_Open_TTY`, `C_Save_Termios`, `C_Set_Raw`, etc.)
* The C helper function lives in `termicap_osc.c` alongside all other OSC C helpers
* `Termicap.OSC` is already `SPARK_Mode => Off` in its entirety
* The foreground check consists of exactly one imported C function and one four-line Ada wrapper function

## Considered Options

* **Option A**: Keep `Is_Foreground_Process` in `Termicap.OSC` (current state)
* **Option B**: Extract into a new `Termicap.OSC.Foreground` child package

## Decision Outcome

Chosen option: **Option A** (keep in `Termicap.OSC`), because the foreground check is a single function with a single C binding that is tightly integrated with the probe session lifecycle. Extracting it into a separate package would increase the package count without improving modularity, testability, or SPARK provability.

### Positive Consequences

* No new files to create or maintain
* All OSC C FFI bindings remain co-located in one package, matching the co-located C helper file
* The `Open` procedure can call `Is_Foreground_Process` directly without a `with` clause on a child package
* Consistent with the existing design established during OSC infrastructure implementation

### Negative Consequences

* The `Termicap.OSC` spec contains more declarations than a minimal "probe session only" design would have, but this is already the case with `Timed_Read`, `Write_Query`, `Open_Terminal`, etc.

## Pros and Cons of the Options

### Option A: Keep in Termicap.OSC (chosen)

The `Is_Foreground_Process` function and its `C_Is_Foreground` import remain in `Termicap.OSC` (spec and body).

* Good, because no new package files needed
* Good, because all POSIX FFI bindings for the probe session are in one place
* Good, because the Open procedure can reference Is_Foreground_Process without cross-package visibility
* Good, because matches the single-C-file pattern (termicap_osc.c contains all helpers)
* Bad, because Termicap.OSC is a moderately large package (but still manageable)

### Option B: Extract into Termicap.OSC.Foreground

Create `src/termicap-osc-foreground.ads` and platform-specific `.adb` files.

* Good, because gives the foreground check its own namespace
* Good, because could have its own SPARK_Mode annotation (but would still be Off due to C FFI)
* Bad, because adds 3 new files (spec + posix body + windows body) for one function
* Bad, because the Open procedure in Termicap.OSC body would need to `with Termicap.OSC.Foreground`, adding a cross-package dependency for an internal implementation detail
* Bad, because the C helper is still in termicap_osc.c, creating a mismatch between Ada package structure and C file structure

## Links

* [ADR-0014](0014-c-helper-for-termios-select.md) -- Established C helper pattern for ioctl/termios
* [ADR-0018](0018-platform-dispatch-via-source-dirs.md) -- Platform dispatch via source directories
* [Tech Spec](../tech-specs/fgpgrp.md) -- FGPGRP technical specification
* FUNC-FGP-012 -- FFI boundary package placement requirement
