// Conformance shim using `xterm-query` (Rust).
//
// xterm-query is a low-level primitive that sends a CSI sequence and reads the
// terminal's reply, but it requires the terminal to already be in raw mode --
// otherwise the read() blocks until newline. This shim manages raw mode itself
// via the `termios` crate, then issues:
//
//   CSI > q  (XTVERSION) -> DCS >| <name> <version> ESC \
//   CSI c    (DA1)       -> CSI ? <class> ; <ext1> ; ... c
//
// Adds a third independent measurer for `xtversion` and `da1_attributes`
// (alongside termicap and blessed). The probe mechanism is direct stdio I/O
// rather than blessed's CPR-boundary guard or termicap's tagged dispatch
// layer -- divergence here would surface bugs in the primitive itself.

use serde_json::json;
use std::env;
use std::fs;
use std::io::{IsTerminal, Write};
use std::os::fd::AsRawFd;
use std::path::PathBuf;
use std::time::Duration;

use termios::*;

const SCHEMA_VERSION: &str = "0.1.0";
const LIB_NAME: &str = "xterm-query";
const LIB_VERSION: &str = "0.5.2";

const PROBE_TIMEOUT: Duration = Duration::from_millis(1000);

/// RAII guard that restores termios on drop.
struct RawGuard {
    fd: i32,
    saved: Termios,
}

impl RawGuard {
    fn enter() -> std::io::Result<Self> {
        let fd = std::io::stdin().as_raw_fd();
        let saved = Termios::from_fd(fd)?;
        let mut raw = saved;
        cfmakeraw(&mut raw);
        // Don't disable output processing — we still want \n -> \r\n on stdout.
        // cfmakeraw sets opost to 0; restore for stdout sanity.
        raw.c_oflag |= OPOST;
        tcsetattr(fd, TCSANOW, &raw)?;
        Ok(RawGuard { fd, saved })
    }
}

impl Drop for RawGuard {
    fn drop(&mut self) {
        let _ = tcsetattr(self.fd, TCSANOW, &self.saved);
    }
}

fn parse_xtversion(reply: &str) -> Option<(String, String)> {
    // Expected: ESC P > | NAME[ VERSION] ESC \\
    // xterm-query strips C0 ESC; reply may start with "P>|..." or contain it inline.
    let body = reply.trim_start_matches(|c: char| c == '\x1b' || c == 'P');
    let body = body.trim_start_matches('>').trim_start_matches('|');
    let body = body.trim_end_matches('\\').trim_end_matches('\x1b');
    let body = body.trim();
    if body.is_empty() {
        return None;
    }
    // Conventional split: name and version separated by space; version may be missing.
    if let Some((name, version)) = body.split_once(' ') {
        Some((name.to_string(), version.trim().to_string()))
    } else {
        Some((body.to_string(), String::new()))
    }
}

fn parse_da1(reply: &str) -> Option<(u32, Vec<u32>)> {
    // Expected: ESC [ ? <class> ; <ext1> ; ... c
    let body = reply.trim_start_matches(|c: char| c == '\x1b' || c == '[');
    let body = body.trim_start_matches('?');
    let body = body.trim_end_matches('c');
    let mut iter = body.split(';');
    let class: u32 = iter.next()?.trim().parse().ok()?;
    let extensions: Vec<u32> = iter
        .filter_map(|s| s.trim().parse().ok())
        .collect();
    Some((class, extensions))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let envelope_path = env::var("CONFORMANCE_ENVELOPE")
        .map_err(|_| "CONFORMANCE_ENVELOPE env var not set; run `runner.py` first".to_string())?;
    let envelope: serde_json::Value =
        serde_json::from_str(&fs::read_to_string(&envelope_path)?)?;

    let output_path: PathBuf = env::args()
        .nth(1)
        .unwrap_or_else(|| "xterm-query.json".into())
        .into();

    let mut xtversion_cap = json!({"supported": false, "raw": "not a tty"});
    let mut da1_cap       = json!({"supported": false, "raw": "not a tty"});
    let mut sixel_cap     = json!({"supported": false, "raw": "not a tty"});

    if std::io::stdin().is_terminal() && std::io::stdout().is_terminal() {
        let _guard = match RawGuard::enter() {
            Ok(g) => g,
            Err(e) => {
                eprintln!("xterm-query-shim: failed to enter raw mode: {}", e);
                std::process::exit(1);
            }
        };

        // XTVERSION
        match xterm_query::query("\x1b[>q", PROBE_TIMEOUT.as_millis() as u64) {
            Ok(reply) => match parse_xtversion(&reply) {
                Some((name, version)) => {
                    xtversion_cap = json!({
                        "supported": true,
                        "value": {"name": name, "version": version},
                        "method": "xterm_query::query(\"\\x1b[>q\") + DCS >| parsing",
                        "raw": {"raw_response": reply}
                    });
                }
                None => {
                    xtversion_cap = json!({
                        "supported": false,
                        "raw": format!("XTVERSION reply not parsable: {:?}", reply)
                    });
                }
            },
            Err(e) => {
                xtversion_cap = json!({
                    "supported": false,
                    "raw": format!("XTVERSION query failed: {}", e)
                });
            }
        }

        // DA1
        match xterm_query::query("\x1b[c", PROBE_TIMEOUT.as_millis() as u64) {
            Ok(reply) => match parse_da1(&reply) {
                Some((class, mut extensions)) => {
                    extensions.sort_unstable();
                    let supports_sixel = extensions.contains(&4);
                    da1_cap = json!({
                        "supported": true,
                        "value": extensions,
                        "method": "xterm_query::query(\"\\x1b[c\") + parameter parsing",
                        "raw": {"service_class": class, "raw_response": reply}
                    });
                    sixel_cap = json!({
                        "supported": true,
                        "value": supports_sixel,
                        "method": "DA1 ext 4 (sixel) check via xterm-query",
                        "raw": {"service_class": class}
                    });
                }
                None => {
                    da1_cap = json!({
                        "supported": false,
                        "raw": format!("DA1 reply not parsable: {:?}", reply)
                    });
                }
            },
            Err(e) => {
                da1_cap = json!({
                    "supported": false,
                    "raw": format!("DA1 query failed: {}", e)
                });
            }
        }
    }

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
            "unicode":                {"supported": false},
            "terminal_kind":          {"supported": false},
            "multiplexer":            {"supported": false},
            "theme":                  {"supported": false},
            "background":             {"supported": false},
            "hyperlinks":             {"supported": false},
            "mouse":                  {"supported": false},
            "keyboard":               {"supported": false},
            "clipboard_osc52":        {"supported": false},
            "graphics_sixel":         sixel_cap,
            "graphics_kitty":         {"supported": false},
            "xtversion":              xtversion_cap,
            "da1_attributes":         da1_cap,
            "ci_detected":            {"supported": false},
        }
    });

    let mut f = fs::File::create(&output_path)?;
    f.write_all(serde_json::to_string_pretty(&result)?.as_bytes())?;
    f.write_all(b"\n")?;

    eprintln!("xterm-query-shim: wrote {}", output_path.display());
    Ok(())
}
