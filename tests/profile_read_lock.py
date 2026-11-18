"""Windows-only, bounded exclusive lock for the Profile migration fixture."""
import ctypes
from ctypes import wintypes
from pathlib import Path
import sys
import time


def main():
    path, ready, release = map(Path, sys.argv[1:])
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                  wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateFileW(str(path), 0x80000000, 0, None, 3, 0, None)
    if handle == wintypes.HANDLE(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        ready.write_text("locked", encoding="utf-8")
        deadline = time.monotonic() + 8
        while not release.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
    finally:
        kernel.CloseHandle(handle)


if __name__ == "__main__":
    main()
