"""Python interface to the asmgrep native search engine.

All searching is performed by libasmgrep; this module only marshals
arguments and results through ctypes.
"""

import ctypes
import os
from typing import List, NamedTuple, Union

from .loader import LibraryNotFoundError, load

__all__ = ["Match", "AsmgrepError", "LibraryNotFoundError", "search",
           "search_bytes", "version"]

_lib = load()
_SCALAR = 0x1


class AsmgrepError(OSError):
    """A search failed. ``errno`` holds the OS error number when applicable."""


class Match(NamedTuple):
    line_number: int
    text: str

    @property
    def raw(self) -> bytes:
        return self.text.encode("utf-8", "surrogateescape")


def version() -> str:
    return _lib.asmgrep_version().decode("ascii")


def _raise(status: int, filename=None):
    message = _lib.asmgrep_strerror(status).decode("utf-8", "replace")
    raise AsmgrepError(-status, message, filename)


def _collect(handle: ctypes.c_void_p) -> List[Match]:
    try:
        count = _lib.asmgrep_result_count(handle)
        results = []
        for i in range(count):
            ptr = _lib.asmgrep_result_text(handle, i)
            length = _lib.asmgrep_result_length(handle, i)
            raw = ctypes.string_at(ptr, length)
            results.append(Match(_lib.asmgrep_result_line_number(handle, i),
                                 raw.decode("utf-8", "surrogateescape")))
        return results
    finally:
        _lib.asmgrep_free(handle)


def _pattern_bytes(pattern: Union[str, bytes]) -> bytes:
    if isinstance(pattern, str):
        return pattern.encode("utf-8", "surrogateescape")
    return bytes(pattern)


def search(pattern: Union[str, bytes], filename: Union[str, bytes, "os.PathLike"],
           *, scalar: bool = False) -> List[Match]:
    """Returns the lines of *filename* that contain *pattern*."""
    pat = _pattern_bytes(pattern)
    if b"\0" in pat:
        raise ValueError("file search patterns cannot contain NUL; use search_bytes")
    path = os.fsencode(filename)
    out = ctypes.c_void_p()
    status = _lib.asmgrep_search_file(pat, path, _SCALAR if scalar else 0,
                                      ctypes.byref(out))
    if status != 0:
        _raise(status, os.fsdecode(path))
    return _collect(out)


def search_bytes(pattern: Union[str, bytes], data: Union[bytes, bytearray, memoryview],
                 *, scalar: bool = False) -> List[Match]:
    """Returns the lines of an in-memory buffer that contain *pattern*."""
    pat = _pattern_bytes(pattern)
    view = memoryview(data).cast("B")
    out = ctypes.c_void_p()
    if view.nbytes:
        if view.readonly:
            buf = ctypes.c_char_p(bytes(view))
            addr = ctypes.cast(buf, ctypes.c_void_p)
            status = _lib.asmgrep_search_buffer(addr, view.nbytes, pat, len(pat),
                                                _SCALAR if scalar else 0,
                                                ctypes.byref(out))
        else:
            arr = (ctypes.c_char * view.nbytes).from_buffer(view)
            status = _lib.asmgrep_search_buffer(ctypes.addressof(arr), view.nbytes,
                                                pat, len(pat),
                                                _SCALAR if scalar else 0,
                                                ctypes.byref(out))
    else:
        status = _lib.asmgrep_search_buffer(None, 0, pat, len(pat),
                                            _SCALAR if scalar else 0,
                                            ctypes.byref(out))
    if status != 0:
        _raise(status)
    return _collect(out)
