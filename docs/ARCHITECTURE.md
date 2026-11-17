# Architecture

## Components

```text
            +--------------+     +-------------------------+
 argv  ---> | cli/args.asm |     | bindings: C, C++, Python,|
            | cli/main.asm |     | Java (JNI adapter)       |
            | cli/output   |     +------------+-------------+
            +------+-------+                  |  C ABI
                   |                          v
                   |               core/src/api.asm (libasmgrep.so)
                   |                          |
                   +-----------+--------------+
                               v
                    core/src/lines.asm   ag_scan  (line driver)
                      |             |
        search_scalar.asm     search_sse2.asm      (substring search)
                               
        mmap.asm / file.asm  (openat, fstat, mmap, munmap, close)
        utils.asm            (strlen, strerror table, utoa, anonymous mmap)
```

Every front end reaches the same two functions, `ag_scan` and the search
routines beneath it. The CLI links the objects statically into an
executable; `libasmgrep.so` links the same objects, plus `api.asm`, into a
shared object. The Python, C++ and Java layers call only the exported C ABI.

## Source files

| File | Role |
|---|---|
| `core/src/search_scalar.asm` | `ag_find_scalar`, the reference substring search |
| `core/src/search_sse2.asm` | `ag_find_sse2`, SSE2 candidate scan with verification |
| `core/src/lines.asm` | `ag_memchr`, `ag_memrchr`, `ag_count_byte`, and `ag_scan` |
| `core/src/file.asm` | `openat` and `fstat` wrappers; regular-file check |
| `core/src/mmap.asm` | `ag_map_file`, `ag_unmap` |
| `core/src/utils.asm` | strlen, errno text, decimal conversion, anonymous allocation |
| `core/src/api.asm` | exported `asmgrep_*` functions and the result block |
| `core/include/internal.inc` | syscall numbers, constants, symbol macros |
| `cli/args.asm` | option parsing |
| `cli/output.asm` | 64 KiB buffered stdout writer and the line callback |
| `cli/main.asm` | `_start`, orchestration, exit codes |

The CLI's output code lives in `cli/` because it is not part of the library.

## Design points

- **No libc.** All I/O uses raw `syscall`. Internal symbols are
  `hidden`; the shared object exports only the nine `asmgrep_*` functions
  (enforced by `core/libasmgrep.map`, version node `ASMGREP_1.0`, soname
  `libasmgrep.so.1`).
- **No global mutable state in the library.** Every search keeps its state
  on its own stack and in its own result mapping, so independent searches
  are thread-safe. The CLI's output buffer is a static buffer, which is
  acceptable because the CLI is single-threaded.
- **Position independence.** All code uses RIP-relative addressing, and the
  errno table stores offsets rather than pointers, so the shared object has
  no text relocations.
- **Result ownership.** A result is one anonymous mapping (header, entry
  table, NUL-terminated text arena). `asmgrep_free` unmaps it. The mapping
  size is stored in the header, so no allocator is needed.
- **Resource handling.** The file descriptor is closed as soon as the mapping
  exists (or on any failure); the mapping is released after the search by
  both the CLI and `asmgrep_search_file`.
- **Callback-driven scan.** `ag_scan` calls a callback per matching line.
  The CLI's callback appends to the output buffer; the library uses two
  callbacks (count pass, fill pass).

## Calling conventions

Assembly routines follow the System V AMD64 ABI. Callee-saved registers are
preserved, the stack is 16-byte aligned at every `call` that can reach C
code (the scan callbacks), and no routine relies on the red zone.
