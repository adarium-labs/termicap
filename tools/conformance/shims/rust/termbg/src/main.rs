// Conformance shim for the `termbg` Rust crate.
//
// termbg's public API:
//   termbg::terminal() -> Terminal       (Screen|Tmux|XtermCompatible|Windows|Emacs)
//   termbg::rgb(timeout) -> Result<Rgb>  (16-bit per channel)
//   termbg::theme(timeout) -> Result<Theme>
//
// We call `terminal()` always (no probing), then `rgb()` once with a short
// timeout. Theme is derived inline using the same ITU-R BT.601 formula
// termbg uses internally, to avoid a second probe.

use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::time::Duration;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "termbg";
const LIB_VERSION: &str = "0.6.2";
const PROBE_TIMEOUT_MS: u64 = 100;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: Value = serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "termbg.json".into())
        .into();

    // ---- Terminal classification (no probing) -----------------------------
    let term = termbg::terminal();
    // termbg's Terminal enum mixes terminal types and multiplexers. Split:
    let (terminal_kind, multiplexer): (Option<&str>, Option<&str>) = match term {
        termbg::Terminal::Screen => (None, Some("screen")),
        termbg::Terminal::Tmux => (None, Some("tmux")),
        termbg::Terminal::XtermCompatible => (Some("xterm"), Some("none")),
        termbg::Terminal::Windows => (Some("windows_terminal"), Some("none")),
        termbg::Terminal::Emacs => (Some("other"), Some("none")),
    };
    let term_raw = format!("{:?}", term);

    // ---- Active probing for background color + theme ----------------------
    let mut bg_cap = json!({"supported": false});
    let mut theme_cap = json!({"supported": false});

    match termbg::rgb(Duration::from_millis(PROBE_TIMEOUT_MS)) {
        Ok(rgb) => {
            // termbg returns 16-bit per channel; downconvert to 8-bit.
            let r8 = (rgb.r >> 8) as u32;
            let g8 = (rgb.g >> 8) as u32;
            let b8 = (rgb.b >> 8) as u32;
            bg_cap = json!({
                "supported": true,
                "value": {"rgb": [r8, g8, b8]},
                "method": "termbg::rgb (OSC 11 probe; falls back to COLORFGBG / WinAPI)",
                "raw": {"r16": rgb.r, "g16": rgb.g, "b16": rgb.b}
            });
            // ITU-R BT.601 luminance, mirroring termbg's threshold (Y > 32768).
            let y = (rgb.r as f64) * 0.299
                  + (rgb.g as f64) * 0.587
                  + (rgb.b as f64) * 0.114;
            let theme_value = if y > 32768.0 { "light" } else { "dark" };
            theme_cap = json!({
                "supported": true,
                "value": theme_value,
                "method": "ITU-R BT.601 luminance derived from termbg::rgb (Y > 32768 -> light)"
            });
        }
        Err(e) => {
            bg_cap = json!({
                "supported": false,
                "raw": {"error": format!("{e}")}
            });
        }
    }

    // ---- terminal_kind / multiplexer caps --------------------------------
    let terminal_kind_cap = match terminal_kind {
        Some(v) => json!({
            "supported": true,
            "value": v,
            "method": "termbg::terminal() -> coarse terminal-class enum",
            "raw": term_raw.clone()
        }),
        None => json!({"supported": false, "raw": {"reason": format!("termbg classifies this as {term_raw} (multiplexer, not a terminal type)")}}),
    };
    let multiplexer_cap = match multiplexer {
        Some(v) => json!({
            "supported": true,
            "value": v,
            "method": "termbg::terminal() (Screen/Tmux variants)",
            "raw": term_raw
        }),
        None => json!({"supported": false}),
    };

    // ---- Result ----------------------------------------------------------
    let result = json!({
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {
            "name": LIB_NAME,
            "version": LIB_VERSION,
            "language": "rust",
            "tier": "active"
        },
        "capabilities": {
            "tty_stdin":              {"supported": false},
            "tty_stdout":             {"supported": false},
            "tty_stderr":             {"supported": false},
            "color_depth":            {"supported": false},
            "windows_console_color":  {"supported": false},
            "dimensions":             {"supported": false},
            "unicode":                {"supported": false},
            "terminal_kind":          terminal_kind_cap,
            "multiplexer":            multiplexer_cap,
            "theme":                  theme_cap,
            "background":             bg_cap,
            "hyperlinks":             {"supported": false},
            "mouse":                  {"supported": false},
            "keyboard":               {"supported": false},
            "clipboard_osc52":        {"supported": false},
            "graphics_sixel":         {"supported": false},
            "graphics_kitty":         {"supported": false},
            "xtversion":              {"supported": false},
            "da1_attributes":         {"supported": false},
            "ci_detected":            {"supported": false}
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;
    eprintln!("termbg-shim: wrote {}", output_path.display());
    Ok(())
}
