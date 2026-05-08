#!/usr/bin/env bash
# Build script for the JLine shim:
#   - download jline-X.jar to libs/ (one-time, idempotent)
#   - javac the Java source
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

JLINE_VERSION="${JLINE_VERSION:-3.30.4}"
JLINE_JAR="libs/jline.jar"
JLINE_URL="https://repo1.maven.org/maven2/org/jline/jline/${JLINE_VERSION}/jline-${JLINE_VERSION}.jar"

mkdir -p libs build

if [[ ! -f "$JLINE_JAR" ]]; then
  echo "Downloading JLine ${JLINE_VERSION}..." >&2
  curl -fsSL -o "$JLINE_JAR" "$JLINE_URL"
fi

# --release 17 keeps us inside JLine's compiled bytecode floor while
# tolerating Java 25 host (host warns about restricted API but still works).
javac --release 17 -cp "$JLINE_JAR" -d build src/JlineShim.java
echo "JLine shim compiled to build/JlineShim.class" >&2
