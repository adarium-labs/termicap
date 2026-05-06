#!/bin/bash
# generate_trace_matrix.sh — Generate bidirectional traceability matrix
#
# Extracts @relation(REQ-ID) annotations from Ada source and test files,
# cross-references with StrictDoc requirement UIDs, and outputs:
#   - output/traceability-matrix.md  (Markdown table)
#   - output/traceability-matrix.csv (CSV for CI/tooling)
#
# Role inference from file path:
#   ./**/*.ads  (excluding tests/) → Specification
#   ./**/*.adb  (excluding tests/) → Implementation
#   tests/**/*                         → Verification
#
# Options:
#   --all    Show all requirements (default: only FUNC-* requirements)
#
# CUSTOMIZE: Search the file for "CUSTOMIZE" comments and adjust paths/patterns.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/output"

# ---------------------------------------------------------------------------
# CUSTOMIZE: Paths relative to PROJECT_ROOT
# ---------------------------------------------------------------------------
REQ_DIR="docs/requirements"              # StrictDoc requirements directory
SRC_DIR="."             # Library/source root (scanned for .ads/.adb)
TEST_DIR="tests"           # Test root (scanned for @relation in tests)
TEST_SRC_SUBDIR="src"             # Subdirectory within TEST_DIR containing test sources

# CUSTOMIZE: Default filter prefix (set to empty string "" to show all by default)
DEFAULT_PREFIX="FUNC-"

# ---------------------------------------------------------------------------
# Parse options
# ---------------------------------------------------------------------------
SHOW_ALL=false
for arg in "$@"; do
    case "$arg" in
        --all) SHOW_ALL=true ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# Temporary work files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

REQS_FILE="$TMP_DIR/requirements.tsv"
SPEC_FILE="$TMP_DIR/spec_relations.tsv"
IMPL_FILE="$TMP_DIR/impl_relations.tsv"
TEST_FILE="$TMP_DIR/test_relations.tsv"

# ---------------------------------------------------------------------------
# Step 1: Extract all requirement UIDs and STATUS from .sdoc files
# ---------------------------------------------------------------------------
extract_requirements() {
    local req_dir="$PROJECT_ROOT/$REQ_DIR"

    if [[ ! -d "$req_dir" ]]; then
        echo "WARNING: Requirements directory not found: $req_dir" >&2
        return
    fi

    local sdoc_files
    sdoc_files=$(find "$req_dir" -name "*.sdoc" 2>/dev/null)
    if [[ -z "$sdoc_files" ]]; then
        echo "WARNING: No .sdoc files found in $req_dir" >&2
        return
    fi

    local in_req=false
    local uid=""
    local status=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            if $in_req && [[ -n "$uid" ]]; then
                [[ -z "$status" ]] && status="Draft"
                printf '%s\t%s\n' "$uid" "$status"
            fi
            if [[ "$line" == "[REQUIREMENT]" ]]; then
                in_req=true
            else
                in_req=false
            fi
            uid=""
            status=""
        elif $in_req; then
            if [[ "$line" =~ ^UID:\ *(.*) ]]; then
                uid="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^STATUS:\ *(.*) ]]; then
                status="${BASH_REMATCH[1]}"
            fi
        fi
    done < <(cat "$req_dir"/*.sdoc)

    # Flush last requirement
    if $in_req && [[ -n "$uid" ]]; then
        [[ -z "$status" ]] && status="Draft"
        printf '%s\t%s\n' "$uid" "$status"
    fi
}

# ---------------------------------------------------------------------------
# Step 2: Extract @relation(REQ-ID) from source files
# ---------------------------------------------------------------------------
extract_relations() {
    local search_path="$1"
    local glob_pattern="$2"
    local exclude_pattern="${3:-}"

    [[ ! -d "$search_path" ]] && return

    find "$search_path" -name "$glob_pattern" -print0 2>/dev/null | while IFS= read -r -d '' file; do
        if [[ -n "$exclude_pattern" && "$file" == *"$exclude_pattern"* ]]; then
            continue
        fi
        local matches
        matches=$(grep -oE '@relation\([A-Z]+-[A-Z]*-?[0-9]+\)' "$file" 2>/dev/null || true)
        [[ -z "$matches" ]] && continue
        local bname
        bname=$(basename "$file")
        echo "$matches" | while read -r match; do
            local req_id
            req_id=$(echo "$match" | sed 's/@relation(\(.*\))/\1/')
            printf '%s\t%s\n' "$req_id" "$bname"
        done
    done
}

extract_test_relations() {
    local test_src="$PROJECT_ROOT/$TEST_DIR/$TEST_SRC_SUBDIR"
    [[ ! -d "$test_src" ]] && test_src="$PROJECT_ROOT/$TEST_DIR"

    for ext in ads adb; do
        find "$test_src" -name "*.$ext" -print0 2>/dev/null | while IFS= read -r -d '' file; do
            local matches
            matches=$(grep -oE '@relation\([A-Z]+-[A-Z]*-?[0-9]+\)' "$file" 2>/dev/null || true)
            [[ -z "$matches" ]] && continue
            local bname
            bname=$(basename "$file")
            echo "$matches" | while read -r match; do
                local req_id
                req_id=$(echo "$match" | sed 's/@relation(\(.*\))/\1/')
                printf '%s\t%s\n' "$req_id" "$bname"
            done
        done
    done
}

# ---------------------------------------------------------------------------
# Step 3: Build the matrix
# ---------------------------------------------------------------------------

echo "Extracting requirements from StrictDoc files..."
if $SHOW_ALL || [[ -z "$DEFAULT_PREFIX" ]]; then
    extract_requirements | sort -u > "$REQS_FILE"
else
    extract_requirements | sort -u | grep "^${DEFAULT_PREFIX}" > "$REQS_FILE" || true
fi

if [[ ! -s "$REQS_FILE" ]]; then
    echo "No requirements found. Check that $REQ_DIR contains .sdoc files with [REQUIREMENT] blocks."
    exit 0
fi

echo "Scanning .ads files (Specification)..."
extract_relations "$PROJECT_ROOT/$SRC_DIR" "*.ads" "tests/" > "$SPEC_FILE" 2>/dev/null || true

echo "Scanning .adb files (Implementation)..."
extract_relations "$PROJECT_ROOT/$SRC_DIR" "*.adb" "tests/" > "$IMPL_FILE" 2>/dev/null || true

echo "Scanning test files (Verification)..."
extract_test_relations | sort -u > "$TEST_FILE"

# ---------------------------------------------------------------------------
# Step 4: Generate outputs
# ---------------------------------------------------------------------------

REQ_COUNT=$(wc -l < "$REQS_FILE" | tr -d ' ')
COVERED_FULL=0
COVERED_SPEC=0
COVERED_TEST=0
COVERED_NONE=0

MD_FILE="$OUTPUT_DIR/traceability-matrix.md"
CSV_FILE="$OUTPUT_DIR/traceability-matrix.csv"

{
    echo "# Traceability Matrix"
    echo ""
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "| Requirement | Status | Spec (.ads) | Impl (.adb) | Test | Coverage |"
    echo "|---|---|---|---|---|---|"
} > "$MD_FILE"

echo "requirement,status,spec_files,impl_files,test_files,coverage" > "$CSV_FILE"

while IFS=$'\t' read -r uid status; do
    spec_files=$(awk -F'\t' -v uid="$uid" '$1 == uid { print $2 }' "$SPEC_FILE" | sort -u | paste -sd ',' - 2>/dev/null)
    [[ -z "$spec_files" ]] && spec_files="-"

    impl_files=$(awk -F'\t' -v uid="$uid" '$1 == uid { print $2 }' "$IMPL_FILE" | sort -u | paste -sd ',' - 2>/dev/null)
    [[ -z "$impl_files" ]] && impl_files="-"

    test_files=$(awk -F'\t' -v uid="$uid" '$1 == uid { print $2 }' "$TEST_FILE" | sort -u | paste -sd ',' - 2>/dev/null)
    [[ -z "$test_files" ]] && test_files="-"

    has_spec=false
    has_test=false
    [[ "$spec_files" != "-" ]] && has_spec=true
    [[ "$test_files" != "-" ]] && has_test=true

    if $has_spec && $has_test; then
        coverage="Full"
        COVERED_FULL=$((COVERED_FULL + 1))
    elif $has_spec; then
        coverage="Spec only"
        COVERED_SPEC=$((COVERED_SPEC + 1))
    elif $has_test; then
        coverage="Test only"
        COVERED_TEST=$((COVERED_TEST + 1))
    else
        coverage="None"
        COVERED_NONE=$((COVERED_NONE + 1))
    fi

    echo "| $uid | $status | $spec_files | $impl_files | $test_files | $coverage |" >> "$MD_FILE"
    echo "\"$uid\",\"$status\",\"$spec_files\",\"$impl_files\",\"$test_files\",\"$coverage\"" >> "$CSV_FILE"

done < "$REQS_FILE"

# Summary
{
    echo ""
    echo "## Summary"
    echo ""
    echo "| Metric | Count |"
    echo "|---|---|"
    echo "| Total requirements | $REQ_COUNT |"
    echo "| Full coverage (spec + test) | $COVERED_FULL |"
    echo "| Spec only | $COVERED_SPEC |"
    echo "| Test only | $COVERED_TEST |"
    echo "| No coverage | $COVERED_NONE |"
} >> "$MD_FILE"

echo ""
echo "Traceability matrix generated:"
echo "  Markdown: $MD_FILE"
echo "  CSV:      $CSV_FILE"
echo ""
if $SHOW_ALL || [[ -z "$DEFAULT_PREFIX" ]]; then
    echo "Summary (all): $REQ_COUNT requirements — Full: $COVERED_FULL, Spec only: $COVERED_SPEC, Test only: $COVERED_TEST, None: $COVERED_NONE"
else
    echo "Summary (${DEFAULT_PREFIX}* only, use --all for all): $REQ_COUNT requirements — Full: $COVERED_FULL, Spec only: $COVERED_SPEC, Test only: $COVERED_TEST, None: $COVERED_NONE"
fi
