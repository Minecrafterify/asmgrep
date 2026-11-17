import ctypes
import random
import sys

lib = ctypes.CDLL("./build/libasmgrep.so")

search = lib.asmgrep_search_buffer
search.argtypes = [
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_void_p, ctypes.c_size_t,
    ctypes.c_uint, ctypes.POINTER(ctypes.c_void_p)
]
search.restype = ctypes.c_int

count = lib.asmgrep_result_count
count.argtypes = [ctypes.c_void_p]
count.restype = ctypes.c_size_t

line_number = lib.asmgrep_result_line_number
line_number.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
line_number.restype = ctypes.c_size_t

result_length = lib.asmgrep_result_length
result_length.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
result_length.restype = ctypes.c_size_t

result_text = lib.asmgrep_result_text
result_text.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
result_text.restype = ctypes.c_void_p

free_result = lib.asmgrep_free
free_result.argtypes = [ctypes.c_void_p]

rng = random.Random(12345)

for test in range(5000):
    data = bytes(rng.randrange(256) for _ in range(rng.randrange(300)))
    pattern = bytes(
        x for x in
        (rng.randrange(256) for _ in range(rng.randrange(40)))
        if x != 10
    )

    dbuf = ctypes.create_string_buffer(data or b"\0")
    pbuf = ctypes.create_string_buffer(pattern or b"\0")
    out = ctypes.c_void_p()

    status = search(
        dbuf, len(data), pbuf, len(pattern),
        0, ctypes.byref(out)
    )

    if status != 0:
        print("FAILED: status", status, "test", test)
        sys.exit(1)

    try:
        lines = data.split(b"\n")
        if data.endswith(b"\n"):
            lines.pop()
        if not data:
            lines = []

        expected = [
            (i + 1, line)
            for i, line in enumerate(lines)
            if pattern in line
        ]

        if count(out) != len(expected):
            print("FAILED: count mismatch, test", test)
            sys.exit(1)

        for i, (expected_line, expected_text) in enumerate(expected):
            actual_line = line_number(out, i)
            actual_len = result_length(out, i)
            actual_ptr = result_text(out, i)
            actual_text = ctypes.string_at(actual_ptr, actual_len)

            if (actual_line, actual_text) != (expected_line, expected_text):
                print("FAILED: result mismatch, test", test)
                sys.exit(1)
    finally:
        free_result(out)

print("5,000 randomized API tests passed!")
