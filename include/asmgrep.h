/*
 * asmgrep - exact substring line search
 *
 * C interface of libasmgrep. All search work is performed by the native
 * engine; this header only declares its ABI.
 *
 * Ownership
 *   A successful search returns a result object through an out parameter.
 *   The caller owns it and must release it with asmgrep_free(). Text
 *   pointers obtained from a result remain valid until that call and must
 *   not be modified or freed separately.
 *
 * Errors
 *   Search functions return 0 on success and a negative errno value on
 *   failure (for example -ENOENT, -EACCES, -ENOMEM, -EINVAL). On failure
 *   *out is set to NULL. asmgrep_strerror() describes a status code.
 *
 * Threading
 *   The library keeps no global mutable state. Independent searches may run
 *   concurrently; a single result object must not be freed while another
 *   thread is reading it.
 *
 * Matching
 *   A line matches when it contains the pattern as an exact, case-sensitive
 *   byte sequence. Each matching line is reported once, in file order,
 *   without its terminating newline. An empty pattern matches every line.
 *   Patterns must not contain a newline (-EINVAL). Because asmgrep_search_file
 *   takes a C string, its pattern cannot contain NUL bytes; use
 *   asmgrep_search_buffer for such patterns.
 */
#ifndef ASMGREP_H
#define ASMGREP_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define ASMGREP_VERSION_MAJOR 1
#define ASMGREP_VERSION_MINOR 0
#define ASMGREP_VERSION_PATCH 0

/* Search flags. Unknown bits are rejected with -EINVAL. */
#define ASMGREP_SEARCH_SCALAR 0x1u /* use the scalar reference search */

typedef struct asmgrep_result asmgrep_result;

/*
 * Searches the file at path. The file is mapped read-only; a file that is
 * truncated by another process while it is being searched can terminate the
 * calling process with SIGBUS. Empty files produce an empty result.
 */
int asmgrep_search_file(const char *pattern, const char *path,
                        unsigned flags, asmgrep_result **out);

/* Searches len bytes at buf. buf may be NULL only when len is 0. */
int asmgrep_search_buffer(const void *buf, size_t len,
                          const char *pattern, size_t pattern_len,
                          unsigned flags, asmgrep_result **out);

/* Number of matching lines. NULL is treated as an empty result. */
size_t asmgrep_result_count(const asmgrep_result *result);

/* 1-based line number of match index, or 0 when index is out of range. */
size_t asmgrep_result_line_number(const asmgrep_result *result, size_t index);

/* NUL-terminated text of match index, or NULL when out of range. */
const char *asmgrep_result_text(const asmgrep_result *result, size_t index);

/* Length in bytes of the text of match index (excluding the NUL). */
size_t asmgrep_result_length(const asmgrep_result *result, size_t index);

/* Releases a result. NULL is accepted. */
void asmgrep_free(asmgrep_result *result);

/* Static description of a status returned by a search function. */
const char *asmgrep_strerror(int status);

/* Library version string, "major.minor.patch". */
const char *asmgrep_version(void);

#ifdef __cplusplus
}
#endif

#endif
