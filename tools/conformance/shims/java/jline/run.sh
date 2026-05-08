#!/usr/bin/env bash
# Run wrapper that invokes the compiled JLine shim.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec java --enable-native-access=ALL-UNNAMED -cp "$DIR/build:$DIR/libs/jline.jar" JlineShim "$@"
