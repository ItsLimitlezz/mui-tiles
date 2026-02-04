#!/usr/bin/env python3
"""Quick sanity checker for an MUI tile tree.

Checks for:
- expected directory layout map/<z>/<x>/<y>.<ext>
- missing files in a given x/y range (optional)
- basic file size sanity

Usage:
  ./verify_tree.py --root /path/to/map --z 13 --ext bin --x 7532..7540 --y 4911..4919

If you omit ranges, it will just count tiles and report min/max sizes.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_range(s: str):
    if ".." not in s:
        v = int(s)
        return v, v
    a, b = s.split("..", 1)
    return int(a), int(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="Path to map root (contains z/x/y.ext)")
    ap.add_argument("--z", type=int, required=True)
    ap.add_argument("--ext", required=True, help="png|jpg|bin")
    ap.add_argument("--x", help="x range like 7532..7540")
    ap.add_argument("--y", help="y range like 4911..4919")
    args = ap.parse_args()

    root = Path(args.root)
    zdir = root / str(args.z)

    if not zdir.exists():
        raise SystemExit(f"Missing zoom dir: {zdir}")

    sizes = []
    missing = 0
    checked = 0

    if args.x and args.y:
        xmin, xmax = parse_range(args.x)
        ymin, ymax = parse_range(args.y)
        for x in range(xmin, xmax + 1):
            for y in range(ymin, ymax + 1):
                p = zdir / str(x) / f"{y}.{args.ext}"
                checked += 1
                if not p.exists():
                    missing += 1
                    continue
                sizes.append(p.stat().st_size)
    else:
        for p in zdir.rglob(f"*.{args.ext}"):
            if p.is_file():
                sizes.append(p.stat().st_size)

    if sizes:
        print(f"found={len(sizes)} files ext=.{args.ext} z={args.z}")
        print(f"min_size={min(sizes)} max_size={max(sizes)}")
    else:
        print(f"found=0 files ext=.{args.ext} z={args.z}")

    if args.x and args.y:
        print(f"checked={checked} missing={missing}")
        if missing:
            raise SystemExit(2)


if __name__ == "__main__":
    main()
