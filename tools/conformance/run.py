#!/usr/bin/env python3
"""End-to-end conformance harness driver.

Generates a fresh envelope, dispatches every shim listed in manifest.json
that has a built binary, validates each output, then runs the comparator
and writes a markdown report.

Usage:
    python3 run.py EMULATOR [--emulator-version VER]
                            [--multiplexer {none,tmux,screen,zellij}]
                            [--results-dir PATH]

EMULATOR is the terminal emulator name (kitty, iTerm2, WezTerm, ...).
It is required: the harness needs to know what to label the run as,
otherwise the results/ tree fills up with `unknown/` and becomes useless.

Default results directory:
    results/<emulator>/<os>[-<arch>][-<multiplexer>]/<timestamp>/

For example:
    results/kitty/darwin-x86_64/20260508T114500Z/
    results/wezterm/linux-aarch64-tmux/20260508T114500Z/

A `latest` symlink at results/<emulator>/<os-slug>/latest -> <timestamp>/
points at the most recent run for each (emulator, os) combination.

Pass --results-dir to override the auto-layout entirely (useful in CI or
when reproducing an old run path).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import platform as _platform
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent


def _current_platform() -> str:
    """Return one canonical OS identifier matching manifest.json `platforms`."""
    p = _platform.system().lower()
    if p == "darwin":  return "darwin"
    if p == "linux":   return "linux"
    if p == "windows": return "windows"
    if p.startswith("freebsd"): return "freebsd"
    if p.startswith("openbsd"): return "openbsd"
    if p.startswith("netbsd"):  return "netbsd"
    if p.startswith("android"): return "android"
    return "other"


def _platform_allows(shim: dict, current: str) -> tuple[bool, str]:
    """If shim has a `platforms` allowlist and current OS is not in it, skip."""
    declared = shim.get("platforms")
    if declared is None or not isinstance(declared, list) or not declared:
        return True, ""
    if current in declared:
        return True, ""
    return False, f"not supported on {current} (declared platforms: {', '.join(sorted(declared))})"


def _slugify(s: str) -> str:
    """Lowercase, collapse runs of non-alnum to single dashes, strip dashes.

    Used to turn human-friendly --emulator values like "iTerm 2" or
    "Apple Terminal" into directory-safe slugs ("iterm-2", "apple-terminal").
    """
    if not s:
        return ""
    s = s.lower().strip()
    out: list[str] = []
    prev_dash = False
    for c in s:
        if c.isalnum() or c == "_" or c == ".":
            out.append(c)
            prev_dash = False
        else:
            if not prev_dash:
                out.append("-")
                prev_dash = True
    return "".join(out).strip("-")


def _auto_results_dir(emulator: str | None, multiplexer: str | None) -> Path:
    """Compute results/<emulator>/<os>[-<arch>][-<multiplexer>]/<timestamp>/.

    The `host` and `terminal` fields used here come from the same sources
    runner.py uses for the envelope (platform.system() / platform.machine()
    + the user-supplied --emulator / --multiplexer args), so the auto-path
    and the envelope agree on what they describe.
    """
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    emu_slug = _slugify(emulator) if emulator else "unknown"

    os_slug = _current_platform()
    arch = _slugify(_platform.machine() or "")
    if arch:
        os_slug = f"{os_slug}-{arch}"
    if multiplexer and multiplexer != "none":
        os_slug = f"{os_slug}-{multiplexer}"

    return HERE / "results" / emu_slug / os_slug / timestamp


def _update_latest_symlink(results_dir: Path) -> None:
    """Maintain a `latest` symlink pointing at the most recent run.

    The link sits at results/<emulator>/<os-slug>/latest and targets the
    timestamped sibling. Uses a relative target so the link is portable
    across host paths (works after rsync, in archives, etc.).
    """
    parent = results_dir.parent
    latest = parent / "latest"
    try:
        if latest.is_symlink() or latest.exists():
            latest.unlink()
        latest.symlink_to(results_dir.name)
    except OSError as exc:
        # Filesystem may not support symlinks (e.g. CI on Windows without
        # admin). Non-fatal: we still wrote the timestamped dir.
        print(f"  WARN  could not update {latest}: {exc}")


def _validator_python() -> str:
    """Pick the python interpreter that can import jsonschema.

    Prefers the project-local .venv/ created by build.py (used when the
    system Python is externally managed under PEP 668). Falls back to
    sys.executable, which is what run.py was started with.
    """
    venv_py = HERE / ".venv" / "bin" / "python"
    if venv_py.exists():
        rc = subprocess.run(
            [str(venv_py), "-c", "import jsonschema"],
            capture_output=True,
        )
        if rc.returncode == 0:
            return str(venv_py)
    return sys.executable


def main() -> int:
    p = argparse.ArgumentParser(description="Run all built shims and compare results.")
    p.add_argument("emulator",
                   help="Terminal emulator name (e.g. kitty, iTerm2, WezTerm). "
                        "Slugified into the results/ path; passed verbatim into the envelope.")
    p.add_argument("--emulator-version")
    p.add_argument("--multiplexer", choices=["none", "tmux", "screen", "zellij"])
    p.add_argument("--results-dir",
                   help="Where to write envelope.json, <lib>.json, and report.md. "
                        "Overrides the auto-layout (results/<emulator>/<os-slug>/<timestamp>/).")
    args = p.parse_args()

    if args.results_dir:
        results_dir = Path(args.results_dir)
        is_auto_layout = False
    else:
        results_dir = _auto_results_dir(args.emulator, args.multiplexer)
        is_auto_layout = True
    results_dir.mkdir(parents=True, exist_ok=True)
    if is_auto_layout:
        _update_latest_symlink(results_dir)

    envelope = results_dir / "envelope.json"

    runner_cmd: list[str] = [
        sys.executable, str(HERE / "runner.py"),
        "--output", str(envelope),
        "--emulator", args.emulator,
    ]
    if args.emulator_version: runner_cmd += ["--emulator-version", args.emulator_version]
    if args.multiplexer:      runner_cmd += ["--multiplexer", args.multiplexer]

    print(f">>> generating envelope at {envelope}")
    subprocess.run(runner_cmd, check=True)

    manifest = json.loads((HERE / "manifest.json").read_text())
    env = os.environ.copy()
    env["CONFORMANCE_ENVELOPE"] = str(envelope.resolve())

    repo_root = HERE.parent.parent  # tools/conformance/run.py -> tools -> repo root
    valid_results: list[Path] = []
    validator_warned = False
    validator_py = _validator_python()
    current_os = _current_platform()

    for shim in manifest["shims"]:
        binary = HERE / shim["binary"]
        out = results_dir / f"{shim['name']}.json"

        allowed, reason = _platform_allows(shim, current_os)
        if not allowed:
            print(f"  SKIP    {shim['name']:<24}  ({reason})")
            continue

        if not binary.exists():
            print(f"  SKIP    {shim['name']:<24}  (not built — to build: {shim['build']})")
            continue

        rc = subprocess.run([str(binary), str(out)], env=env)
        if rc.returncode != 0:
            print(f"  FAIL    {shim['name']:<24}  (shim exited {rc.returncode})")
            continue

        v = subprocess.run(
            [validator_py, str(HERE / "validate.py"), str(out)],
            capture_output=True, text=True
        )
        if v.returncode == 0:
            print(f"  OK      {shim['name']:<24}  -> {out.name}")
            valid_results.append(out)
        elif v.returncode == 2:
            # Validator could not run (e.g. jsonschema missing). Warn and
            # include the result anyway — the comparator only needs valid
            # JSON, which the shims produce regardless.
            if not validator_warned:
                print(f"  WARN    validator unavailable; proceeding without schema check")
                for line in (v.stderr or "").splitlines():
                    print(f"            {line}")
                validator_warned = True
            print(f"  WARN    {shim['name']:<24}  -> {out.name}  (unvalidated)")
            valid_results.append(out)
        else:
            print(f"  INVALID {shim['name']:<24}")
            for line in v.stdout.splitlines():
                print(f"            {line}")
            for line in (v.stderr or "").splitlines():
                print(f"            (stderr) {line}")

    if not valid_results:
        print("\nNo valid shim outputs.")
        print("Build at least one shim first; see manifest.json for the build commands.")
        return 1

    report = subprocess.run(
        [sys.executable, str(HERE / "compare.py")] + [str(p) for p in valid_results],
        capture_output=True, text=True, check=True,
    ).stdout
    (results_dir / "report.md").write_text(report)

    print()
    suffix = "" if not validator_warned else " (unvalidated — install jsonschema to validate)"
    print(f">>> {len(valid_results)} result(s){suffix}; report written to {results_dir / 'report.md'}")
    print()
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
