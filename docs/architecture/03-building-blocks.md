# arc42 §5: Building Blocks

Static structure of the Termicap library — packages, SPARK boundary layers, and their responsibilities.

## Level 1: Package Overview

```
Termicap                          (root namespace — no types or subprograms)
├── Termicap.Environment          [SPARK Silver] — environment snapshot type, query/builder API
│   └── Termicap.Environment.Capture  [SPARK_Mode => Off] — sole OS FFI boundary
├── Termicap.TTY                  [spec: SPARK, body: SPARK_Mode => Off] — TTY detection
└── Termicap.Color                [SPARK Silver] — color level detection (11-step cascade)
```

`Termicap.Color` is the first detection package. It depends on `Termicap.Environment` and does **not** depend on `Termicap.TTY` — TTY status is passed as a plain `Boolean` parameter. The root package remains a namespace-only package.

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
└─────────────────────────────────────────────────────┘
```

The SPARK boundary is deliberately narrow: `Capture_Current` and the `Termicap.TTY` body are the only points where OS calls occur. Once a snapshot is produced and TTY status is captured as a `Boolean`, all subsequent detection operations — including `Termicap.Color` — stay within the provable zone.

## Related Documents

- **ADR-0001** (`docs/adr/0001-environment-snapshot-storage-strategy.md`): Container choice rationale for `Env_Maps`
- **ADR-0002** (`docs/adr/0002-multi-candidate-matching-spark-boundary.md`): `Value_Matches` / `String_Vector` design decision
- **ADR-0003** (`docs/adr/0003-tty-detection-package-structure.md`): TTY package structure and `TTY_Status` type decision
- **Tech Spec F1** (`docs/tech-specs/f1-environment-variable-abstraction.md`): Full design rationale for `Termicap.Environment`
- **Tech Spec F2** (`docs/tech-specs/f2-tty-detection.md`): TTY detection design rationale
- **Tech Spec F3** (`docs/tech-specs/f3-color-level-detection.md`): Color level detection design rationale
- **Requirements** (`docs/requirements/`): FUNC-ENV-001 through FUNC-ENV-008, FUNC-TTY-001 through FUNC-TTY-006, FUNC-CLR-001 through FUNC-CLR-015
