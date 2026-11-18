#include <asmgrep.h>

#include <errno.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FUZZ_CASES 20000
#define MAX_BUFFER 2048
#define MAX_PATTERN 96

#define INITIAL_SEED UINT64_C(0xA51C6E9D73B204F1)

static uint64_t rng_state = INITIAL_SEED;
static size_t failures;

/* Reproducible xorshift64* PRNG. */
static uint64_t random_u64(void)
{
    uint64_t x = rng_state;

    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;

    rng_state = x;

    return x * UINT64_C(2685821657736338717);
}

static size_t random_size(size_t max)
{
    return max ? (size_t)(random_u64() % (max + 1)) : 0;
}

static void random_bytes(unsigned char *p, size_t n)
{
    for (size_t i = 0; i < n; i++)
        p[i] = (unsigned char)random_u64();
}

static void fail(size_t test, const char *reason)
{
    if (failures < 20) {
        fprintf(stderr,
                "FAIL seed=0x%016" PRIx64
                " case=%zu: %s\n",
                INITIAL_SEED, test, reason);
    }

    failures++;
}

/*
 * Independent reference implementation.
 *
 * Lines are separated only by '\n'.
 * Empty patterns match every actual line.
 * Empty buffers contain zero lines.
 * A trailing newline does not create a phantom line.
 */
static size_t reference_search(
    const unsigned char *buf,
    size_t len,
    const unsigned char *pat,
    size_t pat_len,
    size_t *line_numbers,
    size_t *line_starts,
    size_t *line_lengths)
{
    size_t count = 0;
    size_t start = 0;
    size_t line_no = 1;

    while (start < len) {
        size_t end = start;

        while (end < len && buf[end] != '\n')
            end++;

        size_t line_len = end - start;
        int matched = (pat_len == 0);

        if (!matched && pat_len <= line_len) {
            for (size_t i = 0; i <= line_len - pat_len; i++) {
                if (memcmp(buf + start + i, pat, pat_len) == 0) {
                    matched = 1;
                    break;
                }
            }
        }

        if (matched) {
            line_numbers[count] = line_no;
            line_starts[count] = start;
            line_lengths[count] = line_len;
            count++;
        }

        if (end == len)
            break;

        start = end + 1;
        line_no++;
    }

    return count;
}

static int check_mode(
    const unsigned char *buf,
    size_t len,
    const unsigned char *pat,
    size_t pat_len,
    unsigned flags,
    size_t expected_count,
    const size_t *numbers,
    const size_t *starts,
    const size_t *lengths,
    size_t test)
{
    asmgrep_result *result = NULL;

    int status = asmgrep_search_buffer(
        buf,
        len,
        (const char *)pat,
        pat_len,
        flags,
        &result);

    if (status != 0) {
        fail(test, "search_buffer returned an unexpected error");
        asmgrep_free(result);
        return 0;
    }

    if (!result) {
        fail(test, "successful search returned NULL result");
        return 0;
    }

    size_t actual_count = asmgrep_result_count(result);

    if (actual_count != expected_count) {
        fail(test, "result count mismatch");
        asmgrep_free(result);
        return 0;
    }

    int valid = 1;

    for (size_t i = 0; i < expected_count; i++) {
        size_t actual_number =
            asmgrep_result_line_number(result, i);

        size_t actual_length =
            asmgrep_result_length(result, i);

        const char *actual_text =
            asmgrep_result_text(result, i);

        if (actual_number != numbers[i]) {
            fail(test, "line number mismatch");
            valid = 0;
            break;
        }

        if (actual_length != lengths[i]) {
            fail(test, "line length mismatch");
            valid = 0;
            break;
        }

        if (!actual_text) {
            fail(test, "NULL text for valid result index");
            valid = 0;
            break;
        }

        if (memcmp(actual_text, buf + starts[i], lengths[i]) != 0) {
            fail(test, "result text bytes mismatch");
            valid = 0;
            break;
        }

        if (actual_text[actual_length] != '\0') {
            fail(test, "result text is not NUL-terminated");
            valid = 0;
            break;
        }
    }

    if (asmgrep_result_text(result, expected_count) != NULL) {
        fail(test, "out-of-range text accessor was not NULL");
        valid = 0;
    }

    asmgrep_free(result);

    return valid;
}

static int run_case(
    const unsigned char *buf,
    size_t len,
    const unsigned char *pat,
    size_t pat_len,
    size_t test)
{
    size_t capacity = len + 1;

    size_t *numbers = calloc(capacity, sizeof(*numbers));
    size_t *starts = calloc(capacity, sizeof(*starts));
    size_t *lengths = calloc(capacity, sizeof(*lengths));

    if (!numbers || !starts || !lengths) {
        fprintf(stderr, "out of memory\n");

        free(numbers);
        free(starts);
        free(lengths);

        return 0;
    }

    size_t expected = reference_search(
        buf,
        len,
        pat,
        pat_len,
        numbers,
        starts,
        lengths);

    int simd_ok = check_mode(
        buf, len, pat, pat_len,
        0, expected,
        numbers, starts, lengths, test);

    int scalar_ok = check_mode(
        buf, len, pat, pat_len,
        ASMGREP_SEARCH_SCALAR, expected,
        numbers, starts, lengths, test);

    free(numbers);
    free(starts);
    free(lengths);

    return simd_ok && scalar_ok;
}

static void test_invalid_patterns(void)
{
    asmgrep_result *result = NULL;

    static const unsigned char data[] = "alpha\nbeta";

    static const unsigned char bad_pattern[] = {
        'a', '\n', 'b'
    };

    if (asmgrep_search_buffer(
            data, sizeof(data) - 1,
            (const char *)bad_pattern,
            sizeof(bad_pattern),
            0, &result) != -EINVAL) {
        fail(0, "newline pattern should return -EINVAL");
    }

    if (result != NULL) {
        fail(0, "result should be NULL after invalid pattern");
        asmgrep_free(result);
    }

    result = (asmgrep_result *)1;

    if (asmgrep_search_buffer(
            NULL, 1,
            (const char *)data,
            1, 0, &result) != -EINVAL) {
        fail(0, "NULL non-empty buffer should return -EINVAL");
    }

    if (result != NULL) {
        fail(0, "result should be NULL after invalid buffer");
        asmgrep_free(result);
    }

    result = (asmgrep_result *)1;

    if (asmgrep_search_buffer(
            data, sizeof(data) - 1,
            (const char *)data,
            1, 0x80, &result) != -EINVAL) {
        fail(0, "unknown flags should return -EINVAL");
    }

    if (result != NULL) {
        fail(0, "result should be NULL after invalid flags");
        asmgrep_free(result);
    }
}

static void test_fixed_cases(void)
{
    static const unsigned char newline[] = "\n";
    static const unsigned char empty_pattern[] = {0};

    static const unsigned char binary[] = {
        'a', 0, 'b', '\n',
        0, 'x', 0, '\n',
        'z', 'z', 'z'
    };

    static const unsigned char nul_pattern[] = {0};
    static const unsigned char binary_pattern[] = {0, 'b'};

    static const unsigned char too_long[] =
        "this pattern is longer";

    static const unsigned char short_data[] = "abc";

    static const unsigned char trailing[] = "first\nsecond\n";
    static const unsigned char first_pattern[] = "first";

    /* Empty buffer and empty pattern. */
    run_case(NULL, 0, empty_pattern, 0, 1);

    /* One empty line. */
    run_case(
        newline, sizeof(newline) - 1,
        empty_pattern, 0, 2);

    /* Embedded NUL matching. */
    run_case(
        binary, sizeof(binary),
        nul_pattern, sizeof(nul_pattern), 3);

    run_case(
        binary, sizeof(binary),
        binary_pattern, sizeof(binary_pattern), 4);

    /* Pattern longer than the input line. */
    run_case(
        short_data, sizeof(short_data) - 1,
        too_long, sizeof(too_long) - 1, 5);

    /* Trailing newline must not create a phantom line. */
    run_case(
        trailing, sizeof(trailing) - 1,
        first_pattern, sizeof(first_pattern) - 1, 6);
}

int main(void)
{
    printf("asmgrep public C API fuzz test\n");
    printf("seed: 0x%016" PRIx64 "\n", INITIAL_SEED);
    printf("cases: %d\n", FUZZ_CASES);

    test_invalid_patterns();
    test_fixed_cases();

    unsigned char *buffer = malloc(MAX_BUFFER + 32);
    unsigned char *pattern = malloc(MAX_PATTERN + 32);

    if (!buffer || !pattern) {
        fprintf(stderr, "allocation failed\n");

        free(buffer);
        free(pattern);

        return 1;
    }

    for (size_t test = 0; test < FUZZ_CASES; test++) {
        size_t len = random_size(MAX_BUFFER);
        size_t pat_len = random_size(MAX_PATTERN);

        /* Randomize alignment to exercise unaligned input addresses. */
        size_t buf_offset = random_size(15);
        size_t pat_offset = random_size(15);

        unsigned char *buf = buffer + buf_offset;
        unsigned char *pat = pattern + pat_offset;

        random_bytes(buf, len);
        random_bytes(pat, pat_len);

        /* Frequently generate line separators and embedded NUL bytes. */
        for (size_t i = 0; i < len; i++) {
            uint64_t choice = random_u64() % 12;

            if (choice == 0)
                buf[i] = '\n';
            else if (choice == 1)
                buf[i] = '\0';
        }

        /*
         * Patterns must not contain newline.
         * Embedded NUL bytes are valid.
         */
        for (size_t i = 0; i < pat_len; i++) {
            if (pat[i] == '\n')
                pat[i] = '\0';
        }

        run_case(
            buf, len,
            pat, pat_len,
            test + 100);
    }

    free(buffer);
    free(pattern);

    if (failures) {
        fprintf(stderr, "\n%zu failure(s)\n", failures);
        return 1;
    }

    printf("PASS: %d randomized cases, SIMD and scalar\n",
           FUZZ_CASES);

    return 0;
}
