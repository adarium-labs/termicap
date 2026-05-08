# Phase 2 — Schema Design Decisions

This document records the design decisions behind the canonical conformance JSON
schema (`schema/canonical.schema.json`). Follow-up readers: when a decision
becomes wrong, update both this note and the schema together.

## Principles

1. **Diagnosable divergences.** A divergence between two libs must always be
   explainable from the JSON alone — no "you had to be there." This forces us to
   capture the *input state* alongside the *output value*.
2. **No false unanimity.** The schema must distinguish "lib measured X and decided Y"
   from "lib does not measure X." The naïve "key present in both → compare" rule
   only works if absence-of-measurement is explicit, not represented by an
   omitted key (which could also mean "missed it" or "newer schema, older lib").
3. **No false divergence.** Different libs use different vocabulary for the same
   concept. The schema fixes a canonical vocabulary; each lib's shim does the
   translation. Lossy translations are flagged via the `raw` slot.
4. **Lib output is not ground truth.** The harness is a divergence detector,
   never a pass/fail grader. The schema therefore has no `correct` or
   `expected` field — only observations.
5. **Envelopes are mandatory; schemas evolve.** Each result carries
   `schema_version`. The comparator refuses to compare results across major
   versions without an explicit migration. Minor versions are forward-compatible
   (extra fields ignored).

## Top-level shape

```jsonc
{
  "schema_version": "0.1.0",
  "run":           { /* who/what/when — the input state */ },
  "lib":           { /* which lib produced this — name, version, tier */ },
  "capabilities":  { /* the lib's measurements, normalized */ }
}
```

Splitting into three named blocks (rather than a flat dict) lets the comparator
treat them differently:
- `run` is grouped on (one row in the matrix per `run_id`).
- `lib` is the column key.
- `capabilities` is the cell content.

## The `run` block — input state

Required. Without input state, divergences are uninterpretable. The `run` block
captures **everything that could plausibly affect the result**.

```jsonc
"run": {
  "run_id":    "550e8400-e29b-41d4-a716-446655440000", // UUID; same across libs in one session
  "timestamp": "2026-05-08T01:30:00Z",                 // ISO 8601 UTC
  "host":      { "os": "darwin", "os_version": "24.6.0", "arch": "arm64" },
  "terminal":  { "emulator": "iTerm2", "emulator_version": "3.5.0",
                 "shell": "zsh", "multiplexer": null },
  "tty":       { "stdin": true, "stdout": true, "stderr": true },
  "env":       { /* fixed-key allowlist; see below */ }
}
```

### `run.terminal.emulator`

Free-text, but normalized when possible (e.g. `"iTerm2"`, `"WezTerm"`,
`"kitty"`, `"Apple_Terminal"`, `"Windows Terminal"`). The harness fills this
from the user's invocation context — **not** from the lib being tested. (The
lib's *opinion* about the emulator is captured in `capabilities.terminal_kind`
and is allowed to disagree with the ground-truth invocation context.)

### `run.tty`

The harness's own `isatty()` check on each fd. Captured separately from
each lib's TTY field so the comparator can flag a lib that disagrees with
ground truth.

### `run.env` — fixed allowlist

Capturing the entire environment leaks secrets. We capture only the vars that
detection libs actually read, plus a few witness vars used as ground truth for
the terminal emulator. The allowlist (kept stable across schema minor versions):

```
TERM, COLORTERM, NO_COLOR, FORCE_COLOR, CLICOLOR, CLICOLOR_FORCE,
TTY_COMPATIBLE, IGNORE_IS_TERMINAL,
TERM_PROGRAM, TERM_PROGRAM_VERSION, TERMINAL_EMULATOR,
WT_SESSION, KONSOLE_VERSION, VTE_VERSION,
TMUX, STY, INSIDE_EMACS,
COLORFGBG,
LANG, LC_ALL, LC_CTYPE,
CI, GITHUB_ACTIONS, GITEA_ACTIONS, GITLAB_CI, CIRCLECI, TRAVIS, BUILDKITE,
   APPVEYOR, TF_BUILD,
SHELL, OSTYPE
```

Each var maps to either `null` (absent) or a string (present, value verbatim).
**Absent ≠ empty string.** Some libs treat empty `FORCE_COLOR=""` differently
from unset `FORCE_COLOR`; preserve the distinction.

## The `lib` block — provenance

Required. Identifies which library produced these results.

```jsonc
"lib": {
  "name":     "termicap",
  "version":  "0.5.0",
  "language": "ada",
  "tier":     "active",        // "passive" | "active" | "mixed"
  "commit":   "ba17591"        // optional
}
```

### `lib.tier` — operational classification

- `"passive"`: lib reads only env vars + `isatty()`. Examples:
  rust-supports-color, supports-color (JS), is-unicode-supported, termcolor.
- `"active"`: lib sends escape sequences and parses replies. Examples:
  termbg, termicap (full mode), kitty's own detection.
- `"mixed"`: lib does both, depending on configuration. Examples:
  termenv (probes only when not screen/tmux/dumb), rich (queries on Win, env
  elsewhere), termicap base mode (passive heuristics + DA1 only).

This is informational, not algorithmic. It helps explain divergences:
"termicap (active) says truecolor; supports-color (passive) says ansi256
because `COLORTERM` is unset" is a *different* class of disagreement from two
passive libs disagreeing on the same env.

## The `capabilities` block

Each capability is one of two shapes:

```jsonc
// Lib measured this:
"color_depth": {
  "supported": true,
  "value":  "truecolor",
  "method": "active+heuristic",
  "raw":    "True_Color"        // optional, native vocabulary
}

// Lib does not measure this:
"hyperlinks": {
  "supported": false
}
```

`supported: false` is the explicit "not measured" marker. The comparator
treats it differently from "absent key" (which means "shim is older than the
schema" — the comparator should warn).

### Capability set (fixed in this minor version)

| Key                       | Type / vocabulary                                                            | Notes |
|---------------------------|------------------------------------------------------------------------------|-------|
| `tty_stdin`               | `bool`                                                                       | |
| `tty_stdout`              | `bool`                                                                       | |
| `tty_stderr`              | `bool`                                                                       | |
| `color_depth`             | `"none" \| "ansi16" \| "ansi256" \| "truecolor"`                             | |
| `windows_console_color`   | `bool`                                                                       | rich-style; orthogonal to `color_depth` |
| `dimensions`              | `{ cols: int>=1, rows: int>=1, pixel_width: int>=0, pixel_height: int>=0 }`  | pixel = 0 means unknown |
| `unicode`                 | `"none" \| "basic" \| "extended"`                                            | bool→`extended`/`none` for libs without a level |
| `terminal_kind`           | string token (lowercased; vocabulary listed in schema enum)                  | union of termicap's `Terminal_Kind` + `"unknown"` |
| `multiplexer`             | `"none" \| "tmux" \| "screen" \| "zellij"`                                   | |
| `theme`                   | `"light" \| "dark"`                                                          | |
| `background`              | `{ rgb: [int 0-255, int 0-255, int 0-255] }`                                 | normalize from termbg's 16-bit channels |
| `hyperlinks`              | `"unsupported" \| "likely_supported" \| "supported" \| "unknown"`            | termicap-only vocabulary, kept verbatim |
| `mouse`                   | `"none" \| "x10" \| "urxvt" \| "sgr" \| "sgr_pixels"`                        | |
| `keyboard`                | `"legacy" \| "xterm_csi" \| "kitty"`                                         | |
| `clipboard_osc52`         | `"none" \| "read_only" \| "write_only" \| "read_write"`                      | |
| `graphics_sixel`          | `bool`                                                                       | |
| `graphics_kitty`          | `bool`                                                                       | |
| `xtversion`               | `{ name: string, version: string }`                                          | both strings; version may be empty |
| `da1_attributes`          | `int[]`                                                                      | sorted, e.g. `[4, 22, 52]` |
| `ci_detected`             | `bool`                                                                       | |

Capabilities omitted by a lib must still appear in the JSON with
`supported: false`. The shim is responsible for emitting the full key set —
absence-of-key signals shim drift, not absence-of-measurement.

### `method` — informational, not enumerated

Free-text. Examples: `"env"`, `"isatty"`, `"ioctl(TIOCGWINSZ)"`,
`"COLORTERM=truecolor"`, `"OSC 11 + heuristic"`, `"DA1 Ps=4"`,
`"XTVERSION+known-good-table"`. The comparator does not parse it; humans read
it when investigating a divergence. Not normalized because libs themselves
don't normalize their internal "why" reasoning.

### `raw` — escape hatch

Optional, free-shape. Use when the canonical vocabulary loses information
that's worth preserving for debugging. Examples:
- termicap hyperlinks: `{ "support": "Supported", "provenance": "XTVERSION_Confirmed", "version_known": true }`
- supports-color color: `{ "level": 3, "has_basic": true, "has_256": true, "has_16m": true }`

The comparator ignores `raw`. It's purely for humans inspecting individual
results.

## What the comparator is supposed to do (informally — not normative for the schema)

For each capability key, across the libs sharing a `run_id`:
1. Collect `(lib_name, value)` pairs where `supported: true`.
2. If all values are equal → "agreement (N libs)."
3. If values differ → "divergence" — group libs by value, render alongside
   `method` and selected `run.env` keys (TERM, COLORTERM, NO_COLOR, FORCE_COLOR).
4. Libs with `supported: false` are listed separately as "not measured."
5. Libs with the key absent (and `schema_version` matches) are flagged as
   shim drift.

The output is a markdown matrix per terminal/OS, *not* a pass/fail.

## Versioning

`schema_version` follows semver:
- **patch**: editorial changes (descriptions, examples). Comparator runs.
- **minor**: new capability key added, or new enum value. Older shims work
  unchanged (their results omit the new key); comparator warns.
- **major**: incompatible vocabulary change. Comparator refuses without a
  migration.

We start at `0.1.0`. The schema is unstable until we have working shims for
at least three libs in three languages.

## Resolved questions (2026-05-08)

- **Per-stream `color_depth`** — DEFERRED. Single canonical value, derived from
  the stdout stream by default. Shims that report per-stream values (e.g.
  supports-color) stash the secondary stream's value in `color_depth.raw.stderr_level`.
  Revisit if a real-world run shows the two streams diverging on the same
  terminal in a way that matters.
- **Background-color storage** — `[r, g, b]` integer triple, each 0-255.
  Hex strings stay in `background.raw` for libs that natively use them
  (e.g. termenv).
- **Clipboard granularity** — keep termicap's four-value vocabulary
  (`none` / `read_only` / `write_only` / `read_write`) as the canonical.
  No other surveyed lib measures clipboard, so termicap's distinctions are
  preserved without contradiction.
- **`run_id` generation** — UUID v4, generated once by the runner and passed
  to every shim via the envelope file. Not reproducible by design — we want
  every harness invocation to be a fresh row, even if the host state hasn't
  changed.
