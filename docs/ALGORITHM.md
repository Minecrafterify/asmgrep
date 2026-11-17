
# Algorithm

## Search contract

`ag_find(hay, hay_len, pat, pat_len)` returns the index of the first
match of `pat` in `hay`, or `-1` if no match exists. An empty pattern
matches at index `0`.

`ag_find_scalar` is the canonical reference implementation.
`ag_find_sse2` must behave identically for every input. This is verified
through differential testing against `ag_find_scalar` and a Python
implementation in the test suite.

## Scalar search

The scalar implementation examines every possible pattern starting
position in the haystack, from `0` through `hay_len - pat_len`.

At each position, it checks the first byte. If that byte matches, the
remaining pattern bytes are compared.

This approach has a worst-case time complexity of O(n·m), where `n` is
the haystack length and `m` is the pattern length.

It is deliberately simple and serves as a correctness baseline for the
optimized implementation.

## SSE2 search

The SSE2 implementation uses an anchor byte to identify candidate match
positions, then verifies each candidate against the complete pattern.

### Anchor selection

If adaptive anchor selection is not used, the final character in the
pattern is selected as the anchor.

Adaptive anchor selection is enabled when both conditions are met:

- The pattern is at least 8 bytes long.
- The haystack is at least 4096 bytes long.

When adaptive selection is enabled, the implementation samples 64
evenly spaced locations in the haystack to estimate the frequency of
candidate characters at selected positions in the pattern.

Candidate pattern positions depend on the pattern length:

- **8–63 bytes:** Five positions are considered: the first character,
  quarter position, middle position, three-quarter position, and last
  character.
- **64 bytes or longer:** 64 character positions are distributed
  evenly throughout the pattern.

The candidate position with the lowest sampled character frequency is
selected as the anchor.

This is a heuristic. Although sampling estimates the selectivity of
candidate characters, it does not guarantee that the selected character
is the least frequent one in the entire haystack.

### SIMD candidate scanning

Once an anchor character has been selected, the SSE2 search proceeds
as follows:

1. Broadcast the anchor byte into an XMM register.
2. Load 16 haystack bytes using `movdqu`.
3. Compare the loaded bytes against the anchor using `pcmpeqb`.
4. Extract a 16-bit candidate mask using `pmovmskb`.
5. Use `bsf` to locate candidate anchor positions in increasing order.
6. Convert each anchor position into a possible pattern starting
   position by subtracting the anchor offset.
7. Reject candidates outside the valid range
   `[0, hay_len - pat_len]`.
8. Verify the complete pattern using 16-byte SIMD comparisons, with
   scalar processing for any remaining bytes.
9. Continue through the remaining candidate bits and vector blocks
   until the first valid match is found.

The final partial block is handled without reading beyond the haystack.

### Anchor caching

Adaptive anchor selection introduces a sampling cost. In dense search
cases, repeatedly sampling for every matching line can become
particularly expensive.

To avoid this overhead, `ag_scan` caches anchor positions during a scan.

- On the first applicable search, the anchor is selected and its
  position is cached.
- Subsequent searches reuse the cached offset instead of sampling again.
- The cache is valid only for the duration of the current scan.
- No global mutable state is introduced.
- For one-byte searches, adaptive anchor selection is not used, so no
  anchor cache is required.

This allows the search engine to use adaptive anchor selection without
incurring the performance cost of repeatedly sampling for every matching
line.

### Correctness

The implementation preserves first-match behavior through the following
constraints:

- Candidate pattern starting positions are limited to
  `[0, hay_len - pat_len]`.
- Anchor positions are converted into pattern starting positions before
  checking their validity.
- Every candidate is checked against the complete pattern, preventing
  anchor-character collisions from producing false matches.
- Candidates are examined in increasing pattern starting-position order.
- The scalar implementation remains available as the canonical
  correctness reference.
- Differential tests verify that the SSE2 implementation produces
  identical results to the scalar implementation and the Python
  reference implementation.

## Line processing

`ag_scan` maintains a cursor pointing to the beginning of the current
line.

For each iteration:

1. Find the next occurrence of the pattern starting at the cursor.
   If no match is found, exit.
2. Find the beginning of the matching line by searching backward from
   the match position for the previous newline in the range
   `[cursor, match)`. If no newline is found, the cursor is already at
   the beginning of the line.
3. Find the end of the matching line by searching forward from the match
   position for the first newline character. If no newline is found,
   use the end of the buffer. This also supports final lines without
   trailing newlines.
4. Count the matching line. If line numbering is requested, count the
   newlines between the beginning of the previous line and the beginning
   of the current line using `ag_count_byte`. Add this count to the
   cumulative total and invoke the callback with `total + 1`.
5. Advance the cursor to the byte immediately following the newline
   character at the end of the matching line.

Because the cursor advances past the entire matching line, multiple
matches within the same line—including overlapping matches—are reported
as exactly one matching line.

Line-number counting is skipped when it is unnecessary. If line
numbering is not requested, either through the `-c` flag or by not
using `-n`, newline counting is not performed.

### SIMD line helpers

`ag_memchr` and `ag_memrchr` use the same SIMD comparison approach as
the search engine.

- `pcmpeqb` compares bytes against the target character.
- `pmovmskb` generates a mask of matching bytes.
- `bsf` locates the first match when scanning forward.
- `bsr` locates the first match when scanning backward.

`ag_count_byte` uses SIMD instructions to count matching bytes:

1. `pcmpeqb` generates `0xFF` in each matching byte lane and `0` in
   non-matching lanes.
2. `psubb` accumulates the matches in the byte lanes.
3. `psadbw` sums the accumulated match counts into wider values.
4. Remaining tail bytes are counted individually.

Match counts are accumulated at most every 255 blocks to prevent
overflow in the byte lanes.

The implementation does not use POPCNT instructions, so no CPUID check
is required for POPCNT support.

## Patterns containing a newline

A pattern containing a newline could match across line boundaries,
which would not have meaningful semantics for line-based searching.

Therefore, patterns containing newlines are rejected:

- The CLI returns an error.
- The library returns `-EINVAL`.

## Library result construction

`asmgrep_search_*` calls `ag_scan` twice using different callbacks.

### Pass one: sizing

The first pass counts:

- The number of matching lines.
- The total number of text bytes required for the result.

These values determine the memory allocation required for the result.

### Allocation

An anonymous memory block is allocated with enough space to contain
all result entries and their associated text data.

### Pass two: populating results

The second pass fills the allocated result structure and text arena.

During population, the callback verifies that the maximum entry count
and text arena capacity match the values determined during the first
pass.

If the input changes between the two passes, additional data may be
dropped or the search may fail with `-EIO`.

This prevents writes beyond the allocated memory boundaries when the
input changes between passes.
