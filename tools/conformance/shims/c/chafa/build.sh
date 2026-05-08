#!/usr/bin/env bash
# Build the chafa C shim. Uses pkg-config for chafa+glib include/lib paths.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p build
CFLAGS_PKG="$(pkg-config --cflags chafa)"
LDFLAGS_PKG="$(pkg-config --libs chafa)"
# shellcheck disable=SC2086
cc -O2 -Wall -Wextra -o build/chafa-shim shim.c $CFLAGS_PKG $LDFLAGS_PKG
echo "chafa-shim built at build/chafa-shim" >&2
