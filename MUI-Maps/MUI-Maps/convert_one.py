#!/usr/bin/env python3
"""Convert a single PNG tile to LVGL RGB565 .bin using LVGL's LVGLImage.py.

Usage:
  ./convert_one.py <input.png> <output.bin>
"""

import os
import sys
from pathlib import Path

LVGLIMAGE = Path("/home/miles/.openclaw/workspace/standalone-ui/.pio/libdeps/native-mui/lvgl/scripts/LVGLImage.py")


def main():
    if len(sys.argv) != 3:
        print(__doc__.strip())
        return 2

    src = Path(sys.argv[1]).expanduser().resolve()
    dst = Path(sys.argv[2]).expanduser().resolve()
    dst.parent.mkdir(parents=True, exist_ok=True)

    if not LVGLIMAGE.exists():
        print(f"Missing {LVGLIMAGE}. Build standalone-ui first.")
        return 1

    # LVGLImage expects: LVGLImage.py <input> --ofmt BIN --cf RGB565 -o <output>
    import subprocess

    py = Path("/home/miles/.openclaw/workspace/mui-tiles/.venv/bin/python")
    # LVGLImage's -o is an output *directory* (it will derive the filename from input/--name)
    cmd = [str(py), str(LVGLIMAGE), str(src), "--ofmt", "BIN", "--cf", "RGB565", "-o", str(dst.parent), "--name", dst.stem]
    print(" ".join(cmd))
    subprocess.check_call(cmd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
