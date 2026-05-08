// Conformance shim for the Rust standard library's std::io::IsTerminal trait
// (stable since Rust 1.70). Provides a third independent measurer for
// tty_stdin / tty_stdout / tty_stderr alongside go-isatty (Go) and
// termicap (Ada).
//
// IsTerminal::is_terminal calls isatty(3) on Unix and GetConsoleMode on
// Windows -- the same syscalls as go-isatty and termicap. Cross-language
// agreement here is the floor; any divergence indicates a platform-specific
// edge case (cygwin/msys, named pipes mistaken for ttys, etc.).

use serde_json::json;
use std::env;
use std::fs;
use std::io::{IsTerminal, Write};
use std::path::PathBuf;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "rust-std-isterminal";
const LIB_VERSION: &str = env!("CARGO_PKG_RUST_VERSION");

fn cap_bool(value: bool, method: &str) -> serde_json::Value {
    json!({
        "supported": true,
        "value": value,
        "method": method,
    })
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "isatty.json".into())
        .into();

    let stdin_tty = std::io::stdin().is_terminal();
    let stdout_tty = std::io::stdout().is_terminal();
    let stderr_tty = std::io::stderr().is_terminal();

    let result = json!({
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {
            "name": LIB_NAME,
            "version": LIB_VERSION,
            "language": "rust",
            "tier": "passive",
        },
        "capabilities": {
            "tty_stdin":  cap_bool(stdin_tty,  "std::io::stdin().is_terminal() (isatty / GetConsoleMode)"),
            "tty_stdout": cap_bool(stdout_tty, "std::io::stdout().is_terminal() (isatty / GetConsoleMode)"),
            "tty_stderr": cap_bool(stderr_tty, "std::io::stderr().is_terminal() (isatty / GetConsoleMode)"),
            "color_depth":           {"supported": false},
            "windows_console_color": {"supported": false},
            "dimensions":            {"supported": false},
            "unicode":               {"supported": false},
            "terminal_kind":         {"supported": false},
            "multiplexer":           {"supported": false},
            "theme":                 {"supported": false},
            "background":            {"supported": false},
            "hyperlinks":            {"supported": false},
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
        "isatty-shim: wrote {} (stdin={} stdout={} stderr={})",
        output_path.display(), stdin_tty, stdout_tty, stderr_tty
    );
    Ok(())
}
