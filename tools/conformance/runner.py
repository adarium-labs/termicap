#!/usr/bin/env python3
"""Generate the conformance envelope for one harness invocation.

Captures host info, terminal info, ground-truth TTY status, and an env-var
allowlist into a single JSON file ("envelope.json"). Each shim reads this
envelope and merges its own capability measurements to produce one full
canonical result.

The envelope is the part of the canonical result that is identical across
all libs in one session (`run` block + UUID).

Usage:
    python3 runner.py [--emulator NAME] [--emulator-version VER]
                      [--multiplexer {none,tmux,screen,zellij}]
                      [--output envelope.json]

The runner does NOT itself dispatch shims. Run it once at the start of a
session, then invoke each shim with the envelope path in
$CONFORMANCE_ENVELOPE.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import platform
import sys
import uuid
from pathlib import Path
from typing import Optional

ENV_ALLOWLIST = [
    "TERM", "COLORTERM",
    "NO_COLOR", "FORCE_COLOR", "CLICOLOR", "CLICOLOR_FORCE",
    "TTY_COMPATIBLE", "IGNORE_IS_TERMINAL",
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERMINAL_EMULATOR",
    "WT_SESSION", "KONSOLE_VERSION", "VTE_VERSION",
    "TMUX", "STY", "INSIDE_EMACS",
    "COLORFGBG",
    "LANG", "LC_ALL", "LC_CTYPE",
    "CI", "GITHUB_ACTIONS", "GITEA_ACTIONS", "GITLAB_CI",
    "CIRCLECI", "TRAVIS", "BUILDKITE", "APPVEYOR", "TF_BUILD",
    "SHELL", "OSTYPE",
]

OS_MAP = {
    "Darwin": "darwin", "Linux": "linux", "Windows": "windows",
    "FreeBSD": "freebsd", "OpenBSD": "openbsd", "NetBSD": "netbsd",
}
ARCH_MAP = {
    "x86_64": "x86_64", "AMD64": "x86_64",
    "arm64": "arm64", "aarch64": "aarch64",
    "i386": "i386", "i686": "i386",
}


def detect_emulator() -> tuple[Optional[str], Optional[str]]:
    """Best-effort emulator + version from env. Operator should override via CLI."""
    tp = os.environ.get("TERM_PROGRAM")
    if tp:
        version = os.environ.get("TERM_PROGRAM_VERSION")
        # Normalize a few common values
        canonical = {
            "iTerm.app": "iTerm2",
            "Apple_Terminal": "Apple_Terminal",
            "vscode": "VSCode",
            "WezTerm": "WezTerm",
            "ghostty": "Ghostty",
            "tmux": "tmux",
        }.get(tp, tp)
        return canonical, version
    if os.environ.get("WT_SESSION"):
        return "Windows Terminal", None
    te = os.environ.get("TERMINAL_EMULATOR")
    if te:
        return te, None
    if os.environ.get("KONSOLE_VERSION"):
        return "Konsole", os.environ.get("KONSOLE_VERSION")
    if os.environ.get("VTE_VERSION"):
        return "VTE", os.environ.get("VTE_VERSION")
    return None, None


def detect_multiplexer() -> Optional[str]:
    if os.environ.get("TMUX"):
        return "tmux"
    if os.environ.get("STY"):
        return "screen"
    term = os.environ.get("TERM", "")
    if term.startswith("tmux"):
        return "tmux"
    if term.startswith("screen"):
        return "screen"
    if os.environ.get("ZELLIJ"):
        return "zellij"
    return None


def detect_shell() -> str:
    sh = os.environ.get("SHELL", "")
    return Path(sh).name if sh else "unknown"


def capture_env() -> dict:
    return {key: os.environ.get(key) for key in ENV_ALLOWLIST}


def capture_tty() -> dict:
    return {
        "stdin":  sys.stdin.isatty(),
        "stdout": sys.stdout.isatty(),
        "stderr": sys.stderr.isatty(),
    }


def capture_host() -> dict:
    sys_name = platform.system()
    return {
        "os":         OS_MAP.get(sys_name, "other"),
        "os_version": platform.release() or "unknown",
        "arch":       ARCH_MAP.get(platform.machine(), "other"),
    }


def build_envelope(args: argparse.Namespace) -> dict:
    detected_em, detected_ver = detect_emulator()
    emulator = args.emulator or detected_em or "unknown"
    emulator_version = args.emulator_version or detected_ver

    multiplexer = args.multiplexer
    if multiplexer is None:
        multiplexer = detect_multiplexer()
    elif multiplexer == "none":
        multiplexer = None

    return {
        "run_id":    str(uuid.uuid4()),
        "timestamp": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "host":      capture_host(),
        "terminal":  {
            "emulator":         emulator,
            "emulator_version": emulator_version,
            "shell":            detect_shell(),
            "multiplexer":      multiplexer,
        },
        "tty": capture_tty(),
        "env": capture_env(),
    }


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Generate the conformance envelope.")
    p.add_argument("--emulator", default=None,
                   help="Override the auto-detected emulator name (e.g. 'iTerm2').")
    p.add_argument("--emulator-version", default=None,
                   help="Override the auto-detected emulator version.")
    p.add_argument("--multiplexer", choices=["none", "tmux", "screen", "zellij"],
                   default=None, help="Override multiplexer auto-detection.")
    p.add_argument("--output", "-o", default="envelope.json",
                   help="Output path for the envelope JSON.")
    args = p.parse_args(argv)

    envelope = build_envelope(args)
    Path(args.output).write_text(json.dumps(envelope, indent=2) + "\n")

    em = envelope["terminal"]["emulator"]
    em_v = envelope["terminal"]["emulator_version"] or "?"
    sys.stderr.write(f"envelope: run_id={envelope['run_id']}\n")
    sys.stderr.write(f"          terminal={em} {em_v}\n")
    sys.stderr.write(f"          host={envelope['host']['os']} {envelope['host']['arch']}\n")
    sys.stderr.write(f"          tty=stdin:{envelope['tty']['stdin']} stdout:{envelope['tty']['stdout']} stderr:{envelope['tty']['stderr']}\n")
    sys.stderr.write(f"  -> {args.output}\n")
    sys.stderr.write(f"\nNext: invoke each shim with CONFORMANCE_ENVELOPE={args.output}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
