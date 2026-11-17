#include <asmgrep.hpp>

#include <cstdio>
#include <iostream>
#include <string>

static int failures;

#define CHECK(cond)                                                          \
    do {                                                                     \
        if (!(cond)) {                                                       \
            std::cerr << __FILE__ << ':' << __LINE__ << ": check failed: "   \
                      << #cond << '\n';                                      \
            failures++;                                                      \
        }                                                                    \
    } while (0)

int main()
{
    auto results = asmgrep::search_buffer("a\nxERRORx\nb\nERROR", "ERROR");
    CHECK(results.size() == 2);
    std::size_t seen = 0;
    for (const auto &m : results) {
        CHECK(m.line_number == (seen == 0 ? 2u : 4u));
        seen++;
    }
    CHECK(seen == 2);
    CHECK(results.text(0) == "xERRORx");

    auto moved = std::move(results);
    CHECK(moved.size() == 2);
    CHECK(results.size() == 0);

    bool threw = false;
    try {
        asmgrep::search("x", "/nonexistent/file");
    } catch (const asmgrep::error &e) {
        threw = true;
        CHECK(e.status() == -2);
    }
    CHECK(threw);

    threw = false;
    try {
        (void)moved.text(9);
    } catch (const std::out_of_range &) {
        threw = true;
    }
    CHECK(threw);

    auto scalar = asmgrep::search_buffer("xx\nabc", "abc", asmgrep::engine::scalar);
    CHECK(scalar.size() == 1 && scalar[0].line_number == 2);

    if (failures) return 1;
    std::puts("native C++ tests passed");
    return 0;
}
