#include <asmgrep.h>

#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <string.h>
#include <unistd.h>

static int failures;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, \
                    #cond);                                                  \
            failures++;                                                      \
        }                                                                    \
    } while (0)

static void expect_lines(const char *data, const char *pat, unsigned flags,
                         size_t n, const size_t *numbers, const char **texts)
{
    asmgrep_result *r = NULL;
    int st = asmgrep_search_buffer(data, strlen(data), pat, strlen(pat), flags, &r);
    CHECK(st == 0);
    CHECK(asmgrep_result_count(r) == n);
    for (size_t i = 0; i < n && i < asmgrep_result_count(r); i++) {
        CHECK(asmgrep_result_line_number(r, i) == numbers[i]);
        CHECK(strcmp(asmgrep_result_text(r, i), texts[i]) == 0);
        CHECK(asmgrep_result_length(r, i) == strlen(texts[i]));
    }
    asmgrep_free(r);
}

static void test_basic(unsigned flags)
{
    const char *data = "alpha\nbeta ERROR\nERROR ERROR ERROR\ngamma\nlast ERROR";
    size_t nums[] = {2, 3, 5};
    const char *texts[] = {"beta ERROR", "ERROR ERROR ERROR", "last ERROR"};
    expect_lines(data, "ERROR", flags, 3, nums, texts);
    expect_lines(data, "zzz", flags, 0, NULL, NULL);

    size_t onum[] = {1};
    const char *otext[] = {"aaaa"};
    expect_lines("aaaa\nb", "aaa", flags, 1, onum, otext); /* overlapping */

    /* match straddling a 16-byte boundary and a long pattern */
    const char *long_data = "0123456789abcde-needle-in-a-haystack-0123456789\nxx";
    size_t lnum[] = {1};
    const char *ltext[] = {"0123456789abcde-needle-in-a-haystack-0123456789"};
    expect_lines(long_data, "needle-in-a-haystack-0123456789", flags, 1, lnum, ltext);
}

static void test_errors(void)
{
    asmgrep_result *r = (asmgrep_result *)1;
    CHECK(asmgrep_search_file("x", "/nonexistent/file", 0, &r) == -ENOENT);
    CHECK(r == NULL);
    CHECK(asmgrep_search_file("x", "/tmp", 0, &r) == -EISDIR);
    CHECK(asmgrep_search_file(NULL, "/tmp", 0, &r) == -EINVAL);
    CHECK(asmgrep_search_file("x", "/etc/hostname", 0, NULL) == -EINVAL);
    CHECK(asmgrep_search_file("a\nb", "/etc/hostname", 0, &r) == -EINVAL);
    CHECK(asmgrep_search_file("x", "/etc/hostname", 0x80, &r) == -EINVAL);
    CHECK(asmgrep_search_buffer(NULL, 4, "x", 1, 0, &r) == -EINVAL);
    CHECK(asmgrep_search_buffer("a\nb", 3, "a\nb", 3, 0, &r) == -EINVAL);
    CHECK(strcmp(asmgrep_strerror(-ENOENT), "No such file or directory") == 0);
    CHECK(strcmp(asmgrep_strerror(0), "Success") == 0);
    CHECK(strcmp(asmgrep_version(), "1.0.0") == 0);

    CHECK(asmgrep_search_buffer(NULL, 0, "x", 1, 0, &r) == 0);
    CHECK(asmgrep_result_count(r) == 0);
    CHECK(asmgrep_result_text(r, 0) == NULL);
    CHECK(asmgrep_result_line_number(r, 0) == 0);
    asmgrep_free(r);
    asmgrep_free(NULL);
    CHECK(asmgrep_result_count(NULL) == 0);

    if (geteuid() != 0) {
        char tmpl[] = "/tmp/asmgrep-perm-XXXXXX";
        int fd = mkstemp(tmpl);
        CHECK(fd >= 0);
        close(fd);
        chmod(tmpl, 0);
        CHECK(asmgrep_search_file("x", tmpl, 0, &r) == -EACCES);
        unlink(tmpl);
    }
}

static void test_files(void)
{
    char tmpl[] = "/tmp/asmgrep-test-XXXXXX";
    int fd = mkstemp(tmpl);
    CHECK(fd >= 0);
    asmgrep_result *r = NULL;

    CHECK(asmgrep_search_file("x", tmpl, 0, &r) == 0); /* empty file */
    CHECK(asmgrep_result_count(r) == 0);
    asmgrep_free(r);

    const char text[] = "one\ntwo ERROR\nthree";
    CHECK(write(fd, text, sizeof text - 1) == (ssize_t)sizeof text - 1);
    for (int i = 0; i < 3; i++) { /* repeated searches */
        CHECK(asmgrep_search_file("ERROR", tmpl, 0, &r) == 0);
        CHECK(asmgrep_result_count(r) == 1);
        CHECK(asmgrep_result_line_number(r, 0) == 2);
        CHECK(strcmp(asmgrep_result_text(r, 0), "two ERROR") == 0);
        asmgrep_free(r);
    }
    close(fd);
    unlink(tmpl);
}

static size_t count_dir(const char *path)
{
    size_t n = 0;
    DIR *d = opendir(path);
    if (!d)
        return 0;
    while (readdir(d))
        n++;
    closedir(d);
    return n;
}

static size_t count_maps(void)
{
    size_t n = 0;
    FILE *f = fopen("/proc/self/maps", "r");
    int c;
    if (!f)
        return 0;
    while ((c = fgetc(f)) != EOF)
        if (c == '\n')
            n++;
    fclose(f);
    return n;
}

static void test_leaks(void)
{
    char tmpl[] = "/tmp/asmgrep-leak-XXXXXX";
    int fd = mkstemp(tmpl);
    const char text[] = "a ERROR\nb\nc ERROR\n";
    CHECK(write(fd, text, sizeof text - 1) > 0);
    close(fd);
    asmgrep_result *r;
    asmgrep_search_file("ERROR", tmpl, 0, &r); /* warm up allocator state */
    asmgrep_free(r);
    size_t fds = count_dir("/proc/self/fd");
    size_t maps = count_maps();
    for (int i = 0; i < 500; i++) {
        CHECK(asmgrep_search_file("ERROR", tmpl, 0, &r) == 0);
        asmgrep_free(r);
        CHECK(asmgrep_search_file("ERROR", "/nonexistent", 0, &r) < 0);
        CHECK(asmgrep_search_file("a\nb", tmpl, 0, &r) < 0);
    }
    CHECK(count_dir("/proc/self/fd") == fds);
    CHECK(count_maps() == maps);
    unlink(tmpl);
}

static void *worker(void *arg)
{
    size_t *bad = arg;
    char *buf = malloc(1 << 16);
    for (size_t i = 0; i < (1 << 16); i++) buf[i] = (i % 40 == 39) ? '\n' : 'a' + (char)(i % 7);
    for (int round = 0; round < 200; round++) {
        asmgrep_result *r;
        if (asmgrep_search_buffer(buf, 1 << 16, "cde", 3, round & 1, &r) != 0) { (*bad)++; continue; }
        size_t n = asmgrep_result_count(r);
        if (n == 0) (*bad)++;
        for (size_t i = 0; i < n; i++)
            if (!strstr(asmgrep_result_text(r, i), "cde")) (*bad)++;
        asmgrep_free(r);
    }
    free(buf);
    return NULL;
}

static void test_threads(void)
{
    pthread_t t[8];
    size_t bad[8] = {0};
    for (int i = 0; i < 8; i++) pthread_create(&t[i], NULL, worker, &bad[i]);
    for (int i = 0; i < 8; i++) { pthread_join(t[i], NULL); CHECK(bad[i] == 0); }
}

int main(void)
{
    test_basic(0);
    test_basic(ASMGREP_SEARCH_SCALAR);
    test_errors();
    test_files();
    test_leaks();
    test_threads();
    if (failures) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("native C tests passed");
    return 0;
}
