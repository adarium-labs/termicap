# win32ada Alire crate as the primary FFI layer for Win32 API calls

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-10

## Context and Problem Statement

The Windows Console API integration requires Ada bindings for approximately 15 Win32 functions and 8 record types: `GetStdHandle`, `GetConsoleMode`, `SetConsoleMode`, `GetConsoleScreenBufferInfo`, `CreateFileA`, `CloseHandle`, `LoadLibraryA`, `GetProcAddress`, `FreeLibrary`, `HANDLE`, `DWORD`, `BOOL`, `COORD`, `SMALL_RECT`, `CONSOLE_SCREEN_BUFFER_INFO`, `INVALID_HANDLE_VALUE`, and the `STD_*_HANDLE` constants.

How should the library obtain these Win32 bindings: write custom `pragma Import` declarations for each, or reuse the `win32ada` Alire crate that provides them?

## Decision Drivers

* Win32 calling convention is `Stdcall`, not the C default; every `pragma Import` must specify `Convention => Stdcall` or use a dedicated convention identifier
* Record types such as `CONSOLE_SCREEN_BUFFER_INFO` require `pragma Convention (C, ...)` with correct field ordering and alignment, which must exactly match the Windows SDK layout
* `INVALID_HANDLE_VALUE` is `-1` interpreted as a pointer-sized unsigned integer (0xFFFFFFFFFFFFFFFF on 64-bit); the type must be declared correctly or handle comparison will fail
* The library targets SPARK Silver; FFI declarations must be quarantined in `SPARK_Mode => Off` regions regardless of their source
* win32ada is available on the Alire index, is in production use in GNAT projects, and covers the full Win32 surface needed by Termicap
* The win32ada dependency must be conditional (Windows only) so it is never compiled on POSIX targets

## Considered Options

* **Option A**: Use the `win32ada` Alire crate as the primary FFI layer; write custom FFI only for APIs not covered by win32ada
* **Option B**: Write all Win32 FFI declarations from scratch using `pragma Import` and Ada record representation clauses
* **Option C**: Use GNAT's `Interfaces.Win32` package (GNAT-specific runtime addition for Windows)

## Decision Outcome

Chosen option: **Option A** (win32ada as primary FFI layer), because it eliminates hundreds of lines of fragile, manually-maintained FFI declarations, provides correctly typed and Stdcall-convention bindings that have been tested across GNAT versions, and is already available in the Alire ecosystem with no new infrastructure required.

The only custom FFI code written by Termicap is `Termicap.Win32_Ntdll`, which dynamically resolves `RtlGetNtVersionNumbers` from ntdll.dll using `LoadLibraryA` and `GetProcAddress` (themselves provided by win32ada). `RtlGetNtVersionNumbers` is an undocumented ntdll export with no corresponding `.lib` import library in any public Windows SDK, making it impossible to bind via a static `pragma Import`.

The win32ada dependency is declared in `alire.toml` as a conditional dependency, active only when `Alire_Host_OS = "windows"`, so it is never fetched, compiled, or linked on POSIX targets.

The win32ada packages used by Termicap:

| win32ada package | Termicap usage |
|-----------------|---------------|
| `Win32` | `DWORD`, `BOOL`, `SHORT`, `PVOID`, base type definitions |
| `Win32.Winnt` | `HANDLE` type |
| `Win32.Winbase` | `GetStdHandle`, `CreateFileA`, `CloseHandle`, `LoadLibraryA`, `GetProcAddress`, `FreeLibrary`, `INVALID_HANDLE_VALUE`, `STD_*_HANDLE` |
| `Win32.Wincon` | `GetConsoleMode`, `SetConsoleMode`, `GetConsoleScreenBufferInfo`, `COORD`, `SMALL_RECT`, `CONSOLE_SCREEN_BUFFER_INFO` |

The only item not provided by win32ada is `ENABLE_VIRTUAL_TERMINAL_PROCESSING` (value `16#0004#`), a Windows 10 console flag added after win32ada's original development. This constant is declared directly in `Termicap.Win32_VT`.

### Positive Consequences

* Eliminates custom FFI for 15 Win32 functions and 8 record types -- approximately 200 lines of pragma Import, Convention, and representation clause declarations
* Correct Stdcall convention is guaranteed by win32ada; no risk of calling convention mismatch
* `CONSOLE_SCREEN_BUFFER_INFO` record layout matches the Windows SDK exactly, avoiding field order or alignment bugs
* `INVALID_HANDLE_VALUE` is correctly typed as `Win32.Winnt.HANDLE` (subtype of `Win32.PVOID`), so comparison with `Is_Valid_Handle` works correctly on both 32-bit and 64-bit targets
* win32ada is a conditional dependency: zero impact on build times and binary size on POSIX platforms
* Future Win32 API additions only require a `with Win32.*` clause, not a new custom FFI declaration

### Negative Consequences

* Introduces a third-party dependency, which must be version-pinned in `alire.toml` and updated when win32ada releases
* win32ada's package hierarchy (`Win32.Wincon`, `Win32.Winbase`, etc.) is more verbose than custom declarations with shorter aliases would be
* `ENABLE_VIRTUAL_TERMINAL_PROCESSING` must be declared by Termicap since win32ada predates Windows 10's VT sequence support additions

## Pros and Cons of the Options

### Option A: win32ada crate (chosen)

The `win32ada` Alire crate (originally derived from the win32ada GNAT Studio binding project) provides comprehensive Ada bindings for the Win32 API including all console, file, and module functions needed by Termicap.

* Good, because provides correctly typed, Stdcall-convention bindings tested across GNAT versions
* Good, because record layouts (`COORD`, `SMALL_RECT`, `CONSOLE_SCREEN_BUFFER_INFO`) match the Windows SDK exactly
* Good, because `INVALID_HANDLE_VALUE` is correctly handled as a HANDLE-sized sentinel
* Good, because conditional Alire dependency means zero cost on POSIX platforms
* Good, because the Alire ecosystem makes the dependency reproducible and version-locked
* Bad, because adds a third-party dependency to track
* Bad, because win32ada's package names are verbose (`Win32.Wincon.GetConsoleMode` vs a hypothetical `Win32.GetConsoleMode`)
* Bad, because `ENABLE_VIRTUAL_TERMINAL_PROCESSING` is not present and must be declared by Termicap

### Option B: Custom pragma Import declarations from scratch

Write all FFI bindings manually, following the pattern established by `Termicap.Win32_Ntdll`.

* Good, because no external dependency; fully self-contained
* Good, because shorter package names are possible
* Bad, because approximately 200 lines of pragma Import and record representation clauses to write and maintain
* Bad, because `CONSOLE_SCREEN_BUFFER_INFO` has 5 fields with nested records (`COORD`, `SMALL_RECT`); a manual mapping is error-prone
* Bad, because `INVALID_HANDLE_VALUE` must be manually typed; getting the type wrong produces silent comparison failures on 64-bit
* Bad, because Stdcall convention must be specified on every function; a missed `Convention => Stdcall` causes a stack corruption bug
* Bad, because the resulting FFI code is harder to audit than pointing to a known-good crate

### Option C: GNAT Interfaces.Win32

GNAT for Windows provides some Windows type definitions in `Interfaces.Win32` (or similar) as part of the GNAT runtime.

* Good, because no additional Alire dependency
* Bad, because `Interfaces.Win32` is a GNAT internal package not part of the Ada standard; its API and availability vary across GNAT versions and is not documented for general use
* Bad, because it provides type definitions but not function bindings; custom pragma Import declarations would still be needed for all 15 functions
* Bad, because depending on GNAT internal packages makes the library fragile across compiler versions

## Links

* [ADR-0018](0018-platform-dispatch-via-source-dirs.md) -- Platform dispatch via Source_Dirs (how win32ada is conditionally included)
* [Tech Spec: WIN32 Windows Console API Integration](../tech-specs/windows-console.md)
* Requirements: FUNC-WIN-001, FUNC-WIN-002, FUNC-WIN-006, FUNC-WIN-012
* win32ada Alire crate -- `alr search win32ada`
* Windows SDK `wincon.h` -- documents `ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004`
