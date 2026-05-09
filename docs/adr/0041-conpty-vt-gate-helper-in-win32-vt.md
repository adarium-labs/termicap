# ConPTY VT classifier extracted as a helper in Termicap.Win32_VT

* Status: Accepted
* Deciders: Heziode
* Date: 2026-05-08

## Context and Problem Statement

`src/windows/termicap-graphics-io.adb:245-254` (and three sister files: `clipboard-io.adb`, `keyboard-io.adb`, `mouse-io.adb`) currently hard-code the same shape of "if `GetStdHandle(STD_OUTPUT_HANDLE)` is a valid console then skip active probes" gate. The intent was to avoid wasting 1-second timeouts on legacy `conhost.exe` sessions that cannot answer VT queries. The implementation conflates two different cases:

1. **Legacy conhost** — `GetConsoleMode` succeeds, but `ENABLE_VIRTUAL_TERMINAL_PROCESSING` is neither set nor settable. VT queries time out. Skipping is correct.
2. **ConPTY-managed** — `GetConsoleMode` succeeds, AND `ENABLE_VIRTUAL_TERMINAL_PROCESSING` is set (or can be set). VT queries are answered by the real terminal upstream of the pseudo-console. Skipping is **incorrect** — we are missing capability data.

The current single boolean gate ("is this a console?") misclassifies all ConPTY hosts as legacy, causing the conformance regression on Windows Terminal, Warp, VS Code's integrated terminal, and other ConPTY-fronted programs.

We need a richer classifier and a single place that owns it.

## Decision Drivers

* Four call sites already use the same gate; duplicating the new three-way classification across all of them is a maintenance hazard.
* `Termicap.Win32_VT` is the existing home for shared Windows console helpers (`Is_Valid_Handle`, `Open_Console_Input/Output`, `Enable_VT_Processing`, `ENABLE_VIRTUAL_TERMINAL_PROCESSING`).
* The classifier touches the same handle that `Enable_VT_Processing` already manipulates and uses the same `GetConsoleMode`/`SetConsoleMode` calls. Separating it from `Win32_VT` would split closely-related code.
* The OSC layer (`Termicap.OSC`) is **not** the right place for the gate: the OSC layer is host-agnostic, the protocol is identical on conhost and ConPTY, and the timeout mechanism is what handles a non-replying terminal anyway. The gate is a **performance optimisation** layered on top, not a correctness mechanism inside.

## Considered Options

* **Option A**: Add `Console_VT_Status` enum + `Console_VT_Status` function + `Should_Skip_Active_Probes` predicate to `Termicap.Win32_VT`. Each of the four call sites switches to a `case` block on the classifier.
* **Option B**: Add the same helpers but to `Termicap.OSC` (or a new `Termicap.OSC.Windows_Gate` child). Move the call from each *-io body to the OSC layer.
* **Option C**: Inline the three-way logic in each call site without extraction.
* **Option D**: Rely on a runtime probe (send DA1 with a tiny timeout; if it answers, the host is VT-capable). Skip the classifier entirely.

## Decision Outcome

Chosen option: **Option A**, because it co-locates the helper with related Windows console primitives, eliminates duplication across four bodies, keeps the OSC layer host-agnostic, and is the smallest change that satisfies FUNC-WIN-014. The classifier produces an explicit three-valued result rather than a boolean, so future call sites can distinguish "not a console" (fall through to MSYS2/Cygwin path) from "legacy console" (skip outright) from "ConPTY" (proceed with active probes).

### Positive Consequences

* All four `*-io.adb` files become a uniform `case Termicap.Win32_VT.Console_VT_Status is ...` block. Easy to review, easy to extend.
* New Windows-specific bodies (e.g., a future hyperlink-confirm or OSC-11 background path) get the gate "for free" by calling `Should_Skip_Active_Probes`.
* The classifier returns `ConPTY_VT_Enabled` after attempting to set `ENABLE_VIRTUAL_TERMINAL_PROCESSING`. That side-effect (enabling VT output on the standard handle) is the same one `Termicap.Win32_VT.Enable_VT_Processing` performs, so we are not introducing new state mutation, just centralising it.
* The OSC layer remains a pure protocol implementation. Probing decisions stay at the call site.

### Negative Consequences

* `Console_VT_Status` mutates console state as a side-effect (sets the VT processing bit). Callers must understand this. Mitigated by: (i) the docstring is explicit, (ii) the bit is set for the rest of the process lifetime which is exactly what `Enable_VT_Processing` already does.
* If the classifier returns `Not_A_Console` it tells the caller "fall through to the POSIX-like path", which is policy embedded in a name. We accept this because the alternative (returning a list of "what to do next") is over-engineered.

## Pros and Cons of the Options

### Option A — Helper in Termicap.Win32_VT (chosen)

* Good, because reuses the existing shared Windows-console helper package.
* Good, because the four call sites become one-line classifier calls.
* Good, because the OSC layer stays host-agnostic.
* Good, because extending the enum (e.g., adding `MSYS2_PTY` for explicit Cygwin classification) is a one-place change.
* Bad, because `Console_VT_Status` has a side effect (sets the VT bit on success). Documented; matches the existing `Enable_VT_Processing` behaviour.

### Option B — Helper in Termicap.OSC (or Termicap.OSC.Windows_Gate)

* Good, because OSC layer "owns" the active-probe primitives.
* Bad, because pushes Windows-host-detection logic into the cross-platform layer.
* Bad, because mouse-io, keyboard-io, clipboard-io, graphics-io would now need `with Termicap.OSC` purely for the gate. Three of those four don't currently consume any OSC primitive.
* Bad, because `Termicap.OSC` is already large; adding gating semantics expands its responsibility.

### Option C — Inline the three-way logic in each call site

* Good, because no new helper to write.
* Bad, because the ~10-line classifier appears four times. Any future change (e.g., distinguishing Windows Terminal from VS Code from generic ConPTY) requires editing four files.
* Bad, because no shared name to grep for; the gate becomes harder to find.
* Bad, because the side-effect of probing-via-SetConsoleMode would happen at four separate locations during initialisation.

### Option D — Runtime-probe-only (no classifier)

* Good, because no static classification — the terminal's actual response is the answer.
* Bad, because every probe has to wait for a timeout on legacy hosts. With four probes per startup (Sixel, Kitty, OSC 11, OSC 8) that's 4 seconds of UI lag on `cmd.exe`.
* Bad, because the existing classifier is fast (one `GetConsoleMode` + at most one `SetConsoleMode` per process lifetime, cached).
* Bad, because some call sites (e.g., MSYS2/Cygwin path) need to know "this is not a console at all" to choose between two different probing strategies, not just whether to skip.

## Implementation Sketch

```ada
-- src/windows/termicap-win32_vt.ads (additions)

type Console_VT_Status_Kind is
  (Not_A_Console,
   Legacy_Conhost,
   ConPTY_VT_Enabled);

function Console_VT_Status return Console_VT_Status_Kind;

function Should_Skip_Active_Probes return Boolean;
--  Equivalent to (Console_VT_Status = Legacy_Conhost).
```

```ada
-- src/windows/termicap-graphics-io.adb (post-refactor, replaces lines 245-254)

case Termicap.Win32_VT.Console_VT_Status is
   when Termicap.Win32_VT.Legacy_Conhost =>
      return Caps;  --  Probed = False; passive results preserved.
   when Termicap.Win32_VT.Not_A_Console =>
      null;         --  Cygwin/MSYS2 PTY or pipe; fall through to TTY guard.
   when Termicap.Win32_VT.ConPTY_VT_Enabled =>
      null;         --  ConPTY: VT queries will be answered.  Continue.
end case;
```

The same structural change is applied to `clipboard-io.adb`, `keyboard-io.adb`, `mouse-io.adb`. The OSC layer is untouched.

## Links

* [ADR-0019](0019-win32ada-as-ffi-layer.md) — win32ada is the FFI layer; `Termicap.Win32_VT` is the project's only allowed Windows-helper package
* [ADR-0020](0020-cygwin-pty-detection-strategy.md) — Cygwin/MSYS2 detection, which the `Not_A_Console` branch hands off to
* [Tech Spec](../tech-specs/windows-osc-active-probes.md) — Windows OSC active probes (section E)
* [Tech Spec](../tech-specs/windows-console.md) — Windows Console API integration; `Termicap.Win32_VT` introduction
* FUNC-WIN-014 — ConPTY-aware active-probe gate
* Microsoft Docs: Pseudoconsoles (https://learn.microsoft.com/en-us/windows/console/pseudoconsoles)
