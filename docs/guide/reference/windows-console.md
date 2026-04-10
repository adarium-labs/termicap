# Reference: Windows Console Detection

How Termicap detects terminal capabilities on Windows — TTY status, terminal dimensions, and color level.

**Public API:** `Termicap.Capabilities` (same on all platforms)
**Platform bodies:** `src/windows/` (selected automatically via GPR `Source_Dirs`)
**License:** Apache-2.0

---

## Overview

On Windows, Termicap replaces the POSIX bodies of `Termicap.TTY`, `Termicap.Dimensions`, and `Termicap.Capabilities` with Windows Console API implementations. The public-facing API is identical on all platforms: applications call `Termicap.Capabilities.Detect` or `Termicap.Capabilities.Get` and receive a `Terminal_Capabilities` record. No Windows-specific package names appear in application code.

Three internal helper packages handle the Windows-specific logic:

| Package | Role |
|---------|------|
| `Termicap.Win32_Ntdll` | Obtains the Windows build number via dynamic load of `ntdll.dll` |
| `Termicap.Win32_VT` | Console handle helpers: validation, `CONIN$`/`CONOUT$` access, VT processing enablement |
| `Termicap.Win32_Color` | Maps build number and `WT_SESSION` to a `Color_Level` |

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

---

## See Also

- **[Termicap.Capabilities](termicap-capabilities.md)** — primary public API (all platforms)
- **[Termicap.Color](termicap-color.md)** — env-var color cascade (FORCE_COLOR, NO_COLOR, COLORTERM, …)
- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — `Termicap.Win32_*` package descriptions, Windows platform package list
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 24: Windows color detection flow
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`) — GPR `Source_Dirs` platform dispatch rationale
- **ADR-0019** (`docs/adr/0019-win32ada-as-ffi-layer.md`) — win32ada FFI layer rationale
- **Tech Spec WIN32** (`docs/tech-specs/windows-console.md`) — full design rationale and build number threshold derivation
