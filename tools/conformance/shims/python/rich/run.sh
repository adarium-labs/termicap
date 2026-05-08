#!/usr/bin/env bash
# Wrapper that invokes shim.py inside this shim's own venv.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/.venv/bin/python" "$DIR/shim.py" "$@"
