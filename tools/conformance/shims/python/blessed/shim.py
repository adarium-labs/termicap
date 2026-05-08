#!/usr/bin/env python3
"""Conformance shim for the `blessed` Python library.

Public detection surface used here:
    Terminal()
    term.get_software_version(timeout)   -> SoftwareVersion(name, version) | None  (XTVERSION CSI > q)
    term.get_device_attributes(timeout)  -> DeviceAttribute(service_class, extensions) | None  (DA1 CSI c)
    term.does_kitty_graphics(timeout)    -> bool                                     (Kitty graphics APC probe)
    term.does_mouse(*, report_pixels)    -> bool                                     (DECRQM 1006 + 1000 [+1016])
    term.get_bgcolor(bits=8, timeout)    -> (r,g,b)  with (-1,-1,-1) on no response  (OSC 11)
    term.get_kitty_keyboard_state(t)     -> KittyKeyboardProtocol | None             (CSI ? u)
    term.get_iterm2_capabilities(t)      -> ITerm2Capabilities | None                (OSC 1337;Capabilities)

Capability mapping:
    xtversion       : SoftwareVersion -> {name, version}
    da1_attributes  : DA1 'extensions' set, sorted ascending (service_class kept in raw)
    graphics_sixel  : DA1 ext 4 (matches blessed.Terminal.does_sixel)
    graphics_kitty  : APC G probe with i=31,a=q sentinel; supported iff response contains "OK"
    background      : OSC 11 -> [r,g,b] 0-255 (8-bit)
    theme           : ITU-R BT.601 luminance over background -> 'light' | 'dark'
    mouse           : does_mouse(report_pixels=True) -> 'sgr_pixels'; else does_mouse() -> 'sgr';
                      else not_measured (blessed never probes x10/urxvt; "none" would be unsafe)
    keyboard        : get_kitty_keyboard_state present -> 'kitty'; else not_measured
                      (blessed has no public XTerm modifyOtherKeys probe -> can't claim 'xterm_csi')
    terminal_kind   : XTVERSION name mapped to canonical enum; iTerm2 capabilities probe as fallback;
                      else not_measured

All probes return None / sentinel on non-TTY before writing any sequences (blessed lib-level guard).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Optional

from importlib.metadata import version as _pkg_version

from blessed import Terminal

SCHEMA_VERSION = "0.1.0"
LIB_NAME = "blessed"
LIB_VERSION = _pkg_version("blessed")
LIB_LANGUAGE = "python"
LIB_TIER = "active"

PROBE_TIMEOUT_SECONDS = 1.0


# XTVERSION name -> canonical terminal_kind enum.
# blessed reports the name token verbatim from the DCS reply. We lower-case for matching.
_XTVERSION_NAME_MAP = {
    "kitty": "kitty",
    "ghostty": "ghostty",
    "wezterm": "wezterm",
    "alacritty": "alacritty",
    "foot": "foot",
    "xterm": "xterm",
    "konsole": "konsole",
    "vte": "vte",
    "iterm2": "iterm2",
    "iterm.app": "iterm2",
    "mintty": "mintty",
    "rxvt": "rxvt",
    "warp": "warp",
}


def _xtversion_cap(term: Terminal) -> tuple[dict, Optional[str]]:
    """Return (xtversion_cap, raw_name)."""
    if not term.is_a_tty:
        return ({"supported": False, "raw": "not a tty"}, None)
    sv = term.get_software_version(timeout=PROBE_TIMEOUT_SECONDS)
    if sv is None:
        return (
            {"supported": False, "raw": "no XTVERSION response within timeout"},
            None,
        )
    return (
        {
            "supported": True,
            "value": {"name": sv.name or "", "version": sv.version or ""},
            "method": "blessed.Terminal.get_software_version (XTVERSION CSI > q)",
            "raw": {"raw_response": sv.raw},
        },
        sv.name,
    )


def _da1_caps(term: Terminal) -> tuple[dict, dict]:
    """Return (da1_attributes_cap, graphics_sixel_cap)."""
    if not term.is_a_tty:
        not_measured = {"supported": False, "raw": "not a tty"}
        return (not_measured, not_measured)
    da = term.get_device_attributes(timeout=PROBE_TIMEOUT_SECONDS)
    if da is None:
        not_measured = {"supported": False, "raw": "no DA1 response within timeout"}
        return (not_measured, not_measured)

    extensions_sorted = sorted(da.extensions)
    da1_cap = {
        "supported": True,
        "value": extensions_sorted,
        "method": "blessed.Terminal.get_device_attributes (DA1 CSI c)",
        "raw": {"service_class": da.service_class, "raw_response": da.raw},
    }
    sixel_cap = {
        "supported": True,
        "value": bool(da.supports_sixel),
        "method": "blessed DeviceAttribute.supports_sixel (DA1 ext 4)",
        "raw": {"service_class": da.service_class},
    }
    return (da1_cap, sixel_cap)


def _kitty_graphics_cap(term: Terminal) -> dict:
    if not term.is_a_tty:
        return {"supported": False, "raw": "not a tty"}
    supported = bool(term.does_kitty_graphics(timeout=PROBE_TIMEOUT_SECONDS))
    return {
        "supported": True,
        "value": supported,
        "method": "blessed.Terminal.does_kitty_graphics (APC Gi=31,a=q probe; OK response)",
    }


def _background_and_theme_caps(term: Terminal) -> tuple[dict, dict]:
    """Return (background_cap, theme_cap)."""
    if not term.is_a_tty:
        not_measured = {"supported": False, "raw": "not a tty"}
        return (not_measured, not_measured)
    rgb = term.get_bgcolor(timeout=PROBE_TIMEOUT_SECONDS, bits=8)
    if rgb == (-1, -1, -1):
        not_measured = {"supported": False, "raw": "no OSC 11 response within timeout"}
        return (not_measured, not_measured)

    r, g, b = (int(c) & 0xFF for c in rgb)
    bg_cap = {
        "supported": True,
        "value": {"rgb": [r, g, b]},
        "method": "blessed.Terminal.get_bgcolor (OSC 11)",
    }
    # ITU-R BT.601 luminance, same threshold (Y > 128 -> light) as termbg/termenv.
    luminance = 0.299 * r + 0.587 * g + 0.114 * b
    theme_cap = {
        "supported": True,
        "value": "light" if luminance > 128.0 else "dark",
        "method": "ITU-R BT.601 luminance over OSC 11 (>128 -> light)",
        "raw": {"luminance": round(luminance, 2)},
    }
    return (bg_cap, theme_cap)


def _mouse_cap(term: Terminal) -> dict:
    if not term.is_a_tty:
        return {"supported": False, "raw": "not a tty"}
    # Try richest first; blessed caches DEC mode replies internally.
    try:
        if term.does_mouse(report_pixels=True, timeout=PROBE_TIMEOUT_SECONDS):
            return {
                "supported": True,
                "value": "sgr_pixels",
                "method": "blessed.Terminal.does_mouse(report_pixels=True) (DECRQM 1006+1000+1016)",
            }
        if term.does_mouse(timeout=PROBE_TIMEOUT_SECONDS):
            return {
                "supported": True,
                "value": "sgr",
                "method": "blessed.Terminal.does_mouse() (DECRQM 1006+1000)",
            }
    except Exception as exc:  # pragma: no cover - defensive
        return {"supported": False, "raw": f"does_mouse raised: {exc!r}"}
    # blessed doesn't probe x10/urxvt, so we can't safely emit 'none' — withhold.
    return {"supported": False, "raw": "SGR family DECRQM 1006/1000 not supported; x10/urxvt not probed"}


def _keyboard_cap(term: Terminal) -> dict:
    if not term.is_a_tty:
        return {"supported": False, "raw": "not a tty"}
    state = term.get_kitty_keyboard_state(timeout=PROBE_TIMEOUT_SECONDS)
    if state is None:
        return {
            "supported": False,
            "raw": "no Kitty keyboard protocol response (xterm_csi/legacy not probed by blessed)",
        }
    flags = getattr(state, "flags", None)
    return {
        "supported": True,
        "value": "kitty",
        "method": "blessed.Terminal.get_kitty_keyboard_state (CSI ? u progressive enhancement query)",
        "raw": {"flags": flags},
    }


def _terminal_kind_cap(term: Terminal, xtversion_name: Optional[str]) -> dict:
    if not term.is_a_tty:
        return {"supported": False, "raw": "not a tty"}

    if xtversion_name:
        canonical = _XTVERSION_NAME_MAP.get(xtversion_name.strip().lower())
        if canonical:
            return {
                "supported": True,
                "value": canonical,
                "method": "XTVERSION name token mapped to canonical enum",
                "raw": {"xtversion_name": xtversion_name},
            }

    iterm = term.get_iterm2_capabilities(timeout=PROBE_TIMEOUT_SECONDS)
    if iterm is not None and iterm.supported:
        return {
            "supported": True,
            "value": "iterm2",
            "method": "blessed.Terminal.get_iterm2_capabilities (OSC 1337;Capabilities)",
        }

    return {
        "supported": False,
        "raw": (f"XTVERSION name {xtversion_name!r} not in canonical map; iTerm2 probe negative"
                if xtversion_name else "no XTVERSION response; iTerm2 probe negative"),
    }


def main() -> int:
    envelope_path = os.environ.get("CONFORMANCE_ENVELOPE")
    if not envelope_path:
        print("blessed-shim: $CONFORMANCE_ENVELOPE not set", file=sys.stderr)
        return 2
    envelope = json.loads(Path(envelope_path).read_text())

    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("blessed.json")

    term = Terminal()

    xtversion_cap, xtversion_name = _xtversion_cap(term)
    da1_cap, sixel_cap = _da1_caps(term)
    kitty_cap = _kitty_graphics_cap(term)
    bg_cap, theme_cap = _background_and_theme_caps(term)
    mouse_cap = _mouse_cap(term)
    kb_cap = _keyboard_cap(term)
    kind_cap = _terminal_kind_cap(term, xtversion_name)

    result = {
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {
            "name": LIB_NAME,
            "version": LIB_VERSION,
            "language": LIB_LANGUAGE,
            "tier": LIB_TIER,
        },
        "capabilities": {
            "tty_stdin": {"supported": False},
            "tty_stdout": {"supported": False},
            "tty_stderr": {"supported": False},
            "color_depth": {"supported": False},
            "windows_console_color": {"supported": False},
            "dimensions": {"supported": False},
            "unicode": {"supported": False},
            "terminal_kind": kind_cap,
            "multiplexer": {"supported": False},
            "theme": theme_cap,
            "background": bg_cap,
            "hyperlinks": {"supported": False},
            "mouse": mouse_cap,
            "keyboard": kb_cap,
            "clipboard_osc52": {"supported": False},
            "graphics_sixel": sixel_cap,
            "graphics_kitty": kitty_cap,
            "xtversion": xtversion_cap,
            "da1_attributes": da1_cap,
            "ci_detected": {"supported": False},
        },
    }

    output_path.write_text(json.dumps(result, indent=2) + "\n")

    def _val(cap: dict) -> str:
        return repr(cap.get("value")) if cap.get("supported") else "n/a"

    print(
        "blessed-shim: wrote {} (xtversion={} da1={} sixel={} kitty={} bg={} theme={} mouse={} kb={} kind={})".format(
            output_path,
            _val(xtversion_cap), _val(da1_cap), _val(sixel_cap), _val(kitty_cap),
            _val(bg_cap), _val(theme_cap), _val(mouse_cap), _val(kb_cap), _val(kind_cap),
        ),
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
