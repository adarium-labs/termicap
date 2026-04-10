# Platform dispatch via Source_Dirs with Alire_Host_OS subdirectories

* Status: Accepted
* Deciders: Heziode
* Date: 2026-04-10

## Context and Problem Statement

Termicap targets multiple operating systems (Linux, macOS, FreeBSD, Windows). Several packages require completely different body implementations per platform -- `Termicap.TTY`, `Termicap.Dimensions`, `Termicap.Sigwinch`, `Termicap.OSC`, and `Termicap.Capabilities`. The package specs must remain identical across all platforms to preserve a single public API.

How should the build system select the correct platform-specific body files without requiring conditional compilation in Ada source or separate per-OS crates?

## Decision Drivers

* Package specs must be identical across all platforms (same types, same subprogram signatures, same SPARK contracts)
* Body selection must be automatic at build time with no source-level preprocessor directives in Ada
* The solution must be expressible in GPR without external tools or scripts
* win32ada (a Windows-only dependency) must not be compiled on POSIX targets; C helpers must not be compiled on Windows
* Alire already injects `Alire_Host_OS` into the generated config GPR as a string constant (`"linux"`, `"windows"`, `"macos"`, `"freebsd"`)
* The mechanism should be easy to extend to additional platforms in the future

## Considered Options

* **Option A**: `Source_Dirs` with OS-named subdirectories (`src/linux/`, `src/windows/`) selected via `Alire_Host_OS`
* **Option B**: GNAT preprocessor (`-gnatep`) with `#if` directives in single body files
* **Option C**: Separate Alire crates per platform (`termicap-linux`, `termicap-windows`) with a common `termicap-common` dependency
* **Option D**: Single body file with `Ada.Environment.Value ("OS")` runtime dispatch

## Decision Outcome

Chosen option: **Option A** (`Source_Dirs` with OS subdirectories), because it is the standard GPR mechanism for platform dispatch, keeps each platform's code isolated and readable, requires no preprocessor or runtime checks, and is directly supported by the `Alire_Host_OS` variable already available from Alire's config generation.

The GPR file selects source directories as follows:

```gpr
case Host_OS is
   when "windows" =>
      for Languages use ("Ada");
      for Source_Dirs use ("src/", "config/", "src/" & Termicap_Config.Alire_Host_OS);
   when others =>
      for Languages use ("Ada", "C");
      for Source_Dirs use ("src/", "src/c/", "config/", "src/" & Termicap_Config.Alire_Host_OS);
end case;
```

On Windows, `src/windows/` is appended. On Linux, `src/linux/` is appended. On macOS, `src/macos/`. The C source directory `src/c/` (containing `termicap_ioctl.c`, `termicap_sigwinch.c`, `termicap_osc.c`) is included only on non-Windows platforms; Windows uses win32ada Ada bindings instead.

Each OS subdirectory contains only body files (`.adb`). All spec files (`.ads`) remain in `src/`. When `gprbuild` encounters two files with the same package name, one in `src/` and one in `src/linux/`, the body in the OS subdirectory shadows any body in `src/`. This is the standard GPR multi-directory body override mechanism.

### Positive Consequences

* Zero source-level conditional compilation: each platform's body reads as clean, unconditional Ada
* The `SPARK_Mode` annotation on each body is independent: Windows bodies can be `SPARK_Mode => Off` without affecting Linux bodies
* Adding a new platform requires only creating a new `src/<os>/` subdirectory and adding its name to the GPR `OS_Type` enumeration
* Compiler flags can also be varied per platform in the same `case Host_OS` block (as done for `-gnatyM120` + `-gnateG` on Windows for win32ada compatibility)
* win32ada is never compiled or linked on POSIX builds; C helpers are never compiled on Windows builds

### Negative Consequences

* A developer must know to look in `src/<os>/` for the platform-specific body, not in `src/`
* Renaming a platform-dispatched package requires updating files in every OS subdirectory
* There is no compile-time check that all platforms provide a body for every dispatched package; a missing body would surface as a linker error

## Pros and Cons of the Options

### Option A: Source_Dirs with OS subdirectories (chosen)

The GPR file uses `"src/" & Termicap_Config.Alire_Host_OS` to include the appropriate OS subdirectory. Body files in `src/linux/`, `src/windows/`, etc. shadow any body of the same package name in `src/`.

* Good, because this is the canonical GPR pattern for platform dispatch (used by GNATColl, AWS, and other Ada libraries)
* Good, because no preprocessor directives in Ada source
* Good, because each platform's code is fully isolated from others
* Good, because `Alire_Host_OS` is already injected by Alire at no additional cost
* Good, because the C/Ada language split per platform is expressible in the same `case` block
* Bad, because the developer must know the `src/<os>/` layout convention
* Bad, because a missing body file causes a linker error rather than a compiler error

### Option B: GNAT preprocessor with #if directives

Use `-gnatep` preprocessing with `#if OS = "windows"` guards in single body files, similar to C's `#ifdef WIN32`.

* Good, because all variants of a body are visible in one file
* Bad, because GNAT's preprocessor is non-standard Ada and GNAT-specific
* Bad, because `#if` blocks in Ada bodies create visual noise and reduce readability
* Bad, because SPARK analysis on preprocessed files requires separate invocations per platform
* Bad, because win32ada imports mixed with POSIX imports in the same file require defensive preprocessing of all `with` clauses

### Option C: Separate Alire crates per platform

Create `termicap-linux`, `termicap-windows`, and `termicap-common` crates. The platform crates depend on `termicap-common` and provide the platform-specific bodies.

* Good, because dependency isolation is explicit in `alire.toml`
* Good, because `win32ada` appears only in `termicap-windows/alire.toml`
* Bad, because the crate proliferation adds significant maintenance overhead (three `alire.toml` files, three GPR files, three version numbers to keep in sync)
* Bad, because users must depend on `termicap-linux` or `termicap-windows` explicitly rather than a single `termicap` crate
* Bad, because renaming or reorganising the common API requires coordinated changes across multiple crates

### Option D: Runtime OS dispatch in a single body

Use a single body file that calls `Ada.Environment.Value ("OS")` at runtime to branch between Windows and POSIX code paths.

* Good, because only one body file to maintain per package
* Bad, because both win32ada and POSIX C helpers must be compiled on all platforms, forcing a win32ada dependency on Linux
* Bad, because a runtime branch for OS type is fragile (environment variable can be unset or wrong)
* Bad, because SPARK cannot verify branches that depend on runtime OS values
* Bad, because this approach is universally avoided in Ada/SPARK libraries for exactly these reasons

## Links

* [ADR-0019](0019-win32ada-as-ffi-layer.md) -- win32ada as the FFI layer for Win32 API calls
* [ADR-0006](0006-c-wrapper-for-ioctl-tiocgwinsz.md) -- C wrapper pattern (POSIX side of the same dispatch)
* [Tech Spec: WIN32 Windows Console API Integration](../tech-specs/windows-console.md)
* GPR Reference Manual -- `Source_Dirs` attribute and multi-directory body selection
* Alire documentation -- `Alire_Host_OS` config variable
