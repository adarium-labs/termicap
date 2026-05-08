# Iterations 3-6 — First three shims + dispatch wrapper

End state of this batch: a runnable harness with three working shims and a
single-command driver. `python3 run.py` from `tools/conformance/` generates
an envelope, dispatches every built shim, validates each output against the
canonical schema, and writes a markdown divergence report.

## What's new

| Path | Lines | Notes |
|---|---:|---|
| `shims/ada/termicap/alire.toml`                    |  16 | Alire crate; pinned local termicap |
| `shims/ada/termicap/termicap_shim.gpr`             |  12 | Ada project file |
| `shims/ada/termicap/src/termicap_shim.adb`         | 340 | Reads envelope, calls Detect_Full, hand-rolled JSON |
| `shims/rust/supports-color/Cargo.toml`             |  18 | Path-dep on local crate copy |
| `shims/rust/supports-color/src/main.rs`            | 110 | serde_json output |
| `shims/go/termenv/go.mod`                          |  14 | replace-dep on local termenv |
| `shims/go/termenv/main.go`                         | 175 | encoding/json output |
| `manifest.json`                                    |  20 | Shim registry (name + binary path + build cmd) |
| `run.py`                                           | 110 | End-to-end driver |

## Architecture decisions

### One shim per (lib, language). No reuse.

A shim is a tiny program in the lib's host language. It cannot be reused
across libs, even when libs share semantics, because the lib's API surface
and idioms are language-specific. The duplication is intentional — a
shim is *part of* the lib's testimony in the harness, and it should look
like idiomatic code in its host language.

### Strict rule: `supported: true` only when the lib's PUBLIC API exposes the capability.

Even when termenv internally uses TTY detection, OSC 11 probes, and CI env
vars, only what its public `Output` exposes is mapped to canonical
`supported: true`:

| termenv API                       | Canonical key       |
|-----------------------------------|---------------------|
| `output.Profile` / `ColorProfile()` | `color_depth`     |
| `output.BackgroundColor()`        | `background`        |
| `output.HasDarkBackground()`      | `theme`             |

Everything else (TTY status, terminal kind, CI detection) is `supported: false`.
Same rule applied to supports-color (`color_depth` only) and termicap (broad
public surface, so most fields are supported).

The single permitted exception: `ci_detected` is emitted by every shim from a
shim-side env-var allowlist scan, with `method` flagged accordingly. The
alternative (only termicap-style libs reporting it) would suppress useful info.

### JSON output: hand-rolled in Ada, serde_json in Rust, encoding/json in Go.

Ada has no canonical lightweight JSON dep that's universally installed.
Rather than add `gnatcoll-core` just for output, the Ada shim splices the
envelope file verbatim as the `run` value (the envelope is already valid
JSON) and emits the rest from a fixed shape with a small string-quote
helper. ~340 lines total.

Rust uses `serde_json` (universal); the local supports-color path-dep keeps
the version pinned. Go uses `encoding/json` from std.

### Replace/path deps to the local reference-frameworks copies.

Each shim depends on the lib via a *local-path* dep (Cargo `path = ...`,
Go `replace`, Alire `[[pins]]`). This pins the lib version to the copy in
`reference-frameworks/`, so the harness's results are reproducible against
*that exact copy*, not the latest crate / module on the registry.

Tradeoff: when we want to test a newer version, we update
`reference-frameworks/`. That's also the right move — any divergence found
should be reproducible from the same source tree.

### `manifest.json` is the single source of truth for the dispatcher.

`run.py` reads it; users edit it. To add a new shim:

1. Create `shims/<lang>/<lib>/`.
2. Make a buildable project that produces a binary at the path you'll list
   in the manifest.
3. Add an entry to `manifest.json` with `name`, `language`, `binary`, `build`.
4. Build and run: `python3 run.py`.

Unbuilt shims are skipped with a hint that prints the build command.

## End-to-end demo (no-TTY environment)

Running `python3 run.py --results-dir /tmp/conformance-test` from this
sandbox (no real terminal, all `tty.*` are false):

```
>>> generating envelope at /tmp/conformance-test/envelope.json
  OK      termicap                  -> termicap.json
  OK      supports-color-rust       -> supports-color-rust.json
  OK      termenv                   -> termenv.json

>>> 3 valid result(s); report written to /tmp/conformance-test/report.md
```

Comparator's report excerpt:

```
### `color_depth`
**Agreement (3 libs)**: `none`
- supports-color-rust — supports_color::on(Stream::Stdout) -> level mapping
- termenv — termenv.NewOutput(stdout).Profile (env+TTY heuristic)
- termicap — termicap.Color.Detect_Color_Level (env+TTY cascade)

### `ci_detected`
**Agreement (3 libs)**: `false`
- (each lib via its env-var allowlist scan)
```

All three libs agree on `color_depth = none` and `ci_detected = false`.
Real divergence will only show up on a real terminal — that's the next
step (run on iTerm2/Terminal/WezTerm/Windows Terminal/etc.).

## Lessons learned (Ada-specific)

Saved to `.claude/ada-lessons-learned.md` if relevant; quick recap:

1. **Alire description fields cap at 72 chars and are TOML strings (UTF-8).**
   Em-dashes fail UTF-8 validation in some Alire versions.
2. **Ada `case` choices cannot overlap.** To escape generic control chars
   while keeping LF/CR/HT/BS/FF as named branches, write the catch-all
   range as `(0..7) | (11) | (14..31)`.
3. **`Ada.Text_IO.Create`** wants `Mode => Out_File` or use the named
   `Name =>` parameter; positional `Create (X, Y, Z)` will try to take
   `Y` as the Mode.
4. **`use type T;` clauses are needed** to compare enum values across
   package boundaries when the operator isn't otherwise visible.

## Status (post-iter 6)

- [x] Schema v0.1.0
- [x] Validator
- [x] Envelope runner
- [x] Comparator
- [x] Shim contract
- [x] **Termicap shim (Ada)** — runs against `Detect_Full`
- [x] **supports-color-rust shim (Rust)**
- [x] **termenv shim (Go)**
- [x] Manifest + dispatch wrapper (`run.py`)
- [ ] Real-terminal runs (iTerm2 / Terminal / WezTerm / Linux / Windows) — operator-driven
- [ ] Committed `results/` directory + community contributions
- [ ] Maybe: GitHub Pages renderer of the matrix

The harness is complete enough that the maintainer (or any contributor)
can run it on a real terminal and produce a usable result file.

## Iter 7-15 — nine more shims (twelve total, five languages)

Same shim contract, mechanically applied. Each commit is a self-contained
addition of one shim plus its manifest entry.

| Shim                  | Language | Capabilities measured                                            | Notes |
|-----------------------|----------|------------------------------------------------------------------|-------|
| termbg                | rust     | terminal_kind, multiplexer, theme, background                    | first non-termenv active prober (OSC 11) |
| crossterm             | rust     | color_depth (binary floor), dimensions, keyboard                 | first DIVERGENCE: ansi16 vs none |
| is-unicode-supported  | node     | unicode (boolean → extended/none)                                | first Node lib; vocab divergence vs termicap's `basic` |
| terminal-size         | node     | dimensions                                                       | second dimensions measurer |
| rich                  | python   | color_depth + windows_console_color, dimensions, unicode, tty_stdout | first Python lib; only `windows_console_color` measurer |
| supports-hyperlinks   | node     | hyperlinks (binary → supported/unsupported)                      | first non-termicap hyperlinks measurer |
| go-isatty             | go       | tty_stdin, tty_stdout, tty_stderr (+ Cygwin flag)                | first non-termicap TTY measurer (all three streams) |
| supports-color-node   | node     | color_depth, ci_detected                                         | Node port of supports-color-rust; cross-port drift detector |
| anstyle-query         | rust     | color_depth (no 256 signal), ci_detected                         | Cargo's color probe; documented mapping limitation |

## Capability coverage matrix (post-iter 15)

13 of 20 canonical capabilities now have ≥2 measurers; the 7 single-source
rows are mostly termicap's unique Tier 4 features (which is itself a finding).

| Capability               | # libs | Notes |
|--------------------------|:-----:|-------|
| `color_depth`            |   7   | termicap, supports-color-rust, termenv, crossterm, rich, supports-color-node, anstyle-query |
| `ci_detected`            |   4   | termicap, supports-color-rust, termenv, anstyle-query |
| `dimensions`             |   4   | termicap, crossterm, terminal-size, rich |
| `tty_stdout`             |   3   | termicap, rich, go-isatty |
| `unicode`                |   3   | termicap, is-unicode-supported, rich |
| `terminal_kind`          |   3   | termicap, termenv, termbg |
| `multiplexer`            |   2   | termicap, termbg |
| `theme`                  |   2   | termenv, termbg |
| `background`             |   2   | termenv, termbg |
| `hyperlinks`             |   2   | termicap, supports-hyperlinks |
| `keyboard`               |   2   | termicap, crossterm |
| `tty_stdin`              |   2   | termicap, go-isatty |
| `tty_stderr`             |   2   | termicap, go-isatty |
| `windows_console_color`  |   1   | rich (no other lib in the matrix surfaces this) |
| `mouse`                  |   1   | **termicap-unique** — no widely-deployed lib does mouse-protocol probing |
| `clipboard_osc52`        |   1   | **termicap-unique** — DA1 Ps=52 + active OSC 52 |
| `graphics_sixel`         |   1   | **termicap-unique** — DA1 Ps=4 + heuristic |
| `graphics_kitty`         |   1   | **termicap-unique** — active probe + XTVERSION |
| `xtversion`              |   1   | **termicap-unique** — active CSI > q |
| `da1_attributes`         |   1   | **termicap-unique** — active CSI c |

In the no-TTY sandbox where this harness was developed, `python3 run.py`
on the eight installed shims surfaces three real divergences automatically:

- **`color_depth` divergence**: 4 libs say `none` (TTY-gated), crossterm
  says `ansi16` (does not gate on TTY on non-Windows).
- **`dimensions` divergence**: termicap + terminal-size default to 80×24,
  rich defaults to 80×25.
- **`unicode` divergence**: is-unicode-supported + rich say `extended`
  (boolean and encoding paths), termicap says `basic` (three-level
  locale cascade — vocabulary mismatch).

These are exactly the kind of disagreements the harness exists to surface.
None are bugs in any single lib; they're consequences of different
detection contracts. The comparator's `method` field for each lib makes
the *why* visible at a glance.

## What's left (operational, not code)

The harness is feature-complete for the kinds of comparisons it was
designed to support. The remaining work is *runs*, not more code:

1. Run on real terminals (iTerm2, Apple Terminal, WezTerm, Ghostty,
   Windows Terminal, Linux console, tmux, screen, …) and commit the
   resulting JSONs to a `results/<terminal>/<os>/` tree.
2. Optional follow-on shims if a specific lib is interesting:
   chalk's supports-color (Node), termcolor (Rust, intent-style),
   go-isatty (Go), notcurses (C). Each is mechanical given the contract.
3. Optional: a GitHub Pages renderer of the matrix.
