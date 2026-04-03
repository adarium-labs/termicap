# arc42 §5: Building Blocks

Static structure of the Termicap library — packages, SPARK boundary layers, and their responsibilities.

## Level 1: Package Overview

```
Termicap                          (root namespace — no types or subprograms)
├── Termicap.Environment          [SPARK Silver] — environment snapshot type, query/builder API
│   └── Termicap.Environment.Capture  [SPARK_Mode => Off] — sole OS FFI boundary
├── Termicap.TTY                  [spec: SPARK, body: SPARK_Mode => Off] — TTY detection
├── Termicap.Color                [SPARK Silver] — color level detection (11-step cascade)
├── Termicap.Dimensions           [spec: SPARK, body: SPARK_Mode => Off] — terminal size detection
├── Termicap.Unicode              [SPARK Silver] — Unicode support level detection (5-step cascade)
└── Termicap.Terminal_Id          [spec: SPARK, body: SPARK_Mode => Off] — terminal identity detection (8-step cascade)
```

`Termicap.Color`, `Termicap.Dimensions`, `Termicap.Unicode`, and `Termicap.Terminal_Id` are detection packages that depend on `Termicap.Environment`. `Termicap.Color` and `Termicap.Dimensions` receive TTY status as a plain `Boolean` parameter — they do **not** depend on `Termicap.TTY` directly. `Termicap.Unicode` and `Termicap.Terminal_Id` require no TTY parameter at all: Unicode capability is a property of the terminal emulator and locale configuration, and terminal identity is determined entirely from environment variable strings. `Termicap.Dimensions` additionally relies on the C wrapper `termicap_ioctl.c` for the ioctl FFI call in its body. The root package remains a namespace-only package.

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
| `Is_TTY` | Function | Returns `True` if the specified stream is connected to an interactive terminal. Returns `False` on error, never raises. | FUNC-TTY-002, FUNC-TTY-003, FUNC-TTY-004 |
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

`Termicap.TTY` has **no dependency** on `Termicap.Environment`. They are independent foundational building blocks. Downstream detection packages call `Is_TTY` once from an Ada-only region and pass the result as a plain `Boolean` parameter into SPARK-provable detection functions.

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

### `Termicap.Color`

**Responsibility:** Determines the color output capability of a terminal from an immutable environment snapshot and a TTY status flag. Performs no OS calls and reads no global state.

The detection algorithm is a single pure function implementing an 11-step priority cascade. All logic consists of enum comparisons and string matching via the `Termicap.Environment` API; there is no FFI. The package is fully SPARK Silver provable.

| Property | Value |
|----------|-------|
| Files | `src/termicap-color.ads`, `src/termicap-color.adb` |
| SPARK_Mode | On (spec and body) |
| Dependencies | `Termicap.Environment` |

#### Key Types

| Type | Description |
|------|-------------|
| `Color_Level` | Ordered four-value enumeration: `None < Basic_16 < Extended_256 < True_Color`. Supports `Color_Level'Max` for floor operations throughout the cascade. |

#### Public Operations

| Subprogram | Kind | SPARK Contract | Requirements |
|-----------|------|---------------|--------------|
| `Detect_Color_Level` | Function | `Global => null` | FUNC-CLR-002, FUNC-CLR-014, FUNC-CLR-015 |

#### Detection Cascade

`Detect_Color_Level` implements an 11-step priority cascade (FUNC-CLR-015):

| Step | Check | Effect |
|------|-------|--------|
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

`Termicap.Color` depends on `Termicap.Environment` (for `Contains`, `Value`, and `Equal_Case_Insensitive`) and has **no dependency** on `Termicap.TTY`. TTY status enters as a plain `Boolean` parameter, keeping the POSIX FFI call outside the SPARK verification perimeter.

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
│                          ▲                          │
│   Termicap.Color (spec + body)                      │
│   ┌─────────────────────────────────────────────┐  │
│   │  Color_Level type                           │  │
│   │  Detect_Color_Level (Env, Is_TTY : Boolean) │  │
│   │  Global => null — 11-step cascade           │  │
│   └─────────────────────────────────────────────┘  │
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
│                                                     │
│   Termicap.TTY (spec only)                          │
│   ┌─────────────────────────────────────────────┐  │
│   │  Stream_Kind, TTY_Status types              │  │
│   │  Is_TTY, Query_All signatures               │  │
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
└─────────────────────────────────────────────────────┘
```

The SPARK boundary is deliberately narrow: `Capture_Current`, the `Termicap.TTY` body, the `Termicap.Dimensions` body, and the `Termicap.Terminal_Id` body are the only points where non-provable code executes. Once a snapshot is produced and TTY status is captured as a `Boolean`, all subsequent detection operations — including `Termicap.Color`, `Termicap.Unicode`, and the spec contracts on `Get_Size` and `Detect_Terminal_Identity` — stay within the provable zone. `Termicap.Unicode` is the only detection package where both spec and body carry `SPARK_Mode => On`. `Termicap.Unicode` and `Termicap.Terminal_Id` are the two detection functions callable without a TTY status parameter.

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
- **Requirements** (`docs/requirements/`): FUNC-ENV-001 through FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015, FUNC-DIM-001 through FUNC-DIM-008, FUNC-UNI-001 through FUNC-UNI-008, FUNC-TID-001 through FUNC-TID-012
