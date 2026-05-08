# Iteration 2 — Pipeline tooling

Schema is locked at v0.1.0 (the four open questions resolved per the user
on 2026-05-08). This iteration delivers the runnable pipeline that operates
on the canonical schema:

```
                          ┌──────────────┐
                          │  runner.py   │  ← capture host/term/tty/env
                          └──────┬───────┘
                                 │ envelope.json (the `run` block)
                                 ▼
            ┌─────────┬──────────┴──────────┬──────────┐
            ▼         ▼                     ▼          ▼
       ┌────────┐ ┌────────┐            ┌────────┐ ┌────────┐
       │ shim A │ │ shim B │     ...    │ shim C │ │ shim D │  ← TBD per lib
       └───┬────┘ └────┬───┘            └────┬───┘ └────┬───┘
           │           │                     │          │
           └───────────┴──────────┬──────────┴──────────┘
                                  │ <run_id>/<lib>.json (validated against schema)
                                  ▼
                          ┌──────────────┐
                          │ validate.py  │  ← per-file schema check
                          └──────┬───────┘
                                 │
                                 ▼
                          ┌──────────────┐
                          │  compare.py  │  ← markdown divergence report
                          └──────────────┘
```

## What's new in this iteration

| Deliverable                                   | Lines  | Purpose |
|-----------------------------------------------|--------|---------|
| `validate.py`                                 |  ~75   | Validate one or more result JSONs against `canonical.schema.json` |
| `runner.py`                                   | ~150   | Generate the envelope: UUID, host info, terminal info, TTY status, env-var allowlist |
| `compare.py`                                  | ~200   | Group results by `run_id`, render per-capability divergence/agreement as markdown |
| `shims/README.md`                             | ~180   | Shim contract: read envelope, call lib, translate, validate, write |
| `schema/examples/crossterm-iterm2-darwin.json`|  ~80   | Synthetic example to demonstrate the DIVERGENCE branch on `color_depth` |

## Decisions made during implementation

1. **`runner.py` is *only* the envelope generator, not a shim dispatcher.**
   The Unix way: each shim is invoked manually (or by a thin shell wrapper)
   with `CONFORMANCE_ENVELOPE=envelope.json /path/to/shim`. Keeps the
   runner simple and free of language-specific dispatch logic.

2. **Single-lib observations are not "agreement."** The comparator
   distinguishes:
   - `Agreement (N libs)` — N≥2 libs measured this and produced the same value.
   - `Single observation` — exactly one lib measured this; nothing to compare.
   - `DIVERGENCE (M groups, N libs)` — N≥2 libs measured this, M groups of
     distinct values.
   This avoids the false-positive "we agree!" when in fact only one lib
   answered.

3. **Schema drift is reported, not ignored.** A capability key absent from
   a result (rather than `{supported: false}`) is treated as shim drift and
   surfaced in the report. The shim either pre-dates the canonical key, or
   forgot to emit it — both are bugs to fix.

4. **Booleans render lowercase.** The header used Python's
   `True`/`False`; switched to `true`/`false` so the report matches JSON
   conventions and reads cleaner alongside `` `truecolor` `` and
   `` `null` `` markers.

5. **`runner.py` defaults emulator detection to env-var heuristics, but
   accepts `--emulator` override.** The operator is the source of truth
   about which terminal they launched. Auto-detection is best-effort and
   should be overridden when convenient — especially in tmux/screen,
   where `TERM_PROGRAM` is often clobbered.

## What still needs doing (iteration 3 candidates)

In rough order of payoff:

1. **First real shim: `supports-color-rust`.** Rust + Cargo, ~80 lines. Lets
   us run the harness on the maintainer's terminal and produce an actual
   (not synthesized) result file.
2. **Second real shim: `termicap`.** Ada + Alire + GNATCOLL.JSON. ~150–200
   lines. The whole point of the harness — once this is online, we can
   measure ourselves.
3. **Third real shim: `termenv`.** Go module, small. Lets us validate the
   active-probe (OSC 11) divergence against passive libs.
4. **Runner manifest** — small JSON/YAML listing installed shims and how
   to invoke each. Enables `make conformance` to run all installed shims.
5. **A "results" git directory** — committed JSON results from real terminals.
   The community-source compatibility matrix.
6. **GitHub Pages site** rendering the matrix from committed results.

## How to demo the pipeline today (without real shims)

```bash
cd tools/conformance

# 1. Validate one or all examples
python3 validate.py schema/examples/*.json

# 2. Generate a fresh envelope from the current shell
python3 runner.py --emulator iTerm2 --emulator-version 3.5.0 \
                  --output /tmp/envelope.json

# 3. Compare the four example results (which all share a fake run_id):
python3 compare.py schema/examples/*.json
```

The third step shows the comparator's output: agreement on `color_depth`
across three libs, **DIVERGENCE** when `crossterm` reports `ansi16` (its
binary ANSI floor) while the others report `truecolor`, and `Single
observation` rows for capabilities only termicap measures.
