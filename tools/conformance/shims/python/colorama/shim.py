#!/usr/bin/env python3
"""Conformance shim for `colorama` (Python).

colorama is primarily a Windows ANSI -> WinAPI translator. Its detection
surface is exposed via the AnsiToWin32 wrapper:

    AnsiToWin32(stream).convert
        True  -> stream is a Windows console without native VT support
                 (legacy console; colorama would intercept and call WinAPI).
        False -> either non-Windows, or Windows with native VT (Win10+
                 with VirtualTerminal mode, Windows Terminal, ConEmu, ...).

This is exactly the windows_console_color signal: 'is the current Windows
console using the legacy WinAPI color model rather than ANSI VT?'.

Mapping policy (cross-platform):
    Linux/macOS/BSD            : windows_console_color = supported:false
                                 (the capability is meaningless off Windows;
                                 reporting false would be misleading because
                                 'no Windows console' != 'a Windows console
                                 with native VT')
    Windows + convert==True    : windows_console_color = true   (legacy)
    Windows + convert==False   : windows_console_color = false  (native VT)

The 'supported:true value:false' branch on Windows pairs the rich shim's
'value:true on Windows console_system mapping' check, providing a *second
Windows-specific source*. On Unix the shim emits not_measured, which is
honest about the off-platform case.
"""

from __future__ import annotations

import json
import os
import platform
import sys
from pathlib import Path

from importlib.metadata import version as _pkg_version

import colorama  # noqa: F401 (load native bindings on Windows)
from colorama.ansitowin32 import AnsiToWin32

SCHEMA_VERSION = "0.1.0"
LIB_NAME = "colorama"
LIB_VERSION = _pkg_version("colorama")
LIB_LANGUAGE = "python"
LIB_TIER = "passive"


def _windows_console_cap() -> dict:
    system = platform.system()
    if system != "Windows":
        return {
            "supported": False,
            "raw": {
                "platform": system,
                "note": "colorama only measures Windows console mode; capability is platform-specific",
            },
        }
    a = AnsiToWin32(sys.__stdout__)
    legacy = bool(a.convert)
    return {
        "supported": True,
        "value": legacy,
        "method": "colorama AnsiToWin32(stdout).convert (legacy WinAPI conversion needed iff true)",
        "raw": {"convert": legacy, "strip": bool(a.strip), "platform": system},
    }


def main() -> int:
    envelope_path = os.environ.get("CONFORMANCE_ENVELOPE")
    if not envelope_path:
        print("colorama-shim: $CONFORMANCE_ENVELOPE not set", file=sys.stderr)
        return 2
    envelope = json.loads(Path(envelope_path).read_text())
    output_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("colorama.json")

    win_cap = _windows_console_cap()

    result = {
        "schema_version": SCHEMA_VERSION,
        "run": envelope,
        "lib": {"name": LIB_NAME, "version": LIB_VERSION, "language": LIB_LANGUAGE, "tier": LIB_TIER},
        "capabilities": {
            "tty_stdin":  {"supported": False},
            "tty_stdout": {"supported": False},
            "tty_stderr": {"supported": False},
            "color_depth": {"supported": False},
            "windows_console_color": win_cap,
            "dimensions": {"supported": False},
            "unicode": {"supported": False},
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
        f"colorama-shim: wrote {output_path} "
        f"(windows_console_color={'n/a' if not win_cap.get('supported') else win_cap.get('value')})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
