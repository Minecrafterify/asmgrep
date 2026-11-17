# Installation

## Requirements

- NASM
- GNU Make
- GNU ld (binutils)

Optional:
- JDK 11+ and a C compiler for Java support
- `hyperfine` for benchmarks

## Build

```sh
make
```

This builds the CLI and shared library. Java support is built automatically when the required tools are available.

Run tests:

```sh
make test
```

## Make targets

| Command | Description |
|---|---|
| `make` | Build everything available |
| `make cli` | Build CLI |
| `make library` | Build shared library |
| `make java` | Build Java binding |
| `make python` | No build needed |
| `make test` | Run tests |
| `make benchmark` | Run benchmarks |
| `make clean` | Remove build files |

## Install

System-wide:

```sh
sudo make install
```

User-local:

```sh
make install PREFIX="$HOME/.local"
```

For a user-local installation, add these to your shell configuration:

```sh
export PATH="$HOME/.local/bin:$PATH"
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH:-}"
```

## Uninstall

System-wide:

```sh
sudo make uninstall
```

User-local:

```sh
make uninstall PREFIX="$HOME/.local"
```

You can also use:

```sh
scripts/install.sh [PREFIX]
scripts/uninstall.sh [PREFIX]
```

## Python

The Python binding uses `ctypes` and requires the native library.

It can be installed separately:

```sh
pip install bindings/python
```

If Python cannot find the native library, set `ASMGREP_LIBRARY` to its path.

## Java

Java support requires JDK 11+.

Build it with:

```sh
make java
```

Run an application with:

```sh
javac -cp /usr/share/java/asmgrep.jar Main.java
java -Djava.library.path=/usr/lib \
     -cp /usr/share/java/asmgrep.jar:. Main
```

Set `JAVA_HOME` if the JDK is not detected automatically.

## Custom installation

The Makefile supports `PREFIX` and `DESTDIR`:

```sh
make install PREFIX=/usr DESTDIR="$PWD/stage"
```

Other configurable variables include `BINDIR`, `LIBDIR`, `INCLUDEDIR`, `JAVADIR`, `NASM`, `LD`, `CC`, and `PYTHON`.

The shared library uses SONAME `libasmgrep.so.1` and symbol version `ASMGREP_1.0`.