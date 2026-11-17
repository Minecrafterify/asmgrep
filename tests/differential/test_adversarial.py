
#!/usr/bin/env python3
"""Adversarial input tests for asmgrep."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bindings" / "python"))

import asmgrep


SIZE = 1 * 1024 * 1024


def reference_search(data, pattern):
    if not data:
        return []

    lines = data.split(b"\n")
    if data.endswith(b"\n"):
        lines.pop()

    return [
        (number, line)
        for number, line in enumerate(lines, 1)
        if pattern in line
    ]


def check(data, pattern, label):
    expected = reference_search(data, pattern)

    for engine, scalar in (("SSE2", False), ("scalar", True)):
        matches = asmgrep.search_bytes(pattern, data, scalar=scalar)
        actual = [(m.line_number, m.raw) for m in matches]

        if actual != expected:
            raise AssertionError(
                f"\nFAIL: {label}\n"
                f"Engine: {engine}\n"
                f"Pattern: {pattern!r}\n"
                f"Data length: {len(data)}\n"
                f"Expected count: {len(expected)}\n"
                f"Actual count: {len(actual)}\n"
            )


def main():
    cases = [
        # Repeated-byte haystack, absent final byte.
        (
            b"A" * SIZE,
            b"A" * 63 + b"B",
            "repeated bytes / absent pattern",
        ),

        # Almost every candidate has a long matching prefix.
        (
            b"A" * SIZE,
            b"A" * 63 + b"B",
            "long near-match candidates",
        ),

        # Periodic input.
        (
            (b"ABCD" * (SIZE // 4)),
            b"ABCD" * 15 + b"X",
            "periodic data / absent pattern",
        ),

        # Overlapping occurrences.
        (
            b"A" * SIZE,
            b"A" * 64,
            "dense overlapping matches",
        ),

        # One match at the very end.
        (
            b"A" * SIZE + b"\n" + b"Z" * 128,
            b"Z" * 128,
            "late match",
        ),

        # One match at the beginning.
        (
            b"Z" * 128 + b"\n" + b"A" * SIZE,
            b"Z" * 128,
            "early match",
        ),

        # Multiple lines, only one matching line.
        (
            (b"A" * 4096 + b"\n") * 255 + b"TARGET\n",
            b"TARGET",
            "sparse match across many lines",
        ),

        # Binary input with NUL bytes.
        (
            b"\x00" * SIZE,
            b"\x00" * 64 + b"\x01",
            "binary repeated NUL bytes",
        ),
    ]

    print("Adversarial differential testing")
    print(f"Buffer size: approximately {SIZE:,} bytes")
    print(f"Cases: {len(cases)}")
    print()

    for data, pattern, label in cases:
        check(data, pattern, label)
        print(f"PASS: {label}")

    print()
    print(f"PASS: {len(cases)} adversarial cases")
    print("PASS: SSE2 and scalar agree with Python reference")


if __name__ == "__main__":
    main()
