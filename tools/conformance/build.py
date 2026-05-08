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
import platform
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
REPO_ROOT = HERE.parent.parent   # tools/conformance/build.py -> tools -> repo root

# Toolchain executable each language needs, plus an install hint shown when missing.
TOOLCHAIN: dict[str, tuple[str, str]] = {
    "ada":     ("alr",     "Install Alire: https://alire.ada.dev/"),
    "rust":    ("cargo",   "Install rustup: https://rustup.rs/"),
    "go":      ("go",      "Install Go 1.21+: https://go.dev/dl/"),
    "node":    ("npm",     "Install Node 18+: https://nodejs.org/"),
    "python":  ("python3", "Python 3.10+ is required"),
    "java":    ("javac",   "Install a JDK: https://adoptium.net/"),
    "swift":   ("swift",   "Install Swift toolchain: https://swift.org/install/ (or Xcode CLI tools on macOS)"),
    "ruby":    ("ruby",    "Install Ruby + bundler"),
    "csharp":  ("dotnet",  "Install .NET SDK: https://dotnet.microsoft.com/download"),
    "haskell": ("ghc",     "Install GHCup: https://www.haskell.org/ghcup/"),
    "c":       ("cc",      "Install a C toolchain (clang/gcc); on macOS: `xcode-select --install`"),
}


# Recognized OS strings for the optional `platforms` field in manifest.json.
KNOWN_PLATFORMS = frozenset({
    "darwin", "linux", "windows", "freebsd", "openbsd", "netbsd", "android", "other",
})


def current_platform() -> str:
    """Return one canonical OS identifier matching KNOWN_PLATFORMS."""
    p = platform.system().lower()
    if p == "darwin":  return "darwin"
    if p == "linux":   return "linux"
    if p == "windows": return "windows"
    if p.startswith("freebsd"): return "freebsd"
    if p.startswith("openbsd"): return "openbsd"
    if p.startswith("netbsd"):  return "netbsd"
    if p.startswith("android"): return "android"
    return "other"


def platforms_ok(shim: dict) -> tuple[bool, str]:
    """Check if the shim's `platforms` field allows the current OS.

    Returns (allowed, message). When `platforms` is missing, the shim is
    treated as cross-platform and allowed everywhere. The message is empty
    on success and explanatory on skip.
    """
    declared = shim.get("platforms")
    if declared is None:
        return True, ""
    if not isinstance(declared, list) or not declared:
        return True, ""
    cur = current_platform()
    if cur in declared:
        return True, ""
    return False, f"not supported on {cur} (declared platforms: {', '.join(sorted(declared))})"

OK    = "OK"
SKIP  = "SKIP"
BUILD = "BUILD"
FAIL  = "FAIL"


def shim_field(shim: dict, key: str) -> str:
    """Return ``shim[<key>_<plat>]`` if present, falling back to ``shim[key]``.

    Used so manifest entries can override ``build`` / ``binary`` for a
    specific OS without needing a separate top-level shim entry.  Example
    keys: ``build``, ``binary``.  The platform suffix is whatever
    :func:`current_platform` returns (``"windows"`` etc.).
    """
    plat = current_platform()
    override = shim.get(f"{key}_{plat}")
    if override:
        return override
    return shim[key]


def shim_field_optional(shim: dict, key: str) -> str | None:
    """Like :func:`shim_field` but returns None when neither the per-OS
    override nor the plain key is set.  Use for optional manifest fields
    (``build_marker``, ...).
    """
    plat = current_platform()
    return shim.get(f"{key}_{plat}") or shim.get(key)


def shim_dir(shim: dict) -> Path:
    """Directory of the shim itself (the parent of its binary)."""
    binary = HERE / shim_field(shim, "binary")
    # Walk up to the directory immediately under shims/<lang>/<name>/.
    parts = binary.relative_to(HERE).parts
    # parts looks like ("shims", "<lang>", "<name>", ...).
    if len(parts) >= 3 and parts[0] == "shims":
        return HERE / parts[0] / parts[1] / parts[2]
    return binary.parent


def resolve_binary(path: Path) -> Path:
    """Return the on-disk path of a shim binary, trying ``.exe`` on Windows.

    Manifest paths are written POSIX-style (no extension); on Windows the
    same compiled binary lands at ``<name>.exe``.  Returns the existing
    variant when found, otherwise the original path so the caller can
    report a useful "missing" error.
    """
    if path.exists():
        return path
    if current_platform() == "windows":
        with_exe = path.parent / (path.name + ".exe")
        if with_exe.exists():
            return with_exe
    return path


def _python_requirements_satisfied(shim_root: Path) -> bool:
    """Check whether the shim's venv has the first requirement installed.

    The venv directory is created by `python -m venv` before pip runs, so
    its mere existence does not prove the install succeeded.  We parse the
    first non-comment, non-blank line of requirements.txt, extract the
    package name, and look for a matching site-packages entry (either a
    plain dir or a `*.dist-info` for the package).  This is enough to
    catch the common failure mode where venv creation succeeded but
    `pip install` failed silently in an `&&`-chained build command.
    """
    req_file = shim_root / "requirements.txt"
    venv = shim_root / ".venv"
    if not req_file.is_file() or not venv.is_dir():
        return False

    first_pkg: str | None = None
    for line in req_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Strip extras and version specifiers: "rich[jupyter]>=14" -> "rich".
        name = line.split(";")[0].split("[")[0]
        for sep in (">=", "<=", "==", "!=", "~=", ">", "<", " "):
            if sep in name:
                name = name.split(sep)[0]
        first_pkg = name.strip().lower()
        if first_pkg:
            break
    if not first_pkg:
        # No requirements listed; treat venv as sufficient.
        return True

    # Site-packages location varies by platform layout.
    candidates = [venv / "Lib" / "site-packages"]                  # Windows
    for sub in (venv / "lib").glob("python*/site-packages"):       # POSIX
        candidates.append(sub)
    package_dir = first_pkg.replace("-", "_")
    for sp in candidates:
        if not sp.is_dir():
            continue
        for entry in sp.iterdir():
            ename = entry.name.lower()
            if ename == package_dir or ename.startswith(f"{first_pkg.replace('_', '-')}-") or ename.startswith(f"{package_dir}-"):
                return True
    return False


def _build_marker_satisfied(shim: dict) -> bool:
    """Return True iff the shim's ``build_marker`` (or per-OS override) exists.

    Supports a glob pattern in the value: when ``*`` is present the path is
    matched via :py:meth:`Path.glob` against the conformance root.  This is
    the only way to express SPM's per-triple artifact directory on Windows
    (e.g. ``.build/x86_64-unknown-windows-msvc/release/Foo.exe``) where the
    triple varies by host.  Plain paths without ``*`` are checked verbatim.
    Returns False when no marker is configured for the current OS.
    """
    marker = shim_field_optional(shim, "build_marker")
    if not marker:
        return False
    if "*" in marker:
        return any(HERE.glob(marker))
    return resolve_binary(HERE / marker).exists()


def is_built(shim: dict) -> bool:
    """Best-effort check that the shim has been built.

    For compiled langs (Ada/Rust/Go) we just look for the binary.  For
    languages whose `binary` is a wrapper script (node/python/java/ruby/
    csharp/swift), the wrapper exists in git regardless of whether
    `pip install` / `bundle install` / `dotnet publish` / etc. succeeded,
    so we check for an artifact specific to each language.  Manifest
    entries can also set ``build_marker`` (with optional ``build_marker_<os>``
    override) to a path that build.py requires after the build step.
    """
    binary = HERE / shim_field(shim, "binary")
    lang = shim.get("language", "")

    if shim_field_optional(shim, "build_marker"):
        return _build_marker_satisfied(shim)

    if lang == "node":
        # node_modules is the proof npm install ran; reject empty dirs.
        nm = shim_dir(shim) / "node_modules"
        return nm.is_dir() and any(nm.iterdir())
    if lang == "python":
        return _python_requirements_satisfied(shim_dir(shim))
    return resolve_binary(binary).exists()


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
    if current_platform() == "windows":
        venv_py = venv_dir / "Scripts" / "python.exe"
    else:
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

    allowed, reason = platforms_ok(shim)
    if not allowed:
        print_row(SKIP, name, reason)
        return True   # platform-incompatible is a successful skip, not a failure

    if not force and is_built(shim):
        print_row(SKIP, name, "already built (use --force to rebuild)")
        return True

    available, hint = toolchain_ok(language)
    if not available:
        print_row(SKIP, name, hint)
        return True   # not a failure — just skipped, the user can install later

    build_cmd = shim_field(shim, "build")
    print_row(BUILD, name, build_cmd)
    rc = subprocess.run(build_cmd, shell=True, cwd=REPO_ROOT)
    if rc.returncode != 0:
        print_row(FAIL, name, f"build command exited {rc.returncode}")
        return False

    if not is_built(shim):
        print_row(FAIL, name, f"build completed but {shim_field(shim, 'binary')} is not present")
        return False

    print_row(OK, name)
    return True


def cmd_list(shims: list[dict]) -> int:
    """Print each shim's name, language, build state, and platform support."""
    print(f"{'NAME':<26} {'LANG':<8} {'STATE':<14} {'TOOLCHAIN':<14} {'PLATFORMS':<28}")
    print(f"{'-' * 26} {'-' * 8} {'-' * 14} {'-' * 14} {'-' * 28}")
    cur = current_platform()
    for shim in shims:
        name = shim["name"]
        lang = shim.get("language", "?")
        state = "built" if is_built(shim) else "not built"
        avail, _ = toolchain_ok(lang)
        tc = "available" if avail else "MISSING"
        declared = shim.get("platforms")
        if declared is None:
            plat = "(any)"
        else:
            mark = "*" if cur in declared else "x"
            plat = f"{mark} {','.join(sorted(declared))}"
        print(f"{name:<26} {lang:<8} {state:<14} {tc:<14} {plat:<28}")
    print(f"\ncurrent platform: {cur}  (rows marked 'x' will be skipped on this host)")
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
