#!/usr/bin/env python3
"""Conformance shim for the `rich` Python library.

Public detection surface used here:
    Console()                       -> Console
    console.color_system            -> "standard" | "256" | "truecolor" | "windows" | None
    console.is_terminal             -> bool
    console.size                    -> ConsoleDimensions(width, height)
    console.encoding                -> str

Mapping notes:
    - color_system="windows" maps to (color_depth=ansi16, windows_console_color=true)
      so the canonical color_depth enum stays small.
    - encoding "utf-8" / "utf_8" maps to unicode=extended; ASCII to unicode=none.
      Anything else stays supported:false (no clean mapping).
    - is_terminal is exposed by rich as a single field; it does not
      distinguish stdin/stdout/stderr. We map it to tty_stdout only.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from importlib.metadata import version as _pkg_version

from rich.console import Console

SCHEMA_VERSION = "0.1.0"
LIB_NAME = "rich"
LIB_VERSION = _pkg_version("rich")
LIB_LANGUAGE = "python"
LIB_TIER = "mixed"  # rich uses Win VT API + env heuristics


def _color_to_canonical(color_system: str | None) -> tuple[str | None, bool, str | None]:
    """Return (canonical_value, windows_console_color, raw)."""
    if color_system is None:
        return ("none", False, None)
    cs = str(color_system).lower()
    if cs == "windows":
        return ("ansi16", True, "windows")
    if cs == "standard":
        return ("ansi16", False, "standard")
    if cs == "256":
        return ("ansi256", False, "256")
    if cs == "truecolor":
        return ("truecolor", False, "truecolor")
    return (None, False, cs)


def _encoding_to_unicode(encoding: str | None) -> str | None:
    if not encoding:
        return None
    e = encoding.lower().replace("_", "-")
    if e in {"utf-8", "utf-16", "utf-32"}:
        return "extended"
    if e in {"ascii", "us-ascii"}:
        return "none"
    return None


def main() -> int:
    envelope_path = os.environ.get("CONFORMANCE_ENVELOPE")
    if not envelope_path:
        print("rich-shim: $CONFORMANCE_ENVELOPE not set", file=sys.stderr)
        return 2
    envelope = json.loads(Path(envelope_path).read_text())

    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("rich.json")

    console = Console()

    color_value, win_console, color_raw = _color_to_canonical(console.color_system)
    color_cap = (
        {"supported": True, "value": color_value,
         "method": "rich.Console().color_system (env + Win VT API)",
         "raw": {"color_system": color_raw}}
        if color_value is not None
        else {"supported": False, "raw": {"color_system": color_raw}}
    )

    win_cap = {
        "supported": True,
        "value": win_console,
        "method": "rich.Console.color_system == 'windows' (Windows console API path)",
    }

    unicode_value = _encoding_to_unicode(console.encoding)
    unicode_cap = (
        {"supported": True, "value": unicode_value,
         "method": "rich.Console().encoding -> canonical (utf-* -> extended, ascii -> none)",
         "raw": {"encoding": console.encoding}}
        if unicode_value is not None
        else {"supported": False, "raw": {"encoding": console.encoding}}
    )

    tty_cap = {
        "supported": True,
        "value": console.is_terminal,
        "method": "rich.Console().is_terminal (TTY + Jupyter + IDLE + FORCE_COLOR/TTY_COMPATIBLE overrides)",
    }

    dim_cap = {
        "supported": True,
        "value": {
            "cols": int(console.size.width),
            "rows": int(console.size.height),
            "pixel_width": 0,
            "pixel_height": 0,
        },
        "method": "rich.Console().size (TTY size; falls back to defaults)",
    }

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
            "tty_stdout": tty_cap,
            "tty_stderr": {"supported": False},
            "color_depth": color_cap,
            "windows_console_color": win_cap,
            "dimensions": dim_cap,
            "unicode": unicode_cap,
            "terminal_kind": {"supported": False},
            "multiplexer": {"supported": False},
            "theme": {"supported": False},
            "background": {"supported": False},
            "hyperlinks": {"supported": False},
            "mouse": {"supported": False},
            "keyboard": {"supported": False},
            "clipboard_osc52": {"supported": False},
            "graphics_sixel": {"supported": False},
            "graphics_kitty": {"supported": False},
            "xtversion": {"supported": False},
            "da1_attributes": {"supported": False},
            "ci_detected": {"supported": False},
        },
    }

    output_path.write_text(json.dumps(result, indent=2) + "\n")
    print(f"rich-shim: wrote {output_path} (color={color_value} unicode={unicode_value})",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
