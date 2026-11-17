"""Locates and loads the native asmgrep library."""

import ctypes
import ctypes.util
import os
import sys

_SONAME = "libasmgrep.so.1"
_ENV = "ASMGREP_LIBRARY"


class LibraryNotFoundError(ImportError):
    """Raised when libasmgrep cannot be located."""


def _candidates():
    override = os.environ.get(_ENV)
    if override:
        yield override
        return
    here = os.path.dirname(os.path.abspath(__file__))
    yield _SONAME
    found = ctypes.util.find_library("asmgrep")
    if found:
        yield found
    # Installed under a prefix: <prefix>/lib/pythonX.Y/site-packages/asmgrep
    yield os.path.join(here, "..", "..", "..", _SONAME)
    # Uninstalled source tree: bindings/python/asmgrep -> <root>/build
    root = os.path.abspath(os.path.join(here, "..", "..", ".."))
    yield os.path.join(root, "build", _SONAME)
    for prefix in {sys.prefix, "/usr", "/usr/local", os.path.expanduser("~/.local")}:
        yield os.path.join(prefix, "lib", _SONAME)


def load():
    """Returns the ctypes handle with all prototypes declared."""
    errors = []
    lib = None
    for name in _candidates():
        try:
            lib = ctypes.CDLL(name)
            break
        except OSError as exc:
            errors.append(str(exc))
    if lib is None:
        raise LibraryNotFoundError(
            "could not load libasmgrep (set %s to its path):\n  %s"
            % (_ENV, "\n  ".join(errors))
        )

    c_size = ctypes.c_size_t
    c_void_p = ctypes.c_void_p

    lib.asmgrep_search_file.argtypes = [
        ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint, ctypes.POINTER(c_void_p)]
    lib.asmgrep_search_file.restype = ctypes.c_int
    lib.asmgrep_search_buffer.argtypes = [
        c_void_p, c_size, ctypes.c_char_p, c_size, ctypes.c_uint,
        ctypes.POINTER(c_void_p)]
    lib.asmgrep_search_buffer.restype = ctypes.c_int
    lib.asmgrep_result_count.argtypes = [c_void_p]
    lib.asmgrep_result_count.restype = c_size
    lib.asmgrep_result_line_number.argtypes = [c_void_p, c_size]
    lib.asmgrep_result_line_number.restype = c_size
    lib.asmgrep_result_text.argtypes = [c_void_p, c_size]
    lib.asmgrep_result_text.restype = c_void_p
    lib.asmgrep_result_length.argtypes = [c_void_p, c_size]
    lib.asmgrep_result_length.restype = c_size
    lib.asmgrep_free.argtypes = [c_void_p]
    lib.asmgrep_free.restype = None
    lib.asmgrep_strerror.argtypes = [ctypes.c_int]
    lib.asmgrep_strerror.restype = ctypes.c_char_p
    lib.asmgrep_version.argtypes = []
    lib.asmgrep_version.restype = ctypes.c_char_p
    return lib
