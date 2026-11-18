#!/usr/bin/env bash
# Comprehensive single-file CLI benchmark for asmgrep, GNU grep and ripgrep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/build/asmgrep"
DATA="$ROOT/benchmarks/data"
RUNS="${1:-15}"
OUT="$ROOT/benchmarks/results"

GREP=/usr/bin/grep
RG=/usr/bin/rg

for tool in hyperfine "$GREP" "$RG" /usr/bin/time; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Missing required tool: $tool" >&2
        exit 1
    }
done

[[ -x "$BIN" ]] || {
    echo "asmgrep is not built. Run make first." >&2
    exit 1
}

mkdir -p "$OUT"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULT="$OUT/benchmark-$STAMP"
mkdir -p "$RESULT"

export LC_ALL=C
export GREP_COLORS=

echo "=================================================="
echo " asmgrep comprehensive CLI benchmark"
echo "=================================================="
echo "Date: $(date -Is)"
echo "Runs: $RUNS"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
echo "Kernel: $(uname -sr)"
echo "asmgrep: $("$BIN" --version)"
echo "GNU grep: $("$GREP" --version | head -n1)"
echo "ripgrep: $("$RG" --version | head -n1)"
echo "hyperfine: $(hyperfine --version)"
echo "Output: $RESULT"

# Every tool receives the same pattern, input and output destination.
# Output is redirected to a pipe, avoiding grep's /dev/null early-exit
# optimization on match-heavy datasets.
run_case() {
    local name="$1"
    local file="$2"
    local pattern="$3"
    local mode="${4:-normal}"

    local asm_options=""
    local grep_options="-F"
    local rg_options="-F"

    case "$mode" in
        normal) ;;
        count)
            asm_options="-c"
            grep_options="-cF"
            rg_options="-cF"
            ;;
        line-number)
            asm_options="-n"
            grep_options="-nF"
            rg_options="-nF"
            ;;
        *)
            echo "Unknown mode: $mode" >&2
            exit 1
            ;;
    esac

    local safe_name
    safe_name="$(printf '%s' "$name" | tr ' /' '__')"

    echo
    echo "===== $name ====="
    echo "File: $file"
    echo "Pattern: $pattern"
    echo "Mode: $mode"

    local output="$RESULT/$safe_name.json"

    hyperfine \
        --warmup 3 \
        --runs "$RUNS" \
        --ignore-failure \
        --output=pipe \
        --export-json "$output" \
        --command-name "asmgrep-SSE2" \
            "\"$BIN\" $asm_options --color=never -- '$pattern' '$file'" \
        --command-name "asmgrep-scalar" \
            "\"$BIN\" --scalar $asm_options --color=never -- '$pattern' '$file'" \
        --command-name "GNU-grep" \
            "\"$GREP\" $grep_options -- '$pattern' '$file'" \
        --command-name "ripgrep" \
            "\"$RG\" $rg_options -- '$pattern' '$file'"

    echo "Saved: $output"
}

run_case "small-sparse" "$DATA/small.log" "ERROR"
run_case "medium-sparse" "$DATA/medium.log" "ERROR"
run_case "large-sparse" "$DATA/large_sparse.log" "ERROR"
run_case "large-dense" "$DATA/large_dense.log" "ERROR"
run_case "large-no-match" "$DATA/large_nomatch.log" "ERROR"
run_case "large-long-pattern" "$DATA/large_longmatch.log" \
    "request handled in 1000 ms and then some"

run_case "large-sparse-count" "$DATA/large_sparse.log" "ERROR" count
run_case "large-sparse-line-numbers" "$DATA/large_sparse.log" "ERROR" line-number

echo
echo "=================================================="
echo " Benchmark complete"
echo " Results: $RESULT"
echo "=================================================="
