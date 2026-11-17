# asmgrep

Exact-substring line search for Linux x86-64, written in NASM assembly. The
same engine backs a command-line tool and a shared library with C, C++,
Python and Java interfaces.

## Features

- Case-sensitive substring search over memory-mapped files, with a scalar
  reference implementation and an SSE2 implementation that produce identical
  results.
- Line-oriented output: each matching line is reported once, with optional
  line numbers, or counted.
- `libasmgrep.so`, a versioned C ABI with explicit ownership and no global
  mutable state.
- A header-only C++ wrapper, a `ctypes` Python package and a JNI-based Java
  API. None of them implements any search logic.
- The core engine uses raw Linux system calls and has no libc dependency.
- Adaptive SSE2 anchor selection for sufficiently large searches. The engine
  samples the input to select a selective pattern byte, then caches that
  choice across line searches to avoid repeating the sampling overhead.

## Requirements

| Purpose | Requirement |
|---|---|
| Build | NASM, GNU binutils (`ld`), GNU Make |
| Run (CLI, library) | Linux x86-64 with SSE2; nothing else |
| C / C++ tests | a C11 and a C++17 compiler |
| Python | Python 3.8+ (standard library only) |
| Java | JDK 11+ with `jni.h`, and a C compiler for the JNI adapter |
| Benchmarks | `hyperfine`, GNU grep |

## Build, test, install

```sh
make            # CLI, libasmgrep.so, and the Java binding when a JDK is found
make test       # CLI, C, C++, Python and Java suites
sudo make install                       # /usr/bin, /usr/lib, /usr/include
make install PREFIX="$HOME/.local"      # user-local
sudo make uninstall
```

See [docs/INSTALLATION.md](docs/INSTALLATION.md) for library discovery,
Python/Java setup and packaging.

## Command line

```sh
asmgrep "ERROR" server.log        # matching lines
asmgrep -n "ERROR" server.log     # with line numbers
asmgrep -c "ERROR" server.log     # number of matching lines
asmgrep -- "-flag" file.txt       # pattern that starts with '-'
```

Options: `-n`, `-c` (overrides `-n`, as in grep), `--scalar` (reference
engine), `-h/--help`, `-V/--version`. Short options may be combined (`-nc`)
and may follow the operands. Exit status: 0 a line matched, 1 none matched,
2 error.

asmgrep matches fixed strings in one file. It is not a drop-in grep: there is
no regular-expression support, no multiple files, no stdin, and no
`Binary file matches` handling; NUL and other bytes are printed as-is.

## Search optimization

The SSE2 search engine uses adaptive anchor selection for larger inputs.
Instead of always searching for the final pattern byte, it samples the
haystack and selects a pattern position whose byte appears relatively
infrequently. SIMD scanning locates candidate matches, which are then
verified against the full pattern.

The selected anchor is cached across line searches within a scan. This
avoids repeatedly sampling the input when processing files containing
many matching lines.

The scalar implementation remains available through `--scalar` for
reference testing.

See [Benchmarks](docs/BENCHMARKS.md) for methodology and measured results.

## C

```c
#include <asmgrep.h>
#include <stdio.h>

int main(void) {
    asmgrep_result *result;
    int status = asmgrep_search_file("ERROR", "server.log", 0, &result);
    if (status != 0) {
        fprintf(stderr, "asmgrep: %s\n", asmgrep_strerror(status));
        return 1;
    }
    for (size_t i = 0; i < asmgrep_result_count(result); i++)
        printf("%zu: %s\n", asmgrep_result_line_number(result, i),
               asmgrep_result_text(result, i));
    asmgrep_free(result);
    return 0;
}
```

```sh
gcc example.c -lasmgrep -o example
```

## C++

```cpp
#include <asmgrep.hpp>
#include <iostream>

int main() {
    auto results = asmgrep::search("ERROR", "server.log");   // throws asmgrep::error
    for (const auto &m : results)
        std::cout << m.line_number << ": " << m.text << '\n';
}
```

```sh
g++ -std=c++17 example.cpp -lasmgrep -o example
```

## Python

```python
import asmgrep

for result in asmgrep.search("ERROR", "server.log"):
    print(result.line_number, result.text)
```

Errors raise `asmgrep.AsmgrepError` (an `OSError`). `asmgrep.search_bytes`
searches an in-memory buffer. Set `ASMGREP_LIBRARY` to load a specific
library file.

## Java

```java
import com.asmgrep.Asmgrep;

public class Main {
    public static void main(String[] args) {
        var results = Asmgrep.search("ERROR", "server.log");
        for (var result : results)
            System.out.println(result.getLineNumber() + ": " + result.getText());
    }
}
```

```sh
javac -cp asmgrep.jar Main.java
java -Djava.library.path=/usr/lib -cp asmgrep.jar:. Main
```

## Layout

```text
core/        search engine, line processing, mmap and file access, C ABI (NASM)
cli/         command-line front end (NASM)
include/     asmgrep.h, asmgrep.hpp
bindings/    python/ (ctypes), java/ (API + JNI adapter)
tests/       CLI, native, Python and Java suites
benchmarks/  data generator and hyperfine comparison
docs/        architecture, algorithm, API, installation, benchmarks
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Algorithm](docs/ALGORITHM.md)
- [API reference](docs/API.md)
- [Installation and packaging](docs/INSTALLATION.md)
- [Benchmarks](docs/BENCHMARKS.md)

## Limitations

- Linux x86-64 only. The code uses SSE2 only, which every x86-64 CPU has;
  AVX2 and POPCNT are not used.
- A file is mapped in one piece. If it does not fit in the available address
  space the search fails with "Cannot allocate memory" instead of falling
  back to windowed reads.
- A file truncated by another process during a search can raise SIGBUS. No
  signal handler is installed.
- Only regular files are accepted. Special files (pipes, devices) are
  rejected; zero-length regular files such as some `/proc` entries appear
  empty.
- Patterns cannot contain a newline. `asmgrep_search_file` takes a C string,
  so its pattern cannot contain NUL; `asmgrep_search_buffer` can.
- The library searches twice (count, then fill), so it reads the input twice
  and holds all matching lines in memory.

## License

MIT. See [LICENSE](LICENSE).
