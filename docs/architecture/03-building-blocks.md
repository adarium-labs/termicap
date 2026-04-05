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
└── Termicap.Capabilities         [spec: SPARK, body: mixed] — aggregated capability record; Get (cached) and Detect (fresh) entry points
```

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
| Dependencies | `Termicap.Environment.Capture`, `Termicap.TTY`, `Termicap.Color`, `Termicap.Dimensions`, `Termicap.Unicode`, `Termicap.Terminal_Id` |

#### Key Types

| Type | Description |
|------|-------------|
| `Terminal_Capabilities` | Plain Ada record with eight fields: `TTY_Stdin : Boolean`, `TTY_Stdout : Boolean`, `TTY_Stderr : Boolean`, `Color : Termicap.Color.Color_Level`, `Size : Termicap.Dimensions.Terminal_Size`, `Unicode : Termicap.Unicode.Unicode_Level`, `Identity : Termicap.Terminal_Id.Terminal_Identity`, and `Downsampling_Available : Boolean`. Value semantics — assignment produces an independent copy with no aliasing. |

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

The sentinel-bounded query pattern (`Sentinel_Query`) writes the user query followed by the DA1 sentinel (`ESC [ c`) and accumulates response bytes until the DA1 response (`ESC [ ? … c`) is detected or the timeout expires. Pure parsing and detection logic is isolated in the SPARK Silver child package `Termicap.OSC.Parsing`.

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
└─────────────────────────────────────────────────────┘
```

The SPARK boundary is deliberately narrow: `Capture_Current`, the `Termicap.Override` body (protected object, `Set_Override`/`Get_Override` bodies, and `Scoped_Override.Initialize`/`Finalize`), the `Termicap.TTY` body, the `Termicap.Dimensions` body, the `Termicap.Terminal_Id` body, the entirety of `Termicap.Sigwinch`, the `Detect`/`Get` bodies of `Termicap.Capabilities`, and the entirety of `Termicap.OSC` are the only points where non-provable code executes. Once a snapshot is produced and TTY status is captured as a `Boolean`, all subsequent detection operations — including `Termicap.Color`, `Termicap.Unicode`, the spec contracts on `Get_Size` and `Detect_Terminal_Identity`, and the `Assemble` function of `Termicap.Capabilities` — stay within the provable zone. `Termicap.Downsampling` goes further: both its spec and its body carry `SPARK_Mode => On` with Gold-level provability — no FFI, no dynamic allocation, no unbounded loops. `Termicap.Override.Parse_Color_Flag` is also provable at Gold level (pure string comparison, no side effects). `Termicap.Unicode` and `Termicap.Downsampling` are the packages where both spec and body carry `SPARK_Mode => On`; `Termicap.Unicode` and `Termicap.Terminal_Id` are the two detection functions callable without a TTY status parameter. `Termicap.Sigwinch` and `Termicap.OSC` are the packages where both spec and body are wholly outside the SPARK zone: `Termicap.Sigwinch` due to its protected object, interrupt handler, and C FFI; `Termicap.OSC` due to `Limited_Controlled` and POSIX syscall FFI. `Termicap.OSC.Parsing` is the pure SPARK Silver complement to `Termicap.OSC`, containing only provable functions that operate on `Byte_Array` values with no side effects. `Termicap.Capabilities` occupies a hybrid position: its spec and the pure `Assemble` function are SPARK Silver, while the `Detect`/`Get` bodies and the protected cache object are compiled with `SPARK_Mode => Off`. The BG-COLOR subsystem follows the same SPARK split pattern: `Termicap.Color.BG_Query` (both spec and body) is fully SPARK Silver — pure parsing functions with `Global => null` and no FFI; `Termicap.Color.BG_Query.IO` and `Termicap.Color.Detection` are entirely `SPARK_Mode => Off` because they manage `Probe_Session` controlled types and perform terminal I/O. The DARK-LIGHT subsystem continues this layering: `Termicap.Color.Dark_Light` (both spec and body) is SPARK Gold — pure integer arithmetic with `Post` contracts and no I/O; `Termicap.Color.Dark_Light.Detect` is `SPARK_Mode => Off` because it calls `Detect_Background_Color`, which manages `Probe_Session` controlled types and performs terminal I/O.

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
- **Requirements** (`docs/requirements/`): FUNC-ENV-001 through FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015, FUNC-DIM-001 through FUNC-DIM-008, FUNC-UNI-001 through FUNC-UNI-008, FUNC-TID-001 through FUNC-TID-012, FUNC-DSP-001 through FUNC-DSP-012, FUNC-SWC-001 through FUNC-SWC-011, FUNC-OVR-001 through FUNC-OVR-014, FUNC-CAP-001 through FUNC-CAP-014, FUNC-OSC-001 through FUNC-OSC-015, FUNC-DKL-001 through FUNC-DKL-007
