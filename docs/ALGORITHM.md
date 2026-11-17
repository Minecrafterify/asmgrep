# Algorithm

## Search contract

`ag_find_*(hay, hay_len, pat, pat_len)` returns the offset of the first
occurrence of `pat` in `hay`, or `-1`. An empty pattern matches at offset 0.
`ag_find_scalar` is the reference; `ag_find_sse2` must return the same value
for every input (the test suite compares them, and both against GNU grep).

## Scalar search

For each start offset `i` from 0 to `hay_len - pat_len`, compare the first
byte, and on equality compare the remaining bytes. This is O(n·m) in the
worst case and deliberately simple.

## SSE2 search

1. Broadcast the first pattern byte into an XMM register (`movd`,
   `punpcklbw`, `punpcklwd`, `pshufd`).
2. While 16 bytes remain in the buffer at the current offset, load them with
   `movdqu`, compare with `pcmpeqb`, and extract a 16-bit mask with
   `pmovmskb`.
3. A zero mask skips the block. Otherwise `bsf` yields the lowest candidate;
   the candidate is verified against the rest of the pattern byte by byte,
   and the lowest set bit is cleared (`mask & (mask - 1)`) to move to the
   next candidate.
4. A candidate offset greater than `hay_len - pat_len` ends the search:
   later bits and later blocks only have larger offsets.
5. When fewer than 16 bytes remain, a scalar loop covers the remaining start
   offsets.

Consequences:

- **No out-of-bounds loads.** A vector load happens only when
  `offset + 16 <= hay_len`; the tail never reads past the buffer.
- **Verification may read past the 16-byte block** (patterns longer than 16
  bytes) but never past `hay_len`, because candidates are bounded by
  `hay_len - pat_len`.
- **Overlapping matches and block boundaries** need no special handling:
  every start offset is tested exactly once, in increasing order.

Verification is a plain byte loop; no second-byte filter or wider compare is
used.

## Line processing

`ag_scan` keeps a cursor that is always the start of a line. Per iteration:

1. Search from the cursor. No match ends the scan.
2. Line start: `ag_memrchr` for the last `\n` in `[cursor, match)`; the
   cursor itself when none is found.
3. Line end: `ag_memchr` for the first `\n` at or after the match, or the end
   of the buffer. A final line without a newline is therefore handled.
4. Count the line, then, if line numbers are wanted, add the newlines in
   `[previous line start, this line start)` to a running total with
   `ag_count_byte` and call the callback with `total + 1`.
5. Move the cursor to the byte after the line's newline.

Because the cursor jumps past the whole line, a line with several (or
overlapping) occurrences is reported once. Line numbers cost nothing unless
requested: with `-c` or without `-n` no newline counting happens.

`ag_memchr` and `ag_memrchr` use the same `pcmpeqb`/`pmovmskb` pattern
(`bsf` forward, `bsr` backward). `ag_count_byte` accumulates `pcmpeqb`
results into byte lanes with `psubb` (a match subtracts -1), folds at most
255 blocks at a time with `psadbw`, and handles the tail bytewise. It does
not use POPCNT, so no CPUID check is needed.

## Patterns containing a newline

A pattern with `\n` could match across line boundaries, which has no useful
line semantics. `ag_scan` rejects such patterns (the CLI reports an error,
the library returns `-EINVAL`).

## Library result construction

`asmgrep_search_*` runs `ag_scan` twice with different callbacks. Pass one
counts lines and text bytes. A single anonymous mapping is then sized exactly
and pass two fills it. The fill callback checks the entry and arena capacity
established by pass one, so if the input changes between passes the extra
data is dropped (or the search fails with `-EIO`) rather than overflowing.
