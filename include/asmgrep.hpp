// asmgrep - C++ interface
//
// Header-only RAII wrapper over the C API in asmgrep.h. It performs no
// searching itself; every call is forwarded to libasmgrep.
#ifndef ASMGREP_HPP
#define ASMGREP_HPP

#include "asmgrep.h"

#include <cstddef>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace asmgrep {

class error : public std::runtime_error {
public:
    explicit error(int status)
        : std::runtime_error(asmgrep_strerror(status)), status_(status) {}

    // Negative errno value reported by the library.
    int status() const noexcept { return status_; }

private:
    int status_;
};

struct match {
    std::size_t line_number;
    std::string text;
};

enum class engine : unsigned {
    simd = 0,
    scalar = ASMGREP_SEARCH_SCALAR,
};

// Owning handle to a native result. Move-only.
class result_set {
public:
    result_set() noexcept = default;
    explicit result_set(asmgrep_result *raw) noexcept : raw_(raw) {}
    result_set(const result_set &) = delete;
    result_set &operator=(const result_set &) = delete;
    result_set(result_set &&other) noexcept : raw_(std::exchange(other.raw_, nullptr)) {}
    result_set &operator=(result_set &&other) noexcept {
        if (this != &other) {
            asmgrep_free(raw_);
            raw_ = std::exchange(other.raw_, nullptr);
        }
        return *this;
    }
    ~result_set() { asmgrep_free(raw_); }

    std::size_t size() const noexcept { return asmgrep_result_count(raw_); }
    bool empty() const noexcept { return size() == 0; }

    std::size_t line_number(std::size_t i) const { return asmgrep_result_line_number(raw_, check(i)); }

    // Valid while this result_set is alive.
    std::string_view text(std::size_t i) const {
        check(i);
        return {asmgrep_result_text(raw_, i), asmgrep_result_length(raw_, i)};
    }

    match operator[](std::size_t i) const { return {line_number(i), std::string(text(i))}; }

    class const_iterator {
    public:
        using value_type = match;
        using difference_type = std::ptrdiff_t;
        using pointer = const match *;
        using reference = match;
        using iterator_category = std::input_iterator_tag;

        const_iterator(const result_set *set, std::size_t i) noexcept : set_(set), i_(i) {}
        match operator*() const { return (*set_)[i_]; }
        const_iterator &operator++() noexcept { ++i_; return *this; }
        const_iterator operator++(int) noexcept { auto copy = *this; ++i_; return copy; }
        bool operator==(const const_iterator &o) const noexcept { return i_ == o.i_; }
        bool operator!=(const const_iterator &o) const noexcept { return i_ != o.i_; }

    private:
        const result_set *set_;
        std::size_t i_;
    };

    const_iterator begin() const noexcept { return {this, 0}; }
    const_iterator end() const noexcept { return {this, size()}; }

private:
    std::size_t check(std::size_t i) const {
        if (i >= size()) throw std::out_of_range("asmgrep::result_set index out of range");
        return i;
    }

    asmgrep_result *raw_ = nullptr;
};

// Searches a file. Throws asmgrep::error on failure.
inline result_set search(const std::string &pattern, const std::string &path,
                         engine e = engine::simd) {
    asmgrep_result *raw = nullptr;
    int status = asmgrep_search_file(pattern.c_str(), path.c_str(),
                                     static_cast<unsigned>(e), &raw);
    if (status != 0) throw error(status);
    return result_set(raw);
}

// Searches a memory buffer. Throws asmgrep::error on failure.
inline result_set search_buffer(std::string_view data, std::string_view pattern,
                                engine e = engine::simd) {
    asmgrep_result *raw = nullptr;
    // The pattern is passed by length, so an empty view needs a valid pointer.
    const char *pat = pattern.empty() ? "" : pattern.data();
    int status = asmgrep_search_buffer(data.data(), data.size(), pat, pattern.size(),
                                       static_cast<unsigned>(e), &raw);
    if (status != 0) throw error(status);
    return result_set(raw);
}

} // namespace asmgrep

#endif
