# Windows console-mode state stuffed into the existing Termios_State byte array

* Status: Accepted
* Deciders: Heziode
* Date: 2026-05-08

## Context and Problem Statement

The shared `Termicap.OSC` spec (`src/termicap-osc.ads`) declares `Probe_Session` with three fields: `FD : File_Descriptor`, `Saved_State : Termios_State`, `Is_Raw : Boolean`. `Termios_State` is a record carrying `Data : Byte_Array (1 .. 128)` and `Size : Natural`. The POSIX body fills `Data` with the raw `struct termios` bytes via `tcgetattr`.

The Windows body needs to track:

1. Two `Win32.Winnt.HANDLE` values (the input and output console handles).
2. Two `Console_Handle_Origin` flags per handle (`Borrowed_From_Std` vs `Owned_From_CreateFile` vs `Not_Acquired`) so that `Finalize` only `CloseHandle`s handles we owned.
3. Two saved `Win32.DWORD` console modes (input mode, output mode) so we can `SetConsoleMode` back to them on close.
4. Two `Boolean` flags (Input_Saved, Output_Saved) because partial saves are permitted by FUNC-OSC-017.

Two separate concerns: per-session **handles** (1, 2) and per-session **mode snapshot** (3, 4). The mode snapshot fits trivially into the existing `Termios_State.Data` (10 bytes used out of 128). The handles do not, because they are pointer-sized and the spec deliberately says nothing about them.

We must decide where the handles live without changing the shared spec.

## Decision Drivers

* The shared spec must not gain Win32-specific symbols. `Termicap.OSC` is consumed by both POSIX bodies (no `with Win32.*` allowed) and Windows bodies.
* The spec must not gain a discriminant or platform-conditional record (would force every consumer to handle both shapes).
* The Windows body must satisfy FUNC-OSC-016 (Borrowed vs Owned distinction) and the whole-lifecycle FUNC-OSC-008.
* Active sessions are limited to one (FUNC-OSC-012); a constant-size table is acceptable.
* `Probe_Session.FD` is a `File_Descriptor` (`Interfaces.C.int`-derived) on both platforms. On POSIX it is a real OS file descriptor. On Windows nothing makes it a real OS handle — the spec only guarantees `INVALID_FD = -1`.

## Considered Options

* **Option A**: Body-private slot table indexed by a synthetic `File_Descriptor` (1, 2, 3, ...). The `Probe_Session.FD` stores the slot index. `Termios_State.Data` holds the two saved DWORDs and two flags (10 bytes).
* **Option B**: Extend `Probe_Session` with a `Platform_State` discriminant and a variant part holding the handles on Windows.
* **Option C**: Cast a `HANDLE` to an `Interfaces.C.int` and store it in `Probe_Session.FD`, keeping Origin flags in additional bytes of `Termios_State.Data`. `INVALID_FD = -1` would map to `INVALID_HANDLE_VALUE = -1` by happy accident.

## Decision Outcome

Chosen option: **Option A**, because it leaves the shared spec literally unchanged, contains all Win32-specific types behind `src/windows/termicap-osc.adb`, and pays only one extra array indexing per OSC operation (negligible).

### Positive Consequences

* `src/termicap-osc.ads` and `src/termicap-osc-parsing.ads/.adb` need zero changes.
* POSIX behaviour is provably unaffected: the slot table only exists in `src/windows/`, not in `src/posix/`.
* The `Console_Handle_Origin` enum and slot table layout can evolve freely without touching shared code.
* The `Termios_State.Data` array is genuinely opaque and platform-specific in its content. POSIX uses ~80 bytes for `struct termios`; Windows uses 10 bytes for the two DWORDs + two flags. The spec's documentation already acknowledges this (the comment says "platform-specific struct termios bytes").

### Negative Consequences

* The slot table is body-static, so it lives for the program's lifetime (~4 slot records ≈ 96 bytes). Trivial.
* A `File_Descriptor` value on Windows is not a real OS handle. Code outside the OSC body that tries to interpret it would fail. This is already the case on POSIX: nothing outside `Termicap.OSC` is allowed to dereference a session's FD. We add a doc comment to the Windows body reinforcing the constraint.
* Concurrency: the slot table must be accessed under the same `Active_Session_Guard` protected object that the POSIX body uses. The Windows body declares its own copy of the protected object (15 lines). FUNC-OSC-012 caps active sessions to 1 anyway, but a `MAX_SLOTS = 4` defensive over-allocation tolerates test infrastructure where finalization runs late.

### Mode-snapshot encoding (informational)

The 10 bytes used in `Termios_State.Data` on Windows:

| Offset | Size | Contents |
|--------|------|----------|
| 0..3   | 4    | `Input_Mode`  (Win32.DWORD, native LE) |
| 4..7   | 4    | `Output_Mode` (Win32.DWORD, native LE) |
| 8      | 1    | `Input_Saved` (0 or 1) |
| 9      | 1    | `Output_Saved` (0 or 1) |

`Termios_State.Size` is set to 10 on Windows. The body uses native byte order via `Pack_DWORD/Unpack_DWORD` helpers; Win32 is always LE on supported hardware (x86, x64, ARM64). No portability concern.

## Pros and Cons of the Options

### Option A — Body-private slot table (chosen)

* Good, because zero changes to the shared spec.
* Good, because POSIX never sees the Windows-specific types.
* Good, because the slot table can grow new fields freely (e.g., a later "is this session ConPTY-managed" flag).
* Good, because matches the precedent set by `Termicap.SIGWINCH` (which keeps OS-specific state in body-private storage).
* Bad, because adds an indirection: every Windows OSC op is `Slots(Natural(FD))` lookup. Negligible cost — slot index is tiny, array access is constant-time.
* Bad, because the `File_Descriptor` value on Windows is a synthetic index, not a real OS handle. Mitigated by the rule that no code outside `Termicap.OSC` should interpret a session FD.

### Option B — Discriminated `Probe_Session` record

* Good, because per-session state is co-located with the session object, no slot table.
* Bad, because forces the shared spec to `with Win32.Winnt`. POSIX builds would not compile or would need a fake `Winnt.HANDLE` typedef (cross-platform layering nightmare).
* Bad, because Ada discriminated records with default discriminants and `Limited_Controlled` interact awkwardly (and SPARK 2014 disallows them entirely).
* Bad, because every place that reads `Probe_Session` would need a case statement.

### Option C — Cast HANDLE into File_Descriptor

* Good, because no slot table.
* Bad, because `Win32.Winnt.HANDLE` is `System.Address` (pointer-sized), `Interfaces.C.int` is 32-bit. On 64-bit builds (the only ones we ship for Windows), the cast loses the high 32 bits and corrupts the handle.
* Bad, because relies on a coincidence (`INVALID_HANDLE_VALUE = -1` happening to match `INVALID_FD = -1`). Brittle.
* Bad, because doesn't solve the Origin-flag storage problem.
* Outright wrong on 64-bit Windows — rejected on correctness grounds, not just style.

## Links

* [ADR-0015](0015-probe-session-limited-controlled.md) — `Limited_Controlled` rationale; the Windows body uses the same shape
* [ADR-0018](0018-platform-dispatch-via-source-dirs.md) — `src/posix/` vs `src/windows/` dispatch keeps the bodies separate
* [ADR-0019](0019-win32ada-as-ffi-layer.md) — Win32 types (HANDLE, DWORD) come from win32ada and must not leak into shared specs
* [Tech Spec](../tech-specs/windows-osc-active-probes.md) — Windows OSC active probes (sections D.1, D.2, D.3)
* FUNC-OSC-008 (amended) — probe session lifecycle (Windows mapping)
* FUNC-OSC-016 — Windows terminal device acquisition
* FUNC-OSC-017 — Windows console mode save/raw/restore
