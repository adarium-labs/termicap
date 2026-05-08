# Terminal-Capability Conformance Harness

> A cross-language differential-testing harness for terminal capability
> detection libraries. **Not a test suite.** Not a benchmark. The output is
> "these N libraries disagreed on this terminal in these ways," intended for
> human inspection — not pass/fail.

This directory holds the **schema and notes**. The runner and per-language
shims are not yet wired up; this is the design draft.

## Why this exists

There are dozens of terminal-capability detection libraries across languages
(termenv, supports-color, rich, crossterm, termbg, …). They sometimes
disagree about the same terminal. We currently have:

- No way to know *whether* `termicap` agrees with the rest of the ecosystem on
  a given terminal.
- No way to surface *useful* divergences (where termicap's active probing
  beats a passive lib, or where we have a bug the others don't).
- No public artifact telling users "library X reported this, library Y reported
  that" on, say, iTerm2 / WezTerm / Apple Terminal / Windows Terminal.

The harness fills this gap by running every supported lib against the same
terminal session, collecting their results in a canonical JSON shape, and
producing a per-terminal divergence report.

## Layout

```
tools/conformance/
├── README.md                          ← you are here
├── manifest.json                      ← shim registry (name + binary + build cmd)
├── build.py                           ← build every shim listed in manifest
├── run.py                             ← end-to-end driver (envelope + dispatch + report)
├── runner.py                          ← envelope generator only
├── validate.py                        ← validate one or more results against schema
├── compare.py                         ← per-capability divergence report
├── notes/
│   ├── 01-discovery.md                ← what each lib measures + vocabulary
│   ├── 02-schema-design.md            ← canonical schema design decisions
│   ├── 03-mapping.md                  ← how each native lib maps to canonical
│   ├── 04-pipeline.md                 ← validator/runner/comparator design
│   └── 05-shims-and-runner.md         ← shim coverage matrix + iter notes
├── schema/
│   ├── canonical.schema.json          ← JSON Schema 2020-12 for result files
│   └── examples/
│       └── *.json                     ← four hand-crafted example results
└── shims/
    ├── README.md                      ← shim contract
    ├── ada/, rust/, go/, node/, python/   ← one subdir per shim
    └── ...
```

## Quick start

```bash
# 1. build every shim (also sets up the validator venv)
python3 tools/conformance/build.py

# 2. run the harness against your current terminal
./tools/conformance/run.py --emulator iTerm2 --emulator-version 3.5.0
```

`build.py` discovers the validator path: if `python3 -c "import jsonschema"`
works on your system Python, it uses that; otherwise it creates a project-local
venv at `tools/conformance/.venv/` and installs `jsonschema` into it. `run.py`
prefers the project venv when present. This avoids the PEP 668 friction on
Homebrew / system Python where `pip install --user jsonschema` is refused.

`build.py` discovers shims from `manifest.json`, checks each toolchain
is on PATH (printing an install hint if not), skips already-built
shims, and reports per-shim status. Filter with positional args:

```bash
python3 build.py rust              # only build rust shims
python3 build.py termicap rich     # only build named shims
python3 build.py --list            # show shim states + per-host platform support
python3 build.py --force           # rebuild everything
```

### Platform gating

Each manifest entry may include an optional `platforms` allowlist:

```jsonc
{
  "name": "console-kit",
  "language": "swift",
  "binary": "...",
  "build": "...",
  "platforms": ["darwin", "linux", "windows", "android"]   // no *BSD
}
```

Recognized values: `darwin`, `linux`, `windows`, `freebsd`, `openbsd`,
`netbsd`, `android`. When set, `build.py` and `run.py` skip the shim on
hosts whose OS is not in the list. When omitted, the shim is treated as
cross-platform.

This is for shims that genuinely cannot run on a given OS (POSIX-only
syscalls, missing libc module map, etc.) — not for cases where the
toolchain might just be uninstalled. The toolchain-missing case is
already covered by `build.py`'s skip-with-install-hint logic.

## Concept: one JSON per (lib, run)

Each lib emits one JSON document conforming to `canonical.schema.json`:

```jsonc
{
  "schema_version": "0.1.0",
  "run": {                            // input state, identical across libs in one session
    "run_id":   "uuid",
    "timestamp": "...",
    "host":      { "os", "os_version", "arch" },
    "terminal":  { "emulator", "emulator_version", "shell", "multiplexer" },
    "tty":       { "stdin", "stdout", "stderr" },     // ground truth, harness-measured
    "env":       { /* fixed allowlist of relevant env vars */ }
  },
  "lib": {                            // who produced this row
    "name", "version", "language",
    "tier": "passive|active|mixed"
  },
  "capabilities": {                   // each key always present
    "color_depth":  { "supported": true,  "value": "truecolor", "method": "...", "raw": ... },
    "hyperlinks":   { "supported": false },        // explicit "not measured"
    ...
  }
}
```

Multiple JSONs sharing a `run_id` form one row in the matrix. The comparator
groups by `run_id` and compares values for each capability key.

## How a session works (intended flow — not yet implemented)

1. **Runner** generates a `run_id` (UUID) and snapshots the env + ground-truth
   TTY/host/terminal info. Writes the envelope to a file path that shims can
   read.
2. **Each shim** is a tiny program in its lib's host language (~50–100 lines):
   - reads the envelope,
   - calls the lib's detection function(s),
   - translates the lib's native output to canonical values per
     [`notes/03-mapping.md`](notes/03-mapping.md),
   - writes one JSON to `results/<terminal>/<os>/<lib>.json`.
3. **Runner** loops over all installed shims, then invokes the
   **comparator** on the produced JSONs.
4. **Comparator** emits a markdown report grouping libs by capability:
   - "5 libs agree on `color_depth = truecolor`"
   - "**divergence** on `unicode`: termicap says `extended`, is-unicode-supported
     says `none` — `TERM=xterm-256color`, `LANG=C`"
5. The user runs this on every terminal/OS combination they have access to.
   Reports are committed back to the repo (or shared via a community page).

## Why a fixed envelope rather than just dumping `process.env`?

1. **Privacy.** Many env vars contain tokens / paths / hostnames. The
   allowlist is the *exact* set detection libs are known to read.
2. **Schema stability.** `additionalProperties: false` keeps the env block
   from drifting. New env vars require a schema bump.
3. **Diagnosability.** Disagreements between libs are almost always
   explainable by env precedence rules. Capturing the envelope makes the
   explanation trivial.

## Why `supported: false` instead of `null` or absent keys?

Three states must be distinguishable:

- **Lib measured X and decided Y** → `{ "supported": true, "value": Y }`
- **Lib does not measure X** → `{ "supported": false }`
- **Shim is older than schema** → key absent (comparator warns)

The naïve "key present → compare, key absent → skip" rule confuses (2) with (3).
The shim must emit *every* canonical key on every run.

## Why the harness is not (mostly) automatable in CI

Real terminal-capability detection requires a real terminal emulator. CI
runners typically have no TTY, or a synthetic TTY (Linux PTY without an
emulator behind it). The probe results would tell you about the *runner's
PTY*, not about iTerm2 or WezTerm.

This is therefore a **human-run local matrix**. Each maintainer / contributor
runs it on the terminals they have access to and submits the resulting JSONs.

A small subset *can* run in CI: passive-only libs in a known-bad TTY are a
useful regression signal ("is the env-var precedence still right?"). That's a
secondary use case.

## How to add a new lib (procedure, when shims exist)

1. Read [`notes/03-mapping.md`](notes/03-mapping.md) — the patterns are
   consistent across libs; pick the closest match.
2. Add a section to `notes/03-mapping.md` for the new lib: native output →
   canonical mapping table + lossy notes.
3. Drop a shim into `shims/<lang>/<lib>/`. Keep it short (~100 lines).
   The shim must:
   - Read the envelope file path from `$CONFORMANCE_ENVELOPE`.
   - Call the lib (one path per capability).
   - Emit `{ "supported": true, "value": ..., "method": "..." }` or
     `{ "supported": false }` for *every* canonical key.
   - Validate the output against `schema/canonical.schema.json` before
     writing (catches schema drift early).
4. Register the shim in the runner manifest (TBD).

## How to read a result locally (today, by hand)

Until the runner exists, you can compare two example files manually:

```bash
diff <(jq -S '.capabilities | to_entries | map(select(.value.supported))' \
        schema/examples/termicap-iterm2-darwin.json) \
     <(jq -S '.capabilities | to_entries | map(select(.value.supported))' \
        schema/examples/termenv-iterm2-darwin.json)
```

This shows which capabilities both libs measured, in their canonical form.

## Python dependencies

The pipeline uses one Python package, `jsonschema`, for the validator.
You should not need to install it by hand — `build.py` handles this:

- if your system Python can already import `jsonschema`, it's used;
- otherwise `build.py` creates a project-local venv at
  `tools/conformance/.venv/` and installs `jsonschema` there.

If you'd rather install jsonschema yourself, any of the standard
mechanisms work (`pipx install jsonschema`, an existing venv, etc.). On
Homebrew / system Python, `pip install --user` may be refused under
PEP 668; that's why `build.py` falls back to a project-local venv.

If `jsonschema` is missing entirely, `run.py` still produces the report
but marks each result as `(unvalidated)`.

## Status

- [x] Schema drafted (v0.1.0 — unstable until 3 working shims exist)
- [x] Mapping notes for 11 libs
- [x] Three example outputs
- [ ] Validator that confirms a JSON file conforms to the schema
- [ ] Runner script (Bash or Python) that generates the envelope
- [ ] Shims for termicap, termenv, supports-color
- [ ] Comparator that emits a divergence report
- [ ] First real-world run on a maintainer's macOS / Linux / Windows
