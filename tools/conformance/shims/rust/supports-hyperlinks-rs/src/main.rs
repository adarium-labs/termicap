// Conformance shim for the `supports-hyperlinks` Rust crate.
//
// Rust port of the Node `supports-hyperlinks` lib (already integrated as the
// `supports-hyperlinks` shim). Same TERM_PROGRAM allowlist + version-check
// logic; running both detects port-drift between the Node and Rust ports.
//
// Public API:
//   supports_hyperlinks::supports_hyperlinks() -> bool   (stdout)
//   supports_hyperlinks::on(Stream) -> bool              (Stdout/Stderr)

use serde_json::json;
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

use supports_hyperlinks::Stream;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "supports-hyperlinks-rs";
const LIB_VERSION: &str = "3.2.0";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "supports-hyperlinks-rs.json".into())
        .into();

    let stdout_supported = supports_hyperlinks::on(Stream::Stdout);
    let stderr_supported = supports_hyperlinks::on(Stream::Stderr);

    // Map binary stdout support to canonical 'supported' / 'unsupported' (no
    // 'likely_supported' / 'unknown' values from this lib; matches the Node
    // sibling shim's mapping).
    let value = if stdout_supported { "supported" } else { "unsupported" };

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
            "tty_stdin":  {"supported": false},
            "tty_stdout": {"supported": false},
            "tty_stderr": {"supported": false},
            "color_depth":           {"supported": false},
            "windows_console_color": {"supported": false},
            "dimensions":            {"supported": false},
            "unicode":                {"supported": false},
            "terminal_kind":          {"supported": false},
            "multiplexer":            {"supported": false},
            "theme":                  {"supported": false},
            "background":             {"supported": false},
            "hyperlinks": {
                "supported": true,
                "value": value,
                "method": "supports_hyperlinks::on(Stream::Stdout) (Rust port of Node supports-hyperlinks)",
                "raw": { "stderr_supported": stderr_supported }
            },
            "mouse":                 {"supported": false},
            "keyboard":              {"supported": false},
            "clipboard_osc52":       {"supported": false},
            "graphics_sixel":        {"supported": false},
            "graphics_kitty":        {"supported": false},
            "xtversion":             {"supported": false},
            "da1_attributes":        {"supported": false},
            "ci_detected":           {"supported": false},
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;

    eprintln!(
        "supports-hyperlinks-rs-shim: wrote {} (stdout={} stderr={})",
        output_path.display(), stdout_supported, stderr_supported
    );
    Ok(())
}
