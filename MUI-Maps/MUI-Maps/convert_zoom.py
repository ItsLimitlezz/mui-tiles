#!/usr/bin/env python3
"""Batch convert a whole zoom level of tiles PNG/JPG -> LVGL RGB565 .bin.

Example:
  ./convert_zoom.py --z 13 \
    --src-root /home/miles/.openclaw/workspace/standalone-ui/maps \
    --dst-root /home/miles/.openclaw/workspace/standalone-ui/maps

This will create map/<z>/<x>/<y>.bin next to the existing images.

Notes:
- Uses LVGL's scripts/LVGLImage.py (requires mui-tiles/.venv with pypng + lz4)
- Output is folder-tree format: map/z/x/y.bin
- Continues on conversion errors and prints a summary.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

LVGLIMAGE = Path("/home/miles/.openclaw/workspace/standalone-ui/.pio/libdeps/native-mui/lvgl/scripts/LVGLImage.py")
PY = Path("/home/miles/.openclaw/workspace/mui-tiles/.venv/bin/python")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--z", type=int, required=True)
    ap.add_argument("--src-root", required=True)
    ap.add_argument("--dst-root", required=True)
    ap.add_argument("--src-ext", default="png", choices=["png", "jpg", "jpeg"]) 
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    src_z = Path(args.src_root) / str(args.z)
    dst_z = Path(args.dst_root) / str(args.z)
    if not src_z.exists():
        raise SystemExit(f"missing src zoom dir: {src_z}")

    files = sorted(src_z.rglob(f"*.{args.src_ext}"))
    if not files:
        raise SystemExit(f"no *.{args.src_ext} under {src_z}")

    converted = 0
    skipped = 0
    failed = 0

    for src in files:
        rel = src.relative_to(src_z)
        if len(rel.parts) < 2:
            continue
        xdir = rel.parts[0]
        ystem = Path(rel.parts[1]).stem
        dst_dir = dst_z / xdir
        dst = dst_dir / f"{ystem}.bin"
        dst_dir.mkdir(parents=True, exist_ok=True)

        if dst.exists() and dst.stat().st_size > 1024:
            skipped += 1
            continue

        cmd = [str(PY), str(LVGLIMAGE), str(src), "--ofmt", "BIN", "--cf", "RGB565", "-o", str(dst_dir), "--name", dst.stem]
        print(" ".join(cmd))
        if args.dry_run:
            converted += 1
            continue

        try:
            subprocess.check_call(cmd)
            converted += 1
        except subprocess.CalledProcessError:
            failed += 1
            print(f"!! failed converting {src}")

    print(f"converted={converted} skipped={skipped} failed={failed}")
    if failed:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
