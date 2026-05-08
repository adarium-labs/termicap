#!/usr/bin/env python3
"""Validate a conformance result JSON against canonical.schema.json.

Usage:
    python3 validate.py path/to/result.json [path/to/another.json ...]

Exit codes:
    0 - all files valid
    1 - one or more files failed validation
    2 - usage error or missing dependency

Depends on: jsonschema (Draft 2020-12). Install with:
    uv pip install jsonschema
or
    pip install --user jsonschema
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("error: jsonschema module not installed", file=sys.stderr)
    print("       install with: pip install --user jsonschema", file=sys.stderr)
    sys.exit(2)

HERE = Path(__file__).parent
SCHEMA_PATH = HERE / "schema" / "canonical.schema.json"


def validate_file(path: Path, validator: Draft202012Validator) -> int:
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        print(f"  ERROR  {path}: file not found")
        return 1
    except json.JSONDecodeError as e:
        print(f"  ERROR  {path}: invalid JSON: {e}")
        return 1

    errors = list(validator.iter_errors(data))
    if not errors:
        print(f"  OK     {path}")
        return 0

    print(f"  FAIL   {path} ({len(errors)} error{'s' if len(errors) != 1 else ''})")
    for e in errors[:10]:
        loc = ".".join(str(p) for p in e.absolute_path) or "<root>"
        msg = e.message[:200]
        print(f"         at {loc}: {msg}")
    if len(errors) > 10:
        print(f"         ... +{len(errors) - 10} more")
    return 1


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    schema = json.loads(SCHEMA_PATH.read_text())
    validator = Draft202012Validator(schema)

    rc = 0
    for arg in argv:
        rc |= validate_file(Path(arg), validator)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
