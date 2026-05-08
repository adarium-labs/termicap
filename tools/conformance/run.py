#!/usr/bin/env python3
"""End-to-end conformance harness driver.

Generates a fresh envelope, dispatches every shim listed in manifest.json
that has a built binary, validates each output, then runs the comparator
and writes a markdown report.

Usage:
    python3 run.py [--emulator NAME] [--emulator-version VER]
                   [--multiplexer {none,tmux,screen,zellij}]
                   [--results-dir PATH]

Default results directory: results/<UTC timestamp>/.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent


def main() -> int:
    p = argparse.ArgumentParser(description="Run all built shims and compare results.")
    p.add_argument("--emulator")
    p.add_argument("--emulator-version")
    p.add_argument("--multiplexer", choices=["none", "tmux", "screen", "zellij"])
    p.add_argument("--results-dir",
                   help="Where to write envelope.json, <lib>.json, and report.md.")
    args = p.parse_args()

    if args.results_dir:
        results_dir = Path(args.results_dir)
    else:
        stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        results_dir = HERE / "results" / stamp
    results_dir.mkdir(parents=True, exist_ok=True)

    envelope = results_dir / "envelope.json"

    runner_cmd: list[str] = [sys.executable, str(HERE / "runner.py"), "--output", str(envelope)]
    if args.emulator:         runner_cmd += ["--emulator", args.emulator]
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

    for shim in manifest["shims"]:
        binary = HERE / shim["binary"]
        out = results_dir / f"{shim['name']}.json"

        if not binary.exists():
            print(f"  SKIP    {shim['name']:<24}  (not built — to build: {shim['build']})")
            continue

        rc = subprocess.run([str(binary), str(out)], env=env)
        if rc.returncode != 0:
            print(f"  FAIL    {shim['name']:<24}  (shim exited {rc.returncode})")
            continue

        v = subprocess.run(
            [sys.executable, str(HERE / "validate.py"), str(out)],
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
