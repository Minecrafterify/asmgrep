
# API Reference

asmgrep provides C, C++, Python, and Java interfaces.

The native API is declared in:

- `include/asmgrep.h` — C API
- `include/asmgrep.hpp` — C++ API

The shared library is `libasmgrep.so.1`, with symbol version `ASMGREP_1.0`.

## C API

### Status codes

Search functions return `0` on success or a negative `errno` value on failure.

| Status | Cause |
|---|---|
| `-ENOENT`, `-EACCES`, `-ENOTDIR`, `-ELOOP`, `-ENAMETOOLONG` | Errors when opening a file |
| `-EISDIR` | The specified path points to a directory |
| `-EINVAL` | NULL pointer, invalid flags, pattern containing a newline, or file is not a regular file |
| `-ENOMEM` | Mapping the file or allocating the result failed |
| `-EFBIG` | File size does not fit in a signed 64-bit integer |
| `-EIO` | The input changed between search passes in a way that exceeded the allocated result capacity |

On failure, `*out` is set to `NULL`.

### Search functions

**Search a file**

```c
int asmgrep_search_file(const char *pattern, const char *path,
                        unsigned flags, asmgrep_result *out);
```

Searches the file at `path`.

The pattern is supplied as a C string and therefore cannot contain embedded NUL bytes.

**Search a memory buffer**

```c
int asmgrep_search_buffer(const void *buf, size_t len,
                          const char *pattern, size_t pattern_len,
                          unsigned flags, asmgrep_result *out);
```

Searches exactly `len` bytes from the supplied buffer.

- `buf` may be `NULL` when `len` is zero.
- The pattern is specified using an explicit length.
- Embedded NUL bytes are supported in both the buffer and pattern.

### Result accessors

```c
size_t asmgrep_result_count(asmgrep_result r);
size_t asmgrep_result_line_number(asmgrep_result r, size_t i);
const char *asmgrep_result_text(asmgrep_result r, size_t i);
size_t asmgrep_result_length(asmgrep_result r, size_t i);
```

These functions provide access to the search results.

- `asmgrep_result_count` returns the number of matching lines.
- `asmgrep_result_line_number` returns the 1-based line number.
- `asmgrep_result_text` returns a pointer to the matching line's text.
- `asmgrep_result_length` returns the exact text length in bytes.

The index `i` is zero-based.

Returned text is NUL-terminated and excludes the newline at the end of the matched line.

Because matching lines may contain embedded NUL bytes, use `asmgrep_result_length` to determine the actual text length.

Out-of-range indexes return `0` or `NULL`, as appropriate. A `NULL` result is treated as an empty result.

### Utility functions

```c
void asmgrep_free(asmgrep_result r);
const char *asmgrep_strerror(int status);
const char *asmgrep_version(void);
```

- `asmgrep_free` releases a result. Passing `NULL` is allowed.
- `asmgrep_strerror` returns a static error string for zero or a positive or negative `errno` value.
- `asmgrep_version` returns the library version string.

### Search flags

| Flag | Meaning |
|---|---|
| `ASMGREP_SEARCH_SCALAR` | Use the scalar reference implementation instead of SSE2 |

The default behavior uses the SSE2 implementation. Unknown flag bits are rejected with `-EINVAL`.

## Search semantics

The API follows these rules:

- Matching is exact and case-sensitive.
- Results are returned in file order.
- Each matching line produces exactly one result, even if the pattern occurs multiple times within that line.
- An empty pattern matches every line.
- A final line does not need to end with a newline.
- A file ending with a newline does not produce an additional empty final line.
- An empty file produces an empty result.
- Patterns containing newlines are rejected.

## Ownership and thread safety

- Ownership of every successful non-NULL result is transferred to the caller.
- The caller must release each result using `asmgrep_free`.
- Pointers returned by `asmgrep_result_text` remain valid until the corresponding result is freed.
- Results must not be used after being freed.
- The library does not maintain global mutable search state.
- Concurrent searches are safe.

## C++ API

The C++ wrapper provides:

```cpp
asmgrep::search(pattern, path);
asmgrep::search_buffer(data, pattern);
```

Both return a move-only `asmgrep::result_set`.

`result_set` takes ownership of the native result and releases it automatically in its destructor.

Iteration through a `result_set` yields `asmgrep::match` objects containing:

```cpp
line_number,
text
```

Additional behavior:

- `result_set::text(i)` returns a `std::string_view`.
- The returned view remains valid while the corresponding result set exists.
- Failures throw `asmgrep::error`, which provides `status()`.
- Invalid indexes throw `std::out_of_range`.
- The optional `asmgrep::engine::scalar` argument selects the scalar reference implementation.

## Python API

The Python package exposes:

```python
asmgrep.search(pattern, filename, *, scalar=False)
asmgrep.search_bytes(pattern, data, *, scalar=False)
asmgrep.version()
```

Both search functions return a list of `Match` objects.

`Match` is a named tuple containing:

```python
(line_number, text)
```

It also provides a `raw` attribute containing the exact bytes of the matching line.

Text is decoded using UTF-8 with the `surrogateescape` error handler. This allows invalid UTF-8 bytes to be preserved and round-tripped without data loss.

### Error handling

- Search failures raise `asmgrep.AsmgrepError`.
- `AsmgrepError` is an `OSError` subclass with `errno` set.
- A file-search pattern containing NUL bytes raises `ValueError`.
- The `scalar=True` option forces the scalar reference implementation.

## Java API

The Java package exposes the following methods:

```java
com.asmgrep.Asmgrep.search(String pattern, String filename);

com.asmgrep.Asmgrep.search(String pattern, Path path);

com.asmgrep.Asmgrep.searchScalar(String pattern, String filename);

com.asmgrep.Asmgrep.searchBytes(byte[] pattern, byte[] data);

com.asmgrep.Asmgrep.version();
```

Search methods return an unmodifiable `List<Match>`.

Each `Match` provides:

- `getLineNumber()` — returns the 1-based line number.
- `getText()` — returns the matching line decoded using UTF-8.
- `getBytes()` — returns the original bytes of the matching line.

### Error handling

If an error occurs during searching, `AsmgrepException` is thrown.

`AsmgrepException` is an unchecked exception that provides `getStatus()` to retrieve the error status.

The native result is copied into Java objects and freed once the search method has finished.
