# WIN32: Windows Console API Integration

**Feature:** Windows Console API Integration
**Requirements:** FUNC-WIN-001 through FUNC-WIN-013
**Status:** Proposed
**Date:** 2026-04-10

---

## A. Overview

This feature adds full Windows Console API support to Termicap, replacing the stub bodies in `src/windows/` with working implementations. It covers TTY detection, terminal dimensions, color level detection based on the Windows build number, and VT escape sequence processing enablement.

The architecture follows the same pattern used on POSIX: platform-specific body files are selected at build time via `Source_Dirs` using the GPR-level `Alire_Host_OS` dispatch. The package specs (`termicap-tty.ads`, `termicap-dimensions.ads`, `termicap-color.ads`) are platform-agnostic and unchanged. Only the bodies in `src/windows/` differ.

The win32ada Alire crate provides all standard Win32 FFI bindings (console, file, module). The only custom FFI code is `Termicap.Win32_Ntdll`, which dynamically loads `RtlGetNtVersionNumbers` from ntdll.dll, an undocumented export with no import library. A new `Termicap.Win32_VT` package centralises CONIN$/CONOUT$ handle helpers and the VT processing enablement function. A new `Termicap.Win32_Color` package provides the SPARK-provable build-number-to-color-level mapping.

**Minimum supported Windows version:** Windows 10 Build 10586 (November 2015 Update). No attempt is made to support Windows 8.1 or earlier.

**Requirements satisfied:**

| Requirement | Summary |
|-------------|---------|
| FUNC-WIN-001 | Is_Valid_Handle predicate, win32ada HANDLE/DWORD types |
| FUNC-WIN-002 | GetStdHandle binding from win32ada |
| FUNC-WIN-003 | TTY detection via GetConsoleMode |
| FUNC-WIN-004 | CONIN$/CONOUT$ fallback for redirected handles |
| FUNC-WIN-005 | Terminal dimensions via GetConsoleScreenBufferInfo |
| FUNC-WIN-006 | Windows build number via RtlGetNtVersionNumbers |
| FUNC-WIN-007 | WT_SESSION environment variable detection |
| FUNC-WIN-008 | Build number to color level mapping |
| FUNC-WIN-009 | ENABLE_VIRTUAL_TERMINAL_PROCESSING constant |
| FUNC-WIN-010 | SetConsoleMode binding from win32ada |
| FUNC-WIN-011 | Enable VT processing on a console handle |
| FUNC-WIN-012 | FFI boundary: win32ada as primary layer, Win32_Ntdll for custom FFI |
| FUNC-WIN-013 | SPARK-provable Build_To_Color_Level function |

---

## B. Framework Survey

### How reference libraries handle Windows console detection

#### crossterm (Rust) -- GetConsoleMode + SetConsoleMode

crossterm is the most comprehensive Rust terminal library for Windows. Its Windows backend:

1. Calls `GetStdHandle(STD_OUTPUT_HANDLE)` to obtain a handle.
2. Calls `GetConsoleMode(handle, &mode)` to check if the handle is a console -- failure means the handle is redirected.
3. Enables ANSI support by calling `SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING)`.
4. Reads terminal dimensions from `GetConsoleScreenBufferInfo`, computing window size from `srWindow` (not `dwSize`).
5. Checks `WT_SESSION` for Windows Terminal identification.

The read-modify-write pattern for `SetConsoleMode` (get current mode, OR in the new flag, set) is used to avoid clearing flags set by other code.

**Key takeaway:** The guard check (read mode before setting) and the `srWindow` / `dwSize` distinction are both load-bearing. Using `dwSize` for terminal dimensions is a common Windows-specific bug.

#### supports-color (Node.js) -- Build number and WT_SESSION

supports-color on Windows:

1. Checks `WT_SESSION` first: if present, returns `TrueColor` unconditionally.
2. Reads the Windows version via `os.release()`.
3. Maps build number: `< 10586` => no color; `>= 10586` => 256-color; `>= 14931` => TrueColor.
4. Uses `GITHUB_ACTIONS` / `CI` env vars as secondary signals.

**Key takeaway:** `WT_SESSION` takes priority over build-number checks. The threshold values `10586` and `14931` are the cross-language consensus for Windows color capability boundaries.

#### termenv (Go) -- COLORTERM and WT_SESSION

termenv on Windows checks `COLORTERM=truecolor` and `WT_SESSION`. For terminal dimensions it wraps the `golang.org/x/term` package, which calls `GetConsoleScreenBufferInfo` with the `srWindow` calculation.

**Key takeaway:** The same two env var signals (`WT_SESSION`, `COLORTERM`) are used by all major Go/Node/Rust libraries. Build-number detection is the Windows-specific fallback when these are absent.

#### colorama (Python) -- SetConsoleMode wrapper

colorama's Windows backend calls `GetConsoleMode` for TTY detection, then wraps stdout with a translation layer that emits Win32 color calls for ANSI sequences on builds prior to `ENABLE_VIRTUAL_TERMINAL_PROCESSING` support. On Windows 10 build 10586+, it sets `ENABLE_VIRTUAL_TERMINAL_PROCESSING` and passes ANSI through directly.

**Key takeaway:** The consensus across all libraries is to enable VT processing at startup rather than emulating ANSI sequences in software.

### What Termicap adopts and why

1. **GetConsoleMode for TTY detection**: Universal Windows equivalent of `isatty()`. Exactly the technique used by crossterm, colorama, and termcolor.

2. **srWindow for dimensions, not dwSize**: `dwSize` is the scrollback buffer height. `srWindow` is the visible window. Using `dwSize` is a known Windows bug. The `+1` is required because coordinates are inclusive on both ends.

3. **WT_SESSION checked before build number**: Windows Terminal has supported TrueColor since its first stable release. `WT_SESSION` is the reliable signal. This is the priority order used by supports-color and termenv.

4. **Build thresholds 10586 and 14931**: Derived from Microsoft documentation of VT support history. Cross-language consensus from supports-color, termenv, and crossterm.

5. **RtlGetNtVersionNumbers via dynamic load**: GetVersionEx is shimmed for compatibility; `RtlGetNtVersionNumbers` reads the true build number. Dynamic loading via `LoadLibraryA`/`GetProcAddress` is required because there is no import library for this undocumented ntdll export.

6. **Enable VT processing at TTY detection time**: Setting `ENABLE_VIRTUAL_TERMINAL_PROCESSING` at detection time ensures that downstream code can emit ANSI sequences without further setup.

---

## C. Package Design

### Package hierarchy (additions for this feature)

```
Termicap.Win32_Color    [spec: SPARK, Detect_Windows_Color_Level: SPARK_Mode => Off]
                         -- Build_To_Color_Level (pure, SPARK Silver)
                         -- Detect_Windows_Color_Level (impure wrapper)

Termicap.Win32_Ntdll    [SPARK_Mode => Off]
                         -- Get_Build_Number (dynamic load of RtlGetNtVersionNumbers)

Termicap.Win32_VT       [SPARK_Mode => Off]
                         -- ENABLE_VIRTUAL_TERMINAL_PROCESSING constant
                         -- Is_Valid_Handle, Open_Console_Input, Open_Console_Output
                         -- Close_Handle, Enable_VT_Processing
```

All three packages reside in `src/windows/` and are compiled only on Windows targets.

The existing package specs (`Termicap.TTY`, `Termicap.Dimensions`, `Termicap.Capabilities`) are unchanged. Their Windows bodies in `src/windows/` receive full implementations that call into `Termicap.Win32_VT`, `Termicap.Win32_Color`, and `Termicap.Win32_Ntdll`.

### SPARK boundaries

| Package | SPARK_Mode (spec) | SPARK_Mode (body) | Rationale |
|---------|------------------|------------------|-----------|
| `Termicap.Win32_Color` | On | Off (body) | Spec declares `Build_To_Color_Level` as SPARK Silver with postconditions. `Detect_Windows_Color_Level` is annotated `SPARK_Mode => Off` directly on the subprogram because it calls `Win32_Ntdll.Get_Build_Number` (SPARK_Mode => Off). |
| `Termicap.Win32_Ntdll` | Off | Off | Entire package is SPARK_Mode => Off. Uses `Unchecked_Conversion` of a `FARPROC` and calls dynamic-loaded code; no SPARK analysis possible. |
| `Termicap.Win32_VT` | Off | Off | Entire package is SPARK_Mode => Off. Wraps win32ada FFI calls for handle validation, CONIN$/CONOUT$, and console mode manipulation. |
| `Termicap.TTY` (windows body) | On (spec) | Off (body) | Body calls `Win32.Wincon.GetConsoleMode` and `Win32_VT.Enable_VT_Processing` via win32ada. SPARK cannot verify FFI calls. |
| `Termicap.Dimensions` (windows body) | On (spec) | Off (body) | Body calls `Win32.Wincon.GetConsoleScreenBufferInfo` via win32ada. Env var fallback is pure but resides in the same Off body. |

### Dependency graph

```
Termicap.Capabilities
   |-- Termicap.TTY [windows body]
   |     |-- Termicap.Win32_VT
   |     |     |-- Win32, Win32.Winnt, Win32.Wincon, Win32.Winbase
   |     |-- Termicap.Override
   |
   |-- Termicap.Dimensions [windows body]
   |     |-- Termicap.Win32_VT
   |     |-- Termicap.Environment
   |
   |-- Termicap.Color [calls Detect_Windows_Color_Level on Windows]
         |-- Termicap.Win32_Color
               |-- Termicap.Win32_Ntdll
               |     |-- Win32.Winbase (LoadLibraryA, GetProcAddress, FreeLibrary)
               |-- Termicap.Environment
               |-- Termicap.Color (Color_Level type)
```

`Termicap.Win32_Color.Build_To_Color_Level` has no dependencies beyond `Termicap.Color.Color_Level` and `Interfaces.Unsigned_32` -- it is a pure function with `Global => null`.

### How Termicap.Color invokes the Windows path

`Termicap.Color.Detect_Color_Level` already contains the `NO_COLOR`/`FORCE_COLOR`/`CLICOLOR` cascade. On Windows, the build-number and `WT_SESSION` check produces the initial color level that feeds into this cascade. This is implemented by calling `Termicap.Win32_Color.Detect_Windows_Color_Level (Env)` from the Windows body of `Termicap.Color` in place of the POSIX `TERM`-based heuristics.

---

## D. Data Types and Constants

### Win32 types (from win32ada)

| win32ada Type | Ada mapping | Usage |
|---------------|-------------|-------|
| `Win32.Winnt.HANDLE` | `subtype of Win32.PVOID` | Console and file handles |
| `Win32.DWORD` | `subtype of Interfaces.C.unsigned_long` | Mode flags, build number raw value |
| `Win32.BOOL` | `Interfaces.C.int` | Win32 TRUE/FALSE return values |
| `Win32.Wincon.COORD` | C record with X, Y : Win32.SHORT | Buffer and window dimensions |
| `Win32.Wincon.SMALL_RECT` | C record with Left, Top, Right, Bottom : Win32.SHORT | Window rectangle |
| `Win32.Wincon.CONSOLE_SCREEN_BUFFER_INFO` | C record | Full screen buffer info |

### Termicap.Win32_Color types

```ada
subtype Build_Number is Interfaces.Unsigned_32;
```

### Constants

| Constant | Value | Package | Requirement |
|----------|-------|---------|-------------|
| `ENABLE_VIRTUAL_TERMINAL_PROCESSING` | `16#0004#` | `Termicap.Win32_VT` | FUNC-WIN-009 |
| `Win32.Winbase.STD_INPUT_HANDLE` | `To_DWORD(-10)` | win32ada | FUNC-WIN-002 |
| `Win32.Winbase.STD_OUTPUT_HANDLE` | `To_DWORD(-11)` | win32ada | FUNC-WIN-002 |
| `Win32.Winbase.STD_ERROR_HANDLE` | `To_DWORD(-12)` | win32ada | FUNC-WIN-002 |
| `Win32.Winbase.INVALID_HANDLE_VALUE` | `-1` (pointer-sized) | win32ada | FUNC-WIN-001 |

### Build number thresholds

| Threshold | Build | Windows version |
|-----------|-------|-----------------|
| Minimum (256-color) | 10586 | Windows 10 November 2015 Update (1511) |
| TrueColor | 14931 | Windows 10 Anniversary Update branch |

---

## E. Algorithms

### TTY detection (FUNC-WIN-003)

```
function Is_TTY (Stream : Stream_Kind) return Boolean:

   -- Check FORCE_COLOR / NO_COLOR overrides first (existing logic)
   ...

   -- Map Stream to a Win32 standard handle constant
   Handle_Const :=
      (case Stream is
         when Stdin  => Win32.Winbase.STD_INPUT_HANDLE
         when Stdout => Win32.Winbase.STD_OUTPUT_HANDLE
         when Stderr => Win32.Winbase.STD_ERROR_HANDLE)

   H := Win32.Winbase.GetStdHandle (Handle_Const)
   if not Is_Valid_Handle (H) then return False

   -- GetConsoleMode succeeds only on a real console handle
   Mode : aliased Win32.DWORD := 0
   if Win32.Wincon.GetConsoleMode (H, Mode'Access) = Win32.FALSE then
      return False

   -- Enable VT processing while we have the handle
   _ := Win32_VT.Enable_VT_Processing (H)
   return True
```

### Terminal dimensions (FUNC-WIN-005)

```
function Get_Size (Env : Environment; Is_TTY : Boolean) return Terminal_Size:

   Result := DEFAULT_SIZE   -- 80 x 24, pixel = 0

   if Is_TTY then
      H := Win32.Winbase.GetStdHandle (STD_OUTPUT_HANDLE)
      if Is_Valid_Handle (H) then
         Info : aliased CONSOLE_SCREEN_BUFFER_INFO
         if Win32.Wincon.GetConsoleScreenBufferInfo (H, Info'Access) /= Win32.FALSE then
            -- Use srWindow, NOT dwSize (srWindow = visible window, dwSize = scrollback buffer)
            Cols := Integer (Info.srWindow.Right  - Info.srWindow.Left + 1)
            Rows := Integer (Info.srWindow.Bottom - Info.srWindow.Top  + 1)
            if Cols > 0 and Rows > 0 then
               Result.Columns      := Cols
               Result.Rows         := Rows
               Result.Pixel_Width  := 0   -- Win32 API provides no pixel dimensions
               Result.Pixel_Height := 0
               return Result
            end if
         end if
      end if
   end if

   -- Fallback: COLUMNS / LINES env vars, then defaults (same logic as POSIX body)
   if Contains (Env, "COLUMNS") then ... end if
   if Contains (Env, "LINES")   then ... end if
   return Result
```

### Build number detection (FUNC-WIN-006)

```
function Get_Build_Number return Interfaces.Unsigned_32:

   HModule := Win32.Winbase.LoadLibraryA ("ntdll.dll")
   if HModule = null then return 0

   Proc := Win32.Winbase.GetProcAddress (HModule, "RtlGetNtVersionNumbers")
   if Proc = null then
      Win32.Winbase.FreeLibrary (HModule)
      return 0

   -- Unchecked_Conversion of FARPROC to typed access-to-procedure
   type Rtl_Get_Nt_Version_Numbers_Ptr is access procedure
      (Major_Version : out Win32.DWORD;
       Minor_Version : out Win32.DWORD;
       Build_Number  : out Win32.DWORD)
      with Convention => Stdcall;

   Fn := Rtl_Ptr_Conv (Proc)  -- Unchecked_Conversion
   Major, Minor, Build : Win32.DWORD
   Fn (Major, Minor, Build)

   -- Mask off high 4 bits (flags); low 16 bits are the build number
   Build := Build and 16#0000_FFFF#

   Win32.Winbase.FreeLibrary (HModule)
   return Interfaces.Unsigned_32 (Build)
```

### Color level mapping (FUNC-WIN-007, FUNC-WIN-008)

```
function Build_To_Color_Level
   (Build : Build_Number; Has_WT_Session : Boolean) return Color_Level:

   if Has_WT_Session then return True_Color   -- FUNC-WIN-007: WT_SESSION override

   if Build >= 14_931 then return True_Color
   elsif Build >= 10_586 then return Extended_256
   else return None
```

### Enable VT processing (FUNC-WIN-011)

```
function Enable_VT_Processing (H : Win32.Winnt.HANDLE) return Boolean:

   Current_Mode : aliased Win32.DWORD := 0
   if Win32.Wincon.GetConsoleMode (H, Current_Mode'Access) = Win32.FALSE then
      return False

   -- Guard: already enabled, avoid unnecessary SetConsoleMode call
   if (Current_Mode and ENABLE_VIRTUAL_TERMINAL_PROCESSING) /= 0 then
      return True

   New_Mode := Current_Mode or ENABLE_VIRTUAL_TERMINAL_PROCESSING
   return Win32.Wincon.SetConsoleMode (H, New_Mode) /= Win32.FALSE
```

---

## F. SPARK Contracts

### Build_To_Color_Level (FUNC-WIN-013)

```ada
function Build_To_Color_Level
  (Build          : Build_Number;
   Has_WT_Session : Boolean)
   return Termicap.Color.Color_Level
with
  Global => null,
  Post   =>
     (if Has_WT_Session then
        Build_To_Color_Level'Result = Termicap.Color.True_Color)
     and then Build_To_Color_Level'Result in
        Termicap.Color.None | Termicap.Color.Extended_256
          | Termicap.Color.True_Color;
```

The postcondition serves two purposes:
- The `Has_WT_Session` implication documents and proves the FUNC-WIN-007 override rule.
- The membership test `in None | Extended_256 | True_Color` acts as an exhaustiveness check: any branch that accidentally returns `Basic_16` would cause a proof failure. This is the documented SPARK Silver target for detection logic.

### Spec-level contracts for TTY and Dimensions

The existing `Global => null` contracts on `Termicap.TTY.Is_TTY` and `Termicap.Dimensions.Get_Size` are retained unchanged. The Windows bodies are `SPARK_Mode => Off`, so GNATprove does not verify the body implementations. This is the same pattern used by all platform-specific bodies in the library.

---

## G. Implementation Plan

### Phase 1: New packages (specs already written)

The three new `src/windows/` specs are committed:
- `termicap-win32_color.ads` -- `Build_To_Color_Level` (SPARK) + `Detect_Windows_Color_Level`
- `termicap-win32_ntdll.ads` -- `Get_Build_Number`
- `termicap-win32_vt.ads` -- `Is_Valid_Handle`, CONIN$/CONOUT$ ops, `Enable_VT_Processing`

**Deliverable:** Implement the three corresponding bodies in `src/windows/`.

| File | Body work |
|------|-----------|
| `src/windows/termicap-win32_ntdll.adb` | `LoadLibraryA` + `GetProcAddress` + `Unchecked_Conversion` + `FreeLibrary` |
| `src/windows/termicap-win32_vt.adb` | `Is_Valid_Handle` + `CreateFileA` CONIN$/CONOUT$ + `Enable_VT_Processing` read-modify-write |
| `src/windows/termicap-win32_color.adb` | `Build_To_Color_Level` three-branch function + `Detect_Windows_Color_Level` orchestration |

### Phase 2: Replace stub bodies

| File | Current state | Full implementation |
|------|--------------|---------------------|
| `src/windows/termicap-tty.adb` | Always returns False | `GetStdHandle` + `GetConsoleMode` + `Enable_VT_Processing` |
| `src/windows/termicap-dimensions.adb` | Env var + default only | `GetConsoleScreenBufferInfo` with `srWindow` calculation + existing env var fallback |

`termicap-capabilities.adb`, `termicap-osc.adb`, and `termicap-sigwinch.adb` require no changes: the Capabilities body is already platform-agnostic; OSC and Sigwinch are correct no-op stubs on Windows.

### Phase 3: Wire color detection

`Termicap.Color.Detect_Color_Level` calls different detection logic per platform. On Windows, the `TERM`-based heuristics are replaced by a call to `Termicap.Win32_Color.Detect_Windows_Color_Level (Env)` in the Windows body. The NO_COLOR / FORCE_COLOR / CLICOLOR cascade that wraps this result is platform-agnostic and unchanged.

### No build system changes required

The GPR file already dispatches via `Source_Dirs use ("src/", "config/", "src/" & Termicap_Config.Alire_Host_OS)` on Windows. The win32ada conditional dependency in `alire.toml` is already declared. No new GPR attributes or Alire dependencies are needed.

---

## H. SPARK Boundary Table

| Package / Subprogram | SPARK_Mode | Reason |
|----------------------|-----------|--------|
| `Termicap.Win32_Color` spec | On | Declares `Build_To_Color_Level` with Silver contracts |
| `Termicap.Win32_Color.Build_To_Color_Level` body | On | Pure arithmetic + enumeration comparison; no FFI |
| `Termicap.Win32_Color.Detect_Windows_Color_Level` | Off | Calls `Win32_Ntdll.Get_Build_Number` (SPARK_Mode => Off) |
| `Termicap.Win32_Ntdll` | Off | Unchecked_Conversion of FARPROC; dynamic code invocation |
| `Termicap.Win32_VT` | Off | Wraps win32ada FFI (GetConsoleMode, SetConsoleMode, CreateFileA, CloseHandle) |
| `Termicap.TTY` spec | On | Spec unchanged; `Global => null` contract retained |
| `Termicap.TTY` windows body | Off | Calls GetStdHandle + GetConsoleMode (win32ada, FFI) |
| `Termicap.Dimensions` spec | On | Spec unchanged; `Global => null` contract retained |
| `Termicap.Dimensions` windows body | Off | Calls GetConsoleScreenBufferInfo (win32ada, FFI) |
| `Termicap.Capabilities` windows body | Off | Orchestration body; mixed deps |
| `Termicap.OSC` windows body | Off | No-op stub; SPARK_Mode => Off retained |
| `Termicap.Sigwinch` windows body | Off | No-op stub; SPARK_Mode => Off retained |

---

## I. Testing Coverage Table

| Test | Mechanism | CI-safe |
|------|-----------|---------|
| `Build_To_Color_Level` -- all three branches (None, 256, TrueColor) | Unit test, pure path, `Is_TTY => False` | Yes |
| `Build_To_Color_Level` -- `Has_WT_Session => True` overrides any build | Unit test | Yes |
| `Build_To_Color_Level` -- boundary values: 10585, 10586, 14930, 14931 | Unit test | Yes |
| `Detect_Windows_Color_Level` -- `WT_SESSION` present in env | Unit test with programmatic env snapshot | Yes |
| `Detect_Windows_Color_Level` -- `WT_SESSION` absent, real build number path | Integration, Windows-only CI | Windows only |
| `Is_TTY` returns False in CI (stdout redirected) | Existing TTY test suite | Yes |
| `Get_Size` -- env var fallback (COLUMNS/LINES) | Existing dimensions test suite | Yes |
| `Get_Size` -- default 80x24 | Existing dimensions test suite | Yes |
| `Get_Size` -- real console on Windows interactive | Manual / Windows-only CI | Windows only |
| `Enable_VT_Processing` -- already-enabled guard (mode read shows flag set) | Unit test with mock handle | Windows only |
| `Get_Build_Number` -- returns non-zero on Windows 10+ | Integration, Windows-only CI | Windows only |

The pure unit tests (`Build_To_Color_Level` and env var fallback paths) run on all platforms because they exercise no Win32 FFI. The integration tests (real console handle, real build number) run only in Windows CI environments.

---

## J. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `RtlGetNtVersionNumbers` not present on a Windows build | Very low | Medium | Dynamic load returns 0 on failure; 0 maps to `Color_None` which is safe |
| `GetConsoleMode` fails unexpectedly on a valid console | Very low | Low | Returns False (not TTY); downstream code handles non-TTY correctly |
| `SetConsoleMode` fails (pre-10586, or no VT support) | Low (legacy) | Low | Non-fatal; color level already set to `Color_None` for pre-10586 builds |
| `srWindow` returns 0-width or 0-height on degenerate consoles | Very low | Low | Fallback to env vars and then 80x24 default |
| win32ada type layout mismatch with actual Win32 structs | Very low | High | win32ada has been in production use for years with GNAT; well-tested layouts |
| Cygwin/MSYS2 PTY masquerades as a Win32 console | Low | Medium | Out of scope for this feature; documented as a known limitation |

---

## K. File Manifest

### Files to implement (bodies)

| File | Action | SPARK |
|------|--------|-------|
| `src/windows/termicap-win32_ntdll.adb` | Create | Off |
| `src/windows/termicap-win32_vt.adb` | Create | Off |
| `src/windows/termicap-win32_color.adb` | Create | Off / On (Build_To_Color_Level body) |
| `src/windows/termicap-tty.adb` | Replace stub | Off |
| `src/windows/termicap-dimensions.adb` | Replace stub (Is_TTY path) | Off |

### Files already complete (no changes)

| File | Status |
|------|--------|
| `src/windows/termicap-win32_color.ads` | Phase 3 spec complete |
| `src/windows/termicap-win32_ntdll.ads` | Phase 3 spec complete |
| `src/windows/termicap-win32_vt.ads` | Phase 3 spec complete |
| `src/windows/termicap-capabilities.adb` | Platform-agnostic orchestration; complete |
| `src/windows/termicap-osc.adb` | No-op stub; correct and complete |
| `src/windows/termicap-sigwinch.adb` | No-op stub; correct and complete |
| `termicap.gpr` | Platform dispatch already implemented |
| `alire.toml` | win32ada conditional dependency already declared |

---

## Appendix: Requirements Traceability

| Requirement | API / Package Element | SPARK |
|-------------|----------------------|-------|
| FUNC-WIN-001 | `Termicap.Win32_VT.Is_Valid_Handle`, win32ada `HANDLE`/`INVALID_HANDLE_VALUE` | Off |
| FUNC-WIN-002 | `Win32.Winbase.GetStdHandle` (win32ada) | Off |
| FUNC-WIN-003 | `Win32.Wincon.GetConsoleMode` in `Termicap.TTY` windows body | Off |
| FUNC-WIN-004 | `Termicap.Win32_VT.Open_Console_Input`, `Open_Console_Output`, `Close_Handle` | Off |
| FUNC-WIN-005 | `Win32.Wincon.GetConsoleScreenBufferInfo` in `Termicap.Dimensions` windows body; `srWindow` calculation | Off |
| FUNC-WIN-006 | `Termicap.Win32_Ntdll.Get_Build_Number`; dynamic load + mask | Off |
| FUNC-WIN-007 | `Termicap.Win32_Color.Build_To_Color_Level` `Has_WT_Session` path; `Detect_Windows_Color_Level` reads env | Silver (postcondition) / Off |
| FUNC-WIN-008 | `Termicap.Win32_Color.Build_To_Color_Level` three-branch mapping | Silver |
| FUNC-WIN-009 | `Termicap.Win32_VT.ENABLE_VIRTUAL_TERMINAL_PROCESSING` constant | Off |
| FUNC-WIN-010 | `Win32.Wincon.SetConsoleMode` (win32ada) in `Enable_VT_Processing` | Off |
| FUNC-WIN-011 | `Termicap.Win32_VT.Enable_VT_Processing` read-modify-write | Off |
| FUNC-WIN-012 | win32ada as primary FFI; `Termicap.Win32_Ntdll` as sole custom FFI | Off |
| FUNC-WIN-013 | `Build_To_Color_Level` SPARK postconditions (`Global => null`, `Post =>` membership + implication) | Silver |
