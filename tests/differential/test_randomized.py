
#!/usr/bin/env python3
"""Deterministic randomized differential tests for asmgrep."""

import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bindings" / "python"))

import asmgrep


SEED = 0xA5A5_2026
CASES = 10_000
MAX_DATA = 4096
MAX_PATTERN = 256

rng = random.Random(SEED)


def reference_search(data: bytes, pattern: bytes):
    """Independent line-oriented reference implementation."""

    if not data:
        return []

    lines = data.split(b"\n")

    # A trailing newline does not create an extra final line.
    if data.endswith(b"\n"):
        lines.pop()

    return [
        (number, line)
        for number, line in enumerate(lines, 1)
        if pattern in line
    ]


def random_pattern(length):
    """Generate arbitrary pattern bytes, excluding newline."""
    alphabet = [b for b in range(256) if b != 10]
    return bytes(rng.choice(alphabet) for _ in range(length))


def make_case(index):
    """Generate varied data and patterns."""

    mode = index % 6

    if mode == 0:
        # Completely random binary data.
        data = rng.randbytes(rng.randint(0, MAX_DATA))
        pattern = random_pattern(rng.randint(0, MAX_PATTERN))

    elif mode == 1:
        # Repetitive data.
        byte = rng.choice([0, 65, 97, 255])
        data = bytes([byte]) * rng.randint(0, MAX_DATA)
        pattern = bytes([byte]) * rng.randint(0, MAX_PATTERN)

    elif mode == 2:
        # Patterns taken from existing lines: guaranteed possible matches.
        data = rng.randbytes(rng.randint(1, MAX_DATA))
        lines = data.split(b"\n")
        line = rng.choice(lines)
        if line:
            start = rng.randrange(len(line))
            end = rng.randint(start + 1, len(line))
            pattern = line[start:end]
        else:
            pattern = b""

    elif mode == 3:
        # Short patterns.
        data = rng.randbytes(rng.randint(0, MAX_DATA))
        pattern = random_pattern(rng.randint(1, 4))

    elif mode == 4:
        # Long patterns.
        data = rng.randbytes(rng.randint(0, MAX_DATA))
        pattern = random_pattern(rng.randint(64, MAX_PATTERN))

    else:
        # Empty patterns and empty/small inputs.
        data = rng.randbytes(rng.randint(0, 128))
        pattern = b""

    return data, pattern


def normalize(matches):
    return [(m.line_number, m.raw) for m in matches]


def check_case(index, data, pattern):
    expected = reference_search(data, pattern)

    for engine, scalar in (("SSE2", False), ("scalar", True)):
        actual = normalize(
            asmgrep.search_bytes(pattern, data, scalar=scalar)
        )

        if actual != expected:
            raise AssertionError(
                f"\nMismatch detected!\n"
                f"Seed: {SEED}\n"
                f"Case: {index}\n"
                f"Engine: {engine}\n"
                f"Pattern: {pattern!r}\n"
                f"Data length: {len(data)}\n"
                f"Expected: {expected!r}\n"
                f"Actual:   {actual!r}\n"
            )


def main():
    print(f"Randomized differential testing")
    print(f"Seed: {SEED}")
    print(f"Cases: {CASES}")
    print()

    for index in range(CASES):
        data, pattern = make_case(index)
        check_case(index, data, pattern)

    print(f"PASS: {CASES:,} randomized cases")
    print("PASS: SSE2 and scalar agree with Python reference")


if __name__ == "__main__":
    main()
