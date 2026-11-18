
#define _GNU_SOURCE

#include <asmgrep.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static size_t failures;

static void fail(const char *message)
{
    fprintf(stderr, "FAIL: %s\n", message);
    failures++;
}

static void test_guard_page(unsigned scalar)
{
    long page_size = sysconf(_SC_PAGESIZE);

    if (page_size <= 0) {
        fail("could not determine page size");
        return;
    }

    size_t mapping_size = (size_t)page_size * 2;

    unsigned char *mapping = mmap(
        NULL,
        mapping_size,
        PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS,
        -1,
        0);

    if (mapping == MAP_FAILED) {
        fail("mmap failed");
        return;
    }

    if (mprotect(
            mapping + page_size,
            (size_t)page_size,
            PROT_NONE) != 0) {
        fail("mprotect failed");
        munmap(mapping, mapping_size);
        return;
    }

    /*
     * Place the input exactly at the end of the readable page.
     * Any read beyond len reaches the inaccessible page.
     */
    static const unsigned char data[] =
        "alpha beta gamma\n"
        "nothing here\n"
        "gamma at the end";

    static const unsigned char pattern[] = "gamma";

    size_t len = sizeof(data) - 1;

    unsigned char *buffer =
        mapping + page_size - len;

    memcpy(buffer, data, len);

    asmgrep_result *result = NULL;

    unsigned flags = scalar ? ASMGREP_SEARCH_SCALAR : 0;

    int status = asmgrep_search_buffer(
        buffer,
        len,
        (const char *)pattern,
        sizeof(pattern) - 1,
        flags,
        &result);

    if (status != 0) {
        fail("search_buffer returned an error");
    } else if (!result) {
        fail("successful search returned NULL");
    } else {
        if (asmgrep_result_count(result) != 2)
            fail("incorrect result count");

        if (asmgrep_result_line_number(result, 0) != 1)
            fail("incorrect first line number");

        if (asmgrep_result_line_number(result, 1) != 3)
            fail("incorrect second line number");

        const char *first = asmgrep_result_text(result, 0);
        const char *second = asmgrep_result_text(result, 1);

        if (!first || strcmp(first, "alpha beta gamma") != 0)
            fail("incorrect first result text");

        if (!second || strcmp(second, "gamma at the end") != 0)
            fail("incorrect second result text");
    }

    asmgrep_free(result);
    munmap(mapping, mapping_size);
}

int main(void)
{
    puts("asmgrep public C API guard-page test");

    puts("testing SIMD...");
    test_guard_page(0);

    puts("testing scalar...");
    test_guard_page(1);

    if (failures) {
        fprintf(stderr, "%zu failure(s)\n", failures);
        return 1;
    }

    puts("PASS: SIMD and scalar guard-page tests");
    return 0;
}