# Phase 3 — Per-Lib Mapping

How each surveyed lib's native output translates into the canonical schema.
Each section follows the same shape: a small table of `(native field) → (canonical key, canonical value)` and a notes block listing lossy translations.

These mappings are what each lib's **shim** must implement. The shim is a thin
program (in the lib's host language) that:

1. Calls the lib's detection function(s).
2. Reads the harness-provided `run` envelope (UUID, terminal name, env snapshot)
   from a file or env var.
3. Translates the lib's native output to canonical values.
4. Writes one JSON conforming to `canonical.schema.json` to
   `results/<terminal>/<os>/<lib>.json`.

The shim is not the lib. It can have bugs. Keep it short.

---

## termicap (Ada)

Driver: `Termicap.Capabilities.Detect_Full`. Reads the assembled `Full_Terminal_Capabilities`.

| Native field                              | Canonical key            | Translation                                              |
|-------------------------------------------|--------------------------|----------------------------------------------------------|
| `TTY_Stdin/Stdout/Stderr`                 | `tty_stdin/stdout/stderr`| direct                                                   |
| `Color: None/Basic_16/Extended_256/True_Color` | `color_depth`       | `none` / `ansi16` / `ansi256` / `truecolor`              |
| `Size: {Rows, Columns, Pixel_Width, Pixel_Height}` | `dimensions`    | `{rows, cols, pixel_width, pixel_height}` (Pixel_*=0 stays 0) |
| `Unicode: None/Basic/Extended`            | `unicode`                | `none` / `basic` / `extended`                            |
| `Identity.Kind`                           | `terminal_kind`          | lowercase the enum name (e.g. `ITerm2` → `iterm2`)       |
| `Identity.Is_Multiplexer` + `TERM`        | `multiplexer`            | `tmux` / `screen` / `none`                               |
| `Hyperlinks.Support`                      | `hyperlinks`             | direct (`Supported` → `supported`, etc.)                 |
| `Hyperlinks.Provenance`                   | (preserved in `raw`)     | not in canonical value                                   |
| `Mouse: SGR_Pixels/SGR/URXVT/X10/None`    | `mouse`                  | direct (lowercase + underscore)                          |
| `Keyboard: Legacy/XTerm_CSI/Kitty`        | `keyboard`               | direct (lowercase + underscore)                          |
| `Graphics.Sixel_Supported`                | `graphics_sixel`         | direct                                                   |
| `Graphics.Kitty_Supported`                | `graphics_kitty`         | direct                                                   |
| `Clipboard: None/Read/Write/ReadWrite`    | `clipboard_osc52`        | `none` / `read_only` / `write_only` / `read_write`       |
| `XTVERSION.{Name, Version}`               | `xtversion`              | direct (strings; `''` if Status /= Success)              |
| `DA1.Attributes`                          | `da1_attributes`         | sort ascending                                           |
| —                                         | `theme`                  | `supported: false` (not exposed in public record)        |
| —                                         | `background`             | `supported: false` (not exposed in public record)        |
| —                                         | `windows_console_color`  | `supported: false` (Ada doesn't track this dimension)    |
| derived from `Env`                        | `ci_detected`            | shim-side: any CI env var present → `true`               |

**Lossy notes:**
- `Hyperlinks.Provenance` (the 7-value chain) and `Terminal_Version_Known` are
  carried in `capabilities.hyperlinks.raw`, not the canonical value. The
  `Supported` vs `Likely_Supported` distinction *is* preserved in the value.
- termicap's internal `Termicap.Color.Bg_Query` and `Termicap.Color.Dark_Light`
  could populate `theme` and `background`. The shim should call them
  directly (not via `Detect_Full`) once we agree to expose them.

---

## termenv (Go)

Driver: `termenv.NewOutput(os.Stdout).EnvColorProfile()` + `BackgroundColor()` + `HasDarkBackground()`.

| Native value                                   | Canonical key       | Translation                                       |
|------------------------------------------------|---------------------|---------------------------------------------------|
| `Profile: Ascii/ANSI/ANSI256/TrueColor`        | `color_depth`       | `none` / `ansi16` / `ansi256` / `truecolor`       |
| `BackgroundColor() RGBColor("#272822")`        | `background.rgb`    | parse hex, emit `[r,g,b]` 0-255                   |
| `HasDarkBackground() bool`                     | `theme`             | `true` → `dark`, `false` → `light`                |
| `EnvNoColor() / output.IsTTY()`                | `tty_stdout`        | direct                                            |
| `TermProgram` (read from env, exposed via API) | `terminal_kind`     | `Apple_Terminal` → `apple_terminal`, …            |

**Not measured by termenv** → `supported: false`:
`tty_stdin`, `tty_stderr`, `dimensions`, `unicode`, `hyperlinks`, `mouse`,
`keyboard`, `clipboard_osc52`, `graphics_*`, `xtversion`, `da1_attributes`,
`windows_console_color`, `multiplexer` (termenv reads `TMUX` internally but
doesn't expose), `ci_detected`.

**Lossy notes:**
- termenv's RGB is hex; canonical is integer triple. Trivial.
- `HasDarkBackground` is a heuristic threshold; carry the heuristic note in
  `theme.method` (e.g. `"OSC 11 + luminance threshold"`).

---

## rust-supports-color (Rust)

Driver: `supports_color::on(Stream::Stdout)`.

| Native field                              | Canonical key            | Translation                                            |
|-------------------------------------------|--------------------------|--------------------------------------------------------|
| `ColorLevel.level: 0/1/2/3`               | `color_depth`            | `none` / `ansi16` / `ansi256` / `truecolor`            |
| `ColorLevel { has_basic, has_256, has_16m }` | (preserved in `raw`)  | not in canonical value                                 |
| (no API; shim must do this itself)        | `tty_stdout`             | shim calls `IsTerminal::is_terminal(io::stdout())`     |
| (read from env)                           | `ci_detected`            | shim checks `is_ci::uncached()`                        |

**Not measured** → `supported: false` for everything else: `dimensions`,
`unicode`, `terminal_kind`, `multiplexer`, `theme`, `background`, `hyperlinks`,
`mouse`, `keyboard`, `clipboard_osc52`, `graphics_*`, `xtversion`,
`da1_attributes`, `windows_console_color`, `tty_stdin`, `tty_stderr`.

**Lossy notes:**
- `level: 0` is "supports-color returned `None`" → canonical `none`. The shim
  collapses `Option<ColorLevel>` (None = no color) to `color_depth: "none"`.

---

## supports-color (Node.js / chalk)

Driver: `import {supportsColor} from 'supports-color'; supportsColor.stdout`.

| Native value                                       | Canonical key         | Translation                                            |
|----------------------------------------------------|-----------------------|--------------------------------------------------------|
| `false` (no color)                                 | `color_depth`         | `none`                                                 |
| `{ level: 1\|2\|3, hasBasic, has256, has16m }`     | `color_depth`         | level → `ansi16/ansi256/truecolor`                     |
| (full object preserved)                            | (in `raw`)            | not in canonical value                                 |
| `process.stdout.isTTY`                             | `tty_stdout`          | shim reads directly                                    |
| Allowlisted `TERM` (`xterm-kitty`, `xterm-ghostty`, `wezterm`) | `terminal_kind` | shim can expose if desired (not native to lib)        |

**Not measured** → `supported: false` for the rest, identical to the Rust port.

**Lossy notes:**
- supports-color reports per-stream (`.stdout`, `.stderr`). The shim runs both,
  reports the **stdout** value canonically, and stashes the stderr value in
  `color_depth.raw.stderr_level` for visibility.

---

## rich (Python)

Driver: `rich.console.Console()`; inspect `console.color_system` and
`console.options`.

| Native value                                              | Canonical key            | Translation                                            |
|-----------------------------------------------------------|--------------------------|--------------------------------------------------------|
| `ColorSystem.STANDARD/EIGHT_BIT/TRUECOLOR`                | `color_depth`            | `ansi16` / `ansi256` / `truecolor`                     |
| `ColorSystem.WINDOWS`                                     | `color_depth=ansi16`, `windows_console_color=true` | split into two fields           |
| `console.is_terminal`                                     | `tty_stdout`             | direct                                                 |
| `console.size: ConsoleDimensions(width, height)`          | `dimensions`             | `{cols=width, rows=height, pixel_*=0}`                 |
| `console.encoding`                                        | (in `raw` only)          | no canonical key for raw encoding (yet)                |
| Jupyter detection                                         | `terminal_kind`          | `other` with `raw.context = "jupyter"`                 |

**Not measured** → `supported: false` for: `tty_stdin`, `tty_stderr`,
`unicode` (could potentially derive from encoding — currently `false`),
`multiplexer`, `theme`, `background`, `hyperlinks`, `mouse`, `keyboard`,
`clipboard_osc52`, `graphics_*`, `xtversion`, `da1_attributes`.

**Lossy notes:**
- The `WINDOWS` color system is a *kind* not a *level*. The schema splits
  this into two canonical keys to avoid forcing other libs to also have a
  `windows` enum value.
- Rich's `encoding` ("utf-8", "ascii", …) could populate `unicode` — left
  for a future schema minor version.

---

## termbg (Rust)

Driver: `termbg::theme(Duration::from_millis(100))` + `termbg::rgb(...)`.

| Native value                                | Canonical key      | Translation                                        |
|---------------------------------------------|--------------------|----------------------------------------------------|
| `Theme::Light/Dark`                         | `theme`            | `light` / `dark`                                   |
| `Rgb { r, g, b }` (16-bit each)             | `background.rgb`   | `[r >> 8, g >> 8, b >> 8]` (down-convert to 8-bit) |
| `Terminal::Screen/Tmux/XtermCompatible/Windows/Emacs` | `terminal_kind` / `multiplexer` | `Tmux`/`Screen` → `multiplexer`; `XtermCompatible` → `xterm`; `Windows` → `windows_terminal`; `Emacs` → `other` |

**Not measured** → `supported: false` for everything else.

**Lossy notes:**
- termbg's `Terminal::XtermCompatible` is broader than canonical `xterm`; the
  shim should preserve the original token in `terminal_kind.raw`.
- 16→8-bit RGB conversion is intentional (lossy). Most consumers don't need
  16-bit precision; the canonical form is `[0..255]` for ergonomic reasons.

---

## terminal-size (Node)

Driver: `import terminalSize from 'terminal-size'`.

| Native value           | Canonical key     | Translation                                |
|------------------------|-------------------|--------------------------------------------|
| `{ columns, rows }`    | `dimensions`      | `{cols=columns, rows, pixel_*=0}`          |

Everything else: `supported: false`. Single-purpose lib.

---

## is-unicode-supported (Node)

Driver: `import isUnicodeSupported from 'is-unicode-supported'`.

| Native value           | Canonical key     | Translation                                |
|------------------------|-------------------|--------------------------------------------|
| `true`                 | `unicode`         | `extended`                                 |
| `false`                | `unicode`         | `none`                                     |

Everything else: `supported: false`.

**Lossy notes:**
- The lib has no notion of "basic Unicode" (Latin-1). The shim must collapse
  to `extended` or `none`. This is documented divergence — termicap's
  three-level vocabulary will frequently diverge from this lib's two-level
  one, even when they "agree" loosely.

---

## termcolor (Rust)

Driver: not directly comparable — the lib exposes `ColorChoice` (intent), not a
detected level. The shim must make a small contract: emit `Always` → `truecolor`,
`Never` → `none`, `Auto` → run the auto rule and return one of those.

This makes the comparator's life easier, but the divergence "termcolor says
truecolor / supports-color says ansi256" is *not* a real disagreement — it's
a vocabulary mismatch. The shim should annotate `color_depth.method` with
`"intent (Always)"` so humans see the caveat.

---

## crossterm (Rust)

Driver: `crossterm::tty::IsTty` + ANSI flag.

| Native value           | Canonical key     | Translation                                |
|------------------------|-------------------|--------------------------------------------|
| `supports_ansi(): bool`| `color_depth`     | `true` → `ansi16` (lower bound), `false` → `none` |

Everything else: `supported: false`.

**Lossy notes:**
- crossterm answers a binary "ANSI yes/no" — it does not measure depth.
  Mapping to `ansi16` is a deliberate floor: ANSI-supporting terminals
  always have at least 16 colors. This will diverge from libs that report
  `ansi256` or `truecolor` on the same terminal — that's expected and is
  recorded in `color_depth.method = "binary ANSI floor"`.

---

## go-isatty (Go)

Driver: `isatty.IsTerminal(os.Stdout.Fd())`.

| Native value           | Canonical key     | Translation                                |
|------------------------|-------------------|--------------------------------------------|
| `IsTerminal(0)`        | `tty_stdin`       | direct                                     |
| `IsTerminal(1)`        | `tty_stdout`      | direct                                     |
| `IsTerminal(2)`        | `tty_stderr`      | direct                                     |
| `IsCygwinTerminal(...)`| (in `raw`)        | shim emits all three; Cygwin flag → raw    |

Everything else: `supported: false`.

---

## supports-hyperlinks (Node)

Driver: `import supportsHyperlinks from 'supports-hyperlinks'`. Default
export is `{stdout, stderr}` booleans.

| Native value           | Canonical key | Translation |
|------------------------|---------------|-------------|
| `.stdout === true`     | `hyperlinks`  | `supported` |
| `.stdout === false`    | `hyperlinks`  | `unsupported` |
| `.stderr` (preserved)  | `hyperlinks.raw.stderr` | not in canonical value |

**Lossy notes**:
- supports-hyperlinks has no equivalent of canonical `likely_supported`
  or `unknown` — only a definitive yes/no. Comparison vs termicap's
  four-value enum will frequently surface termicap=`likely_supported` /
  `unknown` while this lib stays at `unsupported` (its conservative default
  for unknown emulators), which is the documented vocabulary mismatch.

## go-isatty (Go)

Driver: `isatty.IsTerminal(fd)` and `isatty.IsCygwinTerminal(fd)`.
The shim probes all three standard fds.

| Native value                    | Canonical key  | Translation     |
|---------------------------------|----------------|-----------------|
| `IsTerminal(os.Stdin.Fd())`     | `tty_stdin`    | direct          |
| `IsTerminal(os.Stdout.Fd())`    | `tty_stdout`   | direct          |
| `IsTerminal(os.Stderr.Fd())`    | `tty_stderr`   | direct          |
| `IsCygwinTerminal(...)` (any)   | `tty_stdout.raw.is_cygwin_terminal` | only emitted when true |

Everything else: `supported: false`.

## supports-color (Node, chalk)

Driver: `import supportsColorModule from 'supports-color'`. Default export
is `{stdout, stderr}` where each is `false` or `{level, hasBasic, has256, has16m}`.

| Native value                                  | Canonical key | Translation |
|-----------------------------------------------|---------------|-------------|
| `stdout === false`                            | `color_depth` | `none` |
| `stdout.level === 1`                          | `color_depth` | `ansi16` |
| `stdout.level === 2`                          | `color_depth` | `ansi256` |
| `stdout.level === 3`                          | `color_depth` | `truecolor` |
| stderr per-stream value                       | `color_depth.raw.stderr_*` | preserved for cross-stream divergence |

This shim's results should match supports-color-rust (the Rust port).
Divergence between the two is a port drift — useful signal.

## anstyle-query (Rust)

Driver: `anstyle_query::*` predicates (no single level function).

| Native predicates                          | Canonical key | Translation |
|--------------------------------------------|---------------|-------------|
| `no_color()`                               | `color_depth` | `none` |
| `!term_supports_color() && !clicolor_force()` | `color_depth` | `none` |
| `truecolor()`                              | `color_depth` | `truecolor` |
| `term_supports_ansi_color()`               | `color_depth` | `ansi16` |
| `is_ci()`                                  | `ci_detected` | direct |

**Lossy notes**:
- anstyle-query has no 256-color signal, so this shim **never emits
  `ansi256`**. Real divergence vs supports-color/termenv on a 256-only
  terminal is therefore expected; the `method` field flags this.

## Cross-cutting shim responsibilities

Things every shim must do, regardless of lib:

1. Read the harness-provided `run` envelope (UUID, ground-truth terminal info,
   env snapshot). Pass through verbatim.
2. Detect the lib's own `version` (e.g. via cargo metadata, npm
   `package.json`, `go list -m`, alire metadata). Embed in `lib.version`.
3. Emit *every* required capability key. Use `{supported: false}` for unmeasured.
4. Catch and report errors as `{supported: false, raw: {error: "..."}}` rather
   than crashing — a crashed shim costs an entire result row.
5. Run synchronously and write the JSON to the path the harness expects.
6. Never mutate the env or terminal state (no SetConsoleMode, no terminal
   resize). Read-only.
