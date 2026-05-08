#!/usr/bin/env bash
# Wrapper that resolves the platform-specific .build/<triple>/release/ path.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
BIN_DIR="$(swift build -c release --show-bin-path 2>/dev/null)"
exec "$BIN_DIR/ConsoleKitShim" "$@"
