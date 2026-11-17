
#!/usr/bin/env python3
"""Targeted SIMD boundary and alignment tests for asmgrep."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "bindings" / "python"))

import asmgrep


PATTERN_LENGTHS = [
    1, 2, 3,
    14, 15, 16, 17, 18,
    30, 31, 32, 33, 34,
    46, 47, 48, 49, 50,
    62, 63, 64, 65, 66,
    126, 127, 128, 129, 130,
    254, 255, 256,
]

FILLER = b"\xff"
TAIL = b"\xfe" * 80

# Pattern bytes deliberately exclude newline, 0xFE and 0xFF.
ALPHABET = [b for b in range(1, 255) if b != 10]


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
                f"Pattern length: {len(pattern)}\n"
                f"Data length: {len(data)}\n"
                f"Expected: {expected!r}\n"
                f"Actual:   {actual!r}\n"
            )


def main():
    total = 0

    for length in PATTERN_LENGTHS:
        pattern = bytes(ALPHABET[i % len(ALPHABET)] for i in range(length))

        # Test different starting offsets.
        for offset in range(64):
            data = FILLER * offset + pattern + TAIL
            check(data, pattern, f"start offset {offset}")
            total += 1

        # Test different distances from the end of the buffer.
        for suffix_length in range(64):
            data = FILLER * 64 + pattern + FILLER * suffix_length
            check(data, pattern, f"suffix length {suffix_length}")
            total += 1

        # Test a buffer that is too short to contain the pattern.
        data = FILLER * max(0, length - 1)
        check(data, pattern, "pattern longer than buffer")
        total += 1

    print(f"PASS: {total:,} targeted boundary cases")
    print("PASS: SSE2 and scalar agree with Python reference")


if __name__ == "__main__":
    main()
