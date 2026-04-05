# Probe session using Limited_Controlled for RAII instead of explicit open/close

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-04

## Context and Problem Statement

The OSC Query Infrastructure probe session must guarantee that terminal attributes (termios state) are restored and the `/dev/tty` file descriptor is closed when the session ends, regardless of whether the session exits normally or via an exception. How should this cleanup guarantee be implemented in Ada?

## Decision Drivers

* Terminal state must be restored unconditionally; a broken terminal (no echo, no line editing) is unacceptable
* Exception propagation from any query operation must not prevent cleanup
* The probe session must not be copyable (double-close of FD, double-restore of termios)
* SPARK_Mode => Off is already required for the session package due to C FFI; the SPARK cost of using controlled types is zero (already paid)
* The solution should be idiomatic Ada and not rely on user discipline

## Considered Options

* **Option A**: `Ada.Finalization.Limited_Controlled` with `Finalize` performing cleanup
* **Option B**: Explicit `Open`/`Close` procedures with no controlled type; caller is responsible for cleanup
* **Option C**: Generic `With_Session` procedure that takes an access-to-procedure parameter (callback pattern)

## Decision Outcome

Chosen option: **Option A** (Limited_Controlled), because it provides an unconditional cleanup guarantee enforced by the Ada runtime, prevents copies via the `limited` keyword, and has zero additional SPARK cost since the package is already SPARK_Mode => Off for FFI reasons.

### Positive Consequences

* Cleanup is guaranteed by the Ada runtime on scope exit, exception propagation, and task termination
* The `limited` keyword prevents copying, enforcing single-owner semantics (FUNC-OSC-008)
* Pattern is well-understood in the Ada community (analogous to RAII in C++, `defer` in Go, `scopeguard` in Rust)
* No additional SPARK cost: the session package already requires SPARK_Mode => Off for C FFI and protected objects
* Callers cannot forget to restore terminal state

### Negative Consequences

* `Ada.Finalization.Limited_Controlled` is outside the SPARK 2014 language subset; the entire package must be SPARK_Mode => Off (already the case)
* Finalize must not raise exceptions; error reporting from cleanup is limited to best-effort (silent ignore on failure)
* Ada's finalization order for multiple objects in the same scope is well-defined (reverse declaration order) but may surprise developers unfamiliar with Ada

## Pros and Cons of the Options

### Option A: Limited_Controlled with Finalize (chosen)

The `Probe_Session` type extends `Ada.Finalization.Limited_Controlled`. `Open` performs the setup sequence; `Finalize` restores termios and closes the FD. The `limited` keyword prevents copies.

* Good, because cleanup is unconditional and enforced by the runtime
* Good, because `limited` prevents accidental copies (double-close, double-restore)
* Good, because zero additional SPARK cost (package is already SPARK_Mode => Off)
* Good, because idiomatic Ada pattern, well-understood by Ada developers
* Bad, because Finalize cannot propagate exceptions; cleanup failures are silent

### Option B: Explicit Open/Close

The session is a plain limited record. Callers must call `Close` explicitly, typically in an exception handler.

* Good, because no dependency on `Ada.Finalization`
* Good, because error reporting from Close is straightforward
* Bad, because cleanup is not guaranteed: if the caller forgets the exception handler, or an unexpected exception type propagates, the terminal is left in raw mode
* Bad, because requires discipline at every call site; the entire purpose of RAII is to avoid this
* Bad, because the pattern is error-prone and has been the source of real bugs in terminal libraries (cited in the global synthesis)

### Option C: Generic With_Session callback

A procedure `With_Session (Action : not null access procedure (S : in out Session))` opens the session, calls `Action`, and unconditionally closes in an exception handler.

* Good, because cleanup is guaranteed without controlled types
* Good, because could be used from a SPARK_Mode => On package (if the callback is SPARK-compatible)
* Bad, because forces an unnatural callback-based API on callers
* Bad, because the callback cannot return values directly; results must be communicated via out parameters or side effects
* Bad, because nested callbacks (if multiple sessions or resources are needed) create deep nesting
* Bad, because less familiar to Ada developers than controlled types

## Links

* [Tech Spec](../tech-specs/osc-query-infra.md) -- OSC Query Infrastructure technical specification
* [FUNC-OSC-008](../requirements/osc-query-infra.sdoc) -- Probe session lifecycle requirement
* [FUNC-OSC-015](../requirements/osc-query-infra.sdoc) -- SPARK boundary declaration requirement
* Ada RM 7.6 -- User-Defined Assignment and Finalization
