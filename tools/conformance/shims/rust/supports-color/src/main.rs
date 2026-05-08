// Conformance shim for the `supports-color` Rust crate.
//
// Reads the conformance envelope from $CONFORMANCE_ENVELOPE, calls
// supports_color::on(Stream::Stdout), maps the result to the canonical
// schema vocabulary, and writes one JSON document conforming to
// tools/conformance/schema/canonical.schema.json.
//
// Output path: argv[1], default "supports-color.json".

use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use supports_color::Stream;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "supports-color-rust";
const LIB_VERSION: &str = "3.0.2";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE").map_err(|_| {
        "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string()
    })?;
    let envelope: Value = serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "supports-color.json".into())
        .into();

    // ---- Detection -----------------------------------------------------
    let stdout_level = supports_color::on(Stream::Stdout);

    let (color_value, color_raw) = match stdout_level {
        None => (
            "none",
            json!({"level": 0, "has_basic": false, "has_256": false, "has_16m": false}),
        ),
        Some(c) if c.has_16m => (
            "truecolor",
            json!({"level": 3, "has_basic": c.has_basic, "has_256": c.has_256, "has_16m": c.has_16m}),
        ),
        Some(c) if c.has_256 => (
            "ansi256",
            json!({"level": 2, "has_basic": c.has_basic, "has_256": c.has_256, "has_16m": c.has_16m}),
        ),
        Some(c) => (
            "ansi16",
            json!({"level": 1, "has_basic": c.has_basic, "has_256": c.has_256, "has_16m": c.has_16m}),
        ),
    };

    // supports-color reads CI internally via the is_ci crate. We replicate
    // the env-var allowlist scan here ourselves and tag the method
    // accordingly (the lib does not expose this as a public capability).
    let ci_detected = ["CI", "GITHUB_ACTIONS", "GITLAB_CI", "CIRCLECI",
                        "TRAVIS", "BUILDKITE", "APPVEYOR", "TF_BUILD"]
        .iter()
        .any(|k| env::var(k).is_ok());

    // ---- Result --------------------------------------------------------
    let result = json!({
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {
            "name": LIB_NAME,
            "version": LIB_VERSION,
            "language": "rust",
            "tier": "passive"
        },
        "capabilities": {
            "tty_stdin":              {"supported": false},
            "tty_stdout":             {"supported": false},
            "tty_stderr":             {"supported": false},
            "color_depth": {
                "supported": true,
                "value": color_value,
                "method": "supports_color::on(Stream::Stdout) -> level mapping",
                "raw": color_raw
            },
            "windows_console_color":  {"supported": false},
            "dimensions":             {"supported": false},
            "unicode":                {"supported": false},
            "terminal_kind":          {"supported": false},
            "multiplexer":            {"supported": false},
            "theme":                  {"supported": false},
            "background":             {"supported": false},
            "hyperlinks":             {"supported": false},
            "mouse":                  {"supported": false},
            "keyboard":               {"supported": false},
            "clipboard_osc52":        {"supported": false},
            "graphics_sixel":         {"supported": false},
            "graphics_kitty":         {"supported": false},
            "xtversion":              {"supported": false},
            "da1_attributes":         {"supported": false},
            "ci_detected": {
                "supported": true,
                "value": ci_detected,
                "method": "shim-side env-var allowlist scan (mirrors is_ci internal logic)"
            }
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;
    eprintln!(
        "supports-color-shim: wrote {} (color_depth={})",
        output_path.display(),
        color_value
    );
    Ok(())
}
