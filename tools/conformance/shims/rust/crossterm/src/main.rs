// Conformance shim for the `crossterm` Rust crate.
//
// crossterm public detection API:
//   crossterm::ansi_support::supports_ansi() -> bool       (binary, no levels)
//   crossterm::terminal::size() -> io::Result<(u16,u16)>   (cols, rows)
//   crossterm::terminal::window_size() -> io::Result<WindowSize>  (with pixels)
//   crossterm::terminal::supports_keyboard_enhancement() -> io::Result<bool>
//     (DCS active probe; Ok(true) implies Kitty Progressive Enhancement)
//
// The color_depth mapping is intentionally a binary floor: supports_ansi()
// only confirms ANSI-or-not, so we emit "ansi16" when true (the lower bound
// every ANSI-supporting terminal meets). This will diverge from libs that
// detect 256/truecolor on the same terminal — that is documented and
// expected; the report's `method` field flags it as "binary ANSI floor".

use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "crossterm";
const LIB_VERSION: &str = "0.29.0";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: Value = serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "crossterm.json".into())
        .into();

    // ---- color_depth (binary ANSI floor) --------------------------------
    // crossterm exposes supports_ansi() only on Windows (Win10+ VT enable
    // check). On other platforms the lib *assumes* ANSI support, so the
    // canonical floor is ansi16. Tag the method so the divergence with
    // depth-aware libs is interpretable.
    #[cfg(windows)]
    let supports_ansi = crossterm::ansi_support::supports_ansi();
    #[cfg(not(windows))]
    let supports_ansi: bool = true;

    let color_value = if supports_ansi { "ansi16" } else { "none" };
    #[cfg(windows)]
    let color_method = "crossterm::ansi_support::supports_ansi() (Win VT enable)";
    #[cfg(not(windows))]
    let color_method = "non-Windows: crossterm assumes ANSI; canonical floor=ansi16";
    let color_cap = json!({
        "supported": true,
        "value": color_value,
        "method": color_method,
        "raw": {"supports_ansi": supports_ansi}
    });

    // ---- dimensions ------------------------------------------------------
    let dim_cap = match crossterm::terminal::window_size() {
        Ok(ws) => json!({
            "supported": true,
            "value": {
                "cols": ws.columns as u32,
                "rows": ws.rows as u32,
                "pixel_width": ws.width as u32,
                "pixel_height": ws.height as u32
            },
            "method": "crossterm::terminal::window_size() (TIOCGWINSZ on Unix; WinAPI on Windows)"
        }),
        Err(e) => {
            // Fall back to size() which only returns cols/rows.
            match crossterm::terminal::size() {
                Ok((cols, rows)) => json!({
                    "supported": true,
                    "value": {"cols": cols as u32, "rows": rows as u32, "pixel_width": 0, "pixel_height": 0},
                    "method": "crossterm::terminal::size() (window_size unavailable)"
                }),
                Err(_) => json!({
                    "supported": false,
                    "raw": {"error": format!("{e}")}
                }),
            }
        }
    };

    // ---- keyboard --------------------------------------------------------
    // supports_keyboard_enhancement Ok(true) means Kitty progressive
    // enhancement was acknowledged. Ok(false) means the terminal answered
    // but doesn't support it -- we don't know whether it does xterm CSI or
    // legacy, so we leave the slot supported:false rather than guessing.
    let kbd_cap = match crossterm::terminal::supports_keyboard_enhancement() {
        Ok(true) => json!({
            "supported": true,
            "value": "kitty",
            "method": "crossterm::terminal::supports_keyboard_enhancement() -> Ok(true) (DCS probe)"
        }),
        Ok(false) => json!({
            "supported": false,
            "raw": {"supports_keyboard_enhancement": false, "note": "terminal answered probe but does not support Kitty enhancement; can't infer fallback protocol"}
        }),
        Err(e) => json!({
            "supported": false,
            "raw": {"error": format!("{e}")}
        }),
    };

    // ---- Result ---------------------------------------------------------
    let result = json!({
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {
            "name": LIB_NAME,
            "version": LIB_VERSION,
            "language": "rust",
            "tier": "mixed"
        },
        "capabilities": {
            "tty_stdin":              {"supported": false},
            "tty_stdout":             {"supported": false},
            "tty_stderr":             {"supported": false},
            "color_depth":            color_cap,
            "windows_console_color":  {"supported": false},
            "dimensions":             dim_cap,
            "unicode":                {"supported": false},
            "terminal_kind":          {"supported": false},
            "multiplexer":            {"supported": false},
            "theme":                  {"supported": false},
            "background":             {"supported": false},
            "hyperlinks":             {"supported": false},
            "mouse":                  {"supported": false},
            "keyboard":               kbd_cap,
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
    eprintln!(
        "crossterm-shim: wrote {} (color_depth={})",
        output_path.display(),
        color_value
    );
    Ok(())
}
