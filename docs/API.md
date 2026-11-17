# API reference

Declared in `include/asmgrep.h` (C) and `include/asmgrep.hpp` (C++).
Library: `libasmgrep.so.1`, symbol version `ASMGREP_1.0`.

## Status codes

Search functions return `0` on success or a negative `errno` value:

| Status | Cause |
|---|---|
| `-ENOENT`, `-EACCES`, `-ENOTDIR`, `-ELOOP`, `-ENAMETOOLONG` | `openat` failures |
| `-EISDIR` | the path is a directory |
| `-EINVAL` | NULL argument, unknown flag, pattern containing a newline, or a non-regular file |
| `-ENOMEM` | mapping the file or allocating the result failed |
| `-EFBIG` | file size does not fit a signed 64-bit value |
| `-EIO` | the input changed between the two search passes in a way that exceeded the allocated result |

On failure `*out` is set to `NULL`.

## Functions

```c
int asmgrep_search_file(const char *pattern, const char *path,
                        unsigned flags, asmgrep_result **out);
```
Maps `path` read-only and searches it. The pattern is a C string.

```c
int asmgrep_search_buffer(const void *buf, size_t len,
                          const char *pattern, size_t pattern_len,
                          unsigned flags, asmgrep_result **out);
```
Searches `len` bytes. `buf` may be `NULL` only when `len` is 0. The pattern
is given by length and may contain NUL bytes.

```c
size_t      asmgrep_result_count(const asmgrep_result *r);
size_t      asmgrep_result_line_number(const asmgrep_result *r, size_t i);
const char *asmgrep_result_text(const asmgrep_result *r, size_t i);
size_t      asmgrep_result_length(const asmgrep_result *r, size_t i);
```
Accessors. `i` is zero-based. Line numbers are 1-based. Text is
NUL-terminated and excludes the line terminator; `asmgrep_result_length`
gives the length when lines contain NUL bytes. Out-of-range indexes return
0 / `NULL`; a `NULL` result counts as empty.

```c
void        asmgrep_free(asmgrep_result *r);
const char *asmgrep_strerror(int status);
const char *asmgrep_version(void);
```
`asmgrep_free(NULL)` is allowed. `asmgrep_strerror` returns a static string
for 0 or a negative errno (positive values are accepted too).

## Flags

| Flag | Meaning |
|---|---|
| `ASMGREP_SEARCH_SCALAR` | use the scalar reference search instead of SSE2 |

Other bits are rejected with `-EINVAL`.

## Semantics

- Matching is exact and case-sensitive on bytes.
- Results are in file order, one entry per matching line.
- An empty pattern matches every line.
- The final line need not end with a newline. A file ending in a newline has
  no extra empty final line.
- An empty file yields an empty result.

## Ownership and threading

- The caller owns a result and frees it once with `asmgrep_free`.
- Pointers from `asmgrep_result_text` live until the result is freed.
- No global mutable state exists; concurrent searches are safe.

## C++

`asmgrep::search(pattern, path)` and `asmgrep::search_buffer(data, pattern)`
return a move-only `asmgrep::result_set` that frees the native result in its
destructor. Iteration yields `asmgrep::match { line_number, text }`;
`result_set::text(i)` returns a `std::string_view` valid while the set lives.
Failures throw `asmgrep::error` (with `status()`); bad indexes throw
`std::out_of_range`. The optional `asmgrep::engine::scalar` argument selects
the reference search.

## Python

`asmgrep.search(pattern, filename, *, scalar=False) -> list[Match]`,
`asmgrep.search_bytes(pattern, data, *, scalar=False)`,
`asmgrep.version()`. `Match` is a named tuple `(line_number, text)` with a
`raw` property for the exact bytes; text is decoded as UTF-8 with
`surrogateescape`, so invalid bytes round-trip. Failures raise
`asmgrep.AsmgrepError` (an `OSError` with `errno` set). A file-search
pattern containing NUL raises `ValueError`.

## Java

`com.asmgrep.Asmgrep.search(String pattern, String filename)` (also
`Path`), `searchScalar`, `searchBytes(byte[] pattern, byte[] data)` and
`version()` return an unmodifiable `List<Match>`. `Match` exposes
`getLineNumber()`, `getText()` (UTF-8) and `getBytes()`. Failures throw
`AsmgrepException` (unchecked, with `getStatus()`). The native result is
copied into Java objects and freed before the call returns.
