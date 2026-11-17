#!/usr/bin/env bash
# Generates reproducible benchmark inputs.
# Usage: benchmarks/generate_data.sh [OUTPUT_DIR] [SIZE_MB]
set -euo pipefail

out=${1:-benchmarks/data}
size_mb=${2:-256}
mkdir -p "$out"

# Deterministic pseudo-random log lines. A fixed awk seed makes the data
# identical on every run. Line shape: "<n> <level> <hex words...>".
gen() { # gen <approx MB> <ERROR every N lines (0 = never)>
    awk -v mb="$1" -v every="$2" 'BEGIN {
        srand(12345); bytes = 0; limit = mb * 1048576; n = 0
        while (bytes < limit) {
            n++
            line = sprintf("%d INFO %08x %08x %08x request handled in %d ms",
                           n, int(rand()*4294967295), int(rand()*4294967295),
                           int(rand()*4294967295), int(rand()*900))
            if (every > 0 && n % every == 0) sub(/INFO/, "ERROR", line)
            print line
            bytes += length(line) + 1
        }
    }'
}

gen 1          1000 > "$out/small.log"
gen 32         1000 > "$out/medium.log"
gen "$size_mb" 1000 > "$out/large_sparse.log"
gen "$size_mb" 2    > "$out/large_dense.log"
gen "$size_mb" 0    > "$out/large_nomatch.log"

echo "Generated data in $out:"
ls -l "$out"
