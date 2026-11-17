#!/usr/bin/env bash
# Runs every test suite that the local toolchain supports.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
TMPOUT="$(mktemp -d)"
trap 'rm -rf "$TMPOUT"' EXIT

echo "== CLI =="
bash "$ROOT/tests/cli/test_cli.sh"

echo "== Native C =="
"${CC:-cc}" -Wall -Wextra -I"$ROOT/include" "$ROOT/tests/native/test_c.c" -o "$TMPOUT/test_c" \
    -L"$BUILD" -lasmgrep -lpthread -Wl,-rpath,"$BUILD"
"$TMPOUT/test_c"

echo "== Native C++ =="
"${CXX:-c++}" -std=c++17 -Wall -Wextra -I"$ROOT/include" "$ROOT/tests/native/test_cpp.cpp" \
    -o "$TMPOUT/test_cpp" -L"$BUILD" -lasmgrep -Wl,-rpath,"$BUILD"
"$TMPOUT/test_cpp"

echo "== Python API =="
"${PYTHON:-python3}" "$ROOT/tests/python/test_asmgrep.py"

echo "== Differential: randomized =="
"${PYTHON:-python3}" "$ROOT/tests/differential/test_randomized.py"

echo "== Differential: SIMD boundaries =="
"${PYTHON:-python3}" "$ROOT/tests/differential/test_boundaries.py"

echo "== Differential: adversarial =="
"${PYTHON:-python3}" "$ROOT/tests/differential/test_adversarial.py"

echo "== Java =="
if command -v javac >/dev/null 2>&1 && [ -f "$BUILD/asmgrep.jar" ]; then
    javac -cp "$BUILD/asmgrep.jar" -d "$TMPOUT/java" "$ROOT/tests/java/com/asmgrep/AsmgrepTest.java"
    java --enable-native-access=ALL-UNNAMED \
    -Djava.library.path="$BUILD" \
    -cp "$BUILD/asmgrep.jar:$TMPOUT/java" \
    com.asmgrep.AsmgrepTest
else
    echo "skipped: no JDK (Java bindings were not built)"
fi

echo "All test suites passed"
