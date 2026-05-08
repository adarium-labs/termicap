# Shims

A *shim* is a tiny program — typically 50–150 lines — that drives one
detection library and emits one canonical-schema JSON document.

The harness has one shim per (lib, language). Shims are intentionally short
and dependency-free: they exist purely to translate the lib's native output
into the canonical vocabulary defined in
[`schema/canonical.schema.json`](../schema/canonical.schema.json).

## Contract

A shim:

1. **Reads `$CONFORMANCE_ENVELOPE`** — a path to the envelope JSON written by
   `runner.py`. The envelope contains `run_id`, host info, terminal info,
   ground-truth TTY status, and the env-var allowlist. The shim copies the
   envelope verbatim into `result["run"]`.

2. **Calls the detection library** *exactly once* per capability the lib
   measures. No retries, no caching beyond what the lib does itself.

3. **Translates** the lib's native output to canonical values per
   [`notes/03-mapping.md`](../notes/03-mapping.md). Lossy translations stash
   the native value in `capabilities.<key>.raw`.

4. **Emits *every* canonical capability key** — `{"supported": false}` for
   unmeasured. Absence of a key is treated as schema drift, not silence.

5. **Validates its output** against the canonical schema before writing.
   This catches schema drift early. (Use `validate.py` or the lib's local
   JSON-schema validator.)

6. **Writes** the result to a path under `results/<run_id>/<lib>.json`
   (or wherever the runner instructs). Standard layout:

   ```
   results/
     <run_id>/
       envelope.json                    ← from runner.py
       termicap.json                    ← from termicap shim
       termenv.json                     ← from termenv shim
       supports-color-rust.json         ← from supports-color shim
       ...
   ```

## What a shim must NOT do

- Mutate the env, terminal state, or TTY mode (no `SetConsoleMode`,
  no terminal resize, no ENABLE_VIRTUAL_TERMINAL_PROCESSING toggle).
- Print to stdout (it may be a TTY; the lib under test reads it).
  Use stderr for diagnostics; write the result JSON to a file.
- Crash on detection failure. Catch, report as
  `{"supported": false, "raw": {"error": "..."}}`, continue.
- Read `process.argv` for caller-provided detection state. The envelope is
  the only source of session state.

## Layout

```
shims/
├── README.md                           ← this file
├── ada/
│   └── termicap/                       ← Alire crate; Ada main writes JSON
├── rust/
│   ├── supports-color/                 ← Cargo crate
│   ├── termcolor/
│   ├── termbg/
│   └── crossterm/
├── go/
│   ├── termenv/                        ← Go module
│   ├── go-isatty/
│   └── tcell/
├── node/
│   ├── supports-color/                 ← npm package
│   ├── is-unicode-supported/
│   └── terminal-size/
└── python/
    └── rich/
```

Each shim subdirectory is a standalone, buildable, runnable project in its
host language. The harness invokes them via:

```bash
CONFORMANCE_ENVELOPE=envelope.json ./shims/<lang>/<lib>/run
```

The `run` script (or compiled binary) is the shim entrypoint. It writes the
result JSON path to its first positional arg, defaulting to
`./<lib>.json` if absent.

## Skeleton (Python — for libs that have a Python binding)

```python
#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

ENVELOPE = json.loads(Path(os.environ["CONFORMANCE_ENVELOPE"]).read_text())
RESULT_PATH = Path(sys.argv[1] if len(sys.argv) > 1 else "result.json")

# 1. import + call the lib
import the_lib
detected = the_lib.detect()

# 2. Build the capabilities dict — every key always present.
caps = {
    "tty_stdin":  {"supported": False},
    "tty_stdout": {"supported": True, "value": sys.stdout.isatty(), "method": "isatty"},
    "tty_stderr": {"supported": False},
    "color_depth": {
        "supported": True,
        "value": map_color(detected.color_level),
        "method": detected.method_str,
        "raw": detected.raw_dict,
    },
    # ... every other canonical key, supported:false where not measured
}

# 3. Assemble + write
result = {
    "schema_version": "0.1.0",
    "run": ENVELOPE,                       # verbatim
    "lib": {
        "name": "the_lib",
        "version": the_lib.__version__,
        "language": "python",
        "tier": "passive",
    },
    "capabilities": caps,
}
RESULT_PATH.write_text(json.dumps(result, indent=2) + "\n")
```

## Skeleton (Rust — for native crates)

For Rust crates, the shim is a small Cargo project with the lib as a
dependency:

```rust
// shims/rust/supports-color/src/main.rs
fn main() -> anyhow::Result<()> {
    let envelope: serde_json::Value =
        serde_json::from_reader(std::fs::File::open(std::env::var("CONFORMANCE_ENVELOPE")?)?)?;
    let result_path = std::env::args().nth(1).unwrap_or_else(|| "result.json".into());

    let level = supports_color::on(supports_color::Stream::Stdout);
    let (color_value, raw) = match level {
        Some(c) if c.has_16m  => ("truecolor", serde_json::json!({"level": 3, "has_basic": true, "has_256": true, "has_16m": true})),
        Some(c) if c.has_256  => ("ansi256",   serde_json::json!({"level": 2, "has_basic": true, "has_256": true, "has_16m": false})),
        Some(c) if c.has_basic=> ("ansi16",    serde_json::json!({"level": 1, "has_basic": true, "has_256": false, "has_16m": false})),
        _                     => ("none",      serde_json::json!({"level": 0})),
    };

    let result = serde_json::json!({
        "schema_version": "0.1.0",
        "run": envelope,
        "lib": {
            "name": "supports-color-rust",
            "version": env!("CARGO_PKG_VERSION_OF_DEP_supports-color"),
            "language": "rust",
            "tier": "passive"
        },
        "capabilities": {
            // ... every canonical key
        }
    });

    std::fs::write(result_path, serde_json::to_string_pretty(&result)?)?;
    Ok(())
}
```

(The constant `CARGO_PKG_VERSION_OF_DEP_*` is illustrative; in practice the
shim looks up the dependency version via `cargo_metadata` or hardcodes it.)

## Skeleton (Ada — for termicap itself)

For termicap, the shim lives at `shims/ada/termicap/` as an Alire crate that
depends on `termicap` and a JSON library (likely `gnatcoll-core`'s
`GNATCOLL.JSON`). The Ada main reads `$CONFORMANCE_ENVELOPE`, calls
`Termicap.Capabilities.Detect_Full`, builds a JSON_Value, and writes it.

This is non-trivial (~150–200 lines) but mechanical. It will be the first
real shim because termicap is the lib we most want to compare.

## Adding a new shim

1. Pick a directory: `shims/<lang>/<lib>/`.
2. Write the smallest possible driver that calls the lib once per
   capability and emits canonical JSON.
3. Add a section in `notes/03-mapping.md` describing the native→canonical
   mapping. If the mapping is lossy, stash the native value in `raw`.
4. Validate against the schema:
   `python3 ../../validate.py result.json`
5. Add the shim to the runner manifest (TBD).

If you find a capability the canonical schema doesn't model (e.g. a new
DECRPM probe), open a discussion before adding a key — schema bumps are
the only thing that change shim contracts.
