
#!/usr/bin/env bash
# Run every test suite supported by the local toolchain.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
TMPOUT="$(mktemp -d)"

trap 'rm -rf "$TMPOUT"' EXIT

CC="${CC:-cc}"
CXX="${CXX:-c++}"
PYTHON="${PYTHON:-python3}"

# CLI tests
echo "== CLI =="
bash "$ROOT/tests/cli/test_cli.sh"

# Native C API tests
echo "== Native C =="
"$CC" -Wall -Wextra -Werror \
    -I"$ROOT/include" \
    "$ROOT/tests/native/test_c.c" \
    -o "$TMPOUT/test_c" \
    -L"$BUILD" -lasmgrep -lpthread \
    -Wl,-rpath,"$BUILD"

"$TMPOUT/test_c"

# Public C API randomized differential tests
echo "== Native C API fuzz =="
"$CC" -Wall -Wextra -Werror \
    -I"$ROOT/include" \
    "$ROOT/tests/native/test_c_fuzz.c" \
    -o "$TMPOUT/test_c_fuzz" \
    -L"$BUILD" -lasmgrep \
    -Wl,-rpath,"$BUILD"

"$TMPOUT/test_c_fuzz"

# Public C API memory-boundary tests
echo "== Native C API guard pages =="
"$CC" -Wall -Wextra -Werror \
    -I"$ROOT/include" \
    "$ROOT/tests/native/test_c_guard.c" \
    -o "$TMPOUT/test_c_guard" \
    -L"$BUILD" -lasmgrep \
    -Wl,-rpath,"$BUILD"

"$TMPOUT/test_c_guard"

# Native C++ API tests
echo "== Native C++ =="
"$CXX" -std=c++17 -Wall -Wextra -Werror \
    -I"$ROOT/include" \
    "$ROOT/tests/native/test_cpp.cpp" \
    -o "$TMPOUT/test_cpp" \
    -L"$BUILD" -lasmgrep \
    -Wl,-rpath,"$BUILD"

"$TMPOUT/test_cpp"

# Python API tests
echo "== Python API =="
"$PYTHON" "$ROOT/tests/python/test_asmgrep.py"

# Differential tests
echo "== Differential: randomized =="
"$PYTHON" "$ROOT/tests/differential/test_randomized.py"

echo "== Differential: SIMD boundaries =="
"$PYTHON" "$ROOT/tests/differential/test_boundaries.py"

echo "== Differential: adversarial =="
"$PYTHON" "$ROOT/tests/differential/test_adversarial.py"

# Java binding tests
echo "== Java =="
if command -v javac >/dev/null 2>&1 &&
   command -v java >/dev/null 2>&1 &&
   [ -f "$BUILD/asmgrep.jar" ]; then

    mkdir -p "$TMPOUT/java"

    javac \
        -cp "$BUILD/asmgrep.jar" \
        -d "$TMPOUT/java" \
        "$ROOT/tests/java/com/asmgrep/AsmgrepTest.java"

    java \
        --enable-native-access=ALL-UNNAMED \
        -Djava.library.path="$BUILD" \
        -cp "$BUILD/asmgrep.jar:$TMPOUT/java" \
        com.asmgrep.AsmgrepTest
else
    echo "skipped: JDK or Java bindings unavailable"
fi

echo "All test suites passed"
