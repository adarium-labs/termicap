# Reference: Windows Console Detection

How Termicap detects terminal capabilities on Windows — TTY status, terminal dimensions, and color level.

**Public API:** `Termicap.Capabilities` (same on all platforms)
**Platform bodies:** `src/windows/` (selected automatically via GPR `Source_Dirs`)
**License:** Apache-2.0

---

## Overview

On Windows, Termicap replaces the POSIX bodies of `Termicap.TTY`, `Termicap.Dimensions`, and `Termicap.Capabilities` with Windows Console API implementations. The public-facing API is identical on all platforms: applications call `Termicap.Capabilities.Detect` or `Termicap.Capabilities.Get` and receive a `Terminal_Capabilities` record. No Windows-specific package names appear in application code.

Four internal helper packages handle the Windows-specific logic:

| Package | Role |
|---------|------|
| `Termicap.Win32_Ntdll` | Obtains the Windows build number via dynamic load of `ntdll.dll`; also provides `Query_Object_Name` for pipe name retrieval |
| `Termicap.Win32_VT` | Console handle helpers and the three-way ConPTY classifier (`Console_VT_Status`, `Classify_Console_VT`, `Should_Skip_Active_Probes`); `CONIN$`/`CONOUT$` access; VT-input/output mode enablement |
| `Termicap.Win32_Color` | Maps build number and `WT_SESSION` to a `Color_Level` |
| `Termicap.Win32_Cygwin` | Detects Cygwin/MSYS2 PTY handles via named-pipe name inspection |

These packages are **internal**. Application code does not `with` or call them directly.

---

## Public API

The API entry point is unchanged from non-Windows platforms:

```ada
with Termicap.Capabilities; use Termicap.Capabilities;

Caps : constant Terminal_Capabilities := Detect;

--  or, with per-stream caching:
Caps : constant Terminal_Capabilities := Get (Stdout);
```

The returned `Terminal_Capabilities` record contains `Color`, `Size`, and TTY fields populated from Windows Console API calls as described below.

See [`termicap-capabilities.md`](termicap-capabilities.md) for the full `Terminal_Capabilities` type reference and all `Detect`/`Get` parameters.

---

## How Windows Detection Works

### TTY Detection

On Windows, `Termicap.TTY.Is_TTY` calls `GetConsoleMode` on the standard handle corresponding to the requested stream. A stream is considered a TTY when `GetConsoleMode` succeeds (i.e., the handle is attached to a console, not a pipe or file).

As a side effect, `Enable_VT_Processing` is called on a valid console output handle the first time a TTY is detected, setting the `ENABLE_VIRTUAL_TERMINAL_PROCESSING` flag (`0x0004`) in the console mode. This ensures that ANSI/VT escape sequences work in the Windows Console Host without requiring a separate setup step by the application.

The process-wide override installed via `Termicap.Override.Set_Override` is checked before the `GetConsoleMode` call, identical to the POSIX `isatty()` path.

#### Cygwin and MSYS2 PTY Support

When running inside a Cygwin or MSYS2 environment (for example, Git Bash on Windows), standard streams are backed by named pipes rather than native Windows console objects. `GetConsoleMode` fails on these handles, which would normally cause `Is_TTY` to return `False` even though the user is interacting with an interactive terminal.

To handle this, `Is_TTY` performs a second-chance check using `Termicap.Win32_Cygwin.Is_Cygwin_Terminal`. This function:

1. Guards on `GetFileType` — only named pipe handles proceed further.
2. Retrieves the kernel-level pipe name via `GetFileInformationByHandleEx` (primary) or `NtQueryObject` (fallback).
3. Passes the decoded ASCII name to `Is_Cygwin_Pipe_Name`, a pure SPARK Silver function that validates the Cygwin/MSYS2 pipe name grammar (e.g., `\msys-<hex>-pty<N>-from-master`).

If the pipe name matches, `Is_TTY` returns `True` for that handle. The detection is fully transparent to application code — the returned value is the same `Boolean` on all paths.

This covers the requirements FUNC-CYG-001 through FUNC-CYG-017.

### Terminal Dimensions

`Termicap.Dimensions.Get_Size` calls `GetConsoleScreenBufferInfo` and reads the `srWindow` field (the visible viewport rectangle), not `dwSize` (the scroll-back buffer). This correctly reflects what the user sees in the terminal window.

The `COLUMNS`/`LINES` environment variable fallback and the 80×24 default are identical to the POSIX path.

### Color Level Detection

Color level detection on Windows combines two sources:

1. **Win32 hardware detection** (`Termicap.Win32_Color.Detect_Windows_Color_Level`) — uses the Windows build number and `WT_SESSION`.
2. **Environment variable cascade** (`Termicap.Color.Detect_Color_Level`) — the standard 11-step cascade (FORCE_COLOR, NO_COLOR, COLORTERM, TERM, …).

The final result is:

```ada
Color_Level'Max (Win32_Level, Env_Level)
```

---

## ConPTY Classification — `Console_VT_Status`

Tier-3 capability detection (Sixel/Kitty graphics, OSC 52 clipboard read-back, Kitty keyboard, mouse DECRPM probes) sends escape sequences to the terminal and reads structured replies. On Windows, whether such a probe is safe depends on the host:

- **ConPTY-backed hosts** (Windows Terminal, Warp, VS Code integrated terminal, alacritty, WezTerm Windows) interpret VT sequences correctly and answer OSC/CSI/DCS queries. Active probing is appropriate.
- **Legacy `conhost.exe`** without VT processing echoes raw escape bytes back to the user's screen and never replies. Active probing must be skipped.
- **Non-console streams** (pipes, files, NUL) cannot answer at all.

`Termicap.Win32_VT` exposes a three-way classifier so each Tier-3 site can route correctly:

```ada
type Console_VT_Status is
  (Not_A_Console,
   Legacy_Conhost,
   ConPTY_VT_Enabled);

function Classify_Console_VT (Handle : Win32.Winnt.HANDLE) return Console_VT_Status;
function Should_Skip_Active_Probes (Handle : Win32.Winnt.HANDLE) return Boolean;
```

| Value | Meaning | Active probe? |
|-------|---------|---------------|
| `Not_A_Console` | `GetConsoleMode` failed (handle is a pipe, file, NUL, or closed) | No — fall back to passive heuristics |
| `Legacy_Conhost` | `GetConsoleMode` succeeded but `ENABLE_VIRTUAL_TERMINAL_PROCESSING` is not set | No — bail out before opening a `Probe_Session` |
| `ConPTY_VT_Enabled` | `GetConsoleMode` succeeded with VT processing enabled | Yes — proceed exactly as on POSIX |

`Should_Skip_Active_Probes` is the predicate form: it returns `True` only for `Legacy_Conhost` (the case where probing would be unsafe and produce visible noise). `Not_A_Console` is **not** a skip — the OSC layer can still acquire a working handle pair via the `CONIN$`/`CONOUT$` fallback even when the standard handles are redirected.

### Probe-gate sites

The following Windows bodies use `Classify_Console_VT` to decide whether to issue an active probe:

| Body | Feature | Behaviour on `Legacy_Conhost` |
|------|---------|-------------------------------|
| `src/windows/termicap-graphics-io.adb` | Sixel / Kitty graphics | Returns passive defaults; no probe |
| `src/windows/termicap-clipboard-io.adb` | OSC 52 read-back | Returns passive defaults; no probe |
| `src/windows/termicap-keyboard-io.adb` | Kitty keyboard / XTerm modifiers | Returns `(Win32, Probed => False)` |
| `src/windows/termicap-mouse-io.adb` | Mouse DECRPM cascade | Returns `Win32_Console_Mouse = True` |

Each site has the same shape:

```ada
case Classify_Console_VT (Stdout_Handle) is
   when Legacy_Conhost =>
      --  Bail out — return passive result.
      return Passive_Default;

   when Not_A_Console | ConPTY_VT_Enabled =>
      --  Proceed: the OSC layer can either open the handle directly
      --  (ConPTY_VT_Enabled) or fall back to CONIN$/CONOUT$
      --  (Not_A_Console — stdout may be redirected even though a
      --  console session exists).
      ...
end case;
```

The redundant `Is_TTY (Stdout)` guard previously sitting in front of these probes was removed so that the OSC layer's `CONIN$`/`CONOUT$` fallback can fire under `Not_A_Console` when the user has redirected stdout.

---

## OSC Active Probes on Windows

On Windows, Termicap performs the same OSC/CSI/DCS active probes used on POSIX — Sixel graphics (DA1 / APC), Kitty graphics, Kitty keyboard, XTerm modifier keys, mouse DECRPM cascade, OSC 52 clipboard read-back, OSC 11 background color, XTVERSION, DA1, etc. The `Termicap.OSC.Probe_Session` lifecycle is identical to POSIX; only the underlying primitives differ.

### Lifecycle on Windows

1. **Open.** `Open_Terminal` calls `GetStdHandle (STD_INPUT_HANDLE)` and `GetStdHandle (STD_OUTPUT_HANDLE)`, validates each with `GetConsoleMode`, and opens a slot in a body-private slot table (`MAX_SLOTS = 1`). If either standard handle is redirected, the body falls back to `CreateFileW ("CONIN$", …)` / `CreateFileW ("CONOUT$", …)`. A synthetic `File_Descriptor` indexes into the slot, which carries the input/output handles and a `Console_Handle_Origin` (`From_StdHandle` / `From_ConFile`) used at finalize time to decide which handles must be `CloseHandle`-d and which are owned by the runtime.
2. **Save_Termios.** Two `GetConsoleMode` calls (input + output DWORDs) are packed into the opaque `Termios_State.Data` buffer. No `struct termios` exists on Windows; the buffer is treated as platform-private bytes by the rest of the OSC layer.
3. **Set_Raw_Mode.** `SetConsoleMode` clears `ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT | ENABLE_PROCESSED_INPUT` and ORs in `ENABLE_VIRTUAL_TERMINAL_INPUT` on the input handle, and ORs `ENABLE_VIRTUAL_TERMINAL_PROCESSING | DISABLE_NEWLINE_AUTO_RETURN` into the output handle. This is the equivalent of POSIX termios raw mode for VT-aware reads.
4. **Drain_Input.** Non-blocking `WaitForSingleObject (Handle, 0)` + `ReadFile` is repeated until no further bytes are available, bounded to `MAX_DRAIN_ITERATIONS`.
5. **Sentinel_Query / Timeout_Query.** The shared OSC layer writes the user query (and DA1 sentinel, if applicable) and accumulates response bytes. On Windows, each `Timed_Read` is `WaitForSingleObject (Input_Handle, Timeout_Ms)` followed by a single `ReadFile` for the available bytes; on `WAIT_TIMEOUT`, the read loop exits with `Timed_Out := True`.
6. **Finalize.** The `Limited_Controlled` finalizer restores both saved DWORDs via `SetConsoleMode`, then `CloseHandle`s the input and output handles only when `Console_Handle_Origin = From_ConFile` — handles obtained from `GetStdHandle` are owned by the runtime and must not be closed.

### What this enables

| Terminal | Behaviour before | Behaviour now |
|----------|------------------|---------------|
| Windows Terminal (ConPTY) | Passive heuristics only | Full OSC probing: Sixel/DA1, OSC 52 read-back, OSC 11, Kitty keyboard, mouse DECRPM, XTVERSION |
| Warp on Windows | Passive heuristics only | Full OSC probing |
| VS Code integrated terminal | Passive heuristics only | Full OSC probing |
| ConPTY-fronted alacritty / WezTerm | Passive heuristics only | Full OSC probing |
| Legacy `conhost.exe` (no VT) | Passive heuristics only | Passive heuristics only (the gate bails out cleanly — no escape bytes leak to the user's screen) |
| Stdout redirected to a file/pipe | No probing | OSC layer falls back to `CONIN$`/`CONOUT$`; probing succeeds when a console session is attached even if stdout is not a TTY |

### Foreground process check

POSIX uses `ioctl(TIOCGPGRP) == getpgrp()` to suppress probing from background jobs. Windows has no analogue — console processes are always associated with a single visible window. The Windows `Is_Foreground_Process` returns `True` whenever a usable console-handle pair was obtained; `Open` returns `Session_Not_Foreground` only when no input/output handle could be acquired (FUNC-FGP-012, FUNC-FGP-013).

For full design details, see [`docs/tech-specs/windows-osc-active-probes.md`](../../tech-specs/windows-osc-active-probes.md).

---

## Color Level Thresholds

### `WT_SESSION` — Windows Terminal fast path

If the environment variable `WT_SESSION` is present and non-empty, the result is `True_Color` immediately. This variable is set by Windows Terminal and indicates a modern, TrueColor-capable host.

```ada
--  WT_SESSION is present and non-empty → True_Color
Win32_Level := True_Color
```

### Windows Build Number

When `WT_SESSION` is absent or empty, Termicap reads the Windows build number by dynamically loading `ntdll.dll` and calling `RtlGetNtVersionNumbers`. The build number is mapped to a color level as follows:

| Build Number | Windows Release | Color Level |
|-------------|-----------------|-------------|
| `< 10_586` | Pre-Anniversary Update | `None` |
| `10_586 .. 14_930` | Anniversary Update (1607) | `Extended_256` |
| `>= 14_931` | Fall Creators Update (1709) | `True_Color` |

- Build 10586 introduced 256-color support in the Windows Console Host.
- Build 14931 introduced full TrueColor (24-bit RGB) support.
- `Basic_16` is never returned by the Win32 detection path (guaranteed by a SPARK postcondition on `Build_To_Color_Level`).

If `ntdll.dll` cannot be loaded or `RtlGetNtVersionNumbers` is not found, the build number is treated as `0` and the result is `None`.

---

## FORCE_COLOR / NO_COLOR Override Precedence

Standard overrides apply on all platforms, including Windows. Because the final color is `Color_Level'Max (Win32_Level, Env_Level)`, the env-var cascade result can only raise or maintain the Win32 level — it never lowers it below `None`.

However, the override short-circuit in `Termicap.Override` fires before any detection (Win32 or env-var) is attempted. When an override is active, both the Win32 hardware detection and the env-var cascade are skipped entirely:

| Override | Effect |
|----------|--------|
| `Force_None` (`NO_COLOR` or `--color=never`) | Returns `None`; all detection skipped |
| `Force_Basic` | Returns `Basic_16`; all detection skipped |
| `Force_256` | Returns `Extended_256`; all detection skipped |
| `Force_True_Color` (`FORCE_COLOR=3`, `--color=always`) | Returns `True_Color`; all detection skipped |
| `Auto` (no override) | Win32 + env-var cascade runs normally |

Within the env-var cascade itself (when override is `Auto`), `FORCE_COLOR` and `NO_COLOR` apply with their standard semantics. See [`termicap-color.md`](termicap-color.md) for the full cascade priority table.

---

## Requirements Traceability

| Requirement | Detection Step |
|-------------|---------------|
| FUNC-WIN-001 | `Win32_VT.Is_Valid_Handle` — console handle validation |
| FUNC-WIN-004 | `Win32_VT.Open_Console_Input/Output` — `CONIN$`/`CONOUT$` fallback |
| FUNC-WIN-006 | `Win32_Ntdll.Get_Build_Number` — `RtlGetNtVersionNumbers` dynamic load |
| FUNC-WIN-007 | `Win32_Color`: `WT_SESSION` present and non-empty → `True_Color` |
| FUNC-WIN-008 | `Win32_Color.Build_To_Color_Level` — threshold mapping |
| FUNC-WIN-009 | `Win32_VT.ENABLE_VIRTUAL_TERMINAL_PROCESSING` constant |
| FUNC-WIN-010 | `Win32_VT.Enable_VT_Processing` — `SetConsoleMode` write-back |
| FUNC-WIN-011 | Enable VT processing on valid console output handle |
| FUNC-WIN-012 | Custom FFI boundary for `ntdll.dll` (`Termicap.Win32_Ntdll`) |
| FUNC-WIN-013 | `Build_To_Color_Level` SPARK postcondition: `Basic_16` never returned |
| FUNC-WIN-014 | `Win32_VT.Console_VT_Status`, `Classify_Console_VT`, `Should_Skip_Active_Probes` — three-way ConPTY classifier and probe gate |
| FUNC-OSC-016 | Windows `Open_Terminal` — `GetStdHandle` primary path + `CONIN$`/`CONOUT$` fallback (slot-table indexing) |
| FUNC-OSC-017 | Windows `Save_Termios`/`Set_Raw_Mode` — `GetConsoleMode`/`SetConsoleMode`, two DWORDs packed into `Termios_State.Data` |
| FUNC-OSC-018 | Windows `Timed_Read` — `WaitForSingleObject` + `ReadFile` |
| FUNC-OSC-019 | Windows `Write_Query` / `Drain_Input` / `Finalize` — `WriteFile`, `ENABLE_VIRTUAL_TERMINAL_INPUT` raw mode, owned-handle close |
| FUNC-CYG-006 | `Win32_Cygwin.Is_Cygwin_Pipe_Name` — public SPARK Silver function |
| FUNC-CYG-007 | Token[0] prefix validation (`\msys-` / `\cygwin-`) |
| FUNC-CYG-008 | Token[1] non-empty hex PID segment |
| FUNC-CYG-009 | Token[2] starts with `"pty"` |
| FUNC-CYG-010 | Token[3] is exactly `"from"` or `"to"` |
| FUNC-CYG-011 | Token[4] is exactly `"master"` |
| FUNC-CYG-012 | Minimum 5 `'-'`-delimited segments |
| FUNC-CYG-013 | 14 acceptance test vectors for `Is_Cygwin_Pipe_Name` |
| FUNC-CYG-014 | `Win32_Cygwin.Is_Cygwin_Terminal` — full detection pipeline |
| FUNC-CYG-015 | `Is_TTY_Via_Handle` disjunction: Cygwin check after `GetConsoleMode` fails |
| FUNC-CYG-016 | `Is_Cygwin_Terminal` no-exception contract |
| FUNC-CYG-017 | Package structure and SPARK boundary |

---

## See Also

- **[Termicap.Capabilities](termicap-capabilities.md)** — primary public API (all platforms)
- **[Termicap.Color](termicap-color.md)** — env-var color cascade (FORCE_COLOR, NO_COLOR, COLORTERM, …)
- **[Termicap.OSC](osc.md)** — probe session lifecycle (the "Windows behaviour" subsection covers the platform-specific primitives)
- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — `Termicap.Win32_*` package descriptions, Windows platform package list
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 24: Windows color detection flow; Scenario 25: Cygwin/MSYS2 TTY detection flow; Scenario 28: Windows OSC active probe lifecycle
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — GPR `Source_Dirs` platform dispatch rationale
- **ADR-0019** (`docs/adr/0019-win32ada-as-ffi-layer.md`) — win32ada FFI layer rationale
- **ADR-0020** (`docs/adr/0020-cygwin-pty-detection-strategy.md`) — Cygwin/MSYS2 PTY detection strategy rationale
- **ADR-0039** (`docs/adr/0039-windows-osc-uses-readfile-not-readconsoleinput.md`) — `ReadFile` over `ReadConsoleInput` for OSC reply bytes
- **ADR-0040** (`docs/adr/0040-windows-osc-state-in-termios-state-data.md`) — Console-mode DWORDs packed into `Termios_State.Data`
- **ADR-0041** (`docs/adr/0041-conpty-vt-gate-helper-in-win32-vt.md`) — ConPTY VT gate helper located in `Termicap.Win32_VT`
- **Tech Spec WIN32** (`docs/tech-specs/windows-console.md`) — full design rationale and build number threshold derivation
- **Tech Spec WIN-OSC** (`docs/tech-specs/windows-osc-active-probes.md`) — Windows OSC active-probe design (FUNC-OSC-016..019, FUNC-WIN-014)
- **Tech Spec CYGWIN** (`docs/tech-specs/cygwin-pty.md`) — Cygwin/MSYS2 PTY detection design rationale
