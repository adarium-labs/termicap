// Conformance shim for `viuer` (Rust image viewer).
//
// Detection algorithm differs from termicap/blessed:
//   - get_kitty_support()    -> active probe via `\x1b_Gi=31,a=q...` (similar to blessed)
//                               returns None / Local / Remote (Local = same host, file-share works).
//   - is_iterm_supported()   -> TERM/TERM_PROGRAM env-var allowlist
//   - is_sixel_supported()   -> DA1 probe (CSI c) checking for Ps=4 in extensions
//
// We map Local + Remote -> graphics_kitty=true, None -> false. The Local/Remote
// distinction is preserved in `raw` for cross-host comparison.
//
// terminal_kind: viuer's iterm probe is positive evidence; we emit "iterm2" when true.

use serde_json::json;
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

use viuer::KittySupport;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "viuer";
const LIB_VERSION: &str = "0.11.0";

fn kitty_cap_value() -> (bool, &'static str) {
    match viuer::get_kitty_support() {
        KittySupport::None => (false, "None"),
        KittySupport::Local => (true, "Local"),
        KittySupport::Remote => (true, "Remote"),
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "viuer.json".into())
        .into();

    let (kitty_supported, kitty_raw) = kitty_cap_value();
    let iterm_supported = viuer::is_iterm_supported();
    let sixel_supported = viuer::is_sixel_supported();

    let kitty_cap = json!({
        "supported": true,
        "value": kitty_supported,
        "method": "viuer::get_kitty_support (active APC G probe; KittySupport enum)",
        "raw": { "kitty_support": kitty_raw }
    });
    let sixel_cap = json!({
        "supported": true,
        "value": sixel_supported,
        "method": "viuer::is_sixel_supported (DA1 CSI c probe checking Ps=4)",
    });
    let kind_cap = if iterm_supported {
        json!({
            "supported": true,
            "value": "iterm2",
            "method": "viuer::is_iterm_supported (TERM/TERM_PROGRAM allowlist)"
        })
    } else {
        json!({
            "supported": false,
            "raw": "viuer::is_iterm_supported returned false; viuer does not classify other terminals"
        })
    };

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
            "tty_stdin":  {"supported": false},
            "tty_stdout": {"supported": false},
            "tty_stderr": {"supported": false},
            "color_depth":           {"supported": false},
            "windows_console_color": {"supported": false},
            "dimensions":            {"supported": false},
            "unicode":               {"supported": false},
            "terminal_kind":         kind_cap,
            "multiplexer":           {"supported": false},
            "theme":                 {"supported": false},
            "background":            {"supported": false},
            "hyperlinks":            {"supported": false},
            "mouse":                 {"supported": false},
            "keyboard":              {"supported": false},
            "clipboard_osc52":       {"supported": false},
            "graphics_sixel":        sixel_cap,
            "graphics_kitty":        kitty_cap,
            "xtversion":             {"supported": false},
            "da1_attributes":        {"supported": false},
            "ci_detected":           {"supported": false},
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;

    eprintln!(
        "viuer-shim: wrote {} (kitty={}({}) sixel={} iterm2={})",
        output_path.display(), kitty_supported, kitty_raw, sixel_supported, iterm_supported
    );
    Ok(())
}
