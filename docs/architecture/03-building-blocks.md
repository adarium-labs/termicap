# arc42 §5: Building Blocks

Static structure of the Termicap library — packages, SPARK boundary layers, and their responsibilities.

## Level 1: Package Overview

```
Termicap                          (root namespace — no types or subprograms)
├── Termicap.Environment          [SPARK Silver] — environment snapshot type, query/builder API
│   └── Termicap.Environment.Capture  [SPARK_Mode => Off] — sole OS FFI boundary
├── Termicap.Override             [spec: SPARK, body: mixed] — process-wide color override, Override_Mode type, Parse_Color_Flag, Scoped_Override
├── Termicap.TTY                  [spec: SPARK, body: SPARK_Mode => Off] — TTY detection (depends on Termicap.Override)
├── Termicap.Color                [spec: SPARK, body: SPARK Silver] — color level detection (11-step cascade, depends on Termicap.Override)
│   ├── Termicap.Color.BG_Query       [SPARK Silver] — RGB type, OSC query constants, pure color response parsing
│   │   └── Termicap.Color.BG_Query.IO [SPARK_Mode => Off] — Query_Color I/O via Probe_Session
│   ├── Termicap.Color.Detection      [SPARK_Mode => Off] — Detect_Background/Foreground_Color cascade
│   └── Termicap.Color.Dark_Light     [SPARK Gold] — Theme_Kind, Luminance, Classify_Theme, Is_Dark, Is_Light
│       └── Termicap.Color.Dark_Light.Detect  [SPARK_Mode => Off] — Theme_Result, Detect_Theme
├── Termicap.Downsampling         [SPARK Gold]   — color downsampling conversions (TrueColor/256-color to lower levels)
├── Termicap.Dimensions           [spec: SPARK, body: SPARK_Mode => Off] — terminal size detection
├── Termicap.Sigwinch             [SPARK_Mode => Off] — SIGWINCH resize notification, self-pipe, protected object
├── Termicap.Unicode              [SPARK Silver] — Unicode support level detection (5-step cascade)
├── Termicap.Terminal_Id          [spec: SPARK, body: SPARK_Mode => Off] — terminal identity detection (8-step cascade)
├── Termicap.OSC                  [SPARK_Mode => Off] — probe session lifecycle, terminal I/O, FFI boundary
│   └── Termicap.OSC.Parsing      [SPARK Silver] — pure DA1 sentinel detection, response parsing, passthrough wrapping
├── Termicap.XTVERSION            [SPARK Silver] — XTVERSION_Status/Result/Payload_Slice/Token_Pair types, CSI_XTVERSION_QUERY constant, pure DCS parsing functions
│   └── Termicap.XTVERSION.IO     [SPARK_Mode => Off] — Query_XTVERSION I/O via Probe_Session, Query_And_Identify convenience function
├── Termicap.DA1                  [SPARK Silver] — DA1_Capability/VT_Level/Capability_Flags/DA1_Capabilities types, DA1_QUERY constant, pure interpretation functions
│   └── Termicap.DA1.IO           [SPARK_Mode => Off] — Query_DA1 timeout-only I/O via Probe_Session, Detect_DA1 convenience function
├── Termicap.DECRPM               [SPARK Silver] — Mode_Id/Mode_Status/Mode_Report/Mode_Id_Array/Mode_Report_Array types, MODE_* named constants, DECRPM_Query construction function, pure response recognition and parsing functions
│   └── Termicap.DECRPM.IO        [SPARK_Mode => Off] — Query_Mode/Detect_Mode/Detect_Modes I/O via Probe_Session; Query_Error/Mode_Query_Result/Batch_Query_Result types
├── Termicap.Keyboard             [SPARK Silver (spec + body)] — Keyboard_Protocol/Kitty_Flags/Keyboard_Capability/Parse_Result types; CSI query constants; pure Parse_Kitty_Flags/Parse_Kitty_Response/Parse_XTerm_Keyboard_Response parsers
│   └── Termicap.Keyboard.IO      [SPARK_Mode => Off] — Detect_Keyboard_Protocol (cached) and Probe_Keyboard_Protocol (uncached); platform-dispatched (POSIX/Windows) via GPR Source_Dirs
├── Termicap.Mouse                [SPARK Silver (spec)] — Mouse_Encoding/Mouse_Capabilities/DECRPM_Parse_Result types; MODE_MOUSE_* constants; pure Parse_Mouse_DECRPM_Response and Resolve_Best_Encoding functions
│   └── Termicap.Mouse.IO         [SPARK_Mode => Off] — Detect_Mouse_Protocols (cached) and Probe_Mouse_Protocols (uncached); platform-dispatched (POSIX/Windows) via GPR Source_Dirs
├── Termicap.Graphics             [SPARK Silver (spec)] — Graphics_Capabilities record; APC_Parse_Result enumeration; 11 named constants (TERM_*, TERM_PROGRAM_*, ENV_*, XTVERSION_*); KITTY_APC_QUERY byte array; GRAPHICS_PROBE_TIMEOUT_MS; pure Parse_Kitty_APC_Response function
│   └── Termicap.Graphics.IO      [SPARK_Mode => Off] — Detect_Graphics (cached) and Detect_Graphics_Uncached; platform-dispatched (POSIX/Windows) via GPR Source_Dirs
├── Termicap.Clipboard            [SPARK Silver (spec + body)] — Clipboard_Support enumeration; Clipboard_Capabilities result record; 9 named constants (TERM_PROGRAM_*, ENV_*, TERM_*); OSC52_QUERY byte array; CLIPBOARD_PROBE_TIMEOUT_MS; OSC52_Parse_Result enumeration; pure Parse_OSC52_Response function
│   └── Termicap.Clipboard.IO     [SPARK_Mode => Off] — Detect_Clipboard (cached) and Detect_Clipboard_Uncached; platform-dispatched (POSIX/Windows) via GPR Source_Dirs
├── Termicap.Terminfo             [SPARK Silver (spec + body)] — Terminfo_Snapshot/Result/Error types; bounded string types; magic/index/limit constants; ghost predicates Header_Is_Valid/Extended_Is_Valid; pure Detect_Format, Parse_Header, Get_Boolean, Get_Numeric, Get_String, Parse_Extended_Header, Extract_Truecolor_Flags, Parse_Buffer functions
│   └── Termicap.Terminfo.IO      [SPARK_Mode => Off (body)] — Read_File POSIX file I/O; Parse_Terminfo top-level search-path + parse entry point
└── Termicap.Capabilities         [spec: SPARK, body: mixed] — aggregated capability record; Get (cached) and Detect (fresh) entry points
```

### Windows Platform Packages (`src/windows/`)

On Windows, a set of platform-specific packages is compiled instead of (or alongside) the POSIX bodies. They are selected automatically via GPR `Source_Dirs` (ADR-0018) and are never referenced directly by application code.

```
Termicap.Win32_Ntdll    [SPARK_Mode => Off] — dynamic load of ntdll.dll; RtlGetNtVersionNumbers → Windows build number;
                         extended with Query_Object_Name (NtQueryObject wrapper for pipe name retrieval)
Termicap.Win32_VT       [SPARK_Mode => Off] — Is_Valid_Handle, Open/Close CONIN$/CONOUT$, Enable_VT_Processing
Termicap.Win32_Color    [SPARK_Mode (body Off)] — Build_To_Color_Level (SPARK Silver), Detect_Windows_Color_Level (impure wrapper)
Termicap.Win32_Cygwin   [spec: SPARK_Mode => On; body: Off (Is_Cygwin_Pipe_Name body locally On)] —
                         Cygwin/MSYS2 PTY detection via named-pipe name inspection;
                         Is_Cygwin_Pipe_Name (SPARK Silver, Global => null), Is_Cygwin_Terminal (Ada FFI)
```

Platform-dispatched bodies (replacing the POSIX equivalents on Windows):

- `src/windows/termicap-tty.adb` — TTY detection via `GetConsoleMode`; calls `Win32_VT.Enable_VT_Processing` on success; falls back to `Win32_Cygwin.Is_Cygwin_Terminal` for Cygwin/MSYS2 PTY handles (FUNC-CYG-015)
- `src/windows/termicap-dimensions.adb` — terminal size via `GetConsoleScreenBufferInfo`, reads `srWindow` (not `dwSize`)
- `src/windows/termicap-capabilities.adb` — integrates `Win32_Color.Detect_Windows_Color_Level`; final color is `Color_Level'Max (Win32_Level, env_cascade_level)`
- `src/windows/termicap-sigwinch.adb` — no-op stubs (SIGWINCH does not exist on Windows; FUNC-SWC-008)
- `src/windows/termicap-keyboard-io.adb` — keyboard protocol detection via `GetConsoleMode (STD_INPUT_HANDLE)` fast-path gate; falls through to POSIX-style Kitty/XTerm probe cascade for Cygwin/MSYS2 PTY handles (FUNC-KKB-010)

`Termicap.Color` and `Termicap.TTY` both depend on `Termicap.Override` for the short-circuit override check at the top of their detection functions. `Termicap.Override` itself has no dependency on `Termicap.Environment`, `Termicap.TTY`, `Termicap.Color`, or any OS interface — it is a leaf dependency in the graph. `Termicap.Dimensions`, `Termicap.Sigwinch`, `Termicap.Unicode`, and `Termicap.Terminal_Id` depend on `Termicap.Environment` but not on `Termicap.Override`. `Termicap.Color` and `Termicap.Dimensions` receive TTY status as a plain `Boolean` parameter — they do **not** depend on `Termicap.TTY` directly. `Termicap.Unicode` and `Termicap.Terminal_Id` require no TTY parameter at all: Unicode capability is a property of the terminal emulator and locale configuration, and terminal identity is determined entirely from environment variable strings. `Termicap.Dimensions` additionally relies on the C wrapper `termicap_ioctl.c` for the ioctl FFI call in its body. `Termicap.Downsampling` is a post-detection conversion package: it depends only on `Termicap.Color` (for the `Color_Level` type) and has no dependency on `Termicap.Environment`, `Termicap.TTY`, `Termicap.Override`, or any OS interface. `Termicap.Capabilities` sits at the top of the dependency graph: it depends on all Tier 1 and Tier 2 packages (`Termicap.Environment.Capture`, `Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, `Termicap.Unicode`, and `Termicap.Terminal_Id`) and orchestrates them into a single `Terminal_Capabilities` record. The root package remains a namespace-only package. `Termicap.OSC` is the FFI boundary for active terminal probing; it depends on `Ada.Finalization` and `Interfaces.C` and calls nine C helper functions via `termicap_osc.c`. Its child package `Termicap.OSC.Parsing` is a pure SPARK Silver leaf that depends only on the `Byte` and `Byte_Array` types from the parent package. `Termicap.Color.BG_Query` is a SPARK Silver child of `Termicap.Color` providing the RGB type, OSC 10/11 query byte constants, and pure parsing functions for X11 `rgb:` responses, hex channel normalisation, OSC header stripping, and COLORFGBG parsing; it has no dependency on `Termicap.OSC` (which is `SPARK_Mode => Off`) — instead it re-declares compatible `Byte`/`Byte_Array` types using the same underlying `Interfaces.C.unsigned_char` base. Its child `Termicap.Color.BG_Query.IO` is the I/O boundary: it calls `Termicap.OSC.Sentinel_Query` via a `Probe_Session` and optionally wraps the query for multiplexer passthrough. `Termicap.Color.Detection` is a sibling child of `Termicap.Color` that orchestrates the two-level cascade (OSC query → COLORFGBG fallback) and exposes `Detect_Background_Color` and `Detect_Foreground_Color` as the top-level API; it depends on `Termicap.Color.BG_Query` and `Termicap.Color.BG_Query.IO`.

## Level 2: Package Descriptions

### `Termicap`

Root namespace package with no declarations. Its sole purpose is to establish the top-level package hierarchy used by all child packages.

| Property | Value |
|----------|-------|
| File | `src/termicap.ads` |
| SPARK_Mode | On (inherited) |
| Dependencies | None |

---

### `Termicap.Environment`

**Responsibility:** Provides an immutable snapshot of environment variable bindings with SPARK-provable query operations.

Keys are case-normalized (lowercased) at insertion time so that all lookups are case-insensitive. Values are stored verbatim. The presence/value distinction required for NO_COLOR compliance is preserved: a key set to the empty string has an entry in the map, whereas an absent variable has no entry at all.

| Property | Value |
|----------|-------|
| Files | `src/termicap-environment.ads`, `src/termicap-environment.adb` |
| SPARK_Mode | On (spec and body) |
| Dependencies | `SPARK.Containers.Formal.Unbounded_Hashed_Maps` (sparklib), `SPARK.Containers.Formal.Unbounded_Vectors` (sparklib), `SPARK.Containers.Types` |

#### Key Types

| Type | Description |
|------|-------------|
| `Environment` | Opaque record containing a `Env_Maps.Map`. Represents an immutable snapshot after capture, or a programmatically constructed test environment. |
| `String_Vector` | Subtype of `String_Vectors.Vector` — a SPARK-compatible, indefinite-element vector used by `Value_Matches`. |

#### Key Constants

| Constant | Description |
|----------|-------------|
| `EMPTY_ENVIRONMENT` | Default-initialized environment snapshot containing no variables. Starting point for programmatic construction. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirement |
|-----------|------|---------------|-------------|
| `Contains` | Function | `Global => null` | FUNC-ENV-002 |
| `Value` | Function | `Global => null` | FUNC-ENV-003 |
| `Insert` | Procedure | `Global => null` | FUNC-ENV-005 |
| `Equal_Case_Insensitive` | Function | `Global => null` | FUNC-ENV-006 |
| `Value_Matches` | Function | `Global => null` | FUNC-ENV-008 |

#### Internal: `Env_Maps`

A private package-level instantiation of `SPARK.Containers.Formal.Unbounded_Hashed_Maps` with `String` key and `String` element types. The hash function and equality operate on lowercased key forms:

```ada
package Env_Maps is new
  SPARK.Containers.Formal.Unbounded_Hashed_Maps
    (Key_Type        => String,
     Element_Type    => String,
     Hash            => Case_Insensitive_Hash,
     Equivalent_Keys => Case_Insensitive_Equal);
```

`Case_Insensitive_Hash` and `Case_Insensitive_Equal` are private helper functions with `Global => null` contracts.

#### Internal: `String_Vectors`

A private package-level instantiation of `SPARK.Containers.Formal.Unbounded_Vectors` for passing variable-length lists of `String` values to `Value_Matches`:

```ada
package String_Vectors is new
  SPARK.Containers.Formal.Unbounded_Vectors
    (Index_Type   => Positive,
     Element_Type => String);
```

---

### `Termicap.Environment.Capture`

**Responsibility:** The sole OS interaction point for environment variable access. Reads the live process environment via `Ada.Environment_Variables` and produces an immutable `Environment` snapshot.

This package has `SPARK_Mode => Off` because `Ada.Environment_Variables` performs OS calls that cannot be verified by GNATprove. All downstream detection logic operates exclusively on the captured snapshot, which is fully SPARK-provable.

| Property | Value |
|----------|-------|
| Files | `src/termicap-environment-capture.ads`, `src/termicap-environment-capture.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Ada.Environment_Variables` (Ada standard library) |

#### Key Operations

| Subprogram | Kind | Description | Requirement |
|-----------|------|-------------|-------------|
| `Capture_Current` | Procedure | Reads the live process environment and populates an `Environment` snapshot via `Ada.Environment_Variables.Iterate`. | FUNC-ENV-004 |

### `Termicap.Override`

**Responsibility:** Provides a process-wide color output override that short-circuits automatic terminal detection. Applications set an `Override_Mode` value (e.g., in response to a `--color` flag) and all subsequent calls to `Detect_Color_Level` and `Is_TTY` return immediately without executing their detection logic.

The package spec and all pure functions carry `SPARK_Mode => On`. The protected object that stores the override state and the `Scoped_Override` `Initialize`/`Finalize` procedures are compiled with `SPARK_Mode => Off` because Ada protected types and `Ada.Finalization` are outside the SPARK 2014 language subset. An `Abstract_State` annotation (`Override_State`, `External => (Async_Readers, Async_Writers)`) allows SPARK-annotated callers to reference the state in their own `Global` aspects without the prover needing to reason about tasking.

| Property | Value |
|----------|-------|
| Files | `src/termicap-override.ads`, `src/termicap-override.adb` |
| SPARK_Mode | On (spec and pure functions); Off (protected object, `Set_Override`/`Get_Override` bodies, `Initialize`/`Finalize`) |
| Dependencies | `Ada.Finalization` |

#### Key Types

| Type | Description |
|------|-------------|
| `Override_Mode` | Five-literal flat enumeration: `Auto`, `Force_None`, `Force_Basic`, `Force_256`, `Force_True_Color`. `Auto` means no override is active; the four `Force_*` literals map directly onto `Color_Level` values and bypass all detection logic. |
| `Scoped_Override` | Discriminated `Limited_Controlled` type. Discriminant `Mode : Override_Mode` specifies the override to install. On declaration (`Initialize`), captures the current mode and installs `Mode`. On scope exit (`Finalize`), restores the previously captured mode. `Limited_Controlled` (not `Controlled`) prevents copying, which would cause a double-restore. |

#### Override_Mode — Five-Literal Enumeration

| Literal | Color_Level Equivalent | Typical CLI Flag |
|---------|----------------------|------------------|
| `Auto` | *(no override — normal detection)* | `--color=auto` |
| `Force_None` | `None` | `--color=never` |
| `Force_Basic` | `Basic_16` | `--color=true`, `--color=1` |
| `Force_256` | `Extended_256` | `--color=256`, `--color=2` |
| `Force_True_Color` | `True_Color` | `--color=always`, `--color=truecolor` |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Set_Override` | Procedure | `Global => (In_Out => Override_State)` | FUNC-OVR-002 |
| `Get_Override` | Function | `Global => (Input => Override_State)` | FUNC-OVR-003 |
| `Reset_Override` | Procedure | `Global => (In_Out => Override_State)`, `Post => Get_Override = Auto` | FUNC-OVR-011 |
| `Parse_Color_Flag` | Function | `Global => null` | FUNC-OVR-013 |

#### `Parse_Color_Flag` — CLI Alias Table

| Input strings (case-insensitive) | Result |
|----------------------------------|--------|
| `"never"`, `"false"`, `"off"`, `"0"` | `Force_None` |
| `"true"`, `"1"`, `"16"` | `Force_Basic` |
| `"2"`, `"256"` | `Force_256` |
| `"always"`, `"truecolor"`, `"16m"`, `"3"` | `Force_True_Color` |
| `"auto"` or any unrecognised string | `Auto` |

#### Thread Safety

`Set_Override`, `Get_Override`, and `Reset_Override` delegate to an Ada protected object in the package body. All three are safe to call from multiple Ada tasks concurrently. The `Abstract_State` annotation marks the state as `Async_Readers` and `Async_Writers` so GNATprove does not reject SPARK callers that reference `Override_State` in their `Global` aspects.

`Scoped_Override` is **not** safe for nested guards across tasks. Two tasks creating overlapping `Scoped_Override` objects will interleave their save/restore sequences. The recommended use is single-task scope guards (e.g., CLI flag setup at process startup).

#### Relationship to Other Packages

`Termicap.Override` has **no dependency** on any other Termicap package. It is a leaf in the dependency graph. `Termicap.Color` and `Termicap.TTY` each depend on `Termicap.Override` and reference `Override_State` in the `Global` aspects of their main detection functions.

---

### `Termicap.TTY`

**Responsibility:** Detects whether standard I/O streams (stdin, stdout, stderr) are connected to an interactive terminal using the POSIX `isatty()` system call.

The package spec is SPARK-annotated for type safety and contract documentation. The body has `SPARK_Mode => Off` because every function ultimately calls the C FFI binding — there is no pure logic to prove in the body.

| Property | Value |
|----------|-------|
| Files | `src/termicap-tty.ads`, `src/termicap-tty.adb` |
| SPARK_Mode | On (spec), Off (body) |
| Dependencies | `Interfaces.C` (Ada standard library) |

#### Key Types

| Type | Description |
|------|-------------|
| `Stream_Kind` | Enumeration with values `Stdin`, `Stdout`, `Stderr` identifying the three standard I/O streams. |
| `TTY_Status` | Record with three Boolean fields (`Stdin`, `Stdout`, `Stderr`) for bulk query results. |

#### Public Operations

| Subprogram | Kind | Description | Requirement |
|-----------|------|-------------|-------------|
| `Is_TTY` | Function | Returns `True` if the specified stream is connected to an interactive terminal (or if the override forces color on). Returns `False` on error or when the override forces color off. Never raises. `Global => (Input => Termicap.Override.Override_State)` | FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004 |
| `Query_All` | Function | Returns `TTY_Status` with the TTY state of all three streams. | FUNC-TTY-006 |

#### Internal: `FD_MAP`

A constant array mapping `Stream_Kind` to C file descriptors:

```ada
FD_MAP : constant array (Stream_Kind) of Interfaces.C.int :=
   [Stdin => 0, Stdout => 1, Stderr => 2];
```

#### Internal: `C_Isatty`

The C binding declared via `pragma Import`:

```ada
function C_Isatty (Fd : Interfaces.C.int) return Interfaces.C.int;
pragma Import (C, C_Isatty, "isatty");
```

#### Relationship to Other Packages

`Termicap.TTY` has **no dependency** on `Termicap.Environment`. It depends on `Termicap.Override` to perform the override short-circuit check at the top of `Is_TTY`. Downstream detection packages call `Is_TTY` once from an Ada-only region and pass the result as a plain `Boolean` parameter into SPARK-provable detection functions.

---

### `Termicap.Dimensions`

**Responsibility:** Detects terminal dimensions (columns, rows, and optional pixel size) from an immutable environment snapshot and a TTY status flag. Implements a three-step fallback chain: ioctl(TIOCGWINSZ) on the stdout file descriptor when a TTY is present, then COLUMNS/LINES environment variables, then the industry-standard 80×24 default.

The spec is SPARK-annotated with `Global => null` on `Get_Size`. The body has `SPARK_Mode => Off` because it binds to the C wrapper `termicap_get_winsize` via `pragma Import` and uses access types (out-parameters to C) that SPARK cannot verify.

| Property | Value |
|----------|-------|
| Files | `src/termicap-dimensions.ads`, `src/termicap-dimensions.adb`, `src/c/termicap_ioctl.c` |
| SPARK_Mode | On (spec), Off (body) |
| Dependencies | `Termicap.Environment`, `Interfaces.C` (Ada standard library) |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_COLUMNS` | 80 | Industry-standard default terminal width (FUNC-DIM-004) |
| `DEFAULT_ROWS` | 24 | Industry-standard default terminal height (FUNC-DIM-004) |

#### Key Types

| Type | Description |
|------|-------------|
| `Terminal_Size` | Record with four fields: `Columns : Positive`, `Rows : Positive`, `Pixel_Width : Natural`, `Pixel_Height : Natural`. `Rows` and `Columns` are always ≥ 1. `Pixel_Width` and `Pixel_Height` are 0 when the terminal does not report pixel dimensions. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Get_Size` | Function | `Global => null` | FUNC-DIM-002, FUNC-DIM-003, FUNC-DIM-004, FUNC-DIM-005 |

#### Internal: `C_Get_Winsize`

The C binding declared via `pragma Import`, pointing to the thin wrapper in `src/c/termicap_ioctl.c`:

```ada
function C_Get_Winsize
   (Fd      : Interfaces.C.int;
    Cols    : access Interfaces.C.unsigned_short;
    Rows    : access Interfaces.C.unsigned_short;
    X_Pixel : access Interfaces.C.unsigned_short;
    Y_Pixel : access Interfaces.C.unsigned_short)
   return Interfaces.C.int;
pragma Import (C, C_Get_Winsize, "termicap_get_winsize");
```

`STDOUT_FD : constant Interfaces.C.int := 1` is the file descriptor passed on TTY paths.

#### Internal: `termicap_ioctl.c`

A thin C wrapper is required because `ioctl(2)` is a variadic function (`int ioctl(int, unsigned long, ...)`) that Ada cannot bind directly via `pragma Import`. The wrapper provides the fixed signature `termicap_get_winsize` that unpacks a `struct winsize` returned by `TIOCGWINSZ` into four out-parameters. It returns `0` on success and `-1` on error, with error meaning the calling Ada code falls through to the environment variable fallback.

#### Internal: `Try_Parse_Positive`

A private helper function in the body that converts a `String` to a `Natural`, returning `0` on any parse error (non-digit characters, overflow, or the value `"0"` itself, which is not a valid `Positive`). Used when reading `COLUMNS` and `LINES` from the environment snapshot.

#### Fallback Chain

`Get_Size` implements a per-axis fallback (FUNC-DIM-002, FUNC-DIM-003, FUNC-DIM-004):

| Priority | Source | Condition |
|----------|--------|-----------|
| 1 | `ioctl(TIOCGWINSZ)` on fd 1 | `Is_TTY = True` and C call returns 0 and both dims > 0 |
| 2 | `COLUMNS` / `LINES` env vars | ioctl skipped or failed; each axis falls back independently |
| 3 | `DEFAULT_COLUMNS` / `DEFAULT_ROWS` | Env var absent or not a valid Positive |

Pixel dimensions (`Pixel_Width`, `Pixel_Height`) are populated only from the ioctl path; they remain `0` on all other paths.

#### Relationship to Other Packages

`Termicap.Dimensions` depends on `Termicap.Environment` (for `Contains` and `Value`) and does not depend on `Termicap.TTY` directly. TTY status enters as a plain `Boolean` parameter, keeping the `isatty()` FFI call outside the SPARK verification perimeter — the same pattern used by `Termicap.Color`.

---

### `Termicap.Sigwinch`

**Responsibility:** Manages the SIGWINCH signal handler lifecycle, providing asynchronous terminal resize notification via a self-pipe and a concurrent-safe polling interface. When installed, the handler automatically re-queries terminal dimensions on every SIGWINCH delivery and caches the result. Applications may poll via `Has_Resize` or integrate with `select()`/`poll()`/`epoll()` via the exposed self-pipe read FD.

The entire package (spec and body) carries `SPARK_Mode => Off`. Ada protected objects with interrupt handlers and dynamic signal attachment via `sigaction` are outside the SPARK 2014 language subset. Signal-context work (ioctl query, pipe write) is delegated to a C trampoline (`src/c/termicap_sigwinch.c`) that is async-signal-safe. The Ada body wraps a private protected singleton, presenting a flat procedural API to callers.

| Property | Value |
|----------|-------|
| Files | `src/termicap-sigwinch.ads`, `src/termicap-sigwinch.adb`, `src/c/termicap_sigwinch.c` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.Dimensions` (for the `Terminal_Size` type), C binding (`termicap_sigwinch.c`) |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Install` | Procedure | Creates the self-pipe (write end O_NONBLOCK), performs an initial `ioctl(TIOCGWINSZ)` query, and registers the C-level handler via `sigaction()`. Idempotent. Accepts `Terminal_FD` (default 1) for ioctl queries. | FUNC-SWC-001, FUNC-SWC-004, FUNC-SWC-009, FUNC-SWC-010 |
| `Uninstall` | Procedure | Restores the previous signal disposition, closes the pipe, clears the pending flag, and resets the cached size. Idempotent. | FUNC-SWC-001, FUNC-SWC-006 |
| `Has_Resize` | Function | Returns `True` if at least one SIGWINCH has arrived since install or the last `Acknowledge_Resize`. Non-blocking; no side effects. Returns `False` when not installed. | FUNC-SWC-003 |
| `Acknowledge_Resize` | Procedure | Clears the pending-resize flag atomically. Separate from `Has_Resize` to avoid losing a signal that arrives between query and acknowledgement. No-op when not installed. | FUNC-SWC-003 |
| `Get_Pipe_Read_FD` | Function | Returns the read end of the self-pipe for registration with I/O multiplexers (`select`/`poll`/`epoll`). Returns `-1` when not installed or on non-Unix platforms. | FUNC-SWC-005, FUNC-SWC-008 |
| `Get_Cached_Size` | Function | Returns the most recently cached `Terminal_Size` without performing a new ioctl call. Safe to call concurrently. Returns the default size (80 × 24, 0 pixel dims) when not installed. | FUNC-SWC-002, FUNC-SWC-010 |

#### Internal: `termicap_sigwinch.c`

A C trampoline required because POSIX signal handlers must be async-signal-safe — Ada protected object entry calls are not. The C handler performs `ioctl(TIOCGWINSZ)` to re-query dimensions, writes one byte to the pipe write end, and stores the result in a shared structure. The Ada body reads this structure from within the protected object after each notification.

#### Internal: Protected Singleton

A private protected singleton in the package body serialises concurrent callers of all six public operations. The protected object holds three state items: an `Installed` flag, a `Pending` flag, and a `Cached_Size : Terminal_Size`. It is declared private so that callers interact only through the flat procedural API.

#### Thread Safety

All public operations are safe to call from multiple Ada tasks concurrently. The Ada protected object enforces mutual exclusion. The C handler is async-signal-safe by design (no heap allocation, no non-reentrant functions).

#### Platform Behaviour

On non-Unix platforms (including Windows), `Install` and `Uninstall` are no-ops, `Has_Resize` returns `False`, `Acknowledge_Resize` is a no-op, `Get_Pipe_Read_FD` returns `-1`, and `Get_Cached_Size` returns the default size. The SIGWINCH signal does not exist on Windows; the package degrades gracefully without raising exceptions (FUNC-SWC-008).

#### Relationship to Other Packages

`Termicap.Sigwinch` depends on `Termicap.Dimensions` for the `Terminal_Size` type. Unlike `Termicap.Dimensions.Get_Size`, it does **not** accept an `Environment` snapshot — dimensions are queried live via ioctl inside the C handler, not derived from environment variables. `Termicap.Sigwinch` has no dependency on `Termicap.Environment`, `Termicap.TTY`, `Termicap.Color`, `Termicap.Unicode`, or `Termicap.Terminal_Id`.

---

### `Termicap.Color`

**Responsibility:** Determines the color output capability of a terminal from an immutable environment snapshot and a TTY status flag. Performs no OS calls. Reads the process-wide `Termicap.Override.Override_State` as the first step, returning immediately when an override is active.

The detection algorithm is a single function implementing an 11-step priority cascade preceded by an override check (step 0). All logic consists of enum comparisons and string matching via the `Termicap.Environment` API; there is no FFI. The package is SPARK Silver provable; the `Global` aspect on `Detect_Color_Level` references `Override_State` rather than `null` because the function reads the protected state.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color.ads`, `src/termicap-color.adb` |
| SPARK_Mode | On (spec and body) |
| Dependencies | `Termicap.Environment`, `Termicap.Override` |

#### Key Types

| Type | Description |
|------|-------------|
| `Color_Level` | Ordered four-value enumeration: `None < Basic_16 < Extended_256 < True_Color`. Supports `Color_Level'Max` for floor operations throughout the cascade. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Detect_Color_Level` | Function | `Global => (Input => Termicap.Override.Override_State)` | FUNC-CLR-002, FUNC-CLR-014, FUNC-CLR-015 |

#### Detection Cascade

`Detect_Color_Level` implements a step-0 override check followed by an 11-step environment-variable cascade (FUNC-CLR-015):

| Step | Check | Effect |
|------|-------|--------|
| 0 | `Termicap.Override.Get_Override` | If override ≠ `Auto`, return the mapped `Color_Level` immediately; skip all remaining steps. |
| 1 | `FORCE_COLOR` | Sets a floor level (0/false → return None immediately; 1/true/empty → Basic_16; 2 → Extended_256; 3 → True_Color) |
| 2 | `CLICOLOR_FORCE` (if step 1 inactive) | Sets floor to Basic_16 unless value is `"0"` |
| 3 | `NO_COLOR` (if no force override) | Return None immediately |
| 4 | `TERM=dumb` | Return floor (None unless steps 1–2 set it) |
| 5 | CI environment | Accumulate heuristic: GITHUB_ACTIONS/GITEA_ACTIONS/CIRCLECI → True_Color; TRAVIS/APPVEYOR/GITLAB_CI/BUILDKITE/DRONE/CI → Basic_16 |
| 6 | TTY gate | If not a TTY and no force or CI heuristic, return None |
| 7 | `COLORTERM` | Accumulate heuristic: `truecolor`/`24bit` → True_Color (capped at Extended_256 under `screen` multiplexer); any other value → Basic_16 |
| 8 | `TERM_PROGRAM` | Accumulate heuristic: iTerm.app v3+ → True_Color; iTerm.app <v3/Apple_Terminal/vscode → Extended_256 |
| 9 | `TERM` patterns | Accumulate heuristic: `-256color`/`-256` suffix → Extended_256; xterm/screen/vt100/vt220/rxvt/color/ansi/cygwin/linux substring → Basic_16 |
| 10 | `CLICOLOR` (non-zero) | Raise heuristic floor to Basic_16 |
| 11 | Default | Return `Color_Level'Max (Floor, Heuristic)` |

#### Relationship to Other Packages

`Termicap.Color` depends on `Termicap.Environment` (for `Contains`, `Value`, and `Equal_Case_Insensitive`) and on `Termicap.Override` (for the step-0 override short-circuit). It has **no dependency** on `Termicap.TTY`. TTY status enters as a plain `Boolean` parameter, keeping the POSIX FFI call outside the SPARK verification perimeter.

---

### `Termicap.Unicode`

**Responsibility:** Determines the Unicode rendering capability of a terminal from an immutable environment snapshot. Performs no OS calls and reads no global state.

The detection algorithm is a single pure function implementing a 5-step priority cascade. All logic consists of enum comparisons and string matching via the `Termicap.Environment` API; there is no FFI. The package is fully SPARK Silver provable — uniquely among detection packages, both the spec **and** the body carry `SPARK_Mode => On`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-unicode.ads`, `src/termicap-unicode.adb` |
| SPARK_Mode | On (spec and body) |
| Dependencies | `Termicap.Environment` |

#### Key Types

| Type | Description |
|------|-------------|
| `Unicode_Level` | Ordered three-value enumeration: `None < Basic < Extended`. Supports `Unicode_Level'Max` for floor operations throughout the cascade. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Detect_Unicode_Level` | Function | `Global => null` | FUNC-UNI-002, FUNC-UNI-007, FUNC-UNI-008 |

#### Detection Cascade

`Detect_Unicode_Level` implements a 5-step priority cascade (FUNC-UNI-008):

| Step | Check | Effect |
|------|-------|--------|
| 1 | Locale variables (`LC_ALL`, `LC_CTYPE`, `LANG`) | Value contains `"UTF-8"` (case-insensitive) → Extended |
| 2 | `TERM=linux` | Linux kernel console exclusion → None (overrides locale) |
| 3 | CI environment (`GITHUB_ACTIONS`, `GITEA_ACTIONS`, `CIRCLECI`) | Known Unicode-capable CI → Basic |
| 4 | Windows terminal heuristics (`WT_SESSION`, `TERM_PROGRAM=vscode`, `TERMINAL_EMULATOR`) | Windows Terminal / vscode / JetBrains → Extended |
| 5 | Default | Return `None` |

#### Relationship to Other Packages

`Termicap.Unicode` depends on `Termicap.Environment` (for `Contains`, `Value`, and `Equal_Case_Insensitive`) and has **no dependency** on `Termicap.TTY`. Unlike `Termicap.Color` and `Termicap.Dimensions`, it requires no TTY status parameter — Unicode capability is a property of the terminal emulator and locale configuration, independent of whether the output stream is connected to a TTY. This makes `Termicap.Unicode` the only detection function callable without first invoking `Is_TTY`.

---

### `Termicap.Terminal_Id`

**Responsibility:** Identifies the terminal emulator or multiplexer hosting the current session by inspecting environment variables passively. Performs no OS calls and reads no global state.

The detection algorithm is a single pure function implementing an 8-step priority cascade. All logic consists of enum comparisons and string matching via the `Termicap.Environment` API; there is no FFI. The package spec is SPARK Silver provable. The body has `SPARK_Mode => Off` because it uses `Ada.Strings.Unbounded` (a controlled type not supported by the SPARK subset); the spec-level contracts — `Global => null` and both postconditions — remain verifiable for all callers in the SPARK zone (ADR-0008).

| Property | Value |
|----------|-------|
| Files | `src/termicap-terminal_id.ads`, `src/termicap-terminal_id.adb` |
| SPARK_Mode | On (spec), Off (body) |
| Dependencies | `Termicap.Environment`, `Ada.Strings.Unbounded` (Ada standard library) |

#### Key Types

| Type | Description |
|------|-------------|
| `Terminal_Kind` | Twenty-value enumeration classifying the active terminal emulator or multiplexer. Values: `Unknown`, `Alacritty`, `Apple_Terminal`, `Dumb`, `Foot`, `Ghostty`, `ITerm2`, `JediTerm`, `Kitty`, `Konsole`, `Linux_Console`, `Mintty`, `Rxvt`, `Screen`, `Tmux`, `VSCode`, `VTE`, `WarpTerminal`, `WezTerm`, `Windows_Terminal`, `Xterm`. `Unknown` means no recognised signal was found; `Dumb` means `TERM=dumb` was declared explicitly. |
| `Multiplexer_Kind` | Subtype of `Terminal_Kind` restricted by a static predicate to `Tmux \| Screen`. Usable in membership tests and case alternatives. |
| `Terminal_Identity` | Record with four fields: `Kind : Terminal_Kind`, `Program_Name : Unbounded_String` (raw `TERM_PROGRAM` value), `Program_Version : Unbounded_String` (raw `TERM_PROGRAM_VERSION` value), `Term_Value : Unbounded_String` (raw `TERM` value), and `Is_Multiplexer : Boolean` (derived from `Kind`). String fields are always populated from the environment snapshot regardless of classification outcome; absent variables yield the empty string. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Detect_Terminal_Identity` | Function | `Global => null`; postcondition: if no recognised env var is present then `Kind = Unknown` and `Is_Multiplexer = False`; always `Is_Multiplexer = (Kind in Multiplexer_Kind)` | FUNC-TID-003, FUNC-TID-005, FUNC-TID-006, FUNC-TID-007 |

#### Detection Cascade

`Detect_Terminal_Identity` implements an 8-step priority cascade (FUNC-TID-004):

| Priority | Environment Variable | Rule |
|----------|---------------------|------|
| 1 | `TERM_PROGRAM` | Value matched case-insensitively against known program names: `iTerm.app` → `ITerm2`; `Apple_Terminal` → `Apple_Terminal`; `vscode` → `VSCode`; `WezTerm` → `WezTerm`; `WarpTerminal` → `WarpTerminal`; `mintty` → `Mintty` |
| 2 | `TERMINAL_EMULATOR` | If still `Unknown`: `JetBrains-JediTerm` → `JediTerm` |
| 3 | `WT_SESSION` | If still `Unknown` and variable present: → `Windows_Terminal` |
| 4 | `KONSOLE_VERSION` | If still `Unknown` and variable present: → `Konsole` |
| 5 | `VTE_VERSION` | If still `Unknown` and variable present: → `VTE` |
| 6 | `TMUX` | If still `Unknown` and variable present: → `Tmux` |
| 7 | `TERM` | If still `Unknown`: exact match `"dumb"` → `Dumb`; `"linux"` → `Linux_Console`; prefix `"tmux"` → `Tmux`; prefix `"screen"` → `Screen`; `"xterm-kitty"` → `Kitty`; `"xterm-ghostty"` → `Ghostty`; `"alacritty"` → `Alacritty`; `"wezterm"` → `WezTerm`; prefix `"rxvt"` → `Rxvt`; `"foot"`/`"foot-extra"` → `Foot`; prefix `"xterm"` → `Xterm` |
| 8 | *(default)* | `Kind` remains `Unknown` if no rule matched |

After step 8, `Is_Multiplexer` is derived: `Result.Kind in Multiplexer_Kind`.

#### Relationship to Other Packages

`Termicap.Terminal_Id` depends on `Termicap.Environment` (for `Contains`, `Value`, and `Equal_Case_Insensitive`) and has **no dependency** on `Termicap.TTY`. Unlike `Termicap.Color` and `Termicap.Dimensions`, no TTY status parameter is required — terminal identity is determined entirely from environment variable strings. This makes `Detect_Terminal_Identity` callable in the same manner as `Detect_Unicode_Level`: the environment snapshot alone is sufficient.

---

### `Termicap.Downsampling`

**Responsibility:** Converts color values from higher-fidelity levels (TrueColor, 256-color) to the nearest equivalent at a lower fidelity level (256-color, 16-color, or no-color). Performs no OS calls, no dynamic allocation, no global state, and no unbounded loops.

All functions are pure integer arithmetic over bounded subtypes. The entire package — both spec and body — carries `SPARK_Mode => On`, achieving SPARK Gold provability. This is the complement to `Termicap.Color`: detection tells a caller what the terminal supports; downsampling converts a color value to that level.

| Property | Value |
|----------|-------|
| Files | `src/termicap-downsampling.ads`, `src/termicap-downsampling.adb` |
| SPARK_Mode | On (spec and body) — **Gold level** |
| Dependencies | `Termicap.Color` (for `Color_Level`) |

#### Key Types

| Type | Description |
|------|-------------|
| `Color_Component` | Subtype of `Natural` in `0 .. 255`. Represents one 8-bit sRGB channel. The explicit range lets GNATprove discharge overflow obligations in cube-index and distance calculations without manual lemmas. |
| `RGB` | Plain record with three `Color_Component` fields (`Red`, `Green`, `Blue`). No invariant, no discriminant; usable as a function parameter without dynamic allocation. |
| `Color_Index_256` | Subtype of `Natural` in `0 .. 255`. Represents an xterm 256-color palette index. Sub-range partition: 0–15 = ANSI 16 colors; 16–231 = 6×6×6 RGB cube; 232–255 = 24-step grayscale ramp. |
| `Color_Index_16` | Subtype of `Color_Index_256` in `0 .. 15`. Represents an ANSI 16-color index. Being a subtype of `Color_Index_256`, any `Color_Index_16` value is directly assignable to `Color_Index_256` without conversion. |
| `Downsampled_Color` | Discriminated record keyed on `Color_Level`. Variant `None` carries no data; `Basic_16` carries `Index_16 : Color_Index_16`; `Extended_256` carries `Index_256 : Color_Index_256`; `True_Color` carries `RGB_Value : RGB`. The default discriminant (`Level => None`) allows unconstrained stack allocation. Callers dispatch on the discriminant in a case statement. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Description | Requirements |
|-----------|------|---------------|-------------|--------------|
| `Downsample_True_To_256` | Function | `Global => null`; result in `16 .. 255` | Maps an RGB value to the nearest xterm 256-color palette entry using a grayscale-first check (ramp indices 232–255) then 6×6×6 cube quantization (indices 16–231). Never returns indices 0–15. | FUNC-DSP-004 |
| `Downsample_True_To_16` | Function | `Global => null` | Maps an RGB value to the nearest of the 16 standard ANSI colors using the integer redmean weighted Euclidean distance. Ties are broken in favor of the lower index. | FUNC-DSP-005 |
| `Downsample_256_To_16` | Function | `Global => null` | Maps a 256-color palette index to the nearest ANSI 16-color index. Indices 0–15 are returned directly (pass-through). Indices 16–231 are reconstructed to RGB via the cube formula; indices 232–255 via the grayscale ramp formula; both then pass to `Downsample_True_To_16`. | FUNC-DSP-006 |
| `Downsample` (RGB overload) | Function | `Global => null`; idempotency and monotonicity postconditions | Dispatches a TrueColor RGB value to the appropriate primitive based on `Target`. Returns a `Downsampled_Color` discriminated by the effective output level. Postcondition guarantees: when `Target >= True_Color` the result carries the original RGB; when `Target = None` the result level is `None`; `Color_Level_Of (result) <= Color_Level'Min (True_Color, Target)`. | FUNC-DSP-008, FUNC-DSP-009, FUNC-DSP-010 |
| `Downsample` (256 overload) | Function | `Global => null`; idempotency and monotonicity postconditions | Dispatches a 256-color palette index to the appropriate primitive based on `Target`. Postcondition guarantees: when `Target >= Extended_256` the result carries the original index; when `Target = None` the result level is `None`; `Color_Level_Of (result) <= Color_Level'Min (Extended_256, Target)`. `Color_Index_16` values (0–15) may be passed to this overload directly. | FUNC-DSP-008, FUNC-DSP-009, FUNC-DSP-010 |
| `Color_Level_Of` | Function | `Global => null`; result = `D.Level` | Returns the `Color_Level` discriminant of a `Downsampled_Color`. Used in monotonicity postconditions and by callers that need to inspect the level of a result before extracting the variant. | FUNC-DSP-010 |

#### Relationship to Other Packages

`Termicap.Downsampling` depends on `Termicap.Color` for the `Color_Level` type used as the `Target` parameter and as the discriminant of `Downsampled_Color`. It has no dependency on `Termicap.Environment`, `Termicap.TTY`, or any OS interface. Because it operates purely on values passed by the caller, it is usable in any context where `Termicap.Color` is available, including test bodies, without capturing an environment snapshot or querying TTY status.

---

### `Termicap.Capabilities`

**Responsibility:** Aggregates all sub-detector results into a single `Terminal_Capabilities` record, providing a cached lazy entry point (`Get`) and an uncached fresh entry point (`Detect`). Applications that need the full capability picture in a single call use this package rather than invoking each sub-detector independently.

The pure `Assemble` function is SPARK Silver-provable (`Global => null`) and carries a postcondition that relates `Downsampling_Available` to the `Color` field. `Detect` and `Get` delegate to OS-calling sub-detectors and are compiled without SPARK Global contracts. The per-stream cache is implemented as an Ada protected object in the package body, providing thread-safe lazy initialisation (FUNC-CAP-008).

| Property | Value |
|----------|-------|
| Files | `src/termicap-capabilities.ads`, `src/termicap-capabilities.adb` |
| SPARK_Mode | On (spec and `Assemble` function); Off (protected cache, `Detect` and `Get` bodies) |
| Dependencies | `Termicap.Environment.Capture`, `Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, `Termicap.Unicode`, `Termicap.Terminal_Id`, `Termicap.DA1`, `Termicap.DA1.IO` |

#### Key Types

| Type | Description |
|------|-------------|
| `Terminal_Capabilities` | Plain Ada record with nine fields: `TTY_Stdin : Boolean`, `TTY_Stdout : Boolean`, `TTY_Stderr : Boolean`, `Color : Termicap.Color.Color_Level`, `Size : Termicap.Dimensions.Terminal_Size`, `Unicode : Termicap.Unicode.Unicode_Level`, `Identity : Termicap.Terminal_Id.Terminal_Identity`, `Downsampling_Available : Boolean`, and `DA1 : Termicap.DA1.DA1_Capabilities`. Value semantics — assignment produces an independent copy with no aliasing. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Assemble` | Function | `Global => null`; `Post => Assemble'Result.Downsampling_Available = (Assemble'Result.Color >= Termicap.Color.Extended_256)` | FUNC-CAP-012, FUNC-CAP-013 |
| `Detect` | Function | No Global contract (delegates to OS-calling sub-detectors) | FUNC-CAP-004, FUNC-CAP-005, FUNC-CAP-006, FUNC-CAP-007, FUNC-CAP-010, FUNC-CAP-011, FUNC-CAP-014 |
| `Get` | Function | No Global contract (reads/writes protected cache) | FUNC-CAP-003, FUNC-CAP-005, FUNC-CAP-008, FUNC-CAP-009 |

Both `Detect` and `Get` accept a `Stream : Termicap.TTY.Stream_Kind` parameter with default value `Stdout` (FUNC-CAP-005). `Detect` always performs a full detection run; `Get` populates the per-stream cache slot on the first call and returns a copy of the cached value on subsequent calls (FUNC-CAP-003). Override state installed via `Termicap.Override.Set_Override` is reflected in the `Color` and TTY fields of both `Detect` and `Get` results (FUNC-CAP-006, FUNC-CAP-007).

#### Relationship to Other Packages

`Termicap.Capabilities` is the integration apex of the package hierarchy. It depends on every Tier 1 and Tier 2 detection package and has no dependents within the library itself. Applications and tests interact with it directly; the individual sub-detectors remain available for callers that need only a subset of capabilities.

---

---

### `Termicap.OSC`

**Responsibility:** Provides the probe session type and all low-level terminal I/O operations required to send OSC/DCS/CSI escape sequence queries and read back responses. This package is the sole FFI boundary for active terminal probing.

It encapsulates the full open / raw-mode / query / restore / close lifecycle in `Probe_Session`, a `Limited_Controlled` type whose `Finalize` unconditionally restores termios and closes `/dev/tty` on scope exit or exception propagation. Before opening, the foreground process group is checked via `ioctl(TIOCGPGRP)` to avoid sending queries from background jobs. Only one `Probe_Session` may be open at a time; a concurrent `Open` call returns `Session_Already_Active`.

The sentinel-bounded query pattern (`Sentinel_Query`) writes the user query followed by the DA1 sentinel (`ESC [ c`) and accumulates response bytes until the DA1 response (`ESC [ ? … c`) is detected or the timeout expires. A complementary `Timeout_Query` procedure provides a sentinel-free alternative for callers where the DA1 response itself is the data being sought (ADR-0017): it writes the query without appending a sentinel and exits the read loop when `Contains_DA1_Response` returns True or the timeout expires. Pure parsing and detection logic is isolated in the SPARK Silver child package `Termicap.OSC.Parsing`.

All termios manipulation is delegated to a C helper (`src/c/termicap_osc.c`) which exposes nine fixed-signature functions, avoiding the need to map the platform-specific `struct termios` layout in Ada. The `select()` timed-read path uses the same C helper to avoid the `FD_SET`/`FD_ZERO` macro problem.

| Property | Value |
|----------|-------|
| Files | `src/termicap-osc.ads`, `src/termicap-osc.adb`, `src/c/termicap_osc.c` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Ada.Finalization`, `Interfaces.C`, `Termicap.OSC.Parsing` |

#### Key Types

| Type | Description |
|------|-------------|
| `File_Descriptor` | Distinct integer type derived from `Interfaces.C.int`. Prevents confusion with other integer quantities. Constant `INVALID_FD = -1`. |
| `Byte` | Subtype of `Interfaces.C.unsigned_char`. Matches the C unsigned char type used throughout the C helper interface. |
| `Byte_Array` | Unconstrained array of `Byte` over a `Positive` range. Used for both query sequences sent to the terminal and response bytes accumulated from it. |
| `Termios_State` | Limited record holding an opaque 128-byte buffer (`Data`) and the actual platform `sizeof(struct termios)` (`Size`). The C helper fills and restores this buffer; Ada code treats it as opaque. |
| `Session_Status` | Enumeration reporting the outcome of `Open`: `Session_OK`, `Session_Not_Foreground`, `Session_No_Terminal`, `Session_Save_Failed`, `Session_Raw_Failed`, `Session_Already_Active`. |
| `Response_Buffer` | Constrained subtype of `Byte_Array (1 .. MAX_RESPONSE_SIZE)` where `MAX_RESPONSE_SIZE = 4096`. Stack-allocated; no heap allocation during probing. |
| `Probe_Session` | `Limited_Controlled` record holding an `FD : File_Descriptor`, `Saved_State : Termios_State`, and `Is_Raw : Boolean`. The `Is_Raw` flag also acts as the single-session guard. |

#### Public Operations

| Subprogram | Kind | Requirements |
|-----------|------|--------------|
| `Open` | Procedure | FUNC-OSC-001, FUNC-OSC-002, FUNC-OSC-003, FUNC-OSC-007, FUNC-OSC-008, FUNC-OSC-011, FUNC-OSC-012 |
| `Is_Open` | Function | FUNC-OSC-008 |
| `Close` | Procedure | FUNC-OSC-008 |
| `Sentinel_Query` | Procedure | FUNC-OSC-006, FUNC-OSC-009, FUNC-OSC-013 |
| `Timeout_Query` | Procedure | FUNC-DA1-008 |
| `Write_Query` | Procedure | FUNC-OSC-005 |
| `Timed_Read` | Procedure | FUNC-OSC-004 |
| `Is_Foreground_Process` | Function | FUNC-OSC-007 |
| `Open_Terminal` | Function | FUNC-OSC-001 |
| `Close_Terminal` | Procedure | FUNC-OSC-001 |
| `Save_Termios` | Procedure | FUNC-OSC-002 |
| `Restore_Termios` | Procedure | FUNC-OSC-002 |
| `Set_Raw_Mode` | Procedure | FUNC-OSC-003 |
| `Drain_Input` | Procedure | FUNC-OSC-011 |

#### C Helper: `termicap_osc.c`

A thin C translation unit (`src/c/termicap_osc.c`) exposes nine functions called from the package body via `pragma Import (C, …)`:

| C Function | Purpose |
|-----------|---------|
| `termicap_osc_open_tty` | `open("/dev/tty", O_RDWR)` |
| `termicap_osc_close_fd` | `close(fd)` |
| `termicap_osc_termios_size` | Returns `sizeof(struct termios)` for this platform |
| `termicap_osc_save_termios` | `tcgetattr` → copies struct into caller-supplied buffer |
| `termicap_osc_restore_termios` | Copies buffer → `tcsetattr(TCSANOW)` |
| `termicap_osc_set_raw` | Derives raw mode from saved state → `tcsetattr(TCSANOW)` |
| `termicap_osc_select_read` | `select()` + `read()` with millisecond timeout |
| `termicap_osc_write` | `write()` with full-buffer retry |
| `termicap_osc_is_foreground` | `ioctl(TIOCGPGRP)` + `getpgrp()` comparison |

---

### `Termicap.OSC.Parsing`

**Responsibility:** Pure SPARK functions for DA1 sentinel detection, response parsing, and multiplexer passthrough query wrapping. Contains no side effects, no OS calls, and no global state; it is a leaf in the dependency graph.

All subprograms operate solely on `Byte_Array` values inherited from `Termicap.OSC`. SPARK contracts are verifiable at Silver level without manual lemmas. This package is the provable complement to the FFI-boundary parent.

| Property | Value |
|----------|-------|
| Files | `src/termicap-osc-parsing.ads`, `src/termicap-osc-parsing.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Termicap.OSC` (for `Byte`, `Byte_Array`, `MAX_RESPONSE_SIZE`) |

#### Key Types

| Type | Description |
|------|-------------|
| `DA1_Value_Array` | Fixed-size array `(1 .. MAX_DA1_PARAMS)` of `Natural`. Only indices `1 .. Count` are meaningful; remaining elements are zero-initialised. `MAX_DA1_PARAMS = 16`. |
| `DA1_Params` | Record with `Count : Natural range 0 .. MAX_DA1_PARAMS` and `Values : DA1_Value_Array`. `Count = 0` means no valid DA1 response was found. |
| `Passthrough_Mode` | Enumeration: `No_Passthrough`, `Tmux_Passthrough`, `Screen_Passthrough`. Selects the DCS wrapping syntax applied by `Wrap_For_Passthrough`. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Contains_DA1_Response` | Function | `Pre => Length <= Bytes'Length` | FUNC-OSC-006 |
| `DA1_Response_Start` | Function | `Pre => Length <= Bytes'Length`; `Post => result <= Length` | FUNC-OSC-006 |
| `Parse_DA1_Response` | Function | `Pre => Length <= Bytes'Length and Length <= MAX_RESPONSE_SIZE`; `Post => result.Count <= MAX_DA1_PARAMS` | FUNC-OSC-010 |
| `Wrap_For_Passthrough` | Function | Pure — no Pre/Post beyond type constraints | FUNC-OSC-014 |

#### Relationship to Other Packages

`Termicap.OSC.Parsing` is a pure child of `Termicap.OSC`. It has no knowledge of probe sessions, file descriptors, or termios state — it only processes `Byte_Array` values. `Sentinel_Query` in the parent package calls `Contains_DA1_Response` and `DA1_Response_Start` at runtime to determine response boundaries. Callers that need to inspect DA1 parameters (for feature detection) call `Parse_DA1_Response` on the response slice returned by `Sentinel_Query`.

---

### `Termicap.Color.BG_Query`

**Responsibility:** Pure SPARK types, constants, and parsing functions for OSC 10/11 background and foreground color query responses. Contains all provable building blocks for the BG-COLOR feature; no I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while remaining representation-compatible at the I/O boundary.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color-bg_query.ads`, `src/termicap-color-bg_query.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C` (Ada standard library) |

#### Key Types

| Type | Description |
|------|-------------|
| `RGB` | Record with three `Natural range 0 .. 255` fields (`Red`, `Green`, `Blue`). Independent of `Termicap.Downsampling.RGB` — the BG-COLOR subsystem is standalone. |
| `Query_Kind` | Enumeration: `Background` (OSC 11) / `Foreground` (OSC 10). |
| `Parse_Result` | Discriminated record: `Success => True` carries `Color : RGB`; `Success => False` carries no data. |
| `Channel_Result` | Discriminated record: `Success => True` carries `Value : Natural range 0 .. 255`. |
| `Strip_Result` | Discriminated record: `Success => True` carries `Offset : Positive` and `Payload_Length : Natural` identifying the rgb: payload within the raw response buffer. |
| `Colorfgbg_Result` | Non-discriminated record: `Success : Boolean`; `Foreground`, `Background : Natural range 0 .. 15`. |
| `ANSI_Color_Array` | Array `(Natural range 0 .. 15) of RGB`. Basis for `ANSI_COLOR_TABLE`. |

#### Key Constants

| Constant | Description |
|----------|-------------|
| `OSC_BG_QUERY` | Byte sequence encoding `ESC ] 1 1 ; ? ESC \` (OSC 11 background query). |
| `OSC_FG_QUERY` | Byte sequence encoding `ESC ] 1 0 ; ? ESC \` (OSC 10 foreground query). |
| `ANSI_COLOR_TABLE` | Canonical xterm 16-color palette (`ANSI_Color_Array`). Used by `Ansi_To_RGB` and the COLORFGBG fallback. |
| `DEFAULT_BACKGROUND` | `(0, 0, 0)` — returned when all detection steps fail for background. |
| `DEFAULT_FOREGROUND` | `(170, 170, 170)` — returned when all detection steps fail for foreground. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Query_Sequence` | Function | `Post => result'Length > 0` | FUNC-BGC-005 |
| `Parse_RGB_Response` | Function | `Pre => Length <= Bytes'Length`; `Post => if success then channels in 0..255` | FUNC-BGC-007 |
| `Find_RGB_Prefix` | Procedure | `Pre => Length <= Bytes'Length`; `Post => if Found then Offset in bounds` | FUNC-BGC-008 |
| `Split_RGB_Channels` | Procedure | Pre/Post constraining channel lengths to `1..MAX_CHANNEL_LENGTH` | FUNC-BGC-008 |
| `Parse_Hex_Channel` | Function | `Pre` bounds `Length in 1..MAX_CHANNEL_LENGTH`; `Post => if success then Value in 0..255` | FUNC-BGC-009 |
| `Strip_OSC_Header` | Function | `Pre => Length <= Bytes'Length`; `Post` bounds `Offset` and `Payload_Length` | FUNC-BGC-010 |
| `Parse_Colorfgbg` | Function | `Pre => Value'Length <= MAX_COLORFGBG_LENGTH`; `Post => if success then both fields in 0..15` | FUNC-BGC-011 |
| `Ansi_To_RGB` | Function | `Post => all channels in 0..255` | FUNC-BGC-012 |

---

### `Termicap.Color.BG_Query.IO`

**Responsibility:** I/O boundary for the BG-COLOR feature. Sends one OSC 10 or OSC 11 color query to the terminal via a `Probe_Session` and returns the raw pre-sentinel response bytes. Optionally wraps the query for multiplexer passthrough (tmux / screen) by calling `Termicap.OSC.Parsing.Wrap_For_Passthrough`.

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All parsing logic remains in the provable parent package.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color-bg_query-io.ads`, `src/termicap-color-bg_query-io.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.Color.BG_Query`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Environment.Capture`, `Termicap.Terminal_Id` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Query_Color` | Procedure | Opens a `Probe_Session`, optionally applies multiplexer passthrough wrapping, sends the OSC query via `Sentinel_Query`, and returns raw response bytes with a timeout flag. Never raises. `Pre => Response'Length >= BG_Query.MAX_RESPONSE_SIZE`. | FUNC-BGC-006 |

---

### `Termicap.Color.Detection`

**Responsibility:** Implements the two-level background and foreground color detection cascade: OSC query (via `BG_Query.IO.Query_Color`) first, COLORFGBG environment variable fallback second. Exposes `Detect_Background_Color` and `Detect_Foreground_Color` as the top-level API for the BG-COLOR feature.

Both functions clamp `Timeout_Ms` to 30 000 ms. When `Timeout_Ms = 0`, the OSC query is skipped and the function proceeds directly to the COLORFGBG fallback. Neither function raises exceptions.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color-detection.ads`, `src/termicap-color-detection.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.Color.BG_Query`, `Termicap.Color.BG_Query.IO`, `Termicap.Environment`, `Termicap.Environment.Capture` |

#### Key Types

| Type | Description |
|------|-------------|
| `Detect_Error` | Enumeration: `Not_A_Terminal`, `Not_Foreground`, `Query_Timeout`, `Parse_Failed`, `No_Fallback`. Identifies the specific failure step in the cascade. |
| `Detection_Result` | Discriminated record: `Success => True` carries `Color : BG_Query.RGB`; `Success => False` carries `Error : Detect_Error`. |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Detect_Background_Color` | Function | OSC 11 query → COLORFGBG fallback cascade for background color. `Timeout_Ms` defaults to 1 000 ms. | FUNC-BGC-013, FUNC-BGC-015 |
| `Detect_Foreground_Color` | Function | OSC 10 query → COLORFGBG fallback cascade for foreground color. `Timeout_Ms` defaults to 1 000 ms. | FUNC-BGC-014, FUNC-BGC-015 |

#### Detection Cascade

| Step | Action | Failure outcome |
|------|--------|-----------------|
| 0 | If `Timeout_Ms = 0`, skip to step 3 | — |
| 1 | `Query_Color` via `Probe_Session` (OSC 10 or 11, DA1 sentinel) | `Timed_Out = True` → step 3; session failure → error `Not_A_Terminal` or `Not_Foreground` |
| 2 | `Strip_OSC_Header` + `Parse_RGB_Response` on response bytes | parse failure → step 3 |
| 3 | `Parse_Colorfgbg` on `COLORFGBG` env var + `Ansi_To_RGB` | failure → `Detection_Result'(Success => False, Error => No_Fallback)` |

---

### `Termicap.Color.Dark_Light`

**Responsibility:** All SPARK Gold-provable building blocks for the DARK-LIGHT feature. Provides the `Theme_Kind` enumeration, the `LUMINANCE_THRESHOLD` named number, and pure functions that compute ITU-R BT.601 perceived luminance using integer-only arithmetic, classify an RGB color as `Dark` or `Light`, and expose Boolean convenience predicates. No I/O, no global state, no exceptions.

The luminance formula `Y = (299 * R + 587 * G + 114 * B) / 1000` uses only bounded integer arithmetic. The maximum intermediate value is 255 000, well within `Natural` on all supported platforms. GNATprove discharges all proof obligations (overflow safety, range postcondition) without manual lemmas.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color-dark_light.ads`, `src/termicap-color-dark_light.adb` |
| SPARK_Mode | On (spec and body — Gold level) |
| Dependencies | `Termicap.Color.BG_Query` (for `RGB` type) |

#### Key Types

| Type | Description |
|------|-------------|
| `Theme_Kind` | Two-literal enumeration: `Dark` (luminance < 128), `Light` (luminance >= 128). Strongly typed; SPARK prover verifies exhaustiveness of `case` statements over this type. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LUMINANCE_THRESHOLD` | 128 | Named number (not a typed constant) so it participates in static expressions. Midpoint of the 0..255 luminance scale (0.5 on [0.0, 1.0]). |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirement |
|-----------|------|---------------|-------------|
| `Luminance` | Function (expression) | `Post => Luminance'Result in 0 .. 255` | FUNC-DKL-002 |
| `Classify_Theme` | Function (expression) | — (return type constraint; exhaustiveness proved by path analysis) | FUNC-DKL-003 |
| `Is_Dark` | Function (expression) | `Post => Is_Dark'Result = (Classify_Theme (Color) = Dark)` | FUNC-DKL-004 |
| `Is_Light` | Function (expression) | `Post => Is_Light'Result = (Classify_Theme (Color) = Light)` | FUNC-DKL-004 |

All four functions are expression functions declared in the spec; GNATprove inlines their definitions at every call site and discharges all Gold-level proof obligations automatically.

---

### `Termicap.Color.Dark_Light.Detect`

**Responsibility:** High-level theme detection wrapper. Combines `Detect_Background_Color` (OSC 11 query cascade) with `Classify_Theme` (BT.601 luminance threshold) into a single call returning a discriminated `Theme_Result`. Carries `SPARK_Mode => Off` because it calls `Detect_Background_Color`, which manages `Probe_Session` controlled types and performs terminal I/O.

This package is the SPARK Off boundary for the DARK-LIGHT feature, mirroring the role of `Termicap.Color.BG_Query.IO` in the BG-COLOR feature. All algorithmic correctness properties are proved in the Gold-level parent package.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color-dark_light-detect.ads`, `src/termicap-color-dark_light-detect.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.Color.BG_Query` (for `RGB`), `Termicap.Color.Detection` (for `Detect_Background_Color`, `Detect_Error`), `Termicap.Color.Dark_Light` (for `Theme_Kind`, `Classify_Theme`) |

#### Key Types

| Type | Description |
|------|-------------|
| `Theme_Result` | Discriminated record: `Success => True` carries `Theme : Theme_Kind` and `Color : RGB`; `Success => False` carries `Error : Detect_Error`. Default discriminant `False` ensures uninitialized values are always in the failure state. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_TIMEOUT_MS` | 30 000 | Upper clamp on `Timeout_Ms` before passing to `Detect_Background_Color`, consistent with the FUNC-BGC-015 timeout policy. |

#### Public Operations

| Subprogram | Kind | Description | Requirement |
|-----------|------|-------------|-------------|
| `Detect_Theme` | Function | Clamps `Timeout_Ms`, calls `Detect_Background_Color`, classifies the color with `Classify_Theme`, and returns a `Theme_Result`. `Timeout_Ms` defaults to 1 000 ms. Never raises. | FUNC-DKL-005 |

---

### `Termicap.XTVERSION`

**Responsibility:** Pure SPARK types, constants, and parsing functions for the XTVERSION active terminal identification protocol. Provides all provable building blocks for recognising a `DCS >| <payload> ST` response, extracting its payload span, tokenising the name/version pair, and orchestrating the parse end-to-end. No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while remaining representation-compatible at the I/O boundary in the child package.

| Property | Value |
|----------|-------|
| Files | `src/termicap-xtversion.ads`, `src/termicap-xtversion.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C` (Ada standard library), `Ada.Strings.Unbounded` |

#### Key Types

| Type | Description |
|------|-------------|
| `XTVERSION_Status` | Three-literal enumeration: `Success` (valid name and version extracted), `Timeout` (no response received), `Parse_Error` (response received but malformed). Default discriminant for `XTVERSION_Result`. |
| `XTVERSION_Result` | Discriminated record: `Status = Success` carries `Terminal_Name` and `Terminal_Version` (`Unbounded_String`); `Status = Timeout \| Parse_Error` carries no data. Default discriminant is `Timeout`. |
| `Payload_Slice` | Record with `Offset : Positive` and `Length : Natural` — a zero-copy positional reference into the raw response buffer identifying the DCS payload span. |
| `Token_Pair` | Record with `Name : Unbounded_String` and `Version : Unbounded_String` — intermediate tokenisation result from `Split_XTV_Payload`. `Version` may be empty for name-only payloads. |

#### Key Constants

| Constant | Description |
|----------|-------------|
| `MAX_RESPONSE_SIZE` | `4_096` — maximum bytes accumulated by `Query_XTVERSION`. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`. Used in preconditions to bound all parsing loops. |
| `CSI_XTVERSION_QUERY` | Four-byte `Byte_Array` encoding `ESC [ > q` (`0x1B 0x5B 0x3E 0x71`). The canonical XTVERSION query as used by xterm, WezTerm, and tcell. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Contains_XTVERSION_Response` | Function | `Global => null`; `Pre => Length <= Bytes'Length` | FUNC-XTV-003 |
| `Extract_XTV_Payload` | Function | `Global => null`; `Pre` requires `Contains_XTVERSION_Response`; `Post` bounds `Offset` and `Length` | FUNC-XTV-004 |
| `Split_XTV_Payload` | Function | `Global => null`; `Pre => Length > 0 and Offset in bounds` | FUNC-XTV-005 |
| `Parse_XTVERSION_Response` | Function | `Global => null`; `Pre => Length <= MAX_RESPONSE_SIZE`; `Post => if Success then Terminal_Name non-empty` | FUNC-XTV-006 |

#### Relationship to Other Packages

`Termicap.XTVERSION` is a peer of `Termicap.Color.BG_Query` in the SPARK zone: it re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` rather than depending on `Termicap.OSC` (which is `SPARK_Mode => Off`). Its child `Termicap.XTVERSION.IO` is the I/O boundary that bridges the two type systems. `Parse_XTVERSION_Response` is called from `Query_And_Identify` in the child package after `Query_XTVERSION` delivers the raw response bytes.

---

### `Termicap.XTVERSION.IO`

**Responsibility:** I/O boundary for the XTVERSION feature. Sends a `CSI > q` query to the terminal via a `Probe_Session`, with optional multiplexer passthrough wrapping, and returns the raw pre-sentinel response bytes. `Query_And_Identify` combines I/O and parsing into a single call delivering a fully structured `XTVERSION_Result`.

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All parsing logic remains in the provable parent package `Termicap.XTVERSION`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-xtversion-io.ads`, `src/termicap-xtversion-io.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.XTVERSION`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Environment.Capture`, `Termicap.Terminal_Id` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Query_XTVERSION` | Procedure | Detects terminal identity, optionally wraps `CSI_XTVERSION_QUERY` for multiplexer passthrough, opens a `Probe_Session`, calls `Sentinel_Query` with `Retry => False`, and returns raw response bytes with a timeout flag. Never raises. `Pre => Response'Length >= XTVERSION.MAX_RESPONSE_SIZE`. | FUNC-XTV-008, FUNC-XTV-009, FUNC-XTV-010, FUNC-XTV-011, FUNC-XTV-012 |
| `Query_And_Identify` | Function | Calls `Query_XTVERSION`, maps `Timed_Out = True` to `XTVERSION_Result'(Status => Timeout)`, then calls `Parse_XTVERSION_Response` and returns the result. `Timeout_Ms` defaults to 100 ms. Never raises. | FUNC-XTV-013, FUNC-XTV-015 |

---

### `Termicap.DA1`

**Responsibility:** Pure SPARK types, constants, and interpretation functions for the DA1 Primary Device Attributes active terminal capability protocol (`CSI c` / `ESC [ ? Ps ; Ps ; ... c`). Provides all provable building blocks for interpreting a DA1 response: the `DA1_Capability` enumeration naming relevant `Ps` parameter values, the `VT_Level` enumeration for the VT conformance class encoded in the first `Ps` parameter, the `Capability_Flags` Boolean array and `DA1_Capabilities` aggregate record, the `DA1_QUERY` byte constant, and three pure interpretation functions. No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package.

| Property | Value |
|----------|-------|
| Files | `src/termicap-da1.ads`, `src/termicap-da1.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C`, `Termicap.OSC.Parsing` (for `DA1_Params` type) |

#### Key Types

| Type | Description |
|------|-------------|
| `DA1_Capability` | Eight-literal enumeration of the `Ps` parameter values most relevant to terminal capability detection: `Printer` (2), `ReGIS_Graphics` (3), `Sixel_Graphics` (4), `Selective_Erase` (6), `User_Defined_Keys` (8), `Windowing` (18), `ANSI_Color` (22), `Rectangular_Editing` (28). Unrecognised `Ps` values are silently ignored by `Interpret_DA1`. |
| `VT_Level` | Six-literal enumeration: `Unknown` (no response or unrecognised first `Ps`), `VT100` (reserved), `VT200` (`Ps=62`), `VT300` (`Ps=63`), `VT400` (`Ps=64`), `VT500` (`Ps=65`). Default-initialised to `Unknown`. |
| `Capability_Flags` | `array (DA1_Capability) of Boolean` — Boolean flag array indexed by the capability enumeration. Enables O(1) capability access and automatic defaulting of future enumeration additions to `False`. |
| `DA1_Capabilities` | Plain record: `Supported : Boolean := False`, `Level : VT_Level := Unknown`, `Flags : Capability_Flags := [others => False]`. Default initialisation produces a safe "no DA1 response" value. |

#### Key Constants

| Constant | Description |
|----------|-------------|
| `DA1_QUERY` | Three-byte `Byte_Array` encoding `ESC [ c` (`0x1B 0x5B 0x63`). The canonical Primary Device Attributes request. Defined in the SPARK On package so both the I/O layer and test code can reference it without crossing a SPARK_Mode boundary. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Interpret_DA1` | Function | `Global => null`; `Post => Count = 0 implies not Supported; Count > 0 implies Supported` | FUNC-DA1-004 |
| `Has_Capability` | Function (expression) | `Global => null`; `Post => Result = (Supported and Flags (Cap))` | FUNC-DA1-005 |
| `VT_Level_Of` | Function (expression) | `Global => null`; `Post => Result = Level; not Supported implies Result = Unknown` | FUNC-DA1-006 |

#### Relationship to Other Packages

`Termicap.DA1` depends on `Termicap.OSC.Parsing` (SPARK Silver) for the `DA1_Params` type passed to `Interpret_DA1`. It does not depend on `Termicap.OSC` (SPARK Off), preserving SPARK provability. Its child `Termicap.DA1.IO` is the I/O boundary that bridges the two type systems. `Interpret_DA1` is called from `Detect_DA1` in the child package after `Query_DA1` delivers the raw response bytes and `Parse_DA1_Response` extracts the parameter array.

---

### `Termicap.DA1.IO`

**Responsibility:** I/O boundary for the DA1 Primary Device Attributes feature. Sends a `CSI c` query to the terminal via a `Probe_Session`, using a timeout-only read loop (no DA1 sentinel appended, per ADR-0017), and returns interpreted `DA1_Capabilities`. `Detect_DA1` combines I/O, parsing, and interpretation into a single call.

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All interpretation logic remains in the provable parent package `Termicap.DA1`.

Unlike other active probes (`Termicap.XTVERSION.IO`, `Termicap.Color.BG_Query.IO`), this package calls `Timeout_Query` rather than `Sentinel_Query`. Appending a DA1 sentinel after the DA1 query would produce two overlapping DA1 responses in the accumulation buffer, making boundary detection ambiguous. `Timeout_Query` exits when `Contains_DA1_Response` returns True for the accumulated bytes or the timeout elapses.

| Property | Value |
|----------|-------|
| Files | `src/termicap-da1-io.ads`, `src/termicap-da1-io.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.DA1`, `Termicap.OSC`, `Termicap.OSC.Parsing`, `Termicap.Environment.Capture`, `Termicap.Terminal_Id` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Query_DA1` | Procedure | Detects terminal identity, optionally wraps `DA1_QUERY` for multiplexer passthrough, opens a `Probe_Session`, calls `Timeout_Query` (not `Sentinel_Query`), and returns raw response bytes with a timeout flag. Never raises. `Pre => Response'Length >= OSC.MAX_RESPONSE_SIZE`. | FUNC-DA1-008, FUNC-DA1-010, FUNC-DA1-011, FUNC-DA1-012 |
| `Detect_DA1` | Function | Calls `Query_DA1`, maps `Timed_Out = True` to a default `DA1_Capabilities` record, then calls `Parse_DA1_Response` and `Interpret_DA1` and returns the result. `Timeout_Ms` defaults to 100 ms. Never raises. | FUNC-DA1-009 |

---

### `Termicap.DECRPM`

**Responsibility:** Pure SPARK types, constants, and parsing functions for the DECRPM (DEC Private Mode Report) active terminal mode query protocol (`CSI ? Ps $ p` / `CSI ? Ps ; Pm $ y`). Provides all provable building blocks: the `Mode_Id` subtype, six named mode constants, the `Mode_Status` enumeration mapping the five DECRPM response codes, the `Mode_Report` record pairing a mode number with its decoded status, fixed-size array types for batch queries, the `DECRPM_Query` construction function, and pure recognition and parsing functions for DECRPM responses. No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package.

| Property | Value |
|----------|-------|
| Files | `src/termicap-decrpm.ads`, `src/termicap-decrpm.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte of terminal I/O. Representation-compatible with `Termicap.OSC.Byte`. |
| `Byte_Array` | Unconstrained array of `Byte` — escape sequence data and response buffers. Representation-compatible with `Termicap.OSC.Byte_Array`. |
| `Mode_Id` | Subtype of `Natural` — any non-negative DEC private mode number. Using a subtype (rather than a new type) allows callers to pass literal integers for vendor-specific modes without type conversion. |
| `Mode_Status` | Five-literal enumeration mapping DECRPM response codes: `Not_Recognized` (Pm=0), `Set` (Pm=1), `Reset` (Pm=2), `Permanently_Set` (Pm=3), `Permanently_Reset` (Pm=4). `Not_Recognized` is first so that default-initialised values are safe. |
| `Mode_Report` | Record pairing `Mode : Mode_Id := 0` with `Status : Mode_Status := Not_Recognized`. Default initialisation produces a clearly empty value (mode 0 is not a valid DEC private mode). |
| `Mode_Id_Array` | `array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Id` — fixed-size input array for batch queries. |
| `Mode_Report_Array` | `array (Positive range 1 .. MAX_BATCH_MODES) of Mode_Report` — fixed-size output array for batch query results. |

#### Key Constants

| Constant | Description |
|----------|-------------|
| `MAX_RESPONSE_SIZE` | `4_096` — maximum bytes accumulated by `Query_Mode`. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`; bounds parsing loops for SPARK provability. |
| `MAX_BATCH_MODES` | `16` — maximum modes per batch query. Covers all six standard constants with headroom for vendor extensions. |
| `MODE_CURSOR_VISIBILITY` | `25` — DECTCEM; cursor visible. |
| `MODE_MOUSE_X11` | `1000` — X11 mouse button tracking. |
| `MODE_MOUSE_SGR` | `1006` — SGR mouse coordinate encoding. |
| `MODE_ALT_SCREEN` | `1049` — alternate screen buffer. |
| `MODE_BRACKETED_PASTE` | `2004` — bracketed paste mode. |
| `MODE_SYNC_OUTPUT` | `2026` — synchronized output. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `DECRPM_Query` | Function | `Global => null`; `Post => Result'Length >= 6` | FUNC-RPM-005 |
| `Contains_DECRPM_Response` | Function | `Global => null`; `Pre => Length <= Bytes'Length` | FUNC-RPM-006 |
| `Parse_DECRPM_Response` | Function | `Global => null`; `Pre => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE`; `Post => (if Contains_DECRPM_Response then Result.Mode > 0)` | FUNC-RPM-007 |

#### Relationship to Other Packages

`Termicap.DECRPM` depends only on `Interfaces.C`. It does not depend on `Termicap.OSC` (SPARK Off), preserving SPARK provability. Its child `Termicap.DECRPM.IO` is the I/O boundary that bridges the two type systems. `DECRPM_Query` constructs the query bytes consumed by `Query_Mode` in the child package; `Contains_DECRPM_Response` and `Parse_DECRPM_Response` are called from `Detect_Mode` and `Detect_Modes` after `Query_Mode` delivers the raw response bytes.

---

### `Termicap.DECRPM.IO`

**Responsibility:** I/O boundary for the DECRPM DEC Private Mode Report feature. Sends `CSI ? Ps $ p` queries to the terminal via a `Probe_Session` and `Sentinel_Query` infrastructure, and returns structured `Mode_Query_Result` or `Batch_Query_Result` values. `Detect_Mode` combines I/O and parsing into a single call for single-mode queries; `Detect_Modes` performs a batch of queries within a single `Probe_Session` for lower overhead.

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All parsing logic remains in the provable parent package `Termicap.DECRPM`.

Unlike `Termicap.DA1.IO`, this package uses `Sentinel_Query` (not `Timeout_Query`): DECRPM responses (`CSI ? Ps ; Pm $ y`) are distinct from the DA1 sentinel (`ESC [ c`), so the DA1 sentinel pattern can safely bound the accumulation loop.

| Property | Value |
|----------|-------|
| Files | `src/termicap-decrpm-io.ads`, `src/termicap-decrpm-io.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.DECRPM`, `Termicap.OSC`, `Termicap.Environment.Capture`, `Termicap.Terminal_Id` |

#### Key Types

| Type | Description |
|------|-------------|
| `Query_Error` | Four-literal enumeration: `Not_A_Terminal` (no controlling terminal), `Not_Foreground` (process not in terminal foreground), `Query_Timeout` (no response within timeout), `Parse_Failed` (response received but unparseable). |
| `Mode_Query_Result` | Discriminated record. `Success = True`: `Report : Mode_Report`. `Success = False`: `Error : Query_Error`. Default discriminant `False` ensures uninitialised values are in the failure state. |
| `Batch_Query_Result` | Discriminated record. `Success = True`: `Reports : Mode_Report_Array`, `Count : Positive`. `Success = False`: `Error : Query_Error`. |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Query_Mode` | Procedure | Detects terminal identity, optionally wraps the DECRPM query for multiplexer passthrough, opens a `Probe_Session`, calls `Sentinel_Query` with `Retry => False`, and returns raw response bytes with a timeout flag. `Pre => Timeout_Ms > 0`. Never raises. | FUNC-RPM-008 |
| `Detect_Mode` | Function | Calls `Query_Mode`, maps `Timed_Out = True` to `Mode_Query_Result'(Success => False, Error => Query_Timeout)`, then calls `Parse_DECRPM_Response` and returns the typed result. `Timeout_Ms` defaults to 100 ms. Never raises. | FUNC-RPM-009 |
| `Detect_Modes` | Function | Opens a single `Probe_Session` and queries `Modes(1..Count)` in sequence; per-mode timeout is `max(50, Timeout_Ms / Count)`. Modes that time out individually receive `Status => Not_Recognized`. `Pre => Count <= MAX_BATCH_MODES`. `Timeout_Ms` defaults to 200 ms. Never raises. | FUNC-RPM-011 |

---

### `Termicap.Keyboard`

**Responsibility:** Pure SPARK types, constants, and parsing functions for the Kitty Keyboard Protocol detection feature. Detects which of four keyboard input protocols the controlling terminal supports — `Win32`, `Kitty`, `XTerm_CSI`, `Legacy`, or `Unknown` — by sending a `CSI ? u` Kitty query or `CSI ? 4 m` XTerm query, each bounded by a DA1 sentinel, and parsing the response. The priority cascade is Win32 > Kitty probe > XTerm probe > Legacy (FUNC-KKB-009). No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package `Termicap.Keyboard.IO`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-keyboard.ads`, `src/termicap-keyboard.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte of terminal I/O. Representation-compatible with `Termicap.OSC.Byte`. |
| `Byte_Array` | Unconstrained array of `Byte` — escape sequence data and response buffers. Representation-compatible with `Termicap.OSC.Byte_Array`. |
| `Keyboard_Protocol` | Five-literal enumeration: `Unknown`, `Legacy`, `XTerm_CSI`, `Kitty`, `Win32`. `Unknown` is the default (no probe result). |
| `Kitty_Flags` | Record with five Boolean fields corresponding to Kitty protocol capability bits 0..4. All fields default to `False`. |
| `Keyboard_Capability` | Record with `Protocol : Keyboard_Protocol`, `Flags : Kitty_Flags`, and `Probed : Boolean`. `Probed = False` means the result was inferred without a terminal probe (non-TTY, background, Win32 gate, or cached prior result). |
| `Parse_Result` | Discriminated record returned by `Parse_Kitty_Response`: `Found : Boolean` discriminant. `Found = True`: `Flags : Kitty_Flags`. `Found = False`: no fields. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `NO_KITTY_FLAGS` | All fields `False` | Canonical zero-flags `Kitty_Flags` value. |
| `NO_KEYBOARD_CAPABILITY` | `(Unknown, NO_KITTY_FLAGS, Probed => False)` | Canonical "no result" capability returned on non-TTY, background-process, or probe-failure paths. |
| `CSI_KITTY_QUERY` | `ESC [ ? u` (3 bytes) | Kitty keyboard protocol detection query (FUNC-KKB-004). |
| `CSI_XTERM_KBD_QUERY` | `ESC [ ? 4 m` (5 bytes) | XTerm modifyOtherKeys detection query (FUNC-KKB-007). |
| `KITTY_PROBE_TIMEOUT_MS` | `1_000` | Millisecond timeout for the Kitty probe (FUNC-KKB-013). |
| `XTERM_KBD_PROBE_TIMEOUT_MS` | `1_000` | Millisecond timeout for the XTerm probe (FUNC-KKB-013). |
| `MAX_RESPONSE_SIZE` | `4_096` | Maximum response bytes accumulated per probe. Matches `Termicap.OSC.MAX_RESPONSE_SIZE`; bounds parsing loops for SPARK provability. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Parse_Kitty_Flags` | Function | `Global => null` | FUNC-KKB-005 |
| `Parse_Kitty_Response` | Function | `Global => null`; `Pre => Length <= Bytes'Length and then Length <= MAX_RESPONSE_SIZE`; `Post => (if Result.Found then Result.Flags = Parse_Kitty_Flags (…))` | FUNC-KKB-006 |
| `Parse_XTerm_Keyboard_Response` | Function | `Global => null`; `Pre => Length <= Bytes'Length` | FUNC-KKB-008 |

#### Relationship to Other Packages

`Termicap.Keyboard` depends only on `Interfaces.C`. It does not depend on `Termicap.OSC` (SPARK Off), preserving SPARK provability. Its child `Termicap.Keyboard.IO` is the I/O boundary and carries `SPARK_Mode => Off`. Platform dispatch for the Windows gate follows ADR-0018: `Termicap.Keyboard.IO` has two bodies (`src/posix/termicap-keyboard-io.adb` and `src/windows/termicap-keyboard-io.adb`) selected by GPR `Source_Dirs`. Integration of `Keyboard_Capability` into `Terminal_Capabilities` is deferred; see ADR-0021.

---

### `Termicap.Keyboard.IO`

**Responsibility:** I/O boundary for the Kitty Keyboard Protocol detection feature. Implements the four-level detection cascade Win32 > TTY guard > foreground guard > Kitty probe > XTerm probe > Legacy. Exposes `Detect_Keyboard_Protocol` (result cached per process) and `Probe_Keyboard_Protocol` (uncached, always runs the full cascade).

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All parsing logic remains in the provable parent package `Termicap.Keyboard`.

Platform dispatch via GPR `Source_Dirs` (ADR-0018):
- **POSIX body** (`src/posix/termicap-keyboard-io.adb`, 190 lines): non-TTY guard → `Probe_Session` open → Kitty `Sentinel_Query` → `Parse_Kitty_Response` → XTerm `Sentinel_Query` → `Parse_XTerm_Keyboard_Response` → Legacy fallback.
- **Windows body** (`src/windows/termicap-keyboard-io.adb`, 210 lines): `GetConsoleMode (STD_INPUT_HANDLE)` fast-path check first; if it succeeds, returns `(Win32, Probed => False)` immediately; if it fails (Cygwin/MSYS2 PTY), falls through to the POSIX-style cascade.

| Property | Value |
|----------|-------|
| Files | `src/termicap-keyboard-io.ads`, `src/posix/termicap-keyboard-io.adb`, `src/windows/termicap-keyboard-io.adb` |
| SPARK_Mode | Off (spec and both bodies) |
| Dependencies | `Termicap.Keyboard`, `Termicap.OSC`, `Termicap.TTY` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Detect_Keyboard_Protocol` | Function | Returns `Keyboard_Capability`. On first call: runs full cascade and caches result in a package-level protected object. On subsequent calls: returns cached value directly (< 1 µs). Never raises. | FUNC-KKB-009, FUNC-KKB-017 |
| `Probe_Keyboard_Protocol` | Function | Uncached variant. Runs the full cascade on every call. Useful for testing or when a fresh probe is required after terminal reconfiguration. Never raises. | FUNC-KKB-009 |

**See also:** ADR-0021 (`docs/adr/0021-defer-keyboard-capability-integration.md`) — rationale for not integrating `Keyboard_Capability` into `Terminal_Capabilities` yet, and the migration path when the deferral is lifted.

---

### `Termicap.Mouse`

**Responsibility:** Pure SPARK types, constants, and parsing functions for mouse protocol detection. Defines the six-value `Mouse_Encoding` enumeration (`Unknown`, `None`, `X10`, `URXVT`, `SGR`, `SGR_Pixels`), the `Mouse_Capabilities` aggregate result record with per-mode Boolean support flags and a derived `Best_Encoding`, six `MODE_MOUSE_*` named constants for the DEC private modes queried during detection, the `DECRPM_Parse_Result` record, and two pure functions (`Parse_Mouse_DECRPM_Response` and `Resolve_Best_Encoding`) with SPARK Silver-level contracts. No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package `Termicap.Mouse.IO`. This mirrors the pattern established by `Termicap.Keyboard`, `Termicap.DECRPM`, `Termicap.DA1`, and `Termicap.XTVERSION`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-mouse.ads`, `src/termicap-mouse.adb` |
| SPARK_Mode | On (spec) — **Silver level** |
| Dependencies | `Interfaces.C`, `Termicap.DECRPM` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte of terminal I/O. Representation-compatible with `Termicap.OSC.Byte`. |
| `Byte_Array` | Unconstrained array of `Byte` — escape sequence data and response buffers. Representation-compatible with `Termicap.OSC.Byte_Array`. |
| `Mouse_Encoding` | Six-literal enumeration: `Unknown`, `None`, `X10`, `URXVT`, `SGR`, `SGR_Pixels`. `Unknown` is the default (no probe result). |
| `Mouse_Capabilities` | Record aggregating `Best_Encoding : Mouse_Encoding`, six `Supports_*` Boolean fields, platform flags `Win32_Console_Mouse` and `GPM_Available`, and `Probed : Boolean`. `Probed = False` means the result was determined without an active DECRPM probe (Win32 gate, GPM heuristic, non-TTY guard, or foreground guard). |
| `DECRPM_Parse_Result` | Three-field record: `Valid : Boolean`, `Mode : Termicap.DECRPM.Mode_Id`, `Status : Termicap.DECRPM.Mode_Status`. `Valid = False` implies `Mode = 0` (guaranteed by postcondition). |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `NO_MOUSE_CAPABILITIES` | All fields default-initialised | Canonical "no result" value; used as the cache initial value and on every error path of `Detect_Mouse_Protocols`. |
| `MODE_MOUSE_X10` | `1000` | DEC private mode for X10/X11 button tracking (FUNC-MSE-003). |
| `MODE_MOUSE_BUTTON_EVENT` | `1002` | DEC private mode for button-event / drag tracking (FUNC-MSE-003). |
| `MODE_MOUSE_ANY_EVENT` | `1003` | DEC private mode for any-motion tracking (FUNC-MSE-003). |
| `MODE_MOUSE_URXVT` | `1015` | DEC private mode for URXVT decimal encoding (FUNC-MSE-003). |
| `MODE_MOUSE_SGR` | `1006` | DEC private mode for SGR decimal encoding (FUNC-MSE-003). |
| `MODE_MOUSE_SGR_PIXELS` | `1016` | DEC private mode for SGR pixel-precision encoding (FUNC-MSE-003). |
| `MOUSE_PROBE_TIMEOUT_MS` | `1_000` | Millisecond timeout for the entire batched six-query DECRPM probe session (FUNC-MSE-013). |
| `MAX_RESPONSE_SIZE` | `4_096` | Re-export of `Termicap.DECRPM.MAX_RESPONSE_SIZE`; bounds parsing loops for SPARK provability. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Parse_Mouse_DECRPM_Response` | Function | `Global => null`; `Pre => Length <= Buffer'Length and then Length <= MAX_RESPONSE_SIZE`; `Post => (if not Result.Valid then Result.Mode = 0)` | FUNC-MSE-007 |
| `Resolve_Best_Encoding` | Function | `Global => null`; `Post => (if not Caps.Probed then Result = Unknown) and then (if Caps.Probed and Caps.Supports_SGR_Pixels then Result = SGR_Pixels) and then (if Caps.Probed and not Caps.Supports_SGR_Pixels and Caps.Supports_SGR then Result = SGR)` | FUNC-MSE-008 |

#### Relationship to Other Packages

`Termicap.Mouse` depends on `Interfaces.C` and `Termicap.DECRPM` (for `Mode_Id` and `Mode_Status` types and the `MAX_RESPONSE_SIZE` constant). It does not depend on `Termicap.OSC` (SPARK Off), preserving SPARK provability. Its child `Termicap.Mouse.IO` is the I/O boundary and carries `SPARK_Mode => Off`. Platform dispatch follows ADR-0018: `Termicap.Mouse.IO` has two bodies (`src/posix/termicap-mouse-io.adb` and `src/windows/termicap-mouse-io.adb`) selected by GPR `Source_Dirs`. Integration of `Mouse_Capabilities` into `Terminal_Capabilities` is deferred; see ADR-0026.

---

### `Termicap.Mouse.IO`

**Responsibility:** Platform-dispatched I/O orchestration for mouse protocol detection. Implements the five-guard cascade (Win32 gate > GPM heuristic > non-TTY guard > foreground guard > `/dev/tty` openability), followed by a single batched DECRPM probe session (six queries + one DA1 sentinel), response parsing, and the `Resolve_Best_Encoding` cascade. Exposes `Detect_Mouse_Protocols` (result cached per process) and `Probe_Mouse_Protocols` (uncached, always runs the full cascade).

Has `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O — both outside the SPARK 2014 subset. All parsing and cascade logic remain in the provable parent package `Termicap.Mouse`.

Platform dispatch via GPR `Source_Dirs` (ADR-0018):
- **POSIX body** (`src/posix/termicap-mouse-io.adb`): cascade starts at Guard 2 (GPM heuristic: `TERM=linux` + `/dev/gpmctl` exists); if that passes, continues to Guards 3–5 then the batched DECRPM probe.
- **Windows body** (`src/windows/termicap-mouse-io.adb`): cascade starts at Guard 1 (`GetConsoleMode (STD_INPUT_HANDLE)` succeeds → return `Win32_Console_Mouse = True` immediately); if it fails (Cygwin/MSYS2 PTY), falls through to the POSIX-style Guards 2–5.

| Property | Value |
|----------|-------|
| Files | `src/termicap-mouse-io.ads`, `src/posix/termicap-mouse-io.adb`, `src/windows/termicap-mouse-io.adb` |
| SPARK_Mode | Off (spec and both bodies) |
| Dependencies | `Termicap.Mouse`, `Termicap.OSC`, `Termicap.TTY`, `Ada.Directories` (POSIX body only) |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Detect_Mouse_Protocols` | Function | Returns `Mouse_Capabilities`. On first call: runs the full five-guard cascade + batched DECRPM probe + `Resolve_Best_Encoding`; caches result in a package-level protected object. On subsequent calls: returns cached value directly (< 1 µs). Never raises. | FUNC-MSE-009, FUNC-MSE-014, FUNC-MSE-016 |
| `Probe_Mouse_Protocols` | Function | Uncached variant. Runs the full cascade on every call without consulting or updating the protected-object cache. Useful for testing or after a terminal change. Never raises. | FUNC-MSE-009, FUNC-MSE-014, FUNC-MSE-016 |

**See also:** ADR-0026 (`docs/adr/0026-defer-mouse-capability-integration.md`) — rationale for not integrating `Mouse_Capabilities` into `Terminal_Capabilities` yet, and the migration path when the deferral is lifted.

---

### `Termicap.Graphics`

**Responsibility:** Pure SPARK types, constants, and parsing functions for Sixel and Kitty graphics protocol detection (Tier 4 Stretch Goal — SIXEL). Defines the `Graphics_Capabilities` aggregate result record (seven fields: `Sixel_Supported`, `Kitty_Graphics_Supported`, provenance flags `Sixel_Via_DA1` and `Kitty_Via_Active_Probe`, `Probed`, and optional sub-fields `Sixel_Color_Registers` and `Kitty_Graphics_Version`). Defines the three-value `APC_Parse_Result` enumeration (`Not_Present`, `OK`, `Error`) and the pure parser function `Parse_Kitty_APC_Response` for the Kitty graphics APC response (FUNC-SXL-011). Exposes 11 named string constants centralising known terminal identifier values: five `TERM_*` constants (`TERM_XTERM_KITTY`, `TERM_FOOT`, `TERM_FOOT_EXTRA`, `TERM_XTERM`, `TERM_MLTERM`, `TERM_YAFT`), two `TERM_PROGRAM_*` constants (`TERM_PROGRAM_WEZTERM`, `TERM_PROGRAM_ITERM2`), one `ENV_KITTY_WINDOW_ID` constant, and two `XTVERSION_NAME_*` constants (`XTVERSION_NAME_KITTY`, `XTVERSION_NAME_WEZTERM`). Also provides `KITTY_APC_QUERY` (the 12-byte APC query sequence `ESC _ G i=1,a=q ESC \`) and `GRAPHICS_PROBE_TIMEOUT_MS` (1 000 ms per session). No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package `Termicap.Graphics.IO`. This mirrors the pattern established by `Termicap.Mouse`, `Termicap.Keyboard`, `Termicap.DECRPM`, `Termicap.DA1`, and `Termicap.XTVERSION`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-graphics.ads`, `src/termicap-graphics.adb` |
| SPARK_Mode | On (spec and body) — **Silver level**; `Parse_Kitty_APC_Response` is locally `SPARK_Mode => On` |
| Dependencies | `Interfaces.C` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte of terminal I/O. Representation-compatible with `Termicap.OSC.Byte`. |
| `Byte_Array` | Unconstrained array of `Byte` — escape sequence data and the `KITTY_APC_QUERY` constant. Representation-compatible with `Termicap.OSC.Byte_Array`. |
| `Graphics_Capabilities` | Record aggregating `Sixel_Supported : Boolean`, `Kitty_Graphics_Supported : Boolean`, provenance flags `Sixel_Via_DA1 : Boolean` and `Kitty_Via_Active_Probe : Boolean`, `Probed : Boolean`, and optional sub-fields `Sixel_Color_Registers : Natural` (0 = unknown) and `Kitty_Graphics_Version : Natural` (0 = unknown). All fields default to `False` / `0` (safe: unsupported Sixel renders as visible garbage). `Probed = False` means the result was determined entirely by passive env-var heuristics. |
| `APC_Parse_Result` | Three-literal enumeration: `Not_Present` — no APC G envelope found (DA1 sentinel arrived first); `OK` — APC G envelope found, params contain "OK"; `Error` — APC G envelope found, params contain "EINVAL". Both `Not_Present` and `Error` map to `Kitty_Graphics_Supported = False`. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `NO_GRAPHICS_CAPABILITIES` | All fields default-initialised | Canonical "no result" value; used as the cache initial value and on every error path of `Detect_Graphics`. |
| `TERM_XTERM_KITTY` | `"xterm-kitty"` | Exact TERM value for the kitty GPU terminal (Sixel + Kitty graphics, FUNC-SXL-004). |
| `TERM_FOOT` | `"foot"` | Exact TERM value for the foot Wayland terminal (Sixel, FUNC-SXL-004). |
| `TERM_FOOT_EXTRA` | `"foot-extra"` | Exact TERM value for foot with extra capabilities (Sixel, FUNC-SXL-004). |
| `TERM_XTERM` | `"xterm"` | TERM prefix for xterm-family terminals (Sixel when compiled with `--enable-sixel`, FUNC-SXL-004). |
| `TERM_MLTERM` | `"mlterm"` | Exact TERM value for MLterm (Sixel, FUNC-SXL-004). |
| `TERM_YAFT` | `"yaft"` | Exact TERM value for the yaft framebuffer terminal (Sixel, FUNC-SXL-004). |
| `TERM_PROGRAM_WEZTERM` | `"WezTerm"` | Case-insensitive TERM_PROGRAM match for WezTerm (Sixel + Kitty graphics, FUNC-SXL-004). |
| `TERM_PROGRAM_ITERM2` | `"iTerm.app"` | Exact TERM_PROGRAM match for iTerm2 macOS (Sixel, FUNC-SXL-004). |
| `ENV_KITTY_WINDOW_ID` | `"KITTY_WINDOW_ID"` | Env-var set by kitty for every window it manages; highest-confidence passive Kitty indicator (FUNC-SXL-004). |
| `XTVERSION_NAME_KITTY` | `"kitty"` | Case-insensitive XTVERSION name token for kitty (FUNC-SXL-004). |
| `XTVERSION_NAME_WEZTERM` | `"WezTerm"` | Case-insensitive XTVERSION name token for WezTerm (FUNC-SXL-004). |
| `KITTY_APC_QUERY` | `[ESC, '_', 'G', 'i', '=', '1', ',', 'a', '=', 'q', ESC, '\']` | 12-byte APC query sequence used by the optional Kitty graphics active probe (FUNC-SXL-010). |
| `GRAPHICS_PROBE_TIMEOUT_MS` | `1_000` | Millisecond timeout per independent probe session (DA1 or APC); consistent with `MOUSE_PROBE_TIMEOUT_MS` and `KITTY_PROBE_TIMEOUT_MS` (FUNC-SXL-015). |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Parse_Kitty_APC_Response` | Function | `SPARK_Mode => On`; `Global => null`; `Pre => Length <= Buffer'Length`; `Post => True` | FUNC-SXL-011 |

#### Relationship to Other Packages

`Termicap.Graphics` depends only on `Interfaces.C`. It does not depend on `Termicap.OSC` (SPARK Off), `Termicap.DA1`, `Termicap.XTVERSION`, or any I/O package, preserving SPARK provability. Its child `Termicap.Graphics.IO` is the I/O boundary and carries `SPARK_Mode => Off`. Platform dispatch follows ADR-0018: `Termicap.Graphics.IO` has two bodies (`src/posix/termicap-graphics-io.adb` and `src/windows/termicap-graphics-io.adb`) selected by GPR `Source_Dirs`. Integration of `Graphics_Capabilities` into `Terminal_Capabilities` is deferred; see ADR-0029.

---

### `Termicap.Graphics.IO`

**Responsibility:** Platform-dispatched I/O orchestration for Sixel and Kitty graphics protocol detection. Implements the detection cascade (FUNC-SXL-012): passive Kitty env-var harvest (KITTY_WINDOW_ID, TERM=xterm-kitty, TERM_PROGRAM=WezTerm) → passive Sixel env-var harvest (TERM_PROGRAM=WezTerm, known TERM values, xterm prefix) → TTY guard → DA1 active probe for Sixel Ps=4 (reusing `Termicap.DA1.IO.Detect_DA1`) → XTVERSION name-substring fallback for Sixel → optional Kitty APC active probe (`ESC _ G i=1,a=q ESC \` + DA1 sentinel). Each active probe runs as an **independent session** with its own 1 000 ms budget (ADR-0028), in contrast to the batched single-sentinel approach used by `Termicap.Mouse.IO`. Exposes `Detect_Graphics` (result cached per process) and `Detect_Graphics_Uncached` (cache-bypass, for test harnesses).

Has `SPARK_Mode => Off` because it manages `Probe_Session` (`Limited_Controlled`) objects, performs terminal I/O, and holds a package-level protected-object cache — all outside the SPARK 2014 subset. All parsing and constant definitions remain in the provable parent package `Termicap.Graphics`.

Platform dispatch via GPR `Source_Dirs` (ADR-0018):
- **POSIX body** (`src/posix/termicap-graphics-io.adb`): cascade starts at the non-TTY guard (`Is_TTY (Stdout) = False` → return passive env-var harvest only); if that passes, continues to foreground + `/dev/tty` openability guards inside `Probe_Session.Open`, then DA1 probe, XTVERSION fallback, and optional APC probe.
- **Windows body** (`src/windows/termicap-graphics-io.adb`): cascade starts at Win32 Console gate (`GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → return passive env-var harvest only, `Probed = False`); if it fails (Cygwin/MSYS2 PTY), falls through to the POSIX-style guards.

| Property | Value |
|----------|-------|
| Files | `src/termicap-graphics-io.ads`, `src/posix/termicap-graphics-io.adb`, `src/windows/termicap-graphics-io.adb` |
| SPARK_Mode | Off (spec and both bodies) |
| Dependencies | `Termicap.Graphics`, `Termicap.DA1.IO`, `Termicap.XTVERSION.IO`, `Termicap.OSC`, `Termicap.TTY`, `Termicap.Environment` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Detect_Graphics` | Function | Returns `Graphics_Capabilities`. On first call: runs the full cascade (passive harvests + DA1 probe + XTVERSION fallback + optional APC probe); caches result in a package-level protected object. On subsequent calls: returns cached value directly (< 1 µs). Never raises. | FUNC-SXL-012, FUNC-SXL-016, FUNC-SXL-017 |
| `Detect_Graphics_Uncached` | Function | Cache-bypass variant. Runs the full cascade on every call without consulting or updating the protected-object cache. Intended for test harnesses and edge cases where a fresh probe is needed. Never raises. | FUNC-SXL-016, FUNC-SXL-017 |

**See also:** ADR-0027 (`docs/adr/0027-da1-reuse-vs-fresh-probe.md`) — rationale for reusing `Termicap.DA1.IO.Detect_DA1` rather than issuing a fresh DA1 probe from within `Termicap.Graphics.IO`; ADR-0028 (`docs/adr/0028-graphics-independent-probe-sessions.md`) — rationale for independent sessions (one per probe) vs. the batched approach used for mouse; ADR-0029 (`docs/adr/0029-graphics-package-naming.md`) — rationale for the `Termicap.Graphics` / `Termicap.Graphics.IO` naming and the deferred integration into `Terminal_Capabilities`.

---

### `Termicap.Clipboard`

**Responsibility:** Pure SPARK types, constants, and parsing functions for OSC 52 clipboard capability detection (OSC52, Tier 4 Stretch Goal). Defines the `Clipboard_Support` three-value enumeration (`None`, `Write_Only`, `Read_Write`) with ordered representation supporting `>=` comparisons. Defines the `Clipboard_Capabilities` aggregate result record (five fields: `Support`, three provenance flags `Via_DA1`, `Via_Active_Probe`, `Via_Env_Heuristic`, and `Probed`). Exposes 9 named string constants centralising known terminal identifier values used in passive env-var heuristics: `TERM_PROGRAM_WEZTERM`, `TERM_PROGRAM_ITERM2`, `TERM_PROGRAM_VSCODE` (TERM_PROGRAM matches), `ENV_WT_SESSION`, `ENV_TMUX`, `ENV_STY` (environment variable names), and `TERM_XTERM_KITTY`, `TERM_XTERM` (TERM matches). Also provides `OSC52_QUERY` (the 9-byte OSC 52 read query `ESC ] 52 ; c ; ? BEL`), `CLIPBOARD_PROBE_TIMEOUT_MS` (1 000 ms per session), the three-value `OSC52_Parse_Result` enumeration (`Not_Present`, `Valid_Response`, `Malformed`), and the pure parser function `Parse_OSC52_Response`. No I/O, no global state, no exceptions.

Re-declares `Byte` and `Byte_Array` independently of `Termicap.OSC` (which is `SPARK_Mode => Off`) to remain fully SPARK-provable while preserving representation compatibility at the I/O boundary in the child package `Termicap.Clipboard.IO`. This mirrors the pattern established by `Termicap.Graphics`, `Termicap.Mouse`, `Termicap.Keyboard`, `Termicap.DECRPM`, `Termicap.DA1`, and `Termicap.XTVERSION`.

| Property | Value |
|----------|-------|
| Files | `src/termicap-clipboard.ads`, `src/termicap-clipboard.adb` |
| SPARK_Mode | On (spec and body) — **Silver level**; `Parse_OSC52_Response` carries local `SPARK_Mode => On` with `Global => null` |
| Dependencies | `Interfaces.C` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte of terminal I/O. Representation-compatible with `Termicap.OSC.Byte`. |
| `Byte_Array` | Unconstrained array of `Byte` indexed from `Positive` — escape sequence data and the `OSC52_QUERY` constant. Representation-compatible with `Termicap.OSC.Byte_Array`. |
| `Clipboard_Support` | Three-literal enumeration: `None` (no clipboard access), `Write_Only` (OSC 52 writes accepted, read-back not confirmed), `Read_Write` (both write and read-back confirmed by active probe). `None` < `Write_Only` < `Read_Write`; callers may compare with `>=`. |
| `Clipboard_Capabilities` | Record aggregating `Support : Clipboard_Support`, provenance flags `Via_DA1 : Boolean`, `Via_Active_Probe : Boolean`, `Via_Env_Heuristic : Boolean`, and `Probed : Boolean`. All fields default to `None` / `False`. `Probed = False` means no active probe was attempted. |
| `OSC52_Parse_Result` | Three-literal enumeration: `Not_Present` (no OSC 52 introducer found; DA1 sentinel arrived first), `Valid_Response` (well-formed OSC 52 read-back response found; `BEL` or `ST` terminated), `Malformed` (introducer found but response did not terminate correctly). Both `Not_Present` and `Malformed` map to "read-back not available" in the detection cascade. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `NO_CLIPBOARD_CAPABILITIES` | All fields default-initialised | Canonical "no result" value; used as the cache initial value and on every error path of `Detect_Clipboard`. |
| `TERM_PROGRAM_WEZTERM` | `"WezTerm"` | Case-insensitive TERM_PROGRAM match for WezTerm (Read_Write heuristic, FUNC-C52-009 step 1). |
| `TERM_PROGRAM_ITERM2` | `"iTerm.app"` | Case-insensitive TERM_PROGRAM match for iTerm2 macOS (Read_Write heuristic, FUNC-C52-009 step 1). |
| `TERM_PROGRAM_VSCODE` | `"vscode"` | Case-insensitive TERM_PROGRAM match for VS Code integrated terminal (Write_Only heuristic, FUNC-C52-009 step 2). |
| `ENV_WT_SESSION` | `"WT_SESSION"` | Environment variable set by Windows Terminal (Write_Only heuristic, FUNC-C52-009 step 3). |
| `ENV_TMUX` | `"TMUX"` | Environment variable set by tmux; used for OSC 52 query multiplexer passthrough detection (FUNC-C52-011). |
| `ENV_STY` | `"STY"` | Environment variable set by GNU screen; used for OSC 52 query multiplexer passthrough detection (FUNC-C52-011). |
| `TERM_XTERM_KITTY` | `"xterm-kitty"` | Exact TERM value for the kitty GPU terminal (Read_Write heuristic, FUNC-C52-009 step 4). |
| `TERM_XTERM` | `"xterm"` | TERM prefix for xterm-family terminals (Write_Only heuristic when allowWindowOps disabled, FUNC-C52-009 step 4). |
| `OSC52_QUERY` | `[ESC, ']', '5', '2', ';', 'c', ';', '?', BEL]` | 9-byte OSC 52 clipboard read query sequence; sent by the active probe in `Termicap.Clipboard.IO` (FUNC-C52-007). |
| `CLIPBOARD_PROBE_TIMEOUT_MS` | `1_000` | Millisecond timeout per independent probe session (DA1 or OSC 52); consistent with `MOUSE_PROBE_TIMEOUT_MS`, `KITTY_PROBE_TIMEOUT_MS`, and `GRAPHICS_PROBE_TIMEOUT_MS` (FUNC-C52-015). |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Parse_OSC52_Response` | Function | `SPARK_Mode => On`; `Global => null`; `Pre => Length <= Buffer'Length`; `Post => True` | FUNC-C52-008 |

#### Relationship to Other Packages

`Termicap.Clipboard` depends only on `Interfaces.C`. It does not depend on `Termicap.OSC` (SPARK Off), `Termicap.DA1`, or any I/O package, preserving SPARK provability. Its child `Termicap.Clipboard.IO` is the I/O boundary and carries `SPARK_Mode => Off`. The DA1 `Clipboard_Access` literal (Ps=52) was added to `Termicap.DA1.DA1_Capability` to allow Phase 1 of the detection cascade to infer clipboard write capability from a DA1 response. Platform dispatch follows ADR-0018: `Termicap.Clipboard.IO` has two bodies (`src/posix/termicap-clipboard-io.adb` and `src/windows/termicap-clipboard-io.adb`) selected by GPR `Source_Dirs`. Integration of `Clipboard_Capabilities` into `Terminal_Capabilities` is deferred.

---

### `Termicap.Clipboard.IO`

**Responsibility:** Platform-dispatched I/O orchestration for OSC 52 clipboard capability detection. Implements the three-phase detection cascade (FUNC-C52-010): DA1 passive probe (Phase 1) → active OSC 52 read-back probe (Phase 2) → passive env-var heuristics (Phase 3), guarded by a non-TTY guard (POSIX) and a Win32 Console gate (Windows). Each active probe phase uses an **independent session** with its own 1 000 ms budget, consistent with ADR-0028. Worst-case cold-start latency is 2 s (both probes time out). Exposes `Detect_Clipboard` (result cached per process) and `Detect_Clipboard_Uncached` (cache-bypass, for test harnesses).

Has `SPARK_Mode => Off` because it manages `Probe_Session` (`Limited_Controlled`) objects, performs terminal I/O, and holds a package-level protected-object cache — all outside the SPARK 2014 subset. All parsing and constant definitions remain in the provable parent package `Termicap.Clipboard`.

Multiplexer passthrough: when `TMUX` or `STY` is set, the OSC 52 query is wrapped using `Termicap.OSC.Parsing.Wrap_For_Passthrough` before being sent (FUNC-C52-011). The DA1 probe (Phase 1) is performed by calling `Termicap.DA1.IO.Detect_DA1` directly, which handles its own multiplexer wrapping.

Platform dispatch via GPR `Source_Dirs` (ADR-0018):
- **POSIX body** (`src/posix/termicap-clipboard-io.adb`): cascade starts at the non-TTY guard (`Is_TTY (Stdout) = False` → run env-var heuristics only, `Probed = False`); if that passes, foreground + `/dev/tty` openability guards run inside `Probe_Session.Open`, then Phase 1 (DA1), Phase 2 (OSC 52 probe), Phase 3 (env-var heuristics when `Support = None`).
- **Windows body** (`src/windows/termicap-clipboard-io.adb`): cascade starts at Win32 Console gate (`GetConsoleMode (STD_OUTPUT_HANDLE)` succeeds → run env-var heuristics only, `Probed = False`); if it fails (Cygwin/MSYS2 PTY), falls through to the POSIX-style guards.

| Property | Value |
|----------|-------|
| Files | `src/termicap-clipboard-io.ads`, `src/posix/termicap-clipboard-io.adb`, `src/windows/termicap-clipboard-io.adb` |
| SPARK_Mode | Off (spec and both bodies) |
| Dependencies | `Termicap.Clipboard`, `Termicap.DA1.IO`, `Termicap.OSC`, `Termicap.TTY`, `Termicap.Environment` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Detect_Clipboard` | Function | Returns `Clipboard_Capabilities`. On first call: runs the full three-phase cascade (all guards + DA1 phase + OSC 52 active probe phase + env-var heuristics phase); caches result in a package-level protected object. On subsequent calls: returns cached value directly (< 1 µs). Never raises. | FUNC-C52-010, FUNC-C52-016, FUNC-C52-017 |
| `Detect_Clipboard_Uncached` | Function | Cache-bypass variant. Runs the full cascade on every call without consulting or updating the protected-object cache. Intended for test harnesses and edge cases where a fresh probe is needed. Never raises. | FUNC-C52-016, FUNC-C52-017 |

---

### `Termicap.Terminfo`

**Responsibility:** Pure SPARK types, constants, ghost predicates, and parsing functions for the ncurses compiled terminfo binary database format (TERMINFO feature). Defines the `Terminfo_Snapshot` immutable result record (eight fields: `Colors`, `Has_Setaf`, `Has_Setab`, `Setaf`, `Setab`, `Has_RGB_Flag`, `Has_Tc_Flag`, `Term_Name`), the `Terminfo_Result` discriminated type (wraps `Terminfo_Snapshot` on success, `Terminfo_Error` on failure), bounded string types (`Capability_String`, `Term_Name_String`), and discrete types `Terminfo_Format`, `Boolean_Cap_Value`, `Read_Error`, and `Terminfo_Error`. Exposes all binary-format constants (`MAGIC_LEGACY`, `MAGIC_EXTENDED`, `HEADER_SIZE`, `COLORS_INDEX`, `SETAF_INDEX`, `SETAB_INDEX`, and all `MAX_*` bounds), ghost predicates `Header_Is_Valid` and `Extended_Is_Valid` encapsulating header structural invariants, and the full pure parsing pipeline: `Detect_Format`, `Parse_Header`, `Get_Boolean`, `Get_Numeric`, `Get_String`, `Parse_Extended_Header`, `Extract_Truecolor_Flags`, and the convenience aggregation `Parse_Buffer`. Two terminfo binary format variants are supported: `Legacy_16bit` (magic `0x011A`, 16-bit numerics) and `Extended_32bit` (magic `0x021E`, 32-bit numerics, ncurses 6.1+). No I/O, no global state, no exceptions.

| Property | Value |
|----------|-------|
| Files | `src/termicap-terminfo.ads`, `src/termicap-terminfo.adb` |
| SPARK_Mode | On (spec and body) — **Silver level** |
| Dependencies | `Interfaces.C` |

#### Key Types

| Type | Description |
|------|-------------|
| `Byte` | Subtype of `Interfaces.C.unsigned_char` — single byte, compatible with the I/O child package. |
| `Byte_Array` | Unconstrained array of `Byte` indexed from `Positive` — in-memory representation of a loaded terminfo file. |
| `Terminfo_Format` | Three-literal enumeration: `Legacy_16bit`, `Extended_32bit`, `Unknown`. Produced by `Detect_Format`. |
| `Boolean_Cap_Value` | Four-literal enumeration: `Absent`, `Cancelled`, `True_Value`, `False_Value`. Maps ncurses byte conventions for boolean capabilities. |
| `Read_Error` | Four-literal enumeration: `Read_OK`, `Read_Not_Found`, `Read_IO_Error`, `Read_Too_Large`. Declared here (SPARK On) so SPARK callers can reference it; `Read_File` lives in the IO child. |
| `Terminfo_Error` | Seven-literal enumeration: `Error_No_Term`, `Error_File_Not_Found`, `Error_IO_Failure`, `Error_Invalid_Magic`, `Error_Header_Corrupt`, `Error_File_Too_Large`, `Error_Encoding`. |
| `Capability_String` | Bounded string record (`Data : String (1 .. 64)`, `Length : Natural`). Holds an extracted terminfo string capability value. |
| `Term_Name_String` | Bounded string record (`Data : String (1 .. 64)`, `Length : Natural`). Holds the primary terminal name from the names section. |
| `Parsed_Header` | Internal header record (public for ghost predicate visibility): format, section sizes, and 1-based buffer offsets for all standard sections. Produced by `Parse_Header`. |
| `Extended_Header` | Internal extended-section record (public for ghost predicate visibility): extended capability counts and 1-based buffer offsets. Produced by `Parse_Extended_Header`. |
| `Terminfo_Snapshot` | Immutable result record: `Colors` (integer, `ABSENT_NUMERIC` = −1 when absent), `Has_Setaf`/`Has_Setab` (Boolean), `Setaf`/`Setab` (`Capability_String`), `Has_RGB_Flag`/`Has_Tc_Flag` (Boolean), `Term_Name` (`Term_Name_String`). All fields default-initialised to safe "no capabilities" values. |
| `Terminfo_Result` | Discriminated result type: `(Success => True, Snapshot => Terminfo_Snapshot)` or `(Success => False, Error => Terminfo_Error)`. Default discriminant `False`. |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_TERMINFO_FILE_SIZE` | `32_768` | Maximum accepted file size in bytes (32 KiB). Files larger than this are rejected with `Read_Too_Large`. |
| `HEADER_SIZE` | `12` | Fixed byte size of the standard terminfo binary header. |
| `MAGIC_LEGACY` | `16#011A#` | Magic number for the legacy 16-bit format. |
| `MAGIC_EXTENDED` | `16#021E#` | Magic number for the extended 32-bit format (ncurses 6.1+). |
| `ABSENT_NUMERIC` | `−1` | Sentinel: capability is absent. Matches ncurses `ABSENT_NUMERIC`. |
| `CANCELLED_NUMERIC` | `−2` | Sentinel: capability has been explicitly cancelled. Matches ncurses `CANCELLED_NUMERIC`. |
| `COLORS_INDEX` | `13` | Standard ncurses index of the `colors` numeric capability. |
| `SETAF_INDEX` | `359` | Standard ncurses index of the `setaf` string capability. |
| `SETAB_INDEX` | `360` | Standard ncurses index of the `setab` string capability. |
| `MAX_NAMES_SECTION_SIZE` | `512` | Maximum byte length of the names section. |
| `MAX_BOOL_COUNT` | `64` | Maximum number of standard boolean capabilities. |
| `MAX_NUM_COUNT` | `512` | Maximum number of standard numeric capabilities. |
| `MAX_STRING_COUNT` | `512` | Maximum number of standard string capability offset entries. |
| `MAX_STRING_TABLE_SIZE` | `16_384` | Maximum byte size of the string data table. |
| `MAX_CAPABILITY_STRING_LENGTH` | `64` | Maximum character length of an extracted capability string value. |
| `MAX_TERM_NAME_LENGTH` | `64` | Maximum character length of the terminal name. |
| `MAX_PATH_LENGTH` | `512` | Maximum character length of a constructed terminfo file path. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Header_Is_Valid` | Ghost function | `Global => null`; `with Ghost` | FUNC-TIF-018 |
| `Extended_Is_Valid` | Ghost function | `Global => null`; `with Ghost` | FUNC-TIF-018 |
| `Detect_Format` | Function | `Pre => Size >= 2 and Size <= Buffer'Length`; `Post => Result in Legacy_16bit \| Extended_32bit \| Unknown` | FUNC-TIF-007 |
| `Parse_Header` | Procedure | `Pre => Size >= HEADER_SIZE and Format /= Unknown`; `Post => if Success then Header_Is_Valid (Buffer, Header)` | FUNC-TIF-008 |
| `Get_Boolean` | Function | `Pre => Header_Is_Valid (Buffer, Header)` | FUNC-TIF-009 |
| `Get_Numeric` | Function | `Pre => Header_Is_Valid and Format /= Unknown`; `Post => Result >= CANCELLED_NUMERIC` | FUNC-TIF-010 |
| `Get_String` | Procedure | `Pre => Header_Is_Valid (Buffer, Header)`; `Post => if not Present then Result.Length = 0` | FUNC-TIF-011 |
| `Parse_Extended_Header` | Procedure | `Pre => Header_Is_Valid and Size <= Buffer'Length`; `Post => if Success then Extended_Is_Valid (Buffer, Header, Ext)` | FUNC-TIF-012 |
| `Extract_Truecolor_Flags` | Procedure | `Pre => Extended_Is_Valid and Format /= Unknown` | FUNC-TIF-013, FUNC-TIF-014 |
| `Parse_Buffer` | Function | `Pre => Size >= 2 and Size <= Buffer'Length` | FUNC-TIF-007 through FUNC-TIF-014 |

#### Relationship to Other Packages

`Termicap.Terminfo` depends only on `Interfaces.C`. It does not depend on `Termicap.OSC`, `Termicap.Environment`, or any other Termicap package, preserving full SPARK provability. Its child `Termicap.Terminfo.IO` is the I/O boundary and carries `SPARK_Mode => Off` (body only; spec is `SPARK_Mode => Off` via `pragma SPARK_Mode (Off)`). Unlike the active-probing packages (`Termicap.DA1`, `Termicap.XTVERSION`, etc.), `Termicap.Terminfo.IO` does not use `Probe_Session` — it reads static files from the filesystem via POSIX `open`/`read`/`close`, making it usable in non-TTY contexts.

---

### `Termicap.Terminfo.IO`

**Responsibility:** POSIX file I/O boundary for terminfo database lookup and parsing. Implements the complete search-path resolution (FUNC-TIF-004) and file-read pipeline, then delegates binary parsing to the SPARK Silver parent package `Termicap.Terminfo`. Exposes two public subprograms: `Read_File` (low-level: open a single path, read bytes, return `Read_Error`) and `Parse_Terminfo` (top-level entry point: reads `TERM` from an `Environment` snapshot, walks the ordered candidate directory list, constructs primary and alternate paths, calls `Read_File`, and calls `Parse_Buffer`).

Search directory order: (1) `$TERMINFO`, (2) each colon-separated entry in `$TERMINFO_DIRS`, (3) `$HOME/.terminfo`, (4) `/usr/share/terminfo`, (5) `/etc/terminfo`, (6) `/lib/terminfo`. For each directory `D` and terminal name `T`: primary path `D/T(1)/T` is tried first, then alternate path `D/HH/T` where `HH` is the two-character lowercase hexadecimal encoding of the ASCII value of `T`'s first character (FUNC-TIF-005). Per-path `Read_Not_Found`, `Read_IO_Error`, and `Read_Too_Large` results are non-fatal and cause the search to continue to the next candidate (FUNC-TIF-020). A found-but-corrupt file (parse error) does not fall back to a lower-priority candidate. No Ada exception propagates from any public subprogram (FUNC-TIF-019).

Has `SPARK_Mode => Off` because it uses POSIX `open`/`read`/`close` system calls, exception handling, and string construction — all outside the SPARK 2014 subset. The spec carries `pragma SPARK_Mode (Off)` directly (unlike the IO children of active-probing packages whose specs are `SPARK_Mode => On`). This is deliberate: `Parse_Terminfo` reads from the file system rather than from a terminal device, so there is no benefit to making the spec SPARK-visible for use in SPARK contracts.

| Property | Value |
|----------|-------|
| Files | `src/termicap-terminfo-io.ads`, `src/termicap-terminfo-io.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Termicap.Terminfo`, `Termicap.Environment` |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Read_File` | Procedure | Opens the file at `Path` read-only, reads up to `MAX_TERMINFO_FILE_SIZE` bytes into `Buffer`, sets `Size` and `Error`. Always closes the file descriptor before returning, regardless of outcome. Never raises. | FUNC-TIF-006 |
| `Parse_Terminfo` | Function | Reads `TERM` from `Env`; builds the ordered candidate directory list; for each directory tries primary then alternate path via `Read_File`; on first `Read_OK` calls `Parse_Buffer` and returns the `Terminfo_Result`. Returns `(Success => False, Error => Error_No_Term)` when `TERM` is absent or empty. Returns `(Success => False, Error => Error_File_Not_Found)` when no file is found in any candidate. Never raises. | FUNC-TIF-003, FUNC-TIF-004, FUNC-TIF-005, FUNC-TIF-015, FUNC-TIF-019, FUNC-TIF-020 |

---

### `Termicap.Win32_Ntdll`

**Responsibility:** Dynamically loads `ntdll.dll` at runtime, resolves `RtlGetNtVersionNumbers` via `GetProcAddress`, calls it to obtain the Windows build number, and unloads the library. This is Termicap's only custom FFI package in the Windows integration; all other Win32 calls use the win32ada Alire crate.

Returns `0` when `LoadLibraryA` or `GetProcAddress` fails, allowing callers to treat an unresolvable build number as a pre-Anniversary-Update system (color level `None`).

| Property | Value |
|----------|-------|
| Files | `src/windows/termicap-win32_ntdll.ads`, `src/windows/termicap-win32_ntdll.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | `Interfaces`, `Interfaces.C`, `Interfaces.C.Strings`, win32ada (`Win32.Winbase`) |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Get_Build_Number` | Function | Returns the low 16 bits of the raw NT build number, or `0` on failure. Never raises. | FUNC-WIN-006, FUNC-WIN-012 |
| `Query_Object_Name` | Function | Calls `NtQueryObject` via a dynamically loaded `ntdll.dll` function pointer to retrieve the kernel object name (pipe path) of a handle as a wide-character string. Returns an empty string on any failure. Used by `Termicap.Win32_Cygwin` as a fallback when `GetFileInformationByHandleEx` is unavailable. Never raises. | FUNC-CYG-014 |

---

### `Termicap.Win32_VT`

**Responsibility:** Centralises all Win32 console handle helpers used by the Windows platform bodies. Provides the `ENABLE_VIRTUAL_TERMINAL_PROCESSING` constant (missing from win32ada), handle validation, `CONIN$`/`CONOUT$` open/close operations, and VT processing enablement via a `GetConsoleMode`/`SetConsoleMode` read-modify-write.

| Property | Value |
|----------|-------|
| Files | `src/windows/termicap-win32_vt.ads`, `src/windows/termicap-win32_vt.adb` |
| SPARK_Mode | Off (spec and body) |
| Dependencies | win32ada (`Win32`, `Win32.Winnt`, `Win32.Winbase`, `Win32.Wincon`) |

#### Key Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `ENABLE_VIRTUAL_TERMINAL_PROCESSING` | `16#0004#` | Win32 console mode flag for ANSI/VT sequence interpretation (FUNC-WIN-009). |

#### Public Operations

| Subprogram | Kind | Description | Requirements |
|-----------|------|-------------|--------------|
| `Is_Valid_Handle` | Function | Returns `True` when a `HANDLE` is neither `null` nor `INVALID_HANDLE_VALUE`. | FUNC-WIN-001 |
| `Open_Console_Input` | Function | Opens `CONIN$` via `CreateFileA`; returns `INVALID_HANDLE_VALUE` on failure. | FUNC-WIN-004 |
| `Open_Console_Output` | Function | Opens `CONOUT$` via `CreateFileA`; returns `INVALID_HANDLE_VALUE` on failure. | FUNC-WIN-004 |
| `Close_Handle` | Procedure | Closes a console handle. No-op on invalid handles; never raises. | FUNC-WIN-004 |
| `Enable_VT_Processing` | Function | Reads current console mode, ORs in `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, writes back. Returns `True` on success. | FUNC-WIN-010, FUNC-WIN-011 |

---

### `Termicap.Win32_Color`

**Responsibility:** Windows-specific color level detection. Provides two subprograms: a pure SPARK Silver function mapping a build number and `WT_SESSION` flag to a `Color_Level`, and an impure detection wrapper that reads the live OS build number and consults the environment snapshot.

Build number thresholds (FUNC-WIN-008):

| Build Number Range | Color Level |
|--------------------|-------------|
| `< 10_586` | `None` |
| `10_586 .. 14_930` | `Extended_256` |
| `>= 14_931` | `True_Color` |

If `WT_SESSION` is present and non-empty, the result is always `True_Color` regardless of build number (FUNC-WIN-007). `Basic_16` is never returned — guaranteed by the SPARK postcondition on `Build_To_Color_Level` (FUNC-WIN-013).

| Property | Value |
|----------|-------|
| Files | `src/windows/termicap-win32_color.ads`, `src/windows/termicap-win32_color.adb` |
| SPARK_Mode | On (spec and `Build_To_Color_Level` body); Off (`Detect_Windows_Color_Level` body) |
| Dependencies | `Interfaces`, `Termicap.Color`, `Termicap.Environment`, `Termicap.Win32_Ntdll` (body only) |

#### Key Types

| Type | Description |
|------|-------------|
| `Build_Number` | Subtype of `Interfaces.Unsigned_32`. Matches the return type of `Win32_Ntdll.Get_Build_Number`. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Build_To_Color_Level` | Function | `Global => null`; `Post => (if Has_WT_Session then Result = True_Color) and then Result in None \| Extended_256 \| True_Color` | FUNC-WIN-007, FUNC-WIN-008, FUNC-WIN-013 |
| `Detect_Windows_Color_Level` | Function | `SPARK_Mode => Off` — calls `Win32_Ntdll.Get_Build_Number` and reads `WT_SESSION` from `Env` | FUNC-WIN-007 |

#### Relationship to Other Packages

`Termicap.Win32_Color` depends on `Termicap.Win32_Ntdll` (body only). It is called by the Windows-platform body of `Termicap.Capabilities`, which combines the returned level with the env-var cascade result using `Color_Level'Max`. Application code never calls `Win32_Color` or `Win32_Ntdll` directly.

---

### `Termicap.Win32_Cygwin`

**Responsibility:** Detects whether a Win32 `HANDLE` refers to a Cygwin or MSYS2 pseudo-terminal (PTY). Cygwin/MSYS2 PTYs appear as named pipes to the Windows Console API — `GetConsoleMode` fails on them — so a separate name-inspection step is required.

Provides two subprograms:

- `Is_Cygwin_Pipe_Name`: a pure SPARK Silver function that validates a decoded ASCII pipe name against the Cygwin/MSYS2 pipe name grammar (five token-level rules, minimum five `'-'`-delimited segments). Provable at SPARK Silver with `Global => null`. This is the primary testable unit.
- `Is_Cygwin_Terminal`: an impure Ada wrapper that sequences the full detection pipeline — `GetFileType` guard (must be `FILE_TYPE_PIPE`), pipe name retrieval via `GetFileInformationByHandleEx` (primary) or `NtQueryObject` (fallback), UTF-16 decoding, and `Is_Cygwin_Pipe_Name` pattern matching — for a live Win32 `HANDLE`.

The Windows body of `Termicap.TTY` calls `Is_Cygwin_Terminal` as a second-chance check when `GetConsoleMode` fails, before returning `False` (FUNC-CYG-015).

| Property | Value |
|----------|-------|
| Files | `src/windows/termicap-win32_cygwin.ads`, `src/windows/termicap-win32_cygwin.adb` |
| SPARK_Mode | On (spec); Off (body, except `Is_Cygwin_Pipe_Name` body is locally On) |
| Dependencies | win32ada (`Win32.Winnt`); body also uses `Win32.Winbase`, `Win32.Wincon`, `Termicap.Win32_Ntdll` (for `Query_Object_Name`) |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Is_Cygwin_Pipe_Name` | Function | `Global => null`; pure pattern match — SPARK Silver | FUNC-CYG-006 through FUNC-CYG-013 |
| `Is_Cygwin_Terminal` | Function | `SPARK_Mode => Off` — full pipeline with OS calls | FUNC-CYG-014, FUNC-CYG-016 |

#### Relationship to Other Packages

`Termicap.Win32_Cygwin` depends on `Termicap.Win32_Ntdll` (body only, for `Query_Object_Name`). It is called by the Windows-platform body of `Termicap.TTY`; it is not called by application code directly. `Termicap.Win32_Ntdll` was extended with `Query_Object_Name` to support `NtQueryObject`-based pipe name retrieval as a fallback when `GetFileInformationByHandleEx` is unavailable.

---

## SPARK Boundary Summary

```
┌─────────────────────────────────────────────────────┐
│                   SPARK Silver Zone                 │
│                                                     │
│   Termicap.Environment (spec + body)                │
│   ┌─────────────────────────────────────────────┐  │
│   │  Contains, Value, Insert,                   │  │
│   │  Equal_Case_Insensitive, Value_Matches       │  │
│   │  Global => null on all subprograms           │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Override (spec + pure functions)         │
│   ┌─────────────────────────────────────────────┐  │
│   │  Override_Mode type (five literals)         │  │
│   │  Set_Override / Get_Override /              │  │
│   │    Reset_Override (delegate to protected    │  │
│   │    object — bodies are SPARK_Mode => Off)   │  │
│   │  Parse_Color_Flag — Global => null (Gold)   │  │
│   │  Abstract_State: Override_State (External)  │  │
│   └─────────────────────────────────────────────┘  │
│                          ▲  ▲                       │
│                          │  └──────────────────┐   │
│   Termicap.Color (spec + body)                  │   │
│   ┌─────────────────────────────────────────┐   │   │
│   │  Color_Level type                       │   │   │
│   │  Detect_Color_Level (Env, Is_TTY)       │   │   │
│   │  Global => (Input => Override_State)    │   │   │
│   │  Step 0: override check; steps 1–11:   │   │   │
│   │    env-var cascade                      │   │   │
│   └─────────────────────────────────────────┘   │   │
│                                                  │   │
│   Termicap.TTY (spec only)                       │   │
│   ┌─────────────────────────────────────────┐   │   │
│   │  Stream_Kind, TTY_Status types          │   │   │
│   │  Is_TTY, Query_All signatures           │   │   │
│   │  Global => (Input => Override_State)    │   │   │
│   └─────────────────────────────────────────┘   │   │
│                                           └──────┘   │
│   Termicap.Downsampling (spec + body) [Gold]        │
│   ┌─────────────────────────────────────────────┐  │
│   │  Color_Component, RGB,                      │  │
│   │    Color_Index_256, Color_Index_16,         │  │
│   │    Downsampled_Color types                  │  │
│   │  Downsample_True_To_256/16, _256_To_16,    │  │
│   │    Downsample (×2), Color_Level_Of          │  │
│   │  Global => null — pure arithmetic, no FFI   │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│                                                     │
│   Termicap.Unicode (spec + body)                    │
│   ┌─────────────────────────────────────────────┐  │
│   │  Unicode_Level type                         │  │
│   │  Detect_Unicode_Level (Env)                 │  │
│   │  Global => null — 5-step cascade            │  │
│   │  (no Is_TTY parameter)                      │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Dimensions (spec only)                   │
│   ┌─────────────────────────────────────────────┐  │
│   │  Terminal_Size type                         │  │
│   │  Get_Size (Env, Is_TTY : Boolean)           │  │
│   │  Global => null — 3-step fallback chain     │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Terminal_Id (spec only)                  │
│   ┌─────────────────────────────────────────────┐  │
│   │  Terminal_Kind, Multiplexer_Kind,           │  │
│   │    Terminal_Identity types                  │  │
│   │  Detect_Terminal_Identity (Env)             │  │
│   │  Global => null — 8-step cascade            │  │
│   │  (no Is_TTY parameter)                      │  │
│   └─────────────────────────────────────────────┘  │
└────────────────────────────┬────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────┐
│             Ada-only Zone (SPARK_Mode => Off)        │
│                                                     │
│   Termicap.Environment.Capture                      │
│   ┌─────────────────────────────────────────────┐  │
│   │  Capture_Current                            │  │
│   │  Ada.Environment_Variables.Iterate          │  │
│   │  (OS syscall — not provable by GNATprove)   │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Override (body — non-spec sections)      │
│   ┌─────────────────────────────────────────────┐  │
│   │  Protected object State: holds current      │  │
│   │    Override_Mode; reader-writer semantics   │  │
│   │  Set_Override / Get_Override bodies         │  │
│   │  Scoped_Override.Initialize / Finalize      │  │
│   │  (Ada protected + Ada.Finalization —        │  │
│   │    outside SPARK 2014 subset)               │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.TTY (body)                               │
│   ┌─────────────────────────────────────────────┐  │
│   │  C_Isatty via pragma Import (C, ...)        │  │
│   │  Is_TTY, Query_All implementations          │  │
│   │  (POSIX isatty() — not provable)            │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Dimensions (body)                        │
│   ┌─────────────────────────────────────────────┐  │
│   │  C_Get_Winsize via pragma Import (C, ...)   │  │
│   │  termicap_get_winsize (src/c/termicap_      │  │
│   │    ioctl.c) wraps ioctl(TIOCGWINSZ)         │  │
│   │  Try_Parse_Positive helper                  │  │
│   │  Get_Size implementation                    │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Terminal_Id (body)                       │
│   ┌─────────────────────────────────────────────┐  │
│   │  Ada.Strings.Unbounded (controlled type —   │  │
│   │    not in SPARK subset; see ADR-0008)        │  │
│   │  Starts_With_CI private helper              │  │
│   │  Detect_Terminal_Identity implementation    │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Sigwinch (spec + body)                   │
│   ┌─────────────────────────────────────────────┐  │
│   │  Protected singleton: Installed, Pending,   │  │
│   │    Cached_Size — serialises all callers     │  │
│   │  Install / Uninstall / Has_Resize /         │  │
│   │    Acknowledge_Resize / Get_Pipe_Read_FD /  │  │
│   │    Get_Cached_Size implementations          │  │
│   │  C trampoline (termicap_sigwinch.c):         │  │
│   │    async-signal-safe handler, ioctl +       │  │
│   │    pipe write, sigaction installation       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Capabilities (body — non-spec sections)  │
│   ┌─────────────────────────────────────────────┐  │
│   │  Protected per-stream cache object          │  │
│   │  Detect body — calls sub-detectors, builds  │  │
│   │    Terminal_Capabilities via Assemble       │  │
│   │  Get body — reads/writes cache, delegates   │  │
│   │    to Detect on first call per stream       │  │
│   │  (Ada protected type + OS-calling sub-      │  │
│   │    detectors — outside SPARK 2014 subset)   │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.OSC (spec + body)                        │
│   ┌─────────────────────────────────────────────┐  │
│   │  Probe_Session (Limited_Controlled)         │  │
│   │  Open / Close / Is_Open / Finalize          │  │
│   │  Sentinel_Query / Write_Query / Timed_Read  │  │
│   │  Is_Foreground_Process                      │  │
│   │  Open_Terminal / Close_Terminal             │  │
│   │  Save_Termios / Restore_Termios / Set_Raw   │  │
│   │  Drain_Input                                │  │
│   │  C helper (termicap_osc.c): 9 functions     │  │
│   │  (Limited_Controlled + POSIX syscalls —     │  │
│   │    outside SPARK 2014 subset)               │  │
│   └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────┐
│             SPARK Silver Zone (children)             │
│                                                     │
│   Termicap.OSC.Parsing (spec + body)                │
│   ┌─────────────────────────────────────────────┐  │
│   │  DA1_Value_Array, DA1_Params,               │  │
│   │    Passthrough_Mode types                   │  │
│   │  Contains_DA1_Response — Pre only           │  │
│   │  DA1_Response_Start — Pre + Post            │  │
│   │  Parse_DA1_Response — Pre + Post (Silver)   │  │
│   │  Wrap_For_Passthrough — pure                │  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Color.BG_Query (spec + body)             │
│   ┌─────────────────────────────────────────────┐  │
│   │  RGB, Query_Kind, Parse_Result,             │  │
│   │    Strip_Result, Colorfgbg_Result types     │  │
│   │  OSC_BG_QUERY / OSC_FG_QUERY constants      │  │
│   │  ANSI_COLOR_TABLE (xterm 16-color palette)  │  │
│   │  Parse_RGB_Response, Strip_OSC_Header,      │  │
│   │    Parse_Colorfgbg, Parse_Hex_Channel,      │  │
│   │    Find_RGB_Prefix, Split_RGB_Channels,     │  │
│   │    Ansi_To_RGB, Query_Sequence              │  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Color.Dark_Light (spec + body) [Gold]   │
│   ┌─────────────────────────────────────────────┐  │
│   │  Theme_Kind (Dark, Light) enumeration       │  │
│   │  LUMINANCE_THRESHOLD : constant := 128      │  │
│   │  Luminance — BT.601 integer formula,        │  │
│   │    Post => Result in 0..255                 │  │
│   │  Classify_Theme — threshold comparison      │  │
│   │  Is_Dark / Is_Light — expression functions  │  │
│   │  Global => null — pure arithmetic, no I/O   │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.XTVERSION (spec + body)                  │
│   ┌─────────────────────────────────────────────┐  │
│   │  XTVERSION_Status, XTVERSION_Result,        │  │
│   │    Payload_Slice, Token_Pair types          │  │
│   │  CSI_XTVERSION_QUERY constant               │  │
│   │  MAX_RESPONSE_SIZE : constant := 4_096      │  │
│   │  Contains_XTVERSION_Response — Pre only     │  │
│   │  Extract_XTV_Payload — Pre + Post           │  │
│   │  Split_XTV_Payload — Pre only               │  │
│   │  Parse_XTVERSION_Response — Pre + Post      │  │
│   │    (Silver)                                 │  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.DA1 (spec + body)                        │
│   ┌─────────────────────────────────────────────┐  │
│   │  DA1_Capability, VT_Level enumerations      │  │
│   │  Capability_Flags, DA1_Capabilities types   │  │
│   │  DA1_QUERY constant                         │  │
│   │  Interpret_DA1 — Pre + Post (Silver)        │  │
│   │  Has_Capability — expression function       │  │
│   │  VT_Level_Of — expression function          │  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.DECRPM (spec + body)                     │
│   ┌─────────────────────────────────────────────┐  │
│   │  Mode_Id subtype, Mode_Status enumeration   │  │
│   │  Mode_Report, Mode_Id_Array,                │  │
│   │    Mode_Report_Array types                  │  │
│   │  MODE_* named constants (6)                 │  │
│   │  MAX_RESPONSE_SIZE, MAX_BATCH_MODES         │  │
│   │  DECRPM_Query — Post: Result'Length >= 6    │  │
│   │  Contains_DECRPM_Response — Pre only        │  │
│   │  Parse_DECRPM_Response — Pre + Post (Silver)│  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Keyboard (spec + body)                   │
│   ┌─────────────────────────────────────────────┐  │
│   │  Keyboard_Protocol enumeration (5 values)   │  │
│   │  Kitty_Flags record (5 Boolean fields)      │  │
│   │  Keyboard_Capability record (Protocol,      │  │
│   │    Flags, Probed); Parse_Result type        │  │
│   │  Byte / Byte_Array types                    │  │
│   │  CSI_KITTY_QUERY, CSI_XTERM_KBD_QUERY,     │  │
│   │    NO_KITTY_FLAGS, NO_KEYBOARD_CAPABILITY   │  │
│   │  KITTY_PROBE_TIMEOUT_MS : 1_000             │  │
│   │  XTERM_KBD_PROBE_TIMEOUT_MS : 1_000        │  │
│   │  MAX_RESPONSE_SIZE : 4_096                  │  │
│   │  Parse_Kitty_Flags — Pre only (Silver)      │  │
│   │  Parse_Kitty_Response — Pre + Post (Silver) │  │
│   │  Parse_XTerm_Keyboard_Response — Pre (Silver│  │
│   │    )                                        │  │
│   │  Global => null — no FFI, no state          │  │
│   └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────┐
│      Ada-only Zone (children, SPARK_Mode => Off)     │
│                                                     │
│   Termicap.Color.BG_Query.IO (spec + body)          │
│   ┌─────────────────────────────────────────────┐  │
│   │  Query_Color — opens Probe_Session,         │  │
│   │    applies multiplexer passthrough wrap,    │  │
│   │    calls Sentinel_Query, returns bytes      │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Color.Detection (spec + body)            │
│   ┌─────────────────────────────────────────────┐  │
│   │  Detect_Error, Detection_Result types       │  │
│   │  Detect_Background_Color / Detect_          │  │
│   │    Foreground_Color — two-level cascade:    │  │
│   │    OSC query → COLORFGBG fallback           │  │
│   │  (calls Query_Color + env capture —         │  │
│   │    outside SPARK 2014 subset)               │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Color.Dark_Light.Detect (spec + body)   │
│   ┌─────────────────────────────────────────────┐  │
│   │  Theme_Result discriminated record          │  │
│   │  MAX_TIMEOUT_MS : constant := 30_000        │  │
│   │  Detect_Theme — clamps timeout, calls       │  │
│   │    Detect_Background_Color, classifies      │  │
│   │    via Classify_Theme, returns Theme_Result │  │
│   │  (calls Detect_Background_Color —           │  │
│   │    outside SPARK 2014 subset)               │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.XTVERSION.IO (spec + body)               │
│   ┌─────────────────────────────────────────────┐  │
│   │  Query_XTVERSION — opens Probe_Session,     │  │
│   │    detects multiplexer via                  │  │
│   │    Detect_Terminal_Identity, applies        │  │
│   │    Wrap_For_Passthrough, calls              │  │
│   │    Sentinel_Query (Retry => False),         │  │
│   │    returns bytes                            │  │
│   │  Query_And_Identify — combines I/O with     │  │
│   │    Parse_XTVERSION_Response; default        │  │
│   │    timeout 100 ms                           │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.DA1.IO (spec + body)                     │
│   ┌─────────────────────────────────────────────┐  │
│   │  Query_DA1 — opens Probe_Session, detects   │  │
│   │    multiplexer, applies passthrough wrap,   │  │
│   │    calls Timeout_Query (not Sentinel_Query) │  │
│   │    — DA1 response IS the data sought        │  │
│   │  Detect_DA1 — combines I/O, parsing         │  │
│   │    (Parse_DA1_Response), and interpretation │  │
│   │    (Interpret_DA1); default timeout 100 ms  │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.DECRPM.IO (spec + body)                  │
│   ┌─────────────────────────────────────────────┐  │
│   │  Query_Error, Mode_Query_Result,            │  │
│   │    Batch_Query_Result types                 │  │
│   │  Query_Mode — opens Probe_Session,          │  │
│   │    detects multiplexer, applies passthrough │  │
│   │    wrap, calls Sentinel_Query (Retry=>False)│  │
│   │    — DECRPM response is distinct from DA1   │  │
│   │    sentinel, so Sentinel_Query is safe      │  │
│   │  Detect_Mode — combines I/O with            │  │
│   │    Parse_DECRPM_Response; default 100 ms    │  │
│   │  Detect_Modes — batch query within a single │  │
│   │    Probe_Session; default 200 ms total      │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Keyboard.IO (spec + body)                │
│   ┌─────────────────────────────────────────────┐  │
│   │  Detect_Keyboard_Protocol — cached entry    │  │
│   │    point; returns NO_KEYBOARD_CAPABILITY on │  │
│   │    non-TTY or background process; probes    │  │
│   │    Kitty then XTerm via Sentinel_Query;     │  │
│   │    falls back to Legacy; caches result      │  │
│   │  Probe_Keyboard_Protocol — uncached variant │  │
│   │    (bypasses protected cache; runs full     │  │
│   │    cascade each call)                       │  │
│   │  Windows body: GetConsoleMode fast-path     │  │
│   │    short-circuits to (Win32, Probed=False)  │  │
│   │    before any probe; falls through to       │  │
│   │    Cygwin/MSYS PTY path when gate fails     │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Clipboard.IO (spec + body)               │
│   ┌─────────────────────────────────────────────┐  │
│   │  Detect_Clipboard — cached entry point;     │  │
│   │    three-phase cascade: DA1 passive probe   │  │
│   │    (reuses Detect_DA1) → active OSC 52      │  │
│   │    read-back probe (Sentinel_Query +        │  │
│   │    Parse_OSC52_Response) → env-var          │  │
│   │    heuristics; wraps OSC52_QUERY for        │  │
│   │    TMUX/STY passthrough; caches result      │  │
│   │  Detect_Clipboard_Uncached — cache-bypass   │  │
│   │    variant (bypasses protected cache;       │  │
│   │    runs full cascade each call)             │  │
│   │  Windows body: GetConsoleMode fast-path     │  │
│   │    short-circuits to env-var heuristics     │  │
│   │    only (Probed = False) before any probe   │  │
│   │  (Probe_Session Limited_Controlled +        │  │
│   │    terminal I/O — outside SPARK 2014)       │  │
│   └─────────────────────────────────────────────┘  │
│                                                     │
│   Termicap.Terminfo.IO (spec + body)                │
│   ┌─────────────────────────────────────────────┐  │
│   │  Read_File — opens a file path, reads up    │  │
│   │    to MAX_TERMINFO_FILE_SIZE bytes into a   │  │
│   │    caller-supplied Byte_Array; returns a    │  │
│   │    Read_Error status code (POSIX open/      │  │
│   │    read/close — outside SPARK 2014)         │  │
│   │  Parse_Terminfo — executes the full search  │  │
│   │    path resolution ($TERMINFO, $TERMINFO_   │  │
│   │    DIRS, $HOME/.terminfo, /usr/share/,      │  │
│   │    /etc/, /lib/terminfo), primary + alt     │  │
│   │    path construction (D/T(1)/T and D/HH/T),│  │
│   │    and calls Parse_Buffer; returns a        │  │
│   │    Terminfo_Result; never propagates        │  │
│   │    an Ada exception                         │  │
│   │  (POSIX file I/O + string construction —   │  │
│   │    outside SPARK 2014)                      │  │
│   └─────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

The SPARK boundary is deliberately narrow: `Capture_Current`, the `Termicap.Override` body (protected object, `Set_Override`/`Get_Override` bodies, and `Scoped_Override.Initialize`/`Finalize`), the `Termicap.TTY` body, the `Termicap.Dimensions` body, the `Termicap.Terminal_Id` body, the entirety of `Termicap.Sigwinch`, the `Detect`/`Get` bodies of `Termicap.Capabilities`, and the entirety of `Termicap.OSC` are the only points where non-provable code executes. Once a snapshot is produced and TTY status is captured as a `Boolean`, all subsequent detection operations — including `Termicap.Color`, `Termicap.Unicode`, the spec contracts on `Get_Size` and `Detect_Terminal_Identity`, and the `Assemble` function of `Termicap.Capabilities` — stay within the provable zone. `Termicap.Downsampling` goes further: both its spec and its body carry `SPARK_Mode => On` with Gold-level provability — no FFI, no dynamic allocation, no unbounded loops. `Termicap.Override.Parse_Color_Flag` is also provable at Gold level (pure string comparison, no side effects). `Termicap.Unicode` and `Termicap.Downsampling` are the packages where both spec and body carry `SPARK_Mode => On`; `Termicap.Unicode` and `Termicap.Terminal_Id` are the two detection functions callable without a TTY status parameter. `Termicap.Sigwinch` and `Termicap.OSC` are the packages where both spec and body are wholly outside the SPARK zone: `Termicap.Sigwinch` due to its protected object, interrupt handler, and C FFI; `Termicap.OSC` due to `Limited_Controlled` and POSIX syscall FFI. `Termicap.OSC.Parsing` is the pure SPARK Silver complement to `Termicap.OSC`, containing only provable functions that operate on `Byte_Array` values with no side effects. `Termicap.Capabilities` occupies a hybrid position: its spec and the pure `Assemble` function are SPARK Silver, while the `Detect`/`Get` bodies and the protected cache object are compiled with `SPARK_Mode => Off`. The BG-COLOR subsystem follows the same SPARK split pattern: `Termicap.Color.BG_Query` (both spec and body) is fully SPARK Silver — pure parsing functions with `Global => null` and no FFI; `Termicap.Color.BG_Query.IO` and `Termicap.Color.Detection` are entirely `SPARK_Mode => Off` because they manage `Probe_Session` controlled types and perform terminal I/O. The DARK-LIGHT subsystem continues this layering: `Termicap.Color.Dark_Light` (both spec and body) is SPARK Gold — pure integer arithmetic with `Post` contracts and no I/O; `Termicap.Color.Dark_Light.Detect` is `SPARK_Mode => Off` because it calls `Detect_Background_Color`, which manages `Probe_Session` controlled types and performs terminal I/O. The XTVERSION subsystem applies the identical SPARK split: `Termicap.XTVERSION` (both spec and body) is fully SPARK Silver — pure parsing functions with `Global => null`, no FFI, no global state; `Termicap.XTVERSION.IO` is entirely `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O. Like `Termicap.Color.BG_Query`, `Termicap.XTVERSION` re-declares `Byte`/`Byte_Array` independently of `Termicap.OSC` to avoid a SPARK mode boundary violation while preserving representation compatibility. The DA1 subsystem applies the same SPARK split: `Termicap.DA1` (both spec and body) is fully SPARK Silver — pure `Interpret_DA1`, `Has_Capability`, and `VT_Level_Of` functions with `Global => null`, no FFI, no global state; `Termicap.DA1.IO` is entirely `SPARK_Mode => Off` because it manages a `Probe_Session` and performs terminal I/O via `Timeout_Query`. Unlike other active probes, `Termicap.DA1.IO` cannot use `Sentinel_Query` because the DA1 response is itself the data being sought; it calls `Timeout_Query` instead, a new public procedure added to `Termicap.OSC`. `Termicap.Capabilities` has been extended with a `DA1 : Termicap.DA1.DA1_Capabilities` field and now depends on `Termicap.DA1.IO` in its body. The DECRPM subsystem applies the same SPARK split: `Termicap.DECRPM` (both spec and body) is fully SPARK Silver — `DECRPM_Query`, `Contains_DECRPM_Response`, and `Parse_DECRPM_Response` functions with `Global => null`, no FFI, no global state; `Termicap.DECRPM.IO` is entirely `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O. Unlike `Termicap.DA1.IO`, `Termicap.DECRPM.IO` uses `Sentinel_Query` (not `Timeout_Query`): DECRPM responses (`CSI ? Ps ; Pm $ y`) are structurally distinct from the DA1 sentinel (`ESC [ c`), so the sentinel pattern can safely bound the accumulation loop. Like all other active-probing SPARK packages, `Termicap.DECRPM` re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` independently of `Termicap.OSC` to preserve SPARK provability while maintaining representation compatibility at the I/O boundary. The KEYBOARD subsystem applies the identical SPARK split: `Termicap.Keyboard` (both spec and body) is fully SPARK Silver — `Parse_Kitty_Flags`, `Parse_Kitty_Response`, and `Parse_XTerm_Keyboard_Response` pure functions with `Global => null`, no FFI, no global state; `Termicap.Keyboard.IO` is entirely `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`) and performs terminal I/O. `Termicap.Keyboard.IO` uses `Sentinel_Query` for both probes: the Kitty response (`CSI ? <digits> u`) and the XTerm response (`CSI ? 4 ; <value> m`) are both structurally distinct from the DA1 sentinel, so the sentinel pattern safely bounds each probe's accumulation loop. Like `Termicap.DECRPM`, `Termicap.Keyboard` re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` independently of `Termicap.OSC`. Platform dispatch follows ADR-0018: two bodies under `src/posix/` and `src/windows/` are selected by GPR `Source_Dirs`; the Windows body adds a `GetConsoleMode` fast-path gate before the shared cascade. Integration of `Keyboard_Capability` into `Terminal_Capabilities` is deferred; see ADR-0021. The MOUSE subsystem applies the same SPARK split: `Termicap.Mouse` (spec) is SPARK Silver — `Parse_Mouse_DECRPM_Response` and `Resolve_Best_Encoding` are pure functions with `Global => null`, no FFI, no global state; `Termicap.Mouse.IO` is entirely `SPARK_Mode => Off` because it manages a `Probe_Session` (`Limited_Controlled`), performs terminal I/O, and holds a protected-object cache. Unlike `Termicap.Keyboard.IO` (which fires two independent `Sentinel_Query` calls), `Termicap.Mouse.IO` issues all six DECRPM queries in a single batch followed by one DA1 sentinel — a design documented in ADR-0022. The response scanner in `Termicap.Mouse.IO` calls `Parse_Mouse_DECRPM_Response` at successive positions in the pre-sentinel buffer, matching frames by `Mode` number rather than position. Like `Termicap.Keyboard`, `Termicap.Mouse` re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` independently of `Termicap.OSC`. Platform dispatch follows ADR-0018: two bodies under `src/posix/` and `src/windows/` are selected by GPR `Source_Dirs`; the Windows body adds a `GetConsoleMode` fast-path gate (Guard 1); the POSIX body starts at the GPM heuristic (Guard 2). Integration of `Mouse_Capabilities` into `Terminal_Capabilities` is deferred; see ADR-0026. The GRAPHICS subsystem (Tier 4 — SIXEL) applies the same SPARK split: `Termicap.Graphics` (spec and body) is SPARK Silver — `Parse_Kitty_APC_Response` is a pure function with `Global => null`, no FFI, no global state; `Termicap.Graphics.IO` is entirely `SPARK_Mode => Off` because it manages `Probe_Session` controlled types, performs terminal I/O, and holds a protected-object cache. Unlike `Termicap.Mouse.IO` (which batches all queries into one session), `Termicap.Graphics.IO` uses **independent probe sessions**: one session for the DA1 Sixel probe and a separate session for the optional Kitty APC probe — a design documented in ADR-0028. The DA1 probe reuses `Termicap.DA1.IO.Detect_DA1` directly rather than issuing a fresh low-level probe (ADR-0027). Like all other active-probing SPARK packages, `Termicap.Graphics` re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` independently of `Termicap.OSC`. Platform dispatch follows ADR-0018: two bodies under `src/posix/` and `src/windows/` are selected by GPR `Source_Dirs`; the Windows body starts at the Win32 Console gate (`GetConsoleMode (STD_OUTPUT_HANDLE)`); the POSIX body starts at the non-TTY guard. Integration of `Graphics_Capabilities` into `Terminal_Capabilities` is deferred; see ADR-0029. The TERMINFO subsystem applies the same SPARK split at the parser level: `Termicap.Terminfo` (spec and body) is SPARK Silver — the full binary parsing pipeline is expressed as pure functions and procedures with `Global => null` or explicit preconditions that discharge all array-index checks via the ghost predicates `Header_Is_Valid` and `Extended_Is_Valid`; `Termicap.Terminfo.IO` is `SPARK_Mode => Off` (both spec and body) because it performs POSIX file I/O and builds path strings dynamically. Unlike the active-probing IO children, `Termicap.Terminfo.IO` does not use a `Probe_Session` — the terminfo database is a static filesystem artifact, not a TTY device. The OSC52 CLIPBOARD subsystem (Tier 4 Stretch Goal) applies the same SPARK split: `Termicap.Clipboard` (spec and body) is SPARK Silver — `Parse_OSC52_Response` is a pure function with `Global => null`, no FFI, no global state; `Termicap.Clipboard.IO` is entirely `SPARK_Mode => Off` because it manages `Probe_Session` controlled types, performs terminal I/O, and holds a protected-object cache. Like `Termicap.Graphics.IO`, `Termicap.Clipboard.IO` uses **independent probe sessions**: one session for the DA1 Phase 1 probe (reusing `Termicap.DA1.IO.Detect_DA1`) and a separate session for the OSC 52 active read-back probe — each with its own 1 000 ms budget. The OSC 52 query is wrapped for tmux/screen multiplexer passthrough using `Termicap.OSC.Parsing.Wrap_For_Passthrough` when `TMUX` or `STY` is set in the environment. `Termicap.DA1` was extended with a `Clipboard_Access` literal (Ps=52) to enable Phase 1 passive inference from the DA1 response. Like all other active-probing SPARK packages, `Termicap.Clipboard` re-declares `Byte`/`Byte_Array` from `Interfaces.C.unsigned_char` independently of `Termicap.OSC`. Platform dispatch follows ADR-0018: two bodies under `src/posix/` and `src/windows/` are selected by GPR `Source_Dirs`; the Windows body starts at the Win32 Console gate (`GetConsoleMode (STD_OUTPUT_HANDLE)`); the POSIX body starts at the non-TTY guard. Integration of `Clipboard_Capabilities` into `Terminal_Capabilities` is deferred.

## Related Documents

- **ADR-0001** (`docs/adr/0001-environment-snapshot-storage-strategy.md`): Container choice rationale for `Env_Maps`
- **ADR-0002** (`docs/adr/0002-multi-candidate-matching-spark-boundary.md`): `Value_Matches` / `String_Vector` design decision
- **ADR-0003** (`docs/adr/0003-tty-detection-package-structure.md`): TTY package structure and `TTY_Status` type decision
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`): Full design rationale for `Termicap.Environment`
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`): TTY detection design rationale
- **Tech Spec F3** (`docs/tech-specs/f3-color-level-detection.md`): Color level detection design rationale
- **Tech Spec F4** (`docs/tech-specs/terminal-dimensions.md`): Terminal dimensions detection design rationale
- **Tech Spec F5** (`docs/tech-specs/unicode-support.md`): Unicode support level detection design rationale
- **ADR-0006** (`docs/adr/0006-c-wrapper-for-ioctl-tiocgwinsz.md`): Rationale for the thin C wrapper over ioctl
- **ADR-0007** (`docs/adr/0007-unicode-level-three-value-enum.md`): Rationale for the three-value `Unicode_Level` enumeration
- **ADR-0008** (`docs/adr/0008-terminal-id-string-representation-spark-boundary.md`): Rationale for `SPARK_Mode => Off` body and `Ada.Strings.Unbounded` use in `Termicap.Terminal_Id`
- **Tech Spec F6** (`docs/tech-specs/terminal-identification.md`): Terminal identification detection design rationale
- **Tech Spec F7** (`docs/tech-specs/color-downsampling.md`): Color downsampling design rationale, algorithm survey, and type design decisions (ADR-0009)
- **Tech Spec F8** (`docs/tech-specs/sigwinch.md`): SIGWINCH resize notification design rationale, self-pipe pattern, and C trampoline decision
- **Tech Spec F9** (`docs/tech-specs/override.md`): Global override feature design rationale, SPARK strategy, and framework survey
- **ADR-0010** (`docs/adr/0010-override-mode-flat-enum.md`): Rationale for the five-literal flat enumeration over alternative override representations
- **ADR-0011** (`docs/adr/0011-capability-record-package-placement.md`): Rationale for placing the aggregation package as a top-level child of `Termicap`
- **ADR-0012** (`docs/adr/0012-capability-cache-design.md`): Rationale for the per-stream protected cache design
- **ADR-0013** (`docs/adr/0013-spark-annotation-split-capabilities.md`): Rationale for the SPARK/Ada split in `Termicap.Capabilities`
- **Tech Spec F10** (`docs/tech-specs/capability-record.md`): Capability record assembly design rationale
- **Tech Spec OSC** (`docs/tech-specs/osc-query-infra.md`): OSC query infrastructure design rationale, sentinel pattern, C helper design, and ADR-0014
- **Tech Spec DARK-LIGHT** (`docs/tech-specs/dark-light.md`): Dark/light theme classification design rationale — BT.601 integer luminance, SPARK Gold boundary, discriminated result type
- **Tech Spec XTVERSION** (`docs/tech-specs/xtversion.md`): XTVERSION active terminal identification design rationale — DCS envelope recognition, name/version tokenisation formats, SPARK Silver boundary, multiplexer passthrough strategy
- **Tech Spec DA1** (`docs/tech-specs/da1-response-parsing.md`): DA1 Primary Device Attributes design rationale — capability enumeration design, VT conformance level mapping, timeout-only read loop, SPARK Silver boundary
- **ADR-0017** (`docs/adr/0017-da1-timeout-only-read-loop.md`): Rationale for the timeout-only read loop in DA1 queries (no sentinel appended)
- **Tech Spec DECRPM** (`docs/tech-specs/decrpm.md`): DECRPM DEC Private Mode Report design rationale — Mode_Status enumeration design, sentinel vs. timeout strategy, batch query pattern, SPARK Silver boundary
- **ADR-0018** (`docs/adr/0018-platform-dispatch-via-source-dirs.md`): Rationale for GPR `Source_Dirs` platform dispatch over `pragma Import` or preprocessing
- **ADR-0019** (`docs/adr/0019-win32ada-as-ffi-layer.md`): Rationale for using the win32ada Alire crate as the Win32 FFI layer
- **Tech Spec WIN32** (`docs/tech-specs/windows-console.md`): Windows Console API integration design rationale — TTY detection, dimensions, color level, VT processing enablement
- **Tech Spec KITTY-KB** (`docs/tech-specs/kitty-keyboard.md`): Kitty Keyboard Protocol detection design rationale — cascade strategy, DA1 sentinel reuse, SPARK Silver boundary, platform dispatch for Win32 gate
- **ADR-0021** (`docs/adr/0021-defer-keyboard-capability-integration.md`): Rationale for deferring `Keyboard_Capability` integration into `Terminal_Capabilities`, and the forward-compatible migration path
- **Tech Spec MOUSE** (`docs/tech-specs/mouse-protocol.md`): Mouse protocol detection design rationale — batched DECRPM probe, encoding cascade, GPM heuristic, Win32 gate, SPARK Silver boundary
- **ADR-0022** (`docs/adr/0022-batched-single-sentinel-decrpm-mouse-probe.md`): Rationale for issuing all six DECRPM queries as a single batched session with one DA1 sentinel
- **ADR-0023** (`docs/adr/0023-mouse-encoding-cascade-order.md`): Rationale for the SGR_Pixels > SGR > URXVT > X10 > None cascade order
- **ADR-0024** (`docs/adr/0024-gpm-detection-heuristic.md`): Rationale for the `TERM=linux` + `/dev/gpmctl` GPM detection heuristic
- **ADR-0025** (`docs/adr/0025-mouse-capability-record-shape.md`): Rationale for the `Mouse_Capabilities` record field layout and implicit invariants
- **ADR-0026** (`docs/adr/0026-defer-mouse-capability-integration.md`): Rationale for deferring `Mouse_Capabilities` integration into `Terminal_Capabilities`, and the forward-compatible migration path
- **Tech Spec SIXEL** (`docs/tech-specs/sixel-graphics.md`): Sixel / Kitty Graphics detection design rationale — DA1 Ps=4 probe, APC active probe, XTVERSION name fallback, env-var heuristics, independent session strategy, SPARK boundary
- **ADR-0027** (`docs/adr/0027-da1-reuse-vs-fresh-probe.md`): Rationale for reusing `Termicap.DA1.IO.Detect_DA1` for the Sixel DA1 probe rather than issuing a fresh low-level probe from `Termicap.Graphics.IO`
- **ADR-0028** (`docs/adr/0028-graphics-independent-probe-sessions.md`): Rationale for using two independent probe sessions (DA1 + APC) rather than a batched single-sentinel approach
- **ADR-0029** (`docs/adr/0029-graphics-package-naming.md`): Rationale for the `Termicap.Graphics` / `Termicap.Graphics.IO` package naming and the deferred integration strategy
- **Tech Spec TERMINFO** (`docs/tech-specs/terminfo.md`): Terminfo database parsing design rationale — binary format variants, ghost predicate SPARK strategy, search-path resolution order, path construction algorithm, truecolor flag extraction
- **Tech Spec OSC52** (`docs/tech-specs/osc52-clipboard.md`): OSC 52 Clipboard Detection design rationale — three-phase cascade, DA1 Ps=52 extension, active read-back probe, env-var heuristics, multiplexer passthrough, independent session strategy, SPARK boundary
- **Requirements** (`docs/requirements/`): FUNC-ENV-001 through FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015, FUNC-DIM-001 through FUNC-DIM-008, FUNC-UNI-001 through FUNC-UNI-008, FUNC-TID-001 through FUNC-TID-012, FUNC-DSP-001 through FUNC-DSP-012, FUNC-SWC-001 through FUNC-SWC-011, FUNC-OVR-001 through FUNC-OVR-014, FUNC-CAP-001 through FUNC-CAP-014, FUNC-OSC-001 through FUNC-OSC-015, FUNC-DKL-001 through FUNC-DKL-007, FUNC-RPM-001 through FUNC-RPM-017, FUNC-KKB-001 through FUNC-KKB-019, FUNC-MSE-001 through FUNC-MSE-018, FUNC-SXL-001 through FUNC-SXL-019
