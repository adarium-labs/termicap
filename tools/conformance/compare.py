#!/usr/bin/env python3
"""Compare canonical conformance results and emit a divergence report.

Usage:
    python3 compare.py <result.json> [<result.json> ...]
    python3 compare.py results/iterm2-darwin/

The comparator groups results by run_id. For each capability key, it lists
how many libs measured it, whether they agreed, and which libs did not
measure it. Output is markdown to stdout.

This is a *divergence detector*, not a grader. There is no "expected" or
"correct" value. A divergence is a question, not a failure.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


def load_results(paths: list[str]) -> list[dict]:
    results = []
    for arg in paths:
        p = Path(arg)
        if p.is_dir():
            for child in sorted(p.glob("*.json")):
                try:
                    results.append(json.loads(child.read_text()))
                except json.JSONDecodeError as e:
                    print(f"warning: {child}: {e}", file=sys.stderr)
        elif p.is_file():
            try:
                results.append(json.loads(p.read_text()))
            except json.JSONDecodeError as e:
                print(f"warning: {p}: {e}", file=sys.stderr)
        else:
            print(f"warning: {p}: not a file or directory", file=sys.stderr)
    return results


def group_by_run_id(results: list[dict]) -> dict[str, list[dict]]:
    groups: dict[str, list[dict]] = defaultdict(list)
    for r in results:
        groups[r["run"]["run_id"]].append(r)
    return groups


def render_value(v: Any) -> str:
    """Render a canonical value as a short markdown-safe string."""
    if isinstance(v, bool):
        return f"`{str(v).lower()}`"
    if isinstance(v, (int, float, str)):
        return f"`{v}`"
    return f"`{json.dumps(v, sort_keys=True)}`"


def header(envelope: dict) -> list[str]:
    out = []
    t = envelope["terminal"]
    h = envelope["host"]
    out.append(f"# Conformance Report")
    out.append("")
    out.append(f"- **Run ID**: `{envelope['run_id']}`")
    out.append(f"- **Timestamp**: {envelope['timestamp']}")
    out.append(f"- **Terminal**: {t['emulator']} {t['emulator_version'] or ''}".rstrip())
    out.append(f"- **Host**: {h['os']} {h['os_version']} ({h['arch']})")
    out.append(f"- **Shell**: {t['shell']}")
    out.append(f"- **Multiplexer**: {t['multiplexer'] or 'none'}")
    tty = envelope["tty"]
    out.append(f"- **Ground-truth TTY**: stdin={str(tty['stdin']).lower()} stdout={str(tty['stdout']).lower()} stderr={str(tty['stderr']).lower()}")
    out.append("")
    return out


def env_section(envelope: dict) -> list[str]:
    out = ["## Environment", ""]
    present = {k: v for k, v in envelope["env"].items() if v is not None}
    if not present:
        out.append("*All allowlisted env vars unset.*")
    else:
        for k in sorted(present):
            v = present[k]
            out.append(f"- `{k}` = `{v}`" if v else f"- `{k}` = `<empty>`")
    out.append("")
    return out


def lib_summary_section(libs: list[dict]) -> list[str]:
    out = ["## Libraries probed", ""]
    out.append("| Lib | Version | Language | Tier |")
    out.append("|-----|---------|----------|------|")
    for r in sorted(libs, key=lambda x: x["lib"]["name"]):
        L = r["lib"]
        out.append(f"| {L['name']} | {L['version']} | {L['language']} | {L['tier']} |")
    out.append("")
    return out


def capability_section(libs: list[dict], cap_key: str) -> list[str]:
    """Render one capability's row of agreement/divergence."""
    measured = []
    not_measured = []
    drift = []

    for r in libs:
        cap = r.get("capabilities", {}).get(cap_key)
        if cap is None:
            drift.append(r["lib"]["name"])
        elif cap.get("supported") is True:
            measured.append((r["lib"]["name"], cap))
        else:
            not_measured.append(r["lib"]["name"])

    out = [f"### `{cap_key}`", ""]

    if not measured:
        if not_measured:
            out.append(f"_Not measured by any lib_ ({len(not_measured)})")
        if drift:
            out.append(f"_Schema drift_ in: {', '.join(sorted(drift))}")
        out.append("")
        return out

    # Group measured by canonical value
    by_value: dict[str, list[tuple[str, dict]]] = defaultdict(list)
    for name, cap in measured:
        key = json.dumps(cap.get("value"), sort_keys=True)
        by_value[key].append((name, cap))

    if len(by_value) == 1:
        value_key, libs_for_value = next(iter(by_value.items()))
        value = libs_for_value[0][1]["value"]
        n = len(libs_for_value)
        label = "Single observation" if n == 1 else f"Agreement ({n} libs)"
        out.append(f"**{label}**: {render_value(value)}")
        for name, cap in sorted(libs_for_value, key=lambda x: x[0]):
            method = cap.get("method", "")
            out.append(f"- `{name}` — {method}")
    else:
        n_libs = len(measured)
        out.append(f"**DIVERGENCE** ({len(by_value)} groups, {n_libs} libs)")
        # Sort groups by lib count descending so the majority comes first
        for value_key, libs_for_value in sorted(by_value.items(), key=lambda kv: -len(kv[1])):
            value = libs_for_value[0][1]["value"]
            out.append(f"- {render_value(value)}:")
            for name, cap in sorted(libs_for_value, key=lambda x: x[0]):
                method = cap.get("method", "")
                out.append(f"  - `{name}` — {method}")

    if not_measured:
        out.append(f"")
        out.append(f"_Not measured by_: {', '.join(sorted(not_measured))}")
    if drift:
        out.append(f"")
        out.append(f"_Schema drift in_: {', '.join(sorted(drift))}")

    out.append("")
    return out


def render_run(libs: list[dict]) -> list[str]:
    if not libs:
        return []

    # Verify all libs share an envelope; warn if not.
    envelope = libs[0]["run"]
    schema_versions = {r["schema_version"] for r in libs}

    out = []
    out.extend(header(envelope))
    if len(schema_versions) > 1:
        out.append(f"> **Warning**: mixed schema versions in this run: {sorted(schema_versions)}")
        out.append("")
    out.extend(env_section(envelope))
    out.extend(lib_summary_section(libs))

    # Collect the union of capability keys across all libs.
    all_caps: set[str] = set()
    for r in libs:
        all_caps.update(r.get("capabilities", {}).keys())

    # Stable order for the report — matches schema's required order.
    canonical_order = [
        "tty_stdin", "tty_stdout", "tty_stderr",
        "color_depth", "windows_console_color",
        "dimensions",
        "unicode",
        "terminal_kind", "multiplexer",
        "theme", "background",
        "hyperlinks",
        "mouse", "keyboard",
        "clipboard_osc52",
        "graphics_sixel", "graphics_kitty",
        "xtversion",
        "da1_attributes",
        "ci_detected",
    ]
    ordered = [c for c in canonical_order if c in all_caps]
    leftover = sorted(all_caps - set(canonical_order))

    out.append("## Capabilities")
    out.append("")
    for cap in ordered + leftover:
        out.extend(capability_section(libs, cap))

    return out


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    results = load_results(argv)
    if not results:
        print("error: no results loaded", file=sys.stderr)
        return 2

    groups = group_by_run_id(results)
    out = []
    for run_id in sorted(groups):
        out.extend(render_run(groups[run_id]))
        out.append("---")
        out.append("")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
