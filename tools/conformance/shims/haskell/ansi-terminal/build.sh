#!/usr/bin/env bash
# Build script: cabal build + install binary into bin/ for a stable manifest path.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p bin
cabal build
cabal install --installdir=bin --install-method=copy --overwrite-policy=always exe:ansi-terminal-shim
echo "ansi-terminal-shim built at bin/ansi-terminal-shim" >&2
