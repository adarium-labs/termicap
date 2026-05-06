#!/bin/bash
# format_code.sh — Format all Ada code in the project using gnatformat via Alire
#
# Customize the PROJECT_DIRS array below to list each sub-crate that should
# be formatted, along with its .gpr file name.
#
# Usage:  ./tools/format_code.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Code Formatter ==="

# ---------------------------------------------------------------------------
# CUSTOMIZE: List each (directory, gpr_file) pair to format.
# Use --no-subprojects on the main library to avoid formatting dependencies.
# Remove --no-subprojects where you want recursive formatting.
# ---------------------------------------------------------------------------
# Format: "relative_dir|gpr_file|flags"
#   flags: optional, e.g., "--no-subprojects"
PROJECT_DIRS=(
    ".|termicap.gpr|--no-subprojects"
    # "examples|Termicap_examples.gpr|"
    # "tests|Termicap_tests.gpr|"
)

for entry in "${PROJECT_DIRS[@]}"; do
    IFS='|' read -r dir gpr flags <<< "$entry"

    if [[ ! -d "$REPO_ROOT/$dir" ]]; then
        echo "SKIP: $dir (directory not found)"
        continue
    fi

    echo -e "\n=== Formatting $dir ($gpr) ==="
    cd "$REPO_ROOT/$dir"

    if [[ -n "$flags" ]]; then
        alr exec -- gnatformat -P "$gpr" $flags
    else
        alr exec -- gnatformat -P "$gpr"
    fi
done

echo -e "\n=== Code formatting complete ==="
