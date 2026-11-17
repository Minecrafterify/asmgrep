# Installation

## Build requirements

NASM, GNU ld (binutils) and GNU Make. The Java binding additionally needs a
JDK 11+ (including `jni.h`) and a C compiler. `make` checks for NASM and ld
and stops with a message if they are missing. The Java binding is built
automatically only when `javac` and `jni.h` are found; `make java` builds it
explicitly and reports what is missing. Set `JAVA_HOME` if the JDK is not
detected.

## Targets

| Target | Result |
|---|---|
| `make` / `make all` | `build/asmgrep`, `build/libasmgrep.so*`, Java binding if available |
| `make cli` | the executable only |
| `make library` | the shared library only |
| `make java` | `build/asmgrep.jar`, `build/libasmgrep-jni.so` |
| `make python` | nothing to build (pure `ctypes`) |
| `make test` | all test suites |
| `make benchmark` | hyperfine comparison with GNU grep |
| `make clean` | removes `build/` |

Variables: `PREFIX` (default `/usr`), `DESTDIR`, `BINDIR`, `LIBDIR`,
`INCLUDEDIR`, `JAVADIR`, `NASM`, `LD`, `CC`, `PYTHON`, `JAVA_HOME`, `DEBUG=1`
(debug symbols).

## System-wide

```sh
make
sudo make install
```

Installs `/usr/bin/asmgrep`, `/usr/lib/libasmgrep.so.1.0.0` (with
`libasmgrep.so.1` and `libasmgrep.so` links), `/usr/include/asmgrep.h`,
`/usr/include/asmgrep.hpp`, the Python package into the prefix's
`site-packages`, and, when built, `/usr/share/java/asmgrep.jar` and
`/usr/lib/libasmgrep-jni.so`. `ldconfig` runs when installing as root
without `DESTDIR`.

Note: distributions that use `dist-packages` (Debian, Ubuntu) do not put
`/usr/lib/python3.X/site-packages` on the default path. Install the package
there manually, or use `PYTHONPATH`, or install under `~/.local` and add its
`site-packages` to `PYTHONPATH`.

## User-local

```sh
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH:-}"
```

`scripts/install.sh [PREFIX]` and `scripts/uninstall.sh [PREFIX]` wrap the
same targets (prefix `/usr` as root, `~/.local` otherwise).

## Uninstall

```sh
sudo make uninstall                         # system-wide
make uninstall PREFIX="$HOME/.local"        # user-local
```

## Runtime library discovery

- **C / C++:** link with `-lasmgrep`. For a non-standard prefix add
  `-L$PREFIX/lib -I$PREFIX/include` and either `-Wl,-rpath,$PREFIX/lib` or
  `LD_LIBRARY_PATH`.
- **Python:** the loader tries, in order, `$ASMGREP_LIBRARY` (if set, only
  that), the dynamic linker's search for `libasmgrep.so.1`, `ctypes.util`,
  `<prefix>/lib` relative to the installed package, the source tree's
  `build/`, and the usual prefixes.
- **Java:** put `libasmgrep-jni.so` on `java.library.path`
  (`-Djava.library.path=/usr/lib`). It has an `$ORIGIN` run path, so it
  finds `libasmgrep.so.1` next to itself.

## Python package

The files in `bindings/python/asmgrep` can also be installed with
`pip install bindings/python`; the native library must still be installed
separately.

## Java

```sh
javac -cp /usr/share/java/asmgrep.jar Main.java
java -Djava.library.path=/usr/lib -cp /usr/share/java/asmgrep.jar:. Main
```

## Packaging for distributions

The Makefile honors `DESTDIR` and `PREFIX`, so packagers can stage an install
and split it:

```sh
make PREFIX=/usr
make install PREFIX=/usr DESTDIR="$PWD/stage"
```

Suggested split for deb/rpm:

| Package | Files |
|---|---|
| `asmgrep` | `usr/bin/asmgrep` |
| `libasmgrep1` | `usr/lib/libasmgrep.so.1*` (shared-library package named after the soname) |
| `libasmgrep-dev` | `usr/include/asmgrep.h`, `usr/include/asmgrep.hpp`, `usr/lib/libasmgrep.so` |
| `python3-asmgrep` | the `asmgrep` package directory |
| `libasmgrep-java` | `usr/share/java/asmgrep.jar`, `usr/lib/libasmgrep-jni.so` |

Run `ldconfig` in the post-install scripts of the library package. Build
dependencies: `nasm`, `binutils`, `make` (plus `default-jdk-headless` and
`gcc` for Java). The soname changes only with an ABI break; the symbol
version node is `ASMGREP_1.0`. Packages for specific formats are not
provided.
