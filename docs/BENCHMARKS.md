# Benchmarks

`benchmarks/benchmark.sh` compares `asmgrep` with GNU grep (`grep -F` and
`grep`) using hyperfine. `make benchmark` runs it with defaults;
`benchmarks/benchmark.sh SIZE_MB RUNS` changes the large-file size and run
count. `benchmarks/generate_data.sh` creates the inputs deterministically
(fixed awk seed).

## Method

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
  was not measured. Memory consumption was not measured (`/usr/bin/time` was
  unavailable on the test machine).

## Test machine

| | |
|---|---|
| CPU | Intel Xeon @ 2.10 GHz (virtual machine); flags include sse2, popcnt |
| RAM | 4 GB |
| OS | Linux 6.18 |
| Tools | GNU grep 3.11, hyperfine 1.18.0 |
| Build | `make` (no extra flags) |

## Results (mean ± σ, 10 runs)

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

These come from a single run on one virtualized machine and will vary with
hardware and load. The "40-byte pattern" row uses the text
`request handled in 1000 ms and then some` against the no-match file.

## Reading the numbers

- asmgrep is faster on the tiny file mostly because it is a static binary
  with no dynamic-loading or locale start-up cost.
- On sparse and no-match inputs asmgrep is roughly level with, or a little
  slower than, GNU grep on this machine. GNU grep spends most of its time in
  the kernel reading the file (high system time), asmgrep spends it in user
  space scanning 16 bytes at a time; GNU grep's matcher is more efficient per
  byte here.
- asmgrep is clearly ahead when many lines match, where its line handling
  and output path dominate, and with `-n`.
- asmgrep does not outperform GNU grep in every case, and these results
  should not be generalized to other data or machines. Multi-gigabyte files
  were not benchmarked.
