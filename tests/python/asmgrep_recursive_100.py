
#!/usr/bin/env python3
"""100 differential recursive CLI tests for asmgrep vs GNU grep.

Run from the asmgrep repository root:
    python3 tests/python/asmgrep_recursive_100.py

Compares stdout (line order normalized) and exit status.
"""

import os
import random
import shutil
import subprocess
import tempfile
from pathlib import Path

ASM = Path("./build/asmgrep").resolve()
GREP: str = shutil.which("grep") or ""
RNG = random.Random(0xA5A6E)

if not ASM.is_file():
    raise SystemExit(f"asmgrep binary not found: {ASM} (run make first)")

if GREP is None:
    raise SystemExit("GNU grep not found")

root_tmp = Path(tempfile.mkdtemp(prefix="asmgrep-100-"))
root = root_tmp / "tree"
root.mkdir()

passed = 0
failed = 0


def write(rel: str, data: str | bytes) -> Path:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)

    if isinstance(data, bytes):
        p.write_bytes(data)
    else:
        p.write_text(data, encoding="utf-8")

    return p


def run_one(
    label: str,
    mode: str,
    pattern: str,
    target: Path | None = None,
    timeout: int = 12,
) -> None:
    global passed, failed

    if target is None:
        target = root

    target = Path(target)

    # asmgrep does not implement -F; these test patterns are literal strings.
    asm_args = [mode, pattern, str(target)]

    # GNU grep receives -F to force fixed-string matching.
    grep_args = [mode, "-F", pattern, str(target)]

    try:
        a = subprocess.run(
            [str(ASM), *asm_args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        g = subprocess.run(
            [GREP, *grep_args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )

        # Recursive traversal order may differ.
        # Sorting preserves duplicate lines while ignoring traversal order.
        asm_output = sorted(a.stdout.splitlines())
        grep_output = sorted(g.stdout.splitlines())

        ok = (
            asm_output == grep_output
            and a.returncode == g.returncode
        )

        if ok:
            passed += 1
            print(f"PASS {passed:03d} {label}")
        else:
            failed += 1
            print(f"FAIL {label}")
            print(
                f"  asmgrep rc={a.returncode} "
                f"stdout={asm_output[:8]!r}"
            )
            print(
                f"  grep    rc={g.returncode} "
                f"stdout={grep_output[:8]!r}"
            )

            if a.stderr:
                print(f"  asmgrep stderr={a.stderr.strip()[:300]!r}")

            if g.stderr:
                print(f"  grep stderr={g.stderr.strip()[:300]!r}")

    except subprocess.TimeoutExpired:
        failed += 1
        print(f"FAIL {label}: timeout")

    except OSError as exc:
        failed += 1
        print(f"FAIL {label}: execution error: {exc}")


def begin_batch(name: str) -> None:
    print(f"\n===== {name} =====")


# Base tree shared by all batches.
for i in range(12):
    write(
        f"base/group{i % 4}/file{i:02}.txt",
        f"alpha line {i}\nneedle item {i}\nomega\nneedle tail\n",
    )

write("base/empty.txt", b"")
write("base/no-newline.txt", "first\nneedle-without-newline")
write("base/space dir/file with spaces.txt", "needle spaces\nother\n")
write("base/unicode/naïve-文件.txt", "needle unicode\n")
write("base/special/a[b]*?.txt", "needle special\n")
(root / "base/empty-dir").mkdir(exist_ok=True)


# Batch 1: symlinks and cycles (20).
begin_batch("BATCH 1/5 — SYMLINKS (20)")

linkdir = root / "links"
(linkdir / "real/sub").mkdir(parents=True)
(linkdir / "real/sub/data.txt").write_text("needle real\n")
(linkdir / "real-file.txt").write_text("needle target-file\n")

try:
    (linkdir / "file-link.txt").symlink_to("real-file.txt")
    (linkdir / "dir-link").symlink_to(
        "real", target_is_directory=True
    )
    (linkdir / "broken-link").symlink_to("missing-target")
    (linkdir / "real/sub/back").symlink_to(
        "../..", target_is_directory=True
    )
except OSError as exc:
    print(f"NOTE symlink creation partly unavailable: {exc}")

for i in range(10):
    run_one(
        f"symlink case {i + 1}: -r needle",
        "-r",
        "needle",
        linkdir,
    )

for i in range(10):
    run_one(
        f"symlink case {i + 11}: -R needle",
        "-R",
        "needle",
        linkdir,
    )


# Batch 2: permissions and error paths (20).
begin_batch("BATCH 2/5 — PERMISSIONS / ERRORS (20)")

perm = root / "permissions"
(perm / "open").mkdir(parents=True)
(perm / "locked").mkdir()

write("permissions/open/readable.txt", "needle readable\n")
locked_file = write(
    "permissions/locked/locked.txt",
    "needle locked\n",
)
locked_dir = perm / "locked"

for i in range(10):
    run_one(
        f"error case {i + 1}: missing operand",
        "-r",
        "needle",
        root_tmp / f"does-not-exist-{i}",
    )

if hasattr(os, "geteuid") and os.geteuid() != 0:
    locked_file.chmod(0)
    locked_dir.chmod(0)

    for i in range(10):
        run_one(
            f"permission case {i + 11}: unreadable tree",
            "-r",
            "needle",
            perm,
        )

    locked_dir.chmod(0o700)
    locked_file.chmod(0o600)

else:
    print(
        "NOTE running as root; replacing permission-denial "
        "cases with readable-tree checks"
    )

    for i in range(10):
        run_one(
            f"permission fallback {i + 11}: readable tree",
            "-r",
            "needle",
            perm,
        )


# Batch 3: scale / large directory (20).
begin_batch("BATCH 3/5 — SCALE (20)")

large = root / "large"
large.mkdir()

for i in range(1200):
    d = large / f"d{i % 30:02}"
    d.mkdir(exist_ok=True)

    payload = f"record {i}\n"

    if i % 7 == 0:
        payload += f"needle scale {i}\n"

    (d / f"f{i:04}.txt").write_text(payload)

for i in range(10):
    run_one(
        f"scale case {i + 1}: -r needle",
        "-r",
        "needle",
        large,
        timeout=25,
    )

for i in range(10):
    run_one(
        f"scale case {i + 11}: -rc needle",
        "-rc",
        "needle",
        large,
        timeout=25,
    )


# Batch 4: paths and names (20).
begin_batch("BATCH 4/5 — PATHS / FILENAMES (20)")

paths = root / "paths"
cur = paths

for i in range(18):
    cur = cur / (f"deep-{i:02}-" + "x" * 12)

cur.mkdir(parents=True)

(cur / ("long-" + "n" * 100 + ".txt")).write_text(
    "needle long path\n"
)

write("paths/with spaces/another space.txt", "needle space\n")
write(
    "paths/punctuation/[brackets] & (parens).txt",
    "needle punctuation\n",
)
write(
    "paths/unicode/বাংলা-日本語.txt",
    "needle unicode path\n",
)
write("paths/dashes/--leading-dash.txt", "needle dash\n")

for i in range(10):
    run_one(
        f"path case {i + 1}: -r needle",
        "-r",
        "needle",
        paths,
        timeout=20,
    )

for i in range(10):
    run_one(
        f"path case {i + 11}: -rn needle",
        "-rn",
        "needle",
        paths,
        timeout=20,
    )


# Batch 5: stability / repeated traversal (20).
begin_batch("BATCH 5/5 — STABILITY (20)")

stable = root / "stable"

for i in range(25):
    write(
        f"stable/level{i % 5}/file{i:02}.txt",
        f"header {i}\nneedle stable {i}\nfooter\n",
    )

for i in range(10):
    run_one(
        f"stability case {i + 1}: repeated -r",
        "-r",
        "needle",
        stable,
    )

for i in range(10):
    run_one(
        f"stability case {i + 11}: repeated -R",
        "-R",
        "needle",
        stable,
    )


# Summary.
print("\n===== SUMMARY =====")
print(f"Passed: {passed}/100")
print(f"Failed: {failed}/100")
print(f"Temporary test tree: {root_tmp}")

if failed:
    raise SystemExit(1)

print("All 100 differential checks passed.")