# Benchmarks

`benchmarks/benchmark.sh` compares `asmgrep` with GNU grep (`grep -F` and
`grep`) using hyperfine. `make benchmark` runs it with defaults;
`benchmarks/benchmark.sh SIZE_MB RUNS` changes the large-file size and run
count. `benchmarks/generate_data.sh` creates the inputs deterministically
(fixed awk seed).

## Test machine

| | |
|---|---|
| CPU | Intel Core i3-1115G4 @ 3.00 GHz |
| Architecture | x86-64 |
| SIMD | SSE2 |
| OS | Linux |
| Build | `make` (no extra flags) |

## GNU grep comparison

### Method

- Inputs: synthetic request-log lines (about 60 bytes each).
  `small` = 1 MB, `medium` = 32 MB, `large_*` = `SIZE_MB` (256 by default).
  `sparse` has `ERROR` on one line in 1000, `dense` on every second line,
  `nomatch` never.
- hyperfine options: `-N` (no shell), `--warmup 3`, `--runs 10`,
  `--output=pipe`.
- Output goes to a pipe, not `/dev/null`: GNU grep stops at the first match
  when its stdout is `/dev/null`, which makes match-heavy timings
  meaningless.
- The page cache was warm; files were read from RAM. Cold-cache behavior
  was not measured. Memory consumption was not measured.

### Results (mean ± σ, 10 runs)

| Case | asmgrep | grep -F | grep |
|---|---:|---:|---:|
| small (1 MB), sparse | 0.21 ms ± 0.03 | 1.3 ms ± 0.2 | 1.2 ms ± 0.2 |
| medium (32 MB), sparse | 6.1 ms ± 1.2 | 4.9 ms ± 0.5 | 4.1 ms ± 0.3 |
| large (256 MB), sparse | 49.7 ms ± 1.2 | 44.6 ms ± 0.9 | 47.7 ms ± 3.6 |
| large, dense | 100.3 ms ± 3.1 | 356.1 ms ± 56.3 | 327.4 ms ± 27.2 |
| large, no match | 55.9 ms ± 6.5 | 45.1 ms ± 1.5 | 47.7 ms ± 2.1 |
| large, 40-byte pattern, no match | 117.5 ms ± 21.7 | 110.6 ms ± 3.9 | 108.2 ms ± 1.5 |
| large, sparse, `-c` | 50.9 ms ± 2.6 | 50.0 ms ± 4.5 | 47.4 ms ± 2.1 |
| large, sparse, `-n` | 66.6 ms ± 8.4 | 81.3 ms ± 3.8 | 78.6 ms ± 4.9 |

The "40-byte pattern" row uses the text
`request handled in 1000 ms and then some` against the no-match file.

### Reading the numbers

- asmgrep is faster on the tiny file mostly because it is a static binary
  with no dynamic-loading or locale start-up cost.
- On sparse and no-match inputs asmgrep is roughly level with, or a little
  slower than, GNU grep. GNU grep spends much of its time reading the file;
  its matcher is more efficient per byte on these workloads.
- asmgrep is clearly ahead when many lines match, where its line handling
  and output path dominate, and with `-n`.
- asmgrep does not outperform GNU grep in every case. These results should
  not be generalized to other data or machines. Multi-gigabyte files were
  not benchmarked.

## Adaptive anchor optimization

`bench_search_optimization.py` compares three implementations:

- **Original:** the implementation before adaptive anchor selection.
- **Adaptive:** adaptive anchor selection performed for each search.
- **Cached:** adaptive anchor selection with the selected anchor reused
  across line searches within a scan.

The benchmark checks that all three implementations produce identical
results before reporting timings. It uses 50 paired benchmark rounds and
reports median timings and 95% bootstrap confidence intervals.

### Results

Results from a separate benchmark run on the Intel Core i3-1115G4:

| Workload | Original median | Adaptive median | Cached median |
|---|---:|---:|---:|
| Sparse long match | 102.163 ms | 98.968 ms | 100.001 ms |
| Dense long match | 58.133 ms | 828.321 ms | 48.973 ms |
| Long no match | 33.194 ms | 32.999 ms | 33.017 ms |

### Cached speedup over original

| Workload | Speedup | 95% bootstrap CI |
|---|---:|---:|
| Sparse long match | 1.026x | [1.016x, 1.034x] |
| Dense long match | 1.190x | [1.186x, 1.201x] |
| Long no match | 1.001x | [0.999x, 1.004x] |

### Interpretation

Caching is especially useful for dense matching workloads. In this test,
the cached implementation was approximately 19% faster than the original
implementation.

The uncached adaptive implementation was substantially slower on dense
matches because it repeatedly paid the sampling cost. Caching removes
that repeated overhead.

The sparse workload showed a smaller improvement. The no-match workload
was effectively unchanged within the measured confidence interval.

These results describe specific workloads on one machine. They do not
establish a universal speed advantage over GNU grep or other search
implementations.