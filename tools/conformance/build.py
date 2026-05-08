#!/usr/bin/env python3
"""Build every shim listed in manifest.json.

Run once before ./run.py to ensure each shim has a built binary. Skips
shims whose toolchain is missing (with an install hint), skips shims
that are already built (use --force to rebuild), and reports per-shim
status as it goes.

Usage:
    python3 build.py                  # build everything not yet built
    python3 build.py --force          # rebuild everything
    python3 build.py rust             # only build rust shims
    python3 build.py termicap rich    # only build named shims
    python3 build.py --list           # list shims and their build state, no build

Exit codes:
    0 - all targeted shims built (or already built)
    1 - one or more builds failed
    2 - usage error or no shims matched the filter
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
REPO_ROOT = HERE.parent.parent   # tools/conformance/build.py -> tools -> repo root

# Toolchain executable each language needs, plus an install hint shown when missing.
TOOLCHAIN: dict[str, tuple[str, str]] = {
    "ada":    ("alr",     "Install Alire: https://alire.ada.dev/"),
    "rust":   ("cargo",   "Install rustup: https://rustup.rs/"),
    "go":     ("go",      "Install Go 1.21+: https://go.dev/dl/"),
    "node":   ("npm",     "Install Node 18+: https://nodejs.org/"),
    "python": ("python3", "Python 3.10+ is required"),
}

OK    = "OK"
SKIP  = "SKIP"
BUILD = "BUILD"
FAIL  = "FAIL"


def shim_dir(shim: dict) -> Path:
    """Directory of the shim itself (the parent of its binary)."""
    binary = HERE / shim["binary"]
    # Walk up to the directory immediately under shims/<lang>/<name>/.
    parts = binary.relative_to(HERE).parts
    # parts looks like ("shims", "<lang>", "<name>", ...).
    if len(parts) >= 3 and parts[0] == "shims":
        return HERE / parts[0] / parts[1] / parts[2]
    return binary.parent


def is_built(shim: dict) -> bool:
    """Best-effort check that the shim has been built.

    For compiled langs (Ada/Rust/Go) we just look for the binary. For Node
    and Python the manifest's `binary` is a script that always exists in
    git, so we additionally check for node_modules/ or .venv/.
    """
    binary = HERE / shim["binary"]
    lang = shim.get("language", "")
    if lang == "node":
        return (shim_dir(shim) / "node_modules").is_dir()
    if lang == "python":
        return (shim_dir(shim) / ".venv").is_dir()
    return binary.exists()


def toolchain_ok(language: str) -> tuple[bool, str]:
    """Return (available, hint). Empty hint when available."""
    spec = TOOLCHAIN.get(language)
    if spec is None:
        return True, ""
    exe, hint = spec
    if shutil.which(exe):
        return True, ""
    return False, f"`{exe}` not in PATH — {hint}"


def filter_shims(shims: list[dict], filters: list[str]) -> list[dict]:
    if not filters:
        return shims
    keep = []
    for s in shims:
        if s["name"] in filters or s.get("language") in filters:
            keep.append(s)
    return keep


def print_row(status: str, name: str, message: str = "") -> None:
    suffix = f"  — {message}" if message else ""
    print(f"  {status:<5} {name:<24}{suffix}", flush=True)


def _python_can_import(python: Path | str, module: str) -> bool:
    rc = subprocess.run(
        [str(python), "-c", f"import {module}"],
        capture_output=True,
    )
    return rc.returncode == 0


def ensure_validator() -> Path | None:
    """Ensure jsonschema is importable for the validator step.

    Strategy:
      1. If the current python (sys.executable) can import jsonschema, use it.
      2. Else, if a project-local venv at tools/conformance/.venv/ already
         has jsonschema, use it.
      3. Else, create that venv and install jsonschema into it. This is the
         path we land on under PEP 668 (Homebrew Python on macOS, system
         Python on recent Debian, etc.) where `pip install --user` is
         refused.
    Returns the python path that can run validate.py, or None on failure.
    """
    print(">>> ensuring validator (jsonschema)")
    if _python_can_import(sys.executable, "jsonschema"):
        print_row(OK, "validator", f"system python has jsonschema ({sys.executable})")
        return Path(sys.executable)

    venv_dir = HERE / ".venv"
    venv_py = venv_dir / "bin" / "python"
    if venv_py.exists() and _python_can_import(venv_py, "jsonschema"):
        print_row(OK, "validator", f"project venv has jsonschema ({venv_dir})")
        return venv_py

    print_row(BUILD, "validator", f"creating venv at {venv_dir} and installing jsonschema")
    rc = subprocess.run([sys.executable, "-m", "venv", str(venv_dir)])
    if rc.returncode != 0:
        print_row(FAIL, "validator", f"venv creation failed (exit {rc.returncode})")
        return None
    rc = subprocess.run(
        [str(venv_py), "-m", "pip", "install", "--quiet", "jsonschema"],
        capture_output=False,
    )
    if rc.returncode != 0:
        print_row(FAIL, "validator", f"pip install failed (exit {rc.returncode})")
        return None
    if not _python_can_import(venv_py, "jsonschema"):
        print_row(FAIL, "validator", "jsonschema installed but still not importable")
        return None
    print_row(OK, "validator", f"jsonschema installed into {venv_dir}")
    return venv_py


def build_one(shim: dict, *, force: bool) -> bool:
    """Returns True iff the shim is built (or successfully skipped)."""
    name = shim["name"]
    language = shim.get("language", "?")

    if not force and is_built(shim):
        print_row(SKIP, name, "already built (use --force to rebuild)")
        return True

    available, hint = toolchain_ok(language)
    if not available:
        print_row(SKIP, name, hint)
        return True   # not a failure — just skipped, the user can install later

    print_row(BUILD, name, shim["build"])
    rc = subprocess.run(shim["build"], shell=True, cwd=REPO_ROOT)
    if rc.returncode != 0:
        print_row(FAIL, name, f"build command exited {rc.returncode}")
        return False

    if not is_built(shim):
        print_row(FAIL, name, f"build completed but {shim['binary']} is not present")
        return False

    print_row(OK, name)
    return True


def cmd_list(shims: list[dict]) -> int:
    """Print each shim's name, language, and build state without building."""
    print(f"{'NAME':<24} {'LANG':<8} {'STATE':<14} {'TOOLCHAIN':<24}")
    print(f"{'-' * 24} {'-' * 8} {'-' * 14} {'-' * 24}")
    for shim in shims:
        name = shim["name"]
        lang = shim.get("language", "?")
        state = "built" if is_built(shim) else "not built"
        avail, _ = toolchain_ok(lang)
        tc = "available" if avail else "MISSING"
        print(f"{name:<24} {lang:<8} {state:<14} {tc:<24}")
    return 0


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(
        description="Build every shim listed in manifest.json.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("filters", nargs="*",
                   help="Build only shims whose name or language matches one of these.")
    p.add_argument("--force", action="store_true",
                   help="Rebuild even if the shim's binary is already present.")
    p.add_argument("--list", action="store_true",
                   help="List shims and their build state; do not build.")
    p.add_argument("--no-validator", action="store_true",
                   help="Skip the jsonschema validator setup.")
    args = p.parse_args(argv)

    manifest = json.loads((HERE / "manifest.json").read_text())
    shims = filter_shims(manifest["shims"], args.filters)
    if not shims:
        print(f"error: no shims match filters {args.filters}", file=sys.stderr)
        print(f"available: {', '.join(s['name'] for s in manifest['shims'])}", file=sys.stderr)
        return 2

    if args.list:
        return cmd_list(shims)

    if not args.no_validator:
        ensure_validator()
        print()

    print(f">>> building {len(shims)} shim(s)")
    print()

    rc_overall = 0
    n_built = 0
    n_skipped = 0
    n_failed = 0
    for shim in shims:
        ok = build_one(shim, force=args.force)
        if not ok:
            rc_overall = 1
            n_failed += 1
        else:
            if not args.force and is_built(shim) and toolchain_ok(shim.get("language", ""))[0]:
                # Distinguish 'already built' from 'just built' in the summary.
                n_built += 1   # both count as built; we don't separate

    print()
    if rc_overall == 0:
        print(f">>> all {len(shims)} shim(s) ready")
        print(f"    next: ./run.py")
    else:
        print(f">>> {n_failed} of {len(shims)} shim(s) failed; see output above")
    return rc_overall


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
