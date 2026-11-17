import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "bindings", "python"))

import asmgrep  # noqa: E402


class SearchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(delete=False)
        self.addCleanup(os.unlink, self.tmp.name)

    def write(self, data):
        self.tmp.write(data)
        self.tmp.close()
        return self.tmp.name

    def test_basic(self):
        path = self.write(b"one\ntwo ERROR\nthree\nfour ERROR ERROR")
        results = asmgrep.search("ERROR", path)
        self.assertEqual([(m.line_number, m.text) for m in results],
                         [(2, "two ERROR"), (4, "four ERROR ERROR")])

    def test_empty_file_and_no_match(self):
        self.assertEqual(asmgrep.search("x", self.write(b"")), [])

    def test_scalar_matches_simd(self):
        data = b"".join(b"line %d needle-%d\n" % (i, i % 7) for i in range(5000))
        path = self.write(data)
        self.assertEqual(asmgrep.search("needle-3", path),
                         asmgrep.search("needle-3", path, scalar=True))

    def test_errors(self):
        with self.assertRaises(asmgrep.AsmgrepError) as ctx:
            asmgrep.search("x", "/nonexistent/file")
        self.assertEqual(ctx.exception.errno, 2)
        with self.assertRaises(asmgrep.AsmgrepError):
            asmgrep.search("a\nb", "/etc/hostname")
        with self.assertRaises(ValueError):
            asmgrep.search(b"a\0b", "/etc/hostname")

    def test_bytes_api(self):
        results = asmgrep.search_bytes(b"a\0b", b"x\na\0b\ny")
        self.assertEqual([(m.line_number, m.raw) for m in results], [(2, b"a\0b")])
        self.assertEqual(asmgrep.search_bytes("q", b""), [])
        self.assertEqual(len(asmgrep.search_bytes("a", bytearray(b"a\na"))), 2)

    def test_repeated(self):
        path = self.write(b"x ERROR\n" * 100)
        for _ in range(200):
            self.assertEqual(len(asmgrep.search("ERROR", path)), 100)

    def test_version(self):
        self.assertEqual(asmgrep.version(), "1.0.0")


if __name__ == "__main__":
    unittest.main()
