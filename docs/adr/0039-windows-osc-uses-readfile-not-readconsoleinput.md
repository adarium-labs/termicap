# Windows OSC body uses ReadFile + ENABLE_VIRTUAL_TERMINAL_INPUT, not ReadConsoleInputW

* Status: Accepted
* Deciders: Heziode
* Date: 2026-05-08

## Context and Problem Statement

The Windows body of `Termicap.OSC.Timed_Read` must read raw byte responses to OSC/DCS/CSI escape-sequence queries from a console input handle, with millisecond-precision timeouts. Win32 offers two read paths for console input:

1. `WaitForSingleObject(h, ms) + ReadFile(h, buf, n, &got, NULL)` — returns raw bytes when `ENABLE_VIRTUAL_TERMINAL_INPUT` is set on the handle's console mode (Windows 10 1809+).
2. `WaitForMultipleObjects(...) + PeekConsoleInputW + ReadConsoleInputW` — returns `INPUT_RECORD` structs containing key events with modifier metadata. This is what crossterm's `event/sys/windows` uses.

These produce different shapes of data. The OSC layer is parsing escape-sequence replies (CSI/SS3/OSC/DCS/APC), not reacting to user keystrokes. We must pick one and document why.

## Decision Drivers

* The escape responses we care about (DA1, XTVERSION, OSC 11, OSC 8, OSC 52, Kitty APC, DECRPM) are byte sequences emitted by the terminal in response to our writes — not user input.
* `ENABLE_VIRTUAL_TERMINAL_INPUT` (added in Windows 10 1809) makes the host deliver the same bytes a Unix terminal driver would deliver, which is exactly what `Termicap.OSC.Parsing` expects.
* `ReadConsoleInputW` returns synthesised key events with `KeyEventRecord.uChar.UnicodeChar`, `dwControlKeyState`, and a `wVirtualKeyCode`. Reconstructing the original byte sequence from these requires re-implementing the host's VT translator, which is fragile and would need updating each Windows release.
* The minimum supported Windows version is already Windows 10 build 10586 (per `docs/tech-specs/windows-console.md`); 1809 was October 2018 and is comfortably below our floor.
* crossterm uses `ReadConsoleInputW` because it builds an event-loop API surface where users *want* key events. That is not what termicap is doing.

## Considered Options

* **Option A**: `WaitForSingleObject + ReadFile` with `ENABLE_VIRTUAL_TERMINAL_INPUT` set during raw-mode activation.
* **Option B**: `WaitForMultipleObjects + ReadConsoleInputW`, parsing `INPUT_RECORD` -> bytes manually.
* **Option C**: `PeekConsoleInputW` polling loop with `Sleep(1)` between polls.

## Decision Outcome

Chosen option: **Option A**, because (i) the data we need is bytes-in/bytes-out, (ii) the host's own VT translator is more correct than any byte synthesis we could write, (iii) the resulting code is symmetric with the POSIX `select + read` path (one wait, one read), and (iv) `ENABLE_VIRTUAL_TERMINAL_INPUT` is precisely the Microsoft-supplied bridge from console events to a byte stream.

### Positive Consequences

* The `Sentinel_Query` accumulation loop in `src/windows/termicap-osc.adb` is identical in shape to the POSIX one in `src/posix/termicap-osc.adb`. Only `Timed_Read` and `Write_Query` differ in their primitive calls.
* No INPUT_RECORD parsing, no key-event-to-byte translation table, no maintenance burden as Windows adds new control-key encodings.
* Termicap's response detection (`Termicap.OSC.Parsing.Contains_DA1_Response`) is a pure byte-array predicate that needs no Windows-specific shim.
* `Drain_Input` reuses the same primitive trivially: `Timed_Read(timeout=0)` x 16.

### Negative Consequences

* Loses access to non-character console events (window resize, focus, mouse). For OSC probing this is irrelevant; for future features that need such events (already scoped out of OSC), a separate path will use `ReadConsoleInputW`.
* On any Windows host older than 10 1809, `ENABLE_VIRTUAL_TERMINAL_INPUT` is silently ignored and `ReadFile` would return cooked input. Termicap already requires Windows 10 build 10586 (FUNC-WIN floor), so this is below our minimum and a `Session_No_Terminal` from the active-probe layer is acceptable on those hosts.
* Programs running with `ConsoleHost.exe` overridden to a third-party that does not honour `ENABLE_VIRTUAL_TERMINAL_INPUT` will see degraded behaviour. None of our tested terminals (Windows Terminal, Warp, mintty, ConEmu modern) fall in that category.

## Pros and Cons of the Options

### Option A — ReadFile + ENABLE_VIRTUAL_TERMINAL_INPUT (chosen)

* Good, because the response is a byte sequence and we need a byte sequence.
* Good, because the implementation matches POSIX shape: wait, then read.
* Good, because the host (not termicap) is responsible for VT byte synthesis.
* Good, because no new dependencies — both calls already in win32ada.
* Bad, because requires Windows 10 1809+ for VT input translation. (Acceptable: floor already at 10586; see windows-console.md.)

### Option B — ReadConsoleInputW (crossterm's choice)

* Good, because supports any Windows version with a console subsystem.
* Good, because exposes window-resize and focus events as a side benefit.
* Bad, because returns `INPUT_RECORD`, not bytes. We would need to translate `KEY_EVENT_RECORD.uChar.UnicodeChar + dwControlKeyState` into the same byte sequence the user-facing terminal emitted.
* Bad, because the translation table is large, version-dependent, and must be kept in sync with Microsoft's host.
* Bad, because the additional `INPUT_RECORD` overhead (key-down/key-up pairs, repeat counts, control-state) is wasted CPU for our use case.
* Bad, because crossterm's parse code (`event/sys/windows/parse.rs`) is non-trivial and would need re-implementation in Ada.

### Option C — PeekConsoleInputW polling

* Good, because no `WaitForSingleObject` needed.
* Bad, because polling with `Sleep(1)` adds latency proportional to the response time, easily exceeding 100ms for slow terminals.
* Bad, because it still returns `INPUT_RECORD` like Option B.
* Bad, because `Sleep(1)` is actually a 16 ms tick on default Windows timer resolution (without `timeBeginPeriod(1)`), making "1 ms poll" a 16 ms-bounded latency in practice.

## Links

* [ADR-0014](0014-c-helper-for-termios-select.md) — POSIX-side rationale (`select + read` for the same problem on POSIX)
* [ADR-0019](0019-win32ada-as-ffi-layer.md) — win32ada is the FFI boundary; ReadFile and WaitForSingleObject are already imported
* [Tech Spec](../tech-specs/windows-osc-active-probes.md) — Windows OSC active probes
* FUNC-OSC-018 — Windows timed read on console input handle
* Microsoft Docs: ENABLE_VIRTUAL_TERMINAL_INPUT (https://learn.microsoft.com/en-us/windows/console/setconsolemode)
* `reference-frameworks/crossterm/src/event/sys/windows/poll.rs` — crossterm's INPUT_RECORD-based path (not adopted)
