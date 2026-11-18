#!/usr/bin/env bash
# Extended pattern-length and pattern-file benchmarks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build/asmgrep"
DATA="$ROOT/benchmarks/data/extended"
RUNS="${1:-15}"
GREP=/usr/bin/grep
RG=/usr/bin/rg

for tool in hyperfine "$GREP" "$RG"; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing tool: $tool" >&2
        exit 1
    }
done

[[ -x "$BIN" ]] || {
    echo "Build asmgrep first: make" >&2
    exit 1
}

[[ -d "$DATA" ]] || {
    echo "Missing extended datasets. Run generate_extended_data.py first." >&2
    exit 1
}

export LC_ALL=C
export GREP_COLORS=

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/benchmarks/results/extended-$STAMP"
mkdir -p "$OUT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=================================================="
echo " asmgrep extended benchmark"
echo "=================================================="
echo "Date: $(date -Is)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
echo "asmgrep: $("$BIN" --version)"
echo "GNU grep: $("$GREP" --version | head -n1)"
echo "ripgrep: $("$RG" --version | head -n1)"
echo "hyperfine: $(hyperfine --version)"
echo "Runs: $RUNS"
echo "Output: $OUT"

benchmark_single() {
    local length="$1"
    local pattern
    pattern="$(printf '%*s' "$length" '' | tr ' ' Q)"
    local file="$DATA/pattern_$(printf '%02d' "$length").log"
    local json="$OUT/pattern-${length}-bytes.json"

    echo
    echo "===== SINGLE PATTERN: $length bytes ====="

    # Correctness preflight.
    "$BIN" --color=never -- "$pattern" "$file" > "$TMP/asm"
    "$GREP" -- "$pattern" "$file" > "$TMP/grep-regex"
    "$GREP" -F -- "$pattern" "$file" > "$TMP/grep-fixed"
    "$RG" -- "$pattern" "$file" > "$TMP/rg-regex"
    "$RG" -F -- "$pattern" "$file" > "$TMP/rg-fixed"

    cmp "$TMP/asm" "$TMP/grep-regex"
    cmp "$TMP/asm" "$TMP/grep-fixed"
    cmp "$TMP/asm" "$TMP/rg-regex"
    cmp "$TMP/asm" "$TMP/rg-fixed"

    echo "Correctness: PASS"

    hyperfine \
        --warmup 3 \
        --runs "$RUNS" \
        --ignore-failure \
        --output=pipe \
        --export-json "$json" \
        --command-name "asmgrep-SSE2" \
            "\"$BIN\" --color=never -- '$pattern' '$file'" \
        --command-name "asmgrep-scalar" \
            "\"$BIN\" --scalar --color=never -- '$pattern' '$file'" \
        --command-name "GNU-grep-regex" \
            "\"$GREP\" -- '$pattern' '$file'" \
        --command-name "GNU-grep-fixed" \
            "\"$GREP\" -F -- '$pattern' '$file'" \
        --command-name "ripgrep-regex" \
            "\"$RG\" -- '$pattern' '$file'" \
        --command-name "ripgrep-fixed" \
            "\"$RG\" -F -- '$pattern' '$file'"

    echo "Saved: $json"
}

benchmark_pattern_file() {
    local json="$OUT/pattern-file-16-patterns.json"
    local patterns="$DATA/patterns.txt"
    local file="$DATA/multi_pattern.log"

    echo
    echo "===== PATTERN FILE: 16 PATTERNS ====="

    # Correctness preflight.
    "$GREP" -f "$patterns" "$file" > "$TMP/grep-regex"
    "$GREP" -Ff "$patterns" "$file" > "$TMP/grep-fixed"
    "$RG" -f "$patterns" "$file" > "$TMP/rg-regex"
    "$RG" -Ff "$patterns" "$file" > "$TMP/rg-fixed"

    cmp "$TMP/grep-regex" "$TMP/grep-fixed"
    cmp "$TMP/grep-regex" "$TMP/rg-regex"
    cmp "$TMP/grep-regex" "$TMP/rg-fixed"

    echo "Correctness: PASS"

    hyperfine \
        --warmup 3 \
        --runs "$RUNS" \
        --ignore-failure \
        --output=pipe \
        --export-json "$json" \
        --command-name "GNU-grep-pattern-file" \
            "\"$GREP\" -f '$patterns' '$file'" \
        --command-name "GNU-grep-fixed-pattern-file" \
            "\"$GREP\" -Ff '$patterns' '$file'" \
        --command-name "ripgrep-pattern-file" \
            "\"$RG\" -f '$patterns' '$file'" \
        --command-name "ripgrep-fixed-pattern-file" \
            "\"$RG\" -Ff '$patterns' '$file'"

    echo "Saved: $json"
}

for length in 1 2 4 8 16 32 64; do
    benchmark_single "$length"
done

benchmark_pattern_file

echo
echo "=================================================="
echo " Extended benchmark complete"
echo " Results: $OUT"
echo "=================================================="
