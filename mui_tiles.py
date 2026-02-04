#!/usr/bin/env python3
"""mui-tiles: download slippy-map tiles and convert to LVGL RGB565 .bin for MUI.

Outputs SD-ready folder tree:
  map/<z>/<x>/<y>.bin

Uses LVGL's official converter script LVGLImage.py from the local LVGL libdeps.

Examples:
  # Download + convert a 9x9 tile grid around Sydney at z=13
  ./mui_tiles.py run --lat -33.8688 --lon 151.2093 --z 13 --radius 4 --style osm --out ./export

  # Just verify an output tree
  ./mui_tiles.py verify --root ./export/map --z 13 --ext bin --x 7532..7540 --y 4911..4919
"""

from __future__ import annotations

import math
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional, Tuple

import requests
import typer
from rich.console import Console
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)

app = typer.Typer(add_completion=False, no_args_is_help=True)
console = Console()

BANNER = r"""
 __  __ _   _ ___     _____ ___ _     _____ ____
|  \/  | | | |_ _|   |_   _|_ _| |   | ____/ ___|
| |\/| | | | || |_____ | |  | || |   |  _| \___ \
| |  | | |_| || |_____| | |  | || |___| |___ ___) |
|_|  |_|\___/|___|     |_| |___|_____|_____|____/

MUI tile downloader + LVGL RGB565 .bin converter (no alpha)
"""

# A small set of sane defaults; allow custom template too.
STYLES: Dict[str, str] = {
    "osm": "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    # Carto basemaps (no key, but rate limits apply)
    "carto-light": "https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png",
    "carto-dark": "https://cartodb-basemaps-a.global.ssl.fastly.net/dark_all/{z}/{x}/{y}.png",
}

USER_AGENT = "mui-tiles/0.1 (Meshtastic MUI bin tile tool; contact: local)"

LVGLIMAGE = Path(
    "/home/miles/.openclaw/workspace/standalone-ui/.pio/libdeps/native-mui/lvgl/scripts/LVGLImage.py"
)
PY = Path("/home/miles/.openclaw/workspace/mui-tiles/.venv/bin/python")


@dataclass
class Tile:
    z: int
    x: int
    y: int


def deg2num(lat_deg: float, lon_deg: float, zoom: int) -> Tuple[int, int]:
    lat_rad = math.radians(lat_deg)
    n = 2.0 ** zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return xtile, ytile


def tiles_around(lat: float, lon: float, z: int, radius: int) -> list[Tile]:
    cx, cy = deg2num(lat, lon, z)
    out: list[Tile] = []
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            out.append(Tile(z=z, x=cx + dx, y=cy + dy))
    return out


def ensure_ok_lvglimage():
    if not LVGLIMAGE.exists():
        raise typer.BadParameter(
            f"Missing LVGLImage.py at {LVGLIMAGE}. Build standalone-ui native-mui first."
        )
    if not PY.exists():
        raise typer.BadParameter(
            f"Missing venv python at {PY}. Create venv under mui-tiles/.venv first."
        )


def download_tile(session: requests.Session, url_tmpl: str, t: Tile, out_png: Path, retries: int = 3) -> bool:
    out_png.parent.mkdir(parents=True, exist_ok=True)
    url = url_tmpl.format(z=t.z, x=t.x, y=t.y)

    # Skip if already present and non-trivial.
    if out_png.exists() and out_png.stat().st_size > 256:
        return True

    for attempt in range(1, retries + 1):
        try:
            r = session.get(url, timeout=20)
            if r.status_code == 200 and r.content:
                out_png.write_bytes(r.content)
                # quick sanity: some servers return HTML error pages.
                if out_png.stat().st_size < 256:
                    out_png.unlink(missing_ok=True)
                    raise RuntimeError("downloaded tile too small (likely error response)")
                return True
            elif r.status_code in (429, 500, 502, 503, 504):
                time.sleep(0.7 * attempt)
            else:
                return False
        except Exception:
            if attempt == retries:
                return False
            time.sleep(0.7 * attempt)

    return False


def convert_png_to_bin(src_png: Path, dst_bin: Path) -> bool:
    # LVGLImage's -o is a directory; file name comes from --name
    dst_bin.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(PY),
        str(LVGLIMAGE),
        str(src_png),
        "--ofmt",
        "BIN",
        "--cf",
        "RGB565",
        "-o",
        str(dst_bin.parent),
        "--name",
        dst_bin.stem,
    ]
    try:
        import subprocess

        subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return dst_bin.exists() and dst_bin.stat().st_size > 1024
    except Exception:
        return False


@app.command()
def list_styles():
    """List built-in tile styles."""
    console.print(BANNER)
    for k, v in STYLES.items():
        console.print(f"[bold]{k}[/bold] -> {v}")
    console.print("\nUse --template to supply a custom URL template if needed.")


@app.command()
def run(
    lat: float = typer.Option(..., help="Center latitude"),
    lon: float = typer.Option(..., help="Center longitude"),
    z: int = typer.Option(..., min=0, max=19, help="Zoom level"),
    radius: int = typer.Option(4, min=0, max=50, help="Tile radius (grid = (2r+1)^2)"),
    style: str = typer.Option("osm", help="Style key (see list-styles)"),
    template: Optional[str] = typer.Option(None, help="Custom URL template like https://.../{z}/{x}/{y}.png"),
    out: Path = typer.Option(Path("./export"), help="Output folder (will contain map/...)"),
    keep_png: bool = typer.Option(False, help="Keep downloaded png files next to .bin"),
    delay_ms: int = typer.Option(50, help="Delay between downloads (politeness)")
):
    """Download tiles for an area and convert to MUI-ready RGB565 .bin."""
    console.print(BANNER)

    ensure_ok_lvglimage()

    url_tmpl = template or STYLES.get(style)
    if not url_tmpl:
        raise typer.BadParameter(f"Unknown style '{style}'. Use list-styles or pass --template.")

    tiles = tiles_around(lat, lon, z, radius)
    map_root = out / "map"

    console.print(f"center=({lat},{lon}) z={z} radius={radius} tiles={len(tiles)}")
    console.print(f"style={style} url={url_tmpl}")
    console.print(f"output={map_root}")

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})

    ok_dl = 0
    ok_conv = 0
    miss = 0

    with Progress(
        SpinnerColumn(),
        TextColumn("{task.description}"),
        BarColumn(),
        TextColumn("{task.completed}/{task.total}"),
        TimeElapsedColumn(),
        TimeRemainingColumn(),
        console=console,
    ) as progress:
        task = progress.add_task("download+convert", total=len(tiles))
        for t in tiles:
            png_path = map_root / str(t.z) / str(t.x) / f"{t.y}.png"
            bin_path = map_root / str(t.z) / str(t.x) / f"{t.y}.bin"

            if download_tile(session, url_tmpl, t, png_path):
                ok_dl += 1
                if convert_png_to_bin(png_path, bin_path):
                    ok_conv += 1
                    if not keep_png:
                        png_path.unlink(missing_ok=True)
                else:
                    miss += 1
            else:
                miss += 1

            progress.advance(task)
            time.sleep(max(0.0, delay_ms / 1000.0))

    console.print(
        f"\n[bold]done[/bold] downloaded={ok_dl} converted={ok_conv} failed={miss}"
    )
    console.print(f"SD-ready folder: {map_root}")


@app.command()
def verify(
    root: Path = typer.Option(..., help="Path to map root (contains z/x/y.ext)"),
    z: int = typer.Option(..., help="Zoom"),
    ext: str = typer.Option("bin", help="Extension (bin/png/jpg)"),
    x: Optional[str] = typer.Option(None, help="x range like 7532..7540"),
    y: Optional[str] = typer.Option(None, help="y range like 4911..4919"),
):
    """Verify tile tree coverage and basic file sanity."""
    from verify_tree import parse_range  # local file

    zdir = root / str(z)
    if not zdir.exists():
        raise typer.BadParameter(f"Missing zoom dir: {zdir}")

    sizes = []
    missing = 0
    checked = 0

    if x and y:
        xmin, xmax = parse_range(x)
        ymin, ymax = parse_range(y)
        for xi in range(xmin, xmax + 1):
            for yi in range(ymin, ymax + 1):
                p = zdir / str(xi) / f"{yi}.{ext}"
                checked += 1
                if not p.exists():
                    missing += 1
                    continue
                sizes.append(p.stat().st_size)
    else:
        for p in zdir.rglob(f"*.{ext}"):
            if p.is_file():
                sizes.append(p.stat().st_size)

    console.print(f"found={len(sizes)} files ext=.{ext} z={z}")
    if sizes:
        console.print(f"min_size={min(sizes)} max_size={max(sizes)}")

    if x and y:
        console.print(f"checked={checked} missing={missing}")
        if missing:
            raise typer.Exit(2)


if __name__ == "__main__":
    app()
