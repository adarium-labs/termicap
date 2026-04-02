# API Reference: `Termicap.Color`

Package providing pure, SPARK-provable detection of terminal color capability from environment variable heuristics.

**File:** `src/termicap-color.ads`
**SPARK_Mode:** On (spec and body)
**License:** Apache-2.0

---

## Overview

`Termicap.Color` exposes a single pure function, `Detect_Color_Level`, that determines how many colors a terminal supports. It accepts an immutable `Termicap.Environment.Environment` snapshot and a `Boolean` TTY flag; it performs no OS calls and reads no global state. The `Global => null` contract is machine-verified by GNATprove.

The detection algorithm implements an 11-step priority cascade respecting the NO_COLOR, FORCE_COLOR, and CLICOLOR standards alongside terminal-specific heuristics. Steps that force color (overrides) are separated from steps that detect color (heuristics); the final result is always the maximum of the two.

---

## Types

### `Color_Level`

```ada
type Color_Level is (None, Basic_16, Extended_256, True_Color);
```

Ordered enumeration of terminal color capability levels. The ordering is significant: `None < Basic_16 < Extended_256 < True_Color`. `Color_Level'Max` is used throughout the detection cascade as a floor/ceiling operator.

| Value | Meaning |
|-------|---------|
| `None` | No color output; use plain text. |
| `Basic_16` | Standard ANSI 16-color palette (SGR 30–37, 40–47, 90–97). |
| `Extended_256` | 256-color palette (SGR 38;5;n / 48;5;n). |
| `True_Color` | 24-bit RGB ("truecolor") (SGR 38;2;r;g;b / 48;2;r;g;b). |

**Requirement:** FUNC-CLR-001

---

## Functions

### `Detect_Color_Level`

```ada
function Detect_Color_Level
   (Env    : Termicap.Environment.Environment;
    Is_TTY : Boolean) return Color_Level
   with Global => null;
```

Detect the color level supported by the terminal.

| Parameter | Mode | Description |
|-----------|------|-------------|
| `Env` | in | Immutable environment variable snapshot. Obtained via `Termicap.Environment.Capture.Capture_Current` or built programmatically with `Insert` for testing. |
| `Is_TTY` | in | Whether the target output stream is connected to an interactive terminal. Typically the result of `Termicap.TTY.Is_TTY (Stdout)`. |

**Returns:** The detected `Color_Level` based on the 11-step priority cascade below.

**SPARK contract:** `Global => null` — no hidden state; fully GNATprove-verifiable at Silver level.

**Requirements:** FUNC-CLR-002, FUNC-CLR-014, FUNC-CLR-015

---

## Detection Priority Order

The 11-step cascade is evaluated in strict order. Force-override steps (1–2) set a `Floor` that later heuristic steps can only raise. `NO_COLOR` and `TERM=dumb` are early-exit conditions. The final result is `Color_Level'Max (Floor, Heuristic)`.

| Priority | Step | Environment Variable(s) | Result |
|----------|------|-------------------------|--------|
| 1 | FORCE_COLOR override | `FORCE_COLOR` | `"0"` or `"false"` → return `None` immediately. `"3"` → floor `True_Color`. `"2"` → floor `Extended_256`. Any other value (including empty) → floor `Basic_16`. |
| 2 | CLICOLOR_FORCE override | `CLICOLOR_FORCE` | If present and not `"0"`, set floor to `Basic_16`. Skipped if step 1 set the floor. |
| 3 | NO_COLOR disable | `NO_COLOR` | If present (any value, including empty) and no force override is active, return `None`. Follows the [no-color.org](https://no-color.org) spec exactly. |
| 4 | Dumb terminal | `TERM` | If value is `"dumb"` (case-insensitive), return `Floor` (typically `None`). |
| 5 | CI environment | `GITHUB_ACTIONS`, `GITEA_ACTIONS`, `CIRCLECI`, `TRAVIS`, `APPVEYOR`, `GITLAB_CI`, `BUILDKITE`, `DRONE`, `CI` | GitHub Actions/Gitea/CircleCI → accumulate `True_Color`. Travis/AppVeyor/GitLab CI/Buildkite/Drone/generic `CI` → accumulate `Basic_16`. |
| 6 | TTY gate | *(Is_TTY parameter)* | If `Is_TTY` is `False` and no floor or heuristic has been set, return `None`. |
| 7 | COLORTERM | `COLORTERM`, `TERM`, `TERM_PROGRAM` | `"truecolor"` or `"24bit"` → `True_Color` (capped at `Extended_256` when `TERM` starts with `"screen"` and `TERM_PROGRAM` is not `"tmux"`). Any other non-empty value → `Basic_16`. |
| 8 | TERM_PROGRAM | `TERM_PROGRAM`, `TERM_PROGRAM_VERSION` | `"iTerm.app"` with version ≥ 3 → `True_Color`; `"iTerm.app"` otherwise → `Extended_256`. `"Apple_Terminal"` or `"vscode"` → `Extended_256`. |
| 9 | TERM patterns | `TERM` | Suffix `-256color` or `-256` → `Extended_256`. Substring `xterm`, `screen`, `vt100`, `vt220`, `rxvt`, `color`, `ansi`, `cygwin`, or `linux` → `Basic_16`. |
| 10 | CLICOLOR hint | `CLICOLOR` | If present and not `"0"`, raise heuristic to at least `Basic_16`. |
| 11 | Default | *(none)* | Return `Color_Level'Max (Floor, Heuristic)`. |

All string comparisons are case-insensitive. Presence checks use `Contains` to correctly distinguish an absent variable from one set to the empty string.

---

## Environment Variables Reference

| Variable | Standard / Source | Effect in Cascade |
|----------|-------------------|-------------------|
| `FORCE_COLOR` | npm ecosystem | Step 1: override floor; `0`/`false` disables color entirely |
| `CLICOLOR_FORCE` | BSD/macOS tradition | Step 2: override floor to Basic_16 (unless `"0"`) |
| `NO_COLOR` | [no-color.org](https://no-color.org) | Step 3: disable color (presence alone, any value) |
| `TERM` | POSIX | Steps 4, 9: dumb-terminal gate and pattern heuristic |
| `GITHUB_ACTIONS` | GitHub CI | Step 5: True_Color when value is `"true"` |
| `GITEA_ACTIONS` | Gitea CI | Step 5: True_Color (presence) |
| `CIRCLECI` | CircleCI | Step 5: True_Color (presence) |
| `TRAVIS` | Travis CI | Step 5: Basic_16 (presence) |
| `APPVEYOR` | AppVeyor CI | Step 5: Basic_16 (presence) |
| `GITLAB_CI` | GitLab CI | Step 5: Basic_16 (presence) |
| `BUILDKITE` | Buildkite CI | Step 5: Basic_16 (presence) |
| `DRONE` | Drone CI | Step 5: Basic_16 (presence) |
| `CI` | Generic CI | Step 5: Basic_16 (presence, fallback) |
| `COLORTERM` | xterm/compositor convention | Step 7: `truecolor`/`24bit` → True_Color; other → Basic_16 |
| `TERM_PROGRAM` | macOS/iTerm2 | Step 8: iTerm.app/Apple_Terminal/vscode heuristics |
| `TERM_PROGRAM_VERSION` | macOS/iTerm2 | Step 8: iTerm.app version gating (≥ 3 → True_Color) |
| `CLICOLOR` | BSD/macOS tradition | Step 10: hint Basic_16 (unless `"0"`) |

---

## Usage Examples

### Standard production use

```ada
with Termicap.Color;                   use Termicap.Color;
with Termicap.Environment;             use Termicap.Environment;
with Termicap.Environment.Capture;     use Termicap.Environment.Capture;
with Termicap.TTY;                     use Termicap.TTY;

procedure Main is
   Env   : Environment;
   Level : Color_Level;
begin
   Capture_Current (Env);
   Level := Detect_Color_Level (Env, Is_TTY => Is_TTY (Stdout));

   case Level is
      when None         => null;           --  no SGR codes
      when Basic_16     => Use_Ansi_16;
      when Extended_256 => Use_256_Color;
      when True_Color   => Use_Rgb_Color;
   end case;
end Main;
```

### Deterministic unit test (no OS interaction)

```ada
Env   : Environment := EMPTY_ENVIRONMENT;
Level : Color_Level;

--  TrueColor terminal
Insert (Env, "COLORTERM", "truecolor");
Level := Detect_Color_Level (Env, Is_TTY => True);
pragma Assert (Level = True_Color);

--  NO_COLOR overrides COLORTERM
Insert (Env, "NO_COLOR", "");
Level := Detect_Color_Level (Env, Is_TTY => True);
pragma Assert (Level = None);

--  FORCE_COLOR=3 overrides NO_COLOR
Insert (Env, "FORCE_COLOR", "3");
Level := Detect_Color_Level (Env, Is_TTY => False);
pragma Assert (Level = True_Color);
```

### Non-TTY output (piped)

```ada
Insert (Env, "TERM", "xterm-256color");
--  No force override, no CI → TTY gate returns None
Level := Detect_Color_Level (Env, Is_TTY => False);
pragma Assert (Level = None);
```

---

## Requirements Traceability

| Requirement | Element | SPARK |
|-------------|---------|-------|
| FUNC-CLR-001 | `Color_Level` type | Silver |
| FUNC-CLR-002 | `Detect_Color_Level` signature | Silver |
| FUNC-CLR-003 | NO_COLOR compliance (step 3) | Silver |
| FUNC-CLR-004 | FORCE_COLOR override (step 1) | Silver |
| FUNC-CLR-005 | CLICOLOR_FORCE (step 2) | Silver |
| FUNC-CLR-006 | TERM=dumb handling (step 4) | Silver |
| FUNC-CLR-007 | TTY gate (step 6) | Silver |
| FUNC-CLR-008 | COLORTERM detection (step 7) | Silver |
| FUNC-CLR-009 | TERM pattern detection (step 9) | Silver |
| FUNC-CLR-010 | TERM_PROGRAM detection (step 8) | Silver |
| FUNC-CLR-011 | CI environment detection (step 5) | Silver |
| FUNC-CLR-012 | CLICOLOR support (step 10) | Silver |
| FUNC-CLR-013 | Screen multiplexer cap (step 7) | Silver |
| FUNC-CLR-014 | SPARK Silver provability | Silver |
| FUNC-CLR-015 | Detection priority order | Silver |

---

## See Also

- **Architecture: Building Blocks** (`docs/architecture/03-building-blocks.md`) — package hierarchy, detection cascade table, SPARK boundary diagram
- **Architecture: Runtime View** (`docs/architecture/04-runtime-view.md`) — Scenario 8: full end-to-end color detection flow
- **Tech Spec F3** (`docs/tech-specs/f3-color-level-detection.md`) — full design rationale and reference library survey
- **[Termicap.Environment](termicap-environment.md)** — environment snapshot type used as input
- **[Termicap.TTY](termicap-tty.md)** — `Is_TTY` call that supplies the `Is_TTY` parameter
