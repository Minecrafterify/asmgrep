
#!/usr/bin/env python3
"""Generate deterministic datasets for asmgrep pattern-length benchmarks."""

from pathlib import Path
import random

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "data" / "extended"
TARGET_BYTES = 32 * 1024 * 1024
MATCH_INTERVAL = 1000
PATTERN_LENGTHS = (1, 2, 4, 8, 16, 32, 64)

def generate_pattern_dataset(length: int) -> None:
    rng = random.Random(12345)
    pattern = "Q" * length
    path = OUT / f"pattern_{length:02d}.log"

    written = 0
    line_number = 0
    matches = 0

    with path.open("w", encoding="ascii", newline="\n") as f:
        while written < TARGET_BYTES:
            line_number += 1

            random_part = "".join(
                rng.choice("0123456789abcdef") for _ in range(32)
            )

            matched = line_number % MATCH_INTERVAL == 0
            marker = pattern if matched else "none"

            line = f"{line_number:09d} INFO {random_part} {marker} request complete\n"
            f.write(line)

            written += len(line)
            matches += int(matched)

    print(
        f"{path.name}: {written:,} bytes, "
        f"{line_number:,} lines, {matches:,} matching lines, "
        f"pattern length={length}"
    )


def generate_pattern_file_dataset() -> None:
    rng = random.Random(67890)
    path = OUT / "multi_pattern.log"
    patterns_path = OUT / "patterns.txt"

    patterns = [
        f"TOKEN_{i:04d}_MATCH"
        for i in range(1, 17)
    ]

    patterns_path.write_text(
        "\n".join(patterns) + "\n",
        encoding="ascii",
    )

    written = 0
    line_number = 0
    matches = 0

    with path.open("w", encoding="ascii", newline="\n") as f:
        while written < TARGET_BYTES:
            line_number += 1

            random_part = "".join(
                rng.choice("0123456789abcdef") for _ in range(32)
            )

            if line_number % MATCH_INTERVAL == 0:
                marker = patterns[(matches) % len(patterns)]
                matches += 1
            else:
                marker = "none"

            line = f"{line_number:09d} INFO {random_part} {marker} request complete\n"
            f.write(line)
            written += len(line)

    print(
        f"{path.name}: {written:,} bytes, "
        f"{line_number:,} lines, {matches:,} matching lines"
    )
    print(f"{patterns_path.name}: {len(patterns)} patterns")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    for length in PATTERN_LENGTHS:
        generate_pattern_dataset(length)

    generate_pattern_file_dataset()


if __name__ == "__main__":
    main()
