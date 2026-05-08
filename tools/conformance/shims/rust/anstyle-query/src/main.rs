// Conformance shim for the `anstyle-query` Rust crate (Cargo's own
// terminal capability probe).
//
// anstyle-query exposes a set of small predicates rather than a single
// "level" function. We compose them into the canonical color_depth:
//
//   no_color()                    -> "none"
//   !term_supports_color()
//        AND !clicolor_force()    -> "none"
//   truecolor()                   -> "truecolor"
//   term_supports_ansi_color()    -> "ansi16"  (lib has no 256 signal)
//   else                          -> "none"
//
// The lib has no concept of a 256-color level (it's a binary
// has-ANSI-or-not + a separate truecolor predicate), so this shim
// never emits "ansi256". That's a documented mapping limitation.

use serde_json::json;
use std::env;
use std::fs;
use std::io::Write;
use std::path::PathBuf;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "anstyle-query";
const LIB_VERSION: &str = "1.1.5";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "anstyle-query.json".into())
        .into();

    let no_color = anstyle_query::no_color();
    let clicolor = anstyle_query::clicolor();
    let clicolor_force = anstyle_query::clicolor_force();
    let term_color = anstyle_query::term_supports_color();
    let term_ansi  = anstyle_query::term_supports_ansi_color();
    let truecolor  = anstyle_query::truecolor();
    let is_ci      = anstyle_query::is_ci();

    let color_value = if no_color {
        "none"
    } else if !term_color && !clicolor_force {
        "none"
    } else if truecolor {
        "truecolor"
    } else if term_ansi {
        "ansi16"
    } else {
        "none"
    };

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
                "method": "anstyle_query cascade (no_color/clicolor*/term_supports_color/truecolor)",
                "raw": {
                    "no_color": no_color,
                    "clicolor": clicolor,
                    "clicolor_force": clicolor_force,
                    "term_supports_color": term_color,
                    "term_supports_ansi_color": term_ansi,
                    "truecolor": truecolor
                }
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
                "value": is_ci,
                "method": "anstyle_query::is_ci()"
            }
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;
    eprintln!("anstyle-query-shim: wrote {} (color_depth={})",
              output_path.display(), color_value);
    Ok(())
}
