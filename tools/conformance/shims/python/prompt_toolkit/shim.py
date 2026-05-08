#!/usr/bin/env python3
"""Conformance shim for `prompt_toolkit` (Python).

prompt_toolkit's Output abstraction does TTY detection + color-depth + size
+ encoding internally for its own rendering. Public surface used here:

    from prompt_toolkit.output.defaults import create_output
    out = create_output(stdout=sys.stdout)
    out.get_default_color_depth()  -> ColorDepth.DEPTH_{1,4,8,24}_BIT
    out.get_size()                 -> Size(rows, columns)
    out.encoding()                 -> str
    type(out).__name__             -> 'PlainTextOutput' when no TTY, vt100/win32 otherwise

Capability mapping:
    color_depth : 1bit -> none; 4bit -> ansi16; 8bit -> ansi256; 24bit -> truecolor
    dimensions  : Size -> {cols, rows}
    unicode     : utf-* -> extended; ascii -> none; otherwise -> not_measured
    tty_stdout  : type(out) != PlainTextOutput
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from importlib.metadata import version as _pkg_version

from prompt_toolkit.output.color_depth import ColorDepth
from prompt_toolkit.output.defaults import create_output

SCHEMA_VERSION = "0.1.0"
LIB_NAME = "prompt_toolkit"
LIB_VERSION = _pkg_version("prompt_toolkit")
LIB_LANGUAGE = "python"
LIB_TIER = "passive"


_COLOR_DEPTH_MAP = {
    ColorDepth.DEPTH_1_BIT:  ("none",      "DEPTH_1_BIT (monochrome)"),
    ColorDepth.DEPTH_4_BIT:  ("ansi16",    "DEPTH_4_BIT (16 colors)"),
    ColorDepth.DEPTH_8_BIT:  ("ansi256",   "DEPTH_8_BIT (256 colors)"),
    ColorDepth.DEPTH_24_BIT: ("truecolor", "DEPTH_24_BIT (truecolor)"),
}


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
        print("prompt_toolkit-shim: $CONFORMANCE_ENVELOPE not set", file=sys.stderr)
        return 2
    envelope = json.loads(Path(envelope_path).read_text())
    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("prompt_toolkit.json")

    out = create_output(stdout=sys.stdout)
    is_tty_output = type(out).__name__ != "PlainTextOutput"

    depth = out.get_default_color_depth()
    if depth in _COLOR_DEPTH_MAP:
        color_value, color_raw = _COLOR_DEPTH_MAP[depth]
        color_cap = {
            "supported": True,
            "value": color_value,
            "method": "prompt_toolkit.output.create_output -> get_default_color_depth (env+TTY heuristic)",
            "raw": {"depth": color_raw, "output_class": type(out).__name__},
        }
    else:
        color_cap = {"supported": False, "raw": f"unknown depth: {depth!r}"}

    encoding = out.encoding()
    unicode_value = _encoding_to_unicode(encoding)
    unicode_cap = (
        {"supported": True, "value": unicode_value,
         "method": "prompt_toolkit Output.encoding() -> canonical (utf-* -> extended; ascii -> none)",
         "raw": {"encoding": encoding}}
        if unicode_value is not None
        else {"supported": False, "raw": {"encoding": encoding}}
    )

    size = out.get_size()
    dim_cap = {
        "supported": True,
        "value": {
            "cols": int(size.columns),
            "rows": int(size.rows),
            "pixel_width": 0,
            "pixel_height": 0,
        },
        "method": "prompt_toolkit Output.get_size() (TTY ioctl + 80x40 default)",
    }

    tty_cap = {
        "supported": True,
        "value": is_tty_output,
        "method": "prompt_toolkit create_output -> output class != PlainTextOutput",
        "raw": {"output_class": type(out).__name__},
    }

    result = {
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {"name": LIB_NAME, "version": LIB_VERSION, "language": LIB_LANGUAGE, "tier": LIB_TIER},
        "capabilities": {
            "tty_stdin":  {"supported": False},
            "tty_stdout": tty_cap,
            "tty_stderr": {"supported": False},
            "color_depth": color_cap,
            "windows_console_color": {"supported": False},
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
    print(
        f"prompt_toolkit-shim: wrote {output_path} (color={color_cap.get('value')} "
        f"unicode={unicode_value} cols={dim_cap['value']['cols']} tty_stdout={is_tty_output})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
