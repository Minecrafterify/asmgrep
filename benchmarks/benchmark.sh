#!/usr/bin/env bash
# Compares asmgrep with GNU grep using hyperfine.
# Usage: benchmarks/benchmark.sh [SIZE_MB] [RUNS]
# Requires: hyperfine, GNU grep, a built build/asmgrep.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIZE_MB=${1:-256}
RUNS=${2:-10}
DATA="$ROOT/benchmarks/data"
BIN="$ROOT/build/asmgrep"

command -v hyperfine >/dev/null || { echo "error: hyperfine not found" >&2; exit 1; }
[ -x "$BIN" ] || { echo "error: $BIN missing; run make first" >&2; exit 1; }

"$ROOT/benchmarks/generate_data.sh" "$DATA" "$SIZE_MB" >/dev/null

echo "== environment =="
grep -m1 'model name' /proc/cpuinfo || true
grep -m1 -o -E 'sse2|popcnt' /proc/cpuinfo | sort -u | tr '\n' ' ' || true; echo
grep -m1 MemTotal /proc/meminfo || true
uname -sr
grep --version | head -n1
hyperfine --version
echo "runs: $RUNS (3 warmup runs, page cache warm)"

# Output goes to a pipe, not /dev/null: GNU grep stops at the first match when
# its output is /dev/null, which would make match-heavy runs meaningless.
run() { # run <label> <file> <pattern> [options]
    local label=$1 file=$2 pat=$3
    shift 3
    echo
    echo "== $label ($(( $(stat -c %s "$file") / 1048576 )) MB, pattern '$pat' ${*:-}) =="
    hyperfine --warmup 3 --runs "$RUNS" -N --ignore-failure --output=pipe \
        --command-name "asmgrep" "$BIN $* -- '$pat' $file" \
        --command-name "grep -F" "grep -F $* -- '$pat' $file" \
        --command-name "grep" "grep $* -- '$pat' $file"
}

run "small, sparse"        "$DATA/small.log"        "ERROR"
run "medium, sparse"       "$DATA/medium.log"       "ERROR"
run "large, sparse"        "$DATA/large_sparse.log" "ERROR"
run "large, dense"         "$DATA/large_dense.log"  "ERROR"
run "large, no match"      "$DATA/large_nomatch.log" "ERROR"
run "large, long pattern"  "$DATA/large_nomatch.log" "request handled in 1000 ms and then some"
run "large, count only"    "$DATA/large_sparse.log" "ERROR" -c
run "large, line numbers"  "$DATA/large_sparse.log" "ERROR" -n

echo
if [ -x /usr/bin/time ]; then
    echo "== peak memory (kB), large sparse =="
    for tool in "$BIN" "grep -F"; do
        /usr/bin/time -f "$tool: %M kB" $tool ERROR "$DATA/large_sparse.log" >/dev/null || true
    done
else
    echo "peak memory not measured: /usr/bin/time is not installed"
fi
