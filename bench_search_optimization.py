import subprocess
import time
import statistics
import random

original = "/tmp/asmgrep-original"
adaptive = "/tmp/asmgrep-adaptive"
cached = "/tmp/asmgrep-cached"

binaries = [
    ("Original", original),
    ("Adaptive", adaptive),
    ("Cached", cached),
]

workloads = [
    (
        "Sparse long match",
        "benchmarks/data/large_sparse.log",
        "e829dadd cc88d76d a5c022c6 request handled in 260 ms",
    ),
    (
        "Dense long match",
        "benchmarks/data/large_dense.log",
        "request handled in",
    ),
    (
        "Long no match",
        "benchmarks/data/large_nomatch.log",
        "THIS_PATTERN_SHOULD_NEVER_APPEAR_123456789",
    ),
]

RUNS = 50
random.seed(42)


def run(binary, filename, pattern):
    start = time.perf_counter_ns()

    result = subprocess.run(
        [binary, "-c", pattern, filename],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    elapsed = (time.perf_counter_ns() - start) / 1_000_000

    if result.returncode not in (0, 1):
        raise RuntimeError(
            f"{binary} failed:\n{result.stderr.decode(errors='replace')}"
        )

    return elapsed, result.stdout


def report_comparison(reference_times, candidate_times):
    ratios = [
        old / new
        for old, new in zip(reference_times, candidate_times)
    ]

    boot = []
    for _ in range(10000):
        boot.append(statistics.median(random.choices(ratios, k=RUNS)))

    boot.sort()

    print(f"  Speedup vs original: {statistics.median(ratios):.3f}x")
    print(f"  95% bootstrap CI:    [{boot[249]:.3f}x, {boot[9749]:.3f}x]")


for name, filename, pattern in workloads:
    print(f"\n=== {name} ===", flush=True)
    print(f"Pattern length: {len(pattern)} bytes")

    # Verify that all three implementations return identical counts.
    outputs = {
        label: run(binary, filename, pattern)[1]
        for label, binary in binaries
    }

    if len(set(outputs.values())) != 1:
        raise RuntimeError(f"RESULT MISMATCH in {name}: {outputs}")

    print("Correctness: PASS")

    # Warm up all implementations.
    for _ in range(3):
        for _, binary in binaries:
            run(binary, filename, pattern)

    times = {label: [] for label, _ in binaries}

    # Rotate execution order to reduce ordering bias.
    for i in range(RUNS):
        order = binaries[i % 3:] + binaries[:i % 3]

        for label, binary in order:
            elapsed, _ = run(binary, filename, pattern)
            times[label].append(elapsed)

    for label, _ in binaries:
        print(
            f"{label:>8} median: "
            f"{statistics.median(times[label]):.3f} ms"
        )

    print("\nAdaptive:")
    report_comparison(times["Original"], times["Adaptive"])

    print("\nCached:")
    report_comparison(times["Original"], times["Cached"])
