# F6: Terminal Identification (Passive)

**Feature:** Terminal Identification (Passive)
**Requirements:** FUNC-TID-001 through FUNC-TID-012
**Status:** Approved
**Date:** 2026-04-03

---

## 1. Overview

Terminal identification determines which terminal emulator or multiplexer is hosting the current session by inspecting environment variables from an immutable `Termicap.Environment` snapshot. The result is a structured `Terminal_Identity` record containing a classified `Terminal_Kind` enumeration value, the raw `TERM_PROGRAM` and `TERM_PROGRAM_VERSION` strings, the raw `TERM` value, and a derived `Is_Multiplexer` flag.

This feature sits alongside `Termicap.Color` and `Termicap.Unicode` as a peer detection module. Its output is designed to feed into downstream modules as an authoritative, pre-parsed source for terminal-specific heuristics (FUNC-TID-009), eliminating redundant `TERM_PROGRAM` parsing in color and Unicode detection.

**SPARK level target: Silver.** The function is pure string pattern-matching over an immutable snapshot -- no OS calls, no global state, no dynamic allocation, no unbounded loops. This is the same profile that makes `Termicap.Color` and `Termicap.Unicode` fully SPARK Silver provable. The only design tension is the requirements' use of `Ada.Strings.Unbounded` for string fields; this is resolved in Section 6.

---

## 2. Framework Survey

### 2.1 How reference implementations handle terminal identification

**notcurses (C)** is the most comprehensive reference, fingerprinting 20+ terminal types. It uses a multi-layer approach:

| Priority | Signal | Terminals identified |
|----------|--------|---------------------|
| 1 | `TERM_PROGRAM` | iTerm2, Apple_Terminal, vscode, WezTerm, mintty |
| 2 | `TERM` exact match | xterm-kitty, xterm-ghostty, alacritty, wezterm, foot, linux |
| 3 | `TERM` prefix | xterm-*, screen-*, tmux-*, rxvt-* |
| 4 | `TERMINAL_EMULATOR` | JetBrains-JediTerm |
| 5 | `WT_SESSION` presence | Windows Terminal |
| 6 | Active queries (DA1/DA2/XTVERSION) | Fine-grained identification beyond env vars |

**termenv (Go)** uses `TERM_PROGRAM` for color-gating decisions (iTerm.app, tmux) but does not expose a terminal-kind enumeration. Its `colorTerm` detection reads `COLORTERM`, `TERM_PROGRAM`, and `TERM` in that order.

**is-unicode-supported (JavaScript)** reads `TERM_PROGRAM`, `TERMINAL_EMULATOR`, `WT_SESSION`, and `TERM` for Windows-specific Unicode heuristics.

**supports-color (Rust/JavaScript)** reads `TERM_PROGRAM` for iTerm/Apple_Terminal/vscode color level decisions, and checks `TERM` prefixes for xterm/screen/rxvt detection.

### 2.2 Environment variables checked across implementations

| Variable | Checked by | Identifies |
|----------|-----------|------------|
| `TERM_PROGRAM` | notcurses, termenv, supports-color, is-unicode-supported | iTerm2, Apple_Terminal, vscode, WezTerm, mintty, WarpTerminal |
| `TERM` | All libraries | xterm-kitty, xterm-ghostty, alacritty, foot, linux, dumb, screen-*, tmux-*, rxvt-* |
| `TERMINAL_EMULATOR` | is-unicode-supported | JetBrains-JediTerm |
| `WT_SESSION` | is-unicode-supported, termenv (indirect) | Windows Terminal |
| `KONSOLE_VERSION` | notcurses, tcell | KDE Konsole |
| `VTE_VERSION` | notcurses, tcell | VTE-based (GNOME Terminal, Tilix, XFCE Terminal) |
| `TMUX` | notcurses, termenv | tmux multiplexer |
| `TERM_PROGRAM_VERSION` | supports-color (iTerm v3+ gating) | Version-specific capability |

### 2.3 What Termicap adopts vs. diverges from

**Adopted:**
- The env-var priority order (`TERM_PROGRAM` > `TERMINAL_EMULATOR` > presence checks > `TERM`) matches the consensus across notcurses, supports-color, and is-unicode-supported.
- Case-insensitive comparison for all value matching.
- `TERM` prefix matching for xterm, screen, tmux, rxvt families.
- Treating Screen and Tmux as multiplexers with a derived flag.

**Diverged:**
- Termicap does not perform active terminal queries (DA1, DA2, XTVERSION). This is deliberate -- the feature is named "Passive" and restricts itself to environment variable inspection. Active queries would require TTY I/O and would break SPARK Silver provability.
- Termicap does not parse version strings into structured fields (FUNC-TID-008). Reference implementations that do version-gating (e.g., supports-color for iTerm v3+) perform it in the color detection module, not in terminal identification.
- Termicap stores raw strings for `Program_Version` rather than parsed semver, because version formats are heterogeneous across terminals.

---

## 3. Ada Package Design

### 3.1 Package name and file names

- **Package:** `Termicap.Terminal_Id`
- **Spec file:** `src/termicap-terminal_id.ads`
- **Body file:** `src/termicap-terminal_id.adb`

The name `Terminal_Id` is chosen over `Terminal_Identity` or `Terminal_Identification` for conciseness while remaining unambiguous. It follows the project convention of short, descriptive child package names (cf. `Termicap.Color`, `Termicap.Unicode`, `Termicap.TTY`).

### 3.2 Public types

#### Terminal_Kind enumeration (FUNC-TID-001)

```ada
type Terminal_Kind is
   (Unknown,
    Alacritty,
    Apple_Terminal,
    Dumb,
    Foot,
    Ghostty,
    ITerm2,
    JediTerm,
    Kitty,
    Konsole,
    Linux_Console,
    Mintty,
    Rxvt,
    Screen,
    Tmux,
    VSCode,
    VTE,
    WarpTerminal,
    WezTerm,
    Windows_Terminal,
    Xterm);
```

The values are listed in alphabetical order (with `Unknown` first) for readability. The enumeration has exactly 20 values as specified in FUNC-TID-001. Callers are documented to include an `others` branch in exhaustive case analysis to permit future extension.

#### Multiplexer_Kind subtype (FUNC-TID-011)

```ada
subtype Multiplexer_Kind is Terminal_Kind
   with Static_Predicate => Multiplexer_Kind in Tmux | Screen;
```

This centralises the multiplexer set in a single declaration. Adding a future multiplexer (e.g., Zellij) requires only updating this predicate and the `Is_Multiplexer` postcondition.

#### Terminal_Identity record (FUNC-TID-002)

```ada
type Terminal_Identity is record
   Kind            : Terminal_Kind;
   Program_Name    : Ada.Strings.Unbounded.Unbounded_String;
   Program_Version : Ada.Strings.Unbounded.Unbounded_String;
   Term_Value      : Ada.Strings.Unbounded.Unbounded_String;
   Is_Multiplexer  : Boolean;
end record;
```

See Section 6 for the full SPARK string-handling strategy and why `Unbounded_String` is used despite its SPARK incompatibility.

### 3.3 Public function (FUNC-TID-003)

```ada
function Detect_Terminal_Identity
   (Env : Termicap.Environment.Environment) return Terminal_Identity
with Global => null;
```

No `Is_TTY` parameter is required -- terminal identity is a property of the terminal emulator, not of stream connectivity. This matches `Termicap.Unicode.Detect_Unicode_Level`, which also takes only `Env`.

### 3.4 SPARK contracts

The spec carries `SPARK_Mode => On`. The body carries `SPARK_Mode => Off` because `Ada.Strings.Unbounded` operations in the record construction are not SPARK-compatible (see Section 6 and ADR-0008).

The function carries two postconditions specified by the requirements:

**FUNC-TID-005 (Unknown fallback):**

```ada
Post =>
  (if not Env.Contains ("TERM_PROGRAM") and then
      not Env.Contains ("TERMINAL_EMULATOR") and then
      not Env.Contains ("WT_SESSION") and then
      not Env.Contains ("KONSOLE_VERSION") and then
      not Env.Contains ("VTE_VERSION") and then
      not Env.Contains ("TMUX") and then
      not Env.Contains ("TERM")
   then
      Detect_Terminal_Identity'Result.Kind = Unknown and then
      not Detect_Terminal_Identity'Result.Is_Multiplexer)
```

**FUNC-TID-006 (Is_Multiplexer derivation):**

```ada
Post =>
  (Detect_Terminal_Identity'Result.Is_Multiplexer =
     (Detect_Terminal_Identity'Result.Kind in Multiplexer_Kind))
```

Both postconditions are combined in a single `Post` aspect using `and then`.

Note: Because the body has `SPARK_Mode => Off`, these postconditions serve as documentation and as runtime checks (when assertions are enabled) rather than as GNATprove proof obligations. The SPARK contract on the spec establishes the interface contract for callers in the SPARK Silver zone.

---

## 4. Detection Algorithm Design

### 4.1 Eight-step cascade (FUNC-TID-004)

The function reads seven environment variables in strict priority order:

```
Step 1: TERM_PROGRAM (value match)
  "iTerm.app"       -> ITerm2
  "Apple_Terminal"   -> Apple_Terminal
  "vscode"           -> VSCode
  "WezTerm"          -> WezTerm
  "mintty"           -> Mintty

Step 2: TERMINAL_EMULATOR (value match)
  "JetBrains-JediTerm" -> JediTerm

Step 3: WT_SESSION (presence)
  present -> Windows_Terminal

Step 4: KONSOLE_VERSION (presence)
  present -> Konsole

Step 5: VTE_VERSION (presence)
  present -> VTE

Step 6: TMUX (presence)
  present -> Tmux

Step 7: TERM (value/prefix match, most-specific-first)
  "dumb"               -> Dumb
  "linux"              -> Linux_Console
  starts with "tmux"   -> Tmux
  starts with "screen" -> Screen
  "xterm-kitty"        -> Kitty
  "xterm-ghostty"      -> Ghostty
  "alacritty"          -> Alacritty
  "wezterm"            -> WezTerm
  starts with "rxvt"   -> Rxvt
  "foot"               -> Foot
  "foot-extra"         -> Foot
  starts with "xterm"  -> Xterm

Step 8: Default
  -> Unknown
```

### 4.2 Case-insensitive comparison (FUNC-TID-010)

All value comparisons use `Termicap.Environment.Equal_Case_Insensitive`, which is already provided by the `Termicap.Environment` package and used by both `Termicap.Color` and `Termicap.Unicode`.

For prefix matching (starts-with checks), the function uses a body-local `Starts_With` helper identical to the one in `Termicap.Color`. This helper performs character-by-character case-insensitive comparison using a `To_Lower_Char` expression function.

### 4.3 Prefix matching design

The `Starts_With` helper is reused from the pattern established in `Termicap.Color.Starts_With`:

```ada
function Starts_With (Source : String; Prefix : String) return Boolean
   with Global => null;
```

It is used for `TERM` prefix checks: `"xterm"`, `"screen"`, `"tmux"`, `"rxvt"`. Within the TERM step, more-specific matches (exact `"xterm-kitty"`, `"xterm-ghostty"`) are checked before the generic `"xterm"` prefix to prevent misclassification.

### 4.4 Is_Multiplexer derivation (FUNC-TID-006)

The `Is_Multiplexer` field is set after `Kind` is determined, using the `Multiplexer_Kind` subtype:

```ada
Result.Is_Multiplexer := Result.Kind in Multiplexer_Kind;
```

This is a single membership test that evaluates to `True` for `Tmux` and `Screen`, and `False` for all other values. By using the named subtype, adding a future multiplexer requires updating only the `Static_Predicate` declaration.

### 4.5 Helper subprograms

All helpers are body-local (private to the package body):

| Helper | Purpose | Pattern source |
|--------|---------|----------------|
| `To_Lower_Char` | ASCII case folding | `Termicap.Color` body |
| `Starts_With` | Case-insensitive prefix check | `Termicap.Color` body |
| `Classify_Term_Program` | Classifies TERM_PROGRAM into a body-local token enum | `Termicap.Color.Classify_Term_Program` pattern |
| `Classify_Term` | Classifies TERM value into Terminal_Kind via the step-7 sub-cascade | New, specific to this module |

The `Classify_Term_Program` helper returns a body-local enumeration type:

```ada
type Term_Program_Token is
   (TP_ITerm, TP_Apple_Terminal, TP_VSCode, TP_WezTerm, TP_Mintty, TP_Other);
```

The `Classify_Term` helper encapsulates the step-7 logic (exact matches, then prefix matches, then `Unknown` default), keeping the main function body concise.

### 4.6 String field population

Regardless of which step determined `Kind`, the three string fields are always populated:

```ada
Result.Program_Name    := To_Unbounded_String (Value (Env, "TERM_PROGRAM"));
Result.Program_Version := To_Unbounded_String (Value (Env, "TERM_PROGRAM_VERSION"));
Result.Term_Value      := To_Unbounded_String (Value (Env, "TERM"));
```

`Value` returns `""` for absent variables (per `Termicap.Environment` FUNC-ENV-003), so the empty-string default is handled implicitly.

---

## 5. SPARK Proof Strategy

### 5.1 Why Silver is achievable for the spec

The `Detect_Terminal_Identity` function has the same purity profile as `Detect_Color_Level` and `Detect_Unicode_Level`:

- **No loops:** The detection cascade is a fixed-length if/elsif chain. The `Starts_With` helper has bounded loops (iterating over a known-length prefix), but these are in the body, which has `SPARK_Mode => Off`.
- **No allocation:** The function returns a stack-allocated record.
- **No FFI:** No `pragma Import`, no C bindings.
- **No global state:** `Global => null` is verifiable on the spec.

### 5.2 Postconditions

Two postconditions are expressed as `Post =>` contracts on the spec:

1. **Unknown fallback** (FUNC-TID-005): When all seven env vars are absent, result has `Kind = Unknown` and `Is_Multiplexer = False`.
2. **Is_Multiplexer derivation** (FUNC-TID-006): `Is_Multiplexer` equals the membership test `Kind in Multiplexer_Kind`.

These postconditions are structurally simple and do not require ghost variables, loop invariants, or lemmas.

### 5.3 Spec vs. body SPARK_Mode boundary

The spec has `SPARK_Mode => On`. The body has `SPARK_Mode => Off`. This is the same boundary pattern used by `Termicap.TTY` and `Termicap.Dimensions`, though for a different reason: those packages have `SPARK_Mode => Off` in the body due to FFI calls, whereas `Termicap.Terminal_Id` has it due to `Ada.Strings.Unbounded` usage. See Section 6 for the detailed rationale.

### 5.4 Known proof scope

With the body in Ada mode, GNATprove verifies:
- The `Global => null` contract on the spec (no global reads/writes in the interface).
- Type consistency of the postcondition expressions against the declared types.
- That callers of `Detect_Terminal_Identity` in SPARK packages can rely on the postconditions.

GNATprove does **not** verify the body logic. This is acceptable because:
- The body is pure string-matching with no possibility of runtime errors (no division, no unchecked conversion, no access types).
- The postconditions are verifiable by unit tests (FUNC-TID-012).

---

## 6. String Handling in SPARK

### 6.1 The problem

`Ada.Strings.Unbounded.Unbounded_String` is not SPARK-compatible. The SPARK language subset excludes controlled types (which `Unbounded_String` is) and the hidden heap allocation they perform. Yet FUNC-TID-002 specifies `Unbounded_String` for the `Program_Name`, `Program_Version`, and `Term_Value` fields because environment variable values have no compile-time length bound.

### 6.2 Options considered

| Option | Description | SPARK coverage | Trade-off |
|--------|-------------|---------------|-----------|
| A | Bounded strings (`String (1 .. N)`) for all fields | Spec + body fully SPARK | Must pick a maximum length; truncation risk; wastes stack space for short values |
| B | `Unbounded_String` with spec SPARK_Mode On, body SPARK_Mode Off | Spec contracts provable; body logic in Ada | Matches TTY/Dimensions pattern; postconditions documented but not machine-proved in body |
| C | SPARK formal containers (`SPARK.Containers.Formal.Unbounded_Vectors` of `Character`) | Spec + body SPARK | Over-engineered; awkward API; no precedent in project |

### 6.3 Decision: Option B (ADR-0008)

Option B is chosen for the following reasons:

1. **Consistency with existing modules.** `Termicap.TTY` and `Termicap.Dimensions` already use the spec-On/body-Off pattern. While their reason is FFI rather than string types, the boundary pattern is identical and familiar to contributors.

2. **Requirement compliance.** FUNC-TID-002 explicitly specifies `Ada.Strings.Unbounded.Unbounded_String`. Option A would deviate from the approved requirement.

3. **No truncation risk.** Bounded strings require choosing a maximum length. `TERM_PROGRAM_VERSION` values like `"20231203-110809-5046fc22"` (25 characters, WezTerm) are already long; future terminals may have longer version strings. Any truncation would be a silent data loss bug.

4. **Spec-level SPARK contracts remain valuable.** The `Global => null` and postcondition contracts on the spec are verified by GNATprove for all callers, even though the body is not proved. This is the Silver-level guarantee: the interface is machine-verified, the implementation is tested.

5. **Body purity is testable.** The body contains no FFI, no global state, and no side effects. The postconditions (FUNC-TID-005, FUNC-TID-006) are independently verifiable by the test suite (FUNC-TID-012), compensating for the lack of body-level SPARK proof.

See ADR-0008 for the full decision record.

---

## 7. Integration with Downstream Modules (FUNC-TID-009)

### 7.1 Proposed mechanism: overloaded function

The cleanest integration is to add an overloaded variant of `Detect_Color_Level` and `Detect_Unicode_Level` that accepts a `Terminal_Identity` value alongside the `Environment` snapshot:

```ada
--  In Termicap.Color (future addition):
function Detect_Color_Level
   (Env    : Termicap.Environment.Environment;
    Is_TTY : Boolean;
    TID    : Termicap.Terminal_Id.Terminal_Identity) return Color_Level
with Global => null;

--  In Termicap.Unicode (future addition):
function Detect_Unicode_Level
   (Env : Termicap.Environment.Environment;
    TID : Termicap.Terminal_Id.Terminal_Identity) return Unicode_Level
with Global => null;
```

The overloaded variants use `TID.Kind` for terminal-specific decisions instead of re-reading `TERM_PROGRAM` from `Env`. The existing single-parameter variants remain for backward compatibility and standalone use.

### 7.2 Which downstream modules benefit

**Termicap.Color** benefits the most:
- Step 8 (`Detect_Term_Program`) classifies `TERM_PROGRAM` into iTerm/Apple_Terminal/vscode. With a `Terminal_Identity`, this classification is already done -- the function can switch on `TID.Kind` directly.
- Step 7 (`Detect_Colorterm`) checks for the `screen` multiplexer via `TERM` prefix. With `TID.Is_Multiplexer`, this becomes a direct Boolean check.

**Termicap.Unicode** benefits moderately:
- Step 4 (Windows heuristics) checks `WT_SESSION`, `TERM_PROGRAM=vscode`, and `TERMINAL_EMULATOR`. These are all subsumed by `TID.Kind` values (`Windows_Terminal`, `VSCode`, `JediTerm`).

### 7.3 Dependency direction

`Termicap.Terminal_Id` depends on `Termicap.Environment` (same as Color and Unicode). The overloaded downstream functions would add a dependency from `Termicap.Color` / `Termicap.Unicode` to `Termicap.Terminal_Id`. This is a one-way dependency and does not create a cycle.

### 7.4 Deferred to Phase 3

The actual overloaded functions are not implemented in Phase 2 (Terminal Identification). They are deferred to Phase 3 (Capability Record Assembly), where the full detection pipeline is composed. This tech spec documents the intended integration shape so that the `Terminal_Identity` type and `Detect_Terminal_Identity` function are designed with downstream consumption in mind.

---

## 8. Test Strategy (FUNC-TID-012)

### 8.1 Test structure

Tests follow the established pattern: construct an `Environment` via `EMPTY_ENVIRONMENT` + `Insert`, call `Detect_Terminal_Identity`, and assert the expected result. No OS environment is read or modified.

### 8.2 Required test cases

**One test per Terminal_Kind value (20 tests):**

| Test | Environment setup | Expected Kind |
|------|-------------------|---------------|
| Unknown | Empty environment | Unknown |
| Alacritty | TERM=alacritty | Alacritty |
| Apple_Terminal | TERM_PROGRAM=Apple_Terminal | Apple_Terminal |
| Dumb | TERM=dumb | Dumb |
| Foot (foot) | TERM=foot | Foot |
| Foot (foot-extra) | TERM=foot-extra | Foot |
| Ghostty | TERM=xterm-ghostty | Ghostty |
| ITerm2 | TERM_PROGRAM=iTerm.app | ITerm2 |
| JediTerm | TERMINAL_EMULATOR=JetBrains-JediTerm | JediTerm |
| Kitty | TERM=xterm-kitty | Kitty |
| Konsole | KONSOLE_VERSION=21.08 | Konsole |
| Linux_Console | TERM=linux | Linux_Console |
| Mintty | TERM_PROGRAM=mintty | Mintty |
| Rxvt | TERM=rxvt-unicode-256color | Rxvt |
| Screen | TERM=screen-256color | Screen |
| Tmux (via TMUX) | TMUX=/tmp/tmux-1000/default,12345,0 | Tmux |
| Tmux (via TERM) | TERM=tmux-256color | Tmux |
| VSCode | TERM_PROGRAM=vscode | VSCode |
| VTE | VTE_VERSION=6800 | VTE |
| WarpTerminal | TERM_PROGRAM=WarpTerminal | WarpTerminal
| WezTerm (TERM_PROGRAM) | TERM_PROGRAM=WezTerm | WezTerm |
| WezTerm (TERM) | TERM=wezterm | WezTerm |
| Windows_Terminal | WT_SESSION=some-guid | Windows_Terminal |
| Xterm | TERM=xterm-256color | Xterm |

**All-absent Unknown test (FUNC-TID-005):**

Verify that an empty `Environment` yields `Kind = Unknown`, `Is_Multiplexer = False`, and all string fields are empty.

**Shadow-rule tests (priority verification):**

| Test | Higher-priority signal | Lower-priority signal | Expected Kind |
|------|----------------------|----------------------|---------------|
| TERM_PROGRAM shadows TERM | TERM_PROGRAM=iTerm.app | TERM=xterm | ITerm2 |
| TERMINAL_EMULATOR shadows TERM | TERMINAL_EMULATOR=JetBrains-JediTerm | TERM=xterm | JediTerm |
| WT_SESSION shadows TERM | WT_SESSION=guid | TERM=xterm | Windows_Terminal |
| KONSOLE_VERSION shadows TERM | KONSOLE_VERSION=21 | TERM=xterm | Konsole |
| VTE_VERSION shadows TERM | VTE_VERSION=6800 | TERM=xterm | VTE |
| TMUX shadows TERM=xterm | TMUX=path | TERM=xterm | Tmux |
| TERM xterm-kitty shadows generic xterm | -- | TERM=xterm-kitty | Kitty |

**Is_Multiplexer tests:**

- `Kind = Tmux` yields `Is_Multiplexer = True`
- `Kind = Screen` yields `Is_Multiplexer = True`
- All other Kind values yield `Is_Multiplexer = False`

**Case-insensitivity tests (FUNC-TID-010):**

- `TERM_PROGRAM=ITERM.APP` yields `Kind = ITerm2`
- `TERM=XTERM-KITTY` yields `Kind = Kitty`
- `TERM=Alacritty` yields `Kind = Alacritty`

**String field population tests:**

- Verify `Program_Name` = raw `TERM_PROGRAM` value
- Verify `Program_Version` = raw `TERM_PROGRAM_VERSION` value
- Verify `Term_Value` = raw `TERM` value
- Verify absent variables yield empty strings

---

## 9. Open Questions / ADR Triggers

### ADR-0008: String representation strategy for Terminal_Identity in SPARK (written)

The decision to use `Unbounded_String` with a spec-On/body-Off SPARK boundary is non-trivial and affects the SPARK proof coverage of the module. See Section 6 and `docs/adr/0008-terminal-id-string-representation-spark-boundary.md`.

### Future considerations (not ADR-worthy yet)

- **Shared string helpers.** `To_Lower_Char` and `Starts_With` are duplicated between `Termicap.Color` and `Termicap.Terminal_Id`. A future refactoring could extract them into a `Termicap.Internal.Strings` package. This is deferred because introducing a shared internal package adds a build dependency and the duplication is small (< 30 lines total).

- **TERM_PROGRAM_VERSION parsing.** FUNC-TID-008 explicitly defers version parsing from v1. If a future version adds structured version comparison, it would likely be a separate utility package rather than a change to `Terminal_Identity`.

- **Active terminal queries.** Layers 5-10 of the identification taxonomy (XTVERSION, DA1, DA2, DA3, XTGETTCAP, KDGETMODE) are out of scope for the passive feature. A future `Termicap.Terminal_Id.Active` package could perform these queries via TTY I/O, with `SPARK_Mode => Off`.

---

## 10. Related Documents

- **Requirements:** `docs/requirements/terminal-identification.sdoc` (FUNC-TID-001 through FUNC-TID-012)
- **ADR-0008:** `docs/adr/0008-terminal-id-string-representation-spark-boundary.md`
- **Architecture:** `docs/architecture/03-building-blocks.md` (to be updated after implementation)
- **Architecture:** `docs/architecture/04-runtime-view.md` (to be updated after implementation)
- **Global Synthesis:** `reference-frameworks/analysis/00-GLOBAL-SYNTHESIS.md` (Section 2.13)
- **Existing detection modules:** `src/termicap-color.ads`, `src/termicap-unicode.ads` (pattern reference)
