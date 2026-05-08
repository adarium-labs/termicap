# Phase 1 — Discovery

Survey of detection surfaces across reference libs in `reference-frameworks/`, plus
termicap's own surface. Goal: identify the **union of capabilities**, the
**vocabulary disagreements**, and the **inputs each lib considers**.

## Capability matrix

Rows are capability dimensions; columns are libs. `✓` = the lib measures this and
exposes it as a discrete value. `±` = partial / coarse. `·` = not measured.

| Capability             | termicap (full) | termenv | rust-supports-color | supports-color (JS) | rich (Py) | crossterm | termbg | terminal-size | is-unicode-supported | termcolor | go-isatty |
|------------------------|:---------------:|:-------:|:-------------------:|:-------------------:|:---------:|:---------:|:------:|:-------------:|:--------------------:|:---------:|:---------:|
| TTY (per-stream)       | ✓ (3)           | ±       | ±                   | ±                   | ±         | ·         | ±      | ·             | ·                    | ·         | ✓ (1)     |
| Color depth            | ✓ (4 lvl)       | ✓ (4)   | ✓ (3)               | ✓ (3)               | ✓ (4+W)   | ± (bool)  | ·      | ·             | ·                    | ± (3)     | ·         |
| Dimensions             | ✓               | ·       | ·                   | ·                   | ✓ (size)  | ·         | ·      | ✓             | ·                    | ·         | ·         |
| Unicode level          | ✓ (3)           | ·       | ·                   | ·                   | ± (enc)   | ·         | ·      | ·             | ✓ (bool)             | ·         | ·         |
| Terminal identity      | ✓ (21 kinds)    | ±       | ±                   | ± (allowlist)       | ·         | ·         | ± (5)  | ·             | ± (Win-only)         | ·         | ·         |
| Multiplexer awareness  | ✓               | ✓       | ·                   | ·                   | ·         | ·         | ✓      | ·             | ·                    | ·         | ·         |
| Background color (RGB) | ·*              | ✓       | ·                   | ·                   | ·         | ·         | ✓      | ·             | ·                    | ·         | ·         |
| Theme (light/dark)     | ·*              | ✓ (h.)  | ·                   | ·                   | ·         | ·         | ✓      | ·             | ·                    | ·         | ·         |
| Hyperlinks (OSC 8)     | ✓ (4 lvl)       | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| Mouse encoding         | ✓ (4)           | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| Keyboard protocol      | ✓ (3)           | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| Graphics: Sixel        | ✓               | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| Graphics: Kitty        | ✓               | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| Clipboard (OSC 52)     | ✓ (4 lvl)       | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| XTVERSION (id+ver)     | ✓               | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| DA1 attributes         | ✓               | ·       | ·                   | ·                   | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |
| CI environment         | ✓ (input)       | ✓ (in.) | ✓ (in.)             | ✓ (in.+specific)    | ·         | ·         | ·      | ·             | ·                    | ·         | ·         |

\* termicap has internal sub-detectors for background/theme but does not currently
expose these in `Terminal_Capabilities` / `Full_Terminal_Capabilities`. The schema
allows for it; today these slots will be `supported: false` for termicap.

## Vocabulary disagreements

### Color depth

| Lib                  | Vocabulary                                             | Levels |
|----------------------|--------------------------------------------------------|--------|
| termicap             | `None` `Basic_16` `Extended_256` `True_Color`          | 4      |
| termenv              | `Ascii` `ANSI` `ANSI256` `TrueColor`                   | 4      |
| rust-supports-color  | `level: 0\|1\|2\|3` + booleans `has_basic/256/16m`     | 3 (+0) |
| supports-color (JS)  | same as rust-supports-color, returns `false` for none  | 3 (+0) |
| rich (Python)        | `STANDARD` `EIGHT_BIT` `TRUECOLOR` **`WINDOWS`**       | 4      |
| crossterm            | `bool` (ANSI yes/no)                                   | 2      |
| termcolor            | `Always` `Never` `Auto` (intent, not depth)            | n/a    |

**Notable**: rich's `WINDOWS` is a separate *kind* (Windows Console API), not a level.
Schema choice: treat color depth as `none|ansi16|ansi256|truecolor`, plus a separate
boolean `windows_console_api` for the rich case.

### Unicode

| Lib                   | Vocabulary                                  |
|-----------------------|---------------------------------------------|
| termicap              | `None` `Basic` `Extended`                   |
| is-unicode-supported  | `bool`                                      |
| rich                  | encoding string (`utf-8`, etc.)             |

Schema choice: `"none" | "basic" | "extended"`; libs that only have a boolean map
`true → "extended"`, `false → "none"`.

### Hyperlinks (OSC 8)

Only termicap measures this:
- `Unsupported` / `Likely_Supported` / `Supported` / `Unknown`
- + `Provenance`: `Default` / `Env_Excluded` / `Env_Known_Good` / `Env_Unknown` /
  `XTVERSION_Confirmed` / `XTVERSION_Rejected` / `XTVERSION_Unresolved`
- + `Terminal_Version_Known: bool`

Schema choice: keep all four canonical values; provenance preserved in `method` and
`raw` fields. Other libs leave the slot `supported: false`.

### Theme / background

| Lib       | Vocabulary                                            |
|-----------|-------------------------------------------------------|
| termbg    | `Theme: Light\|Dark` + RGB (16-bit per channel)       |
| termenv   | `bool HasDarkBackground` + RGB                        |

Schema choice: separate fields. `theme: "light" | "dark"` and
`background: { rgb: [r,g,b] }` (8-bit per channel; normalize termbg from 16-bit).

## Inputs considered (what each lib reads)

| Input source          | termicap | termenv | rust-sc | sc-js | rich | crossterm | termbg | term-size | is-uni | termcolor | go-isatty |
|-----------------------|:--------:|:-------:|:-------:|:-----:|:----:|:---------:|:------:|:---------:|:------:|:---------:|:---------:|
| `TERM`                | ✓        | ✓       | ✓       | ✓     | ✓    | ✓         | ✓      | ·         | ✓      | ✓         | ·         |
| `COLORTERM`           | ✓        | ✓       | ✓       | ✓     | ✓    | ·         | ·      | ·         | ·      | ·         | ·         |
| `NO_COLOR`            | ✓        | ✓       | ✓       | ✓     | ✓    | ·         | ·      | ·         | ·      | ✓         | ·         |
| `FORCE_COLOR`         | ✓        | ·       | ✓       | ✓     | ✓    | ·         | ·      | ·         | ·      | ·         | ·         |
| `CLICOLOR(_FORCE)`    | ✓        | ✓       | ✓       | ✓     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| `TERM_PROGRAM(_VER)`  | ✓        | ✓       | ✓       | ✓     | ·    | ·         | ✓      | ·         | ✓      | ·         | ·         |
| `WT_SESSION`          | ✓        | ·       | ·       | ·     | ·    | ·         | ·      | ·         | ✓      | ·         | ·         |
| `TMUX` / `INSIDE_EMACS` | ✓      | ·       | ·       | ·     | ·    | ·         | ✓      | ·         | ·      | ·         | ·         |
| `COLORFGBG`           | ·        | ✓       | ·       | ·     | ·    | ·         | ✓      | ·         | ·      | ·         | ·         |
| CI vars (`CI`, …)     | ✓        | ✓       | ✓       | ✓     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| Locale (`LC_*`/`LANG`)| ✓        | ·       | ·       | ·     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| `isatty()` syscall    | ✓        | ✓       | ✓       | ✓     | ✓    | ✓ (Win)   | ✓      | ✓         | ·      | ✓         | ✓         |
| `ioctl(TIOCGWINSZ)`   | ✓        | ·       | ·       | ·     | ·    | ·         | ·      | ✓ (alt)   | ·      | ·         | ·         |
| `ioctl(TIOCGPGRP)`    | ✓        | ✓       | ·       | ·     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| OSC 10/11 probe       | ·*       | ✓       | ·       | ·     | ·    | ·         | ✓      | ·         | ·      | ·         | ·         |
| DA1 (`CSI c`)         | ✓        | ± (CPR) | ·       | ·     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| XTVERSION             | ✓        | ·       | ·       | ·     | ·    | ·         | ·      | ·         | ·      | ·         | ·         |
| Win Console API       | ✓        | ·       | ✓       | ✓     | ✓    | ✓         | ✓      | ·         | ·      | ✓ (Win)   | ✓ (Win)   |

\* termicap has the OSC 11 probe internally (`Termicap.Color.Bg_Query`) but does
not currently surface bg color in the public capability records.

## Input-precedence patterns (color)

The "decide order" varies; this matters because two libs can read the same env
and arrive at different answers:

- **rust-supports-color**: `FORCE_COLOR` → `NO_COLOR` → `TTY` → `TERM/COLORTERM` → CI
- **supports-color (JS)**: CLI flags → `FORCE_COLOR` → CI-specific → `TERM/COLORTERM` → TTY
- **termenv**: `NO_COLOR` → `CLICOLOR=0` → TTY → `TERM/COLORTERM` → active OSC
- **rich**: `FORCE_COLOR` (TTY gate) → TTY → `COLORTERM/TERM` → Jupyter override
- **termicap**: 11-step cascade; `NO_COLOR` → `FORCE_COLOR` → `CLICOLOR_FORCE` → TTY → `COLORTERM` → `TERM` → `TERM_PROGRAM` → CI → `CLICOLOR` → multiplexer
- **crossterm**: WinAPI VT-enable → `TERM != dumb`

## Active probing details

| Lib       | Probe                            | Sequence                  | Timeout    | Failure mode                          |
|-----------|----------------------------------|---------------------------|------------|---------------------------------------|
| termenv   | OSC 10 / OSC 11 / CPR            | `\x1b]10;?\a` / `\x1b]11;?\a` / `\x1b[6n` | 5 s | Skip on screen/tmux/dumb              |
| termbg    | OSC 11 + DSR                     | `\x1b]11;?\x1b\\` + `\x1b[5n` | ~100 ms | Recover unterminated `rgb:` responses |
| termicap  | DA1, XTVERSION, Kitty graphics, mouse SGR/SGR-pixel, kbd progressive enhancement, OSC 52 | various                   | per-probe budgets summing to ~6 s worst | Per-probe gate; degrade to passive value |

## Notable quirks worth preserving in the harness

- termenv special-cases **Google Cloud Shell** → forced TrueColor.
- supports-color hard-codes **Windows build numbers** for color level (≥10586 → 256, ≥14931 → 16m).
- rich overrides TTY to **`False` in Jupyter** even when `FORCE_COLOR` is set.
- supports-color allowlists `xterm-kitty`, `xterm-ghostty`, `wezterm` to truecolor.
- go-isatty's Windows path inspects pipe names with the **Cygwin/MSYS2 GUID pattern** to
  distinguish a Cygwin PTY from a native console.
- termbg's response parser tolerates **unterminated OSC 11 replies** by detecting
  the `rgb:` prefix and trimming at slash boundaries.
- termenv refuses to probe when the process is **not in the foreground process group**
  (TIOCGPGRP), to avoid SIGTTIN.
