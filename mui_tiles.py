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
from rich.prompt import IntPrompt, Prompt

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

HERE = Path(__file__).resolve().parent

# You can override these with env vars:
#   MUI_TILES_LVGLIMAGE=/path/to/LVGLImage.py
#   MUI_TILES_PYTHON=/path/to/python
#   MUI_TILES_STANDALONE_UI=/path/to/standalone-ui (used for auto-discovery)
DEFAULT_STANDALONE_UI = Path(os.environ.get("MUI_TILES_STANDALONE_UI", str(HERE.parent / "standalone-ui")))

LVGLIMAGE = Path(os.environ.get(
    "MUI_TILES_LVGLIMAGE",
    str(DEFAULT_STANDALONE_UI / ".pio/libdeps/native-mui/lvgl/scripts/LVGLImage.py"),
))

# Prefer local venv python, but fall back to current interpreter.
PY = Path(os.environ.get("MUI_TILES_PYTHON", str(HERE / ".venv/bin/python")))


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


def tiles_for_bbox(z: int, west: float, south: float, east: float, north: float) -> list[Tile]:
    """Return all tiles at zoom z that intersect the given lat/lon bounding box."""
    # Note: deg2num expects lat,lon. y increases southward.
    x1, y1 = deg2num(north, west, z)  # top-left
    x2, y2 = deg2num(south, east, z)  # bottom-right

    xmin, xmax = sorted((x1, x2))
    ymin, ymax = sorted((y1, y2))

    out: list[Tile] = []
    for x in range(xmin, xmax + 1):
        for y in range(ymin, ymax + 1):
            out.append(Tile(z=z, x=x, y=y))
    return out


def ensure_ok_lvglimage():
    if not LVGLIMAGE.exists():
        raise typer.BadParameter(
            "Missing LVGLImage.py. Either build standalone-ui (native-mui) so it exists at:\n"
            f"  {LVGLIMAGE}\n"
            "or set MUI_TILES_LVGLIMAGE=/path/to/LVGLImage.py"
        )

    # If the venv python path doesn't exist, we'll fall back to the current interpreter.
    # This keeps the tool usable without forcing a venv, but venv is still recommended.
    if not PY.exists():
        import sys

        return Path(sys.executable)

    return PY


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

    py = ensure_ok_lvglimage()

    cmd = [
        str(py),
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


def geocode_places(query: str, country_code: str, limit: int = 6) -> list[dict]:
    """Geocode using Nominatim (OpenStreetMap).

    Returns raw JSON dicts with keys like: display_name, lat, lon, boundingbox.
    boundingbox format: [south, north, west, east] as strings.
    """
    url = "https://nominatim.openstreetmap.org/search"
    params = {
        "q": query,
        "format": "jsonv2",
        "limit": str(limit),
        "addressdetails": "1",
        "countrycodes": country_code,
    }
    r = requests.get(url, params=params, headers={"User-Agent": USER_AGENT}, timeout=20)
    r.raise_for_status()
    data = r.json()
    if not isinstance(data, list):
        return []
    return data


def bbox_from_nominatim(place: dict) -> tuple[float, float, float, float]:
    bb = place.get("boundingbox")
    if not bb or len(bb) != 4:
        raise ValueError("No boundingbox returned for place")
    south, north, west, east = (float(bb[0]), float(bb[1]), float(bb[2]), float(bb[3]))
    return west, south, east, north


def download_convert_tiles(
    tiles: list[Tile],
    url_tmpl: str,
    out: Path,
    keep_png: bool,
    delay_ms: int,
) -> tuple[int, int, int]:
    """Download (png) then convert to .bin into out/map/<z>/<x>/<y>.bin."""
    map_root = out / "map"

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

    return ok_dl, ok_conv, miss


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
def wizard(
    out: Path = typer.Option(Path("./export"), help="Output folder (will contain map/...)") ,
    keep_png: bool = typer.Option(False, help="Keep downloaded png files next to .bin"),
    delay_ms: int = typer.Option(80, help="Delay between downloads (politeness)"),
):
    """Interactive menu flow (country -> place -> zoom range -> style)"""
    console.print(BANNER)
    ensure_ok_lvglimage()

    countries = [
        ("USA", "us"),
        ("Canada", "ca"),
        ("Mexico", "mx"),
    ]

    console.print("[bold]Select a country[/bold]")
    for i, (name, _) in enumerate(countries, start=1):
        console.print(f"  {i}) {name}")
    idx = IntPrompt.ask("Country", choices=[str(i) for i in range(1, len(countries) + 1)], default="1")
    country_name, country_code = countries[int(idx) - 1]

    console.print(
        f"\n[bold]{country_name}[/bold] selected. Now choose a place/region (examples: 'Ontario', 'Florida', 'Toronto', 'Miami')."
    )
    query = Prompt.ask("Place/region")

    console.print("\nSearching...")
    try:
        results = geocode_places(query=query, country_code=country_code, limit=6)
    except Exception as e:
        raise typer.BadParameter(f"Geocoding failed: {e}")

    if not results:
        raise typer.BadParameter("No matches found. Try a more specific query (e.g., 'Florida USA', 'Ontario Canada').")

    console.print("\n[bold]Pick a match[/bold]")
    for i, r in enumerate(results, start=1):
        name = r.get("display_name", "(unknown)")
        console.print(f"  {i}) {name}")

    pick = IntPrompt.ask("Match", choices=[str(i) for i in range(1, len(results) + 1)], default="1")
    place = results[int(pick) - 1]
    west, south, east, north = bbox_from_nominatim(place)

    console.print(
        f"\nUsing bounding box:\n  west={west:.5f} south={south:.5f}\n  east={east:.5f} north={north:.5f}"
    )

    min_z = IntPrompt.ask("Zoom OUT (min zoom)", default=10)
    max_z = IntPrompt.ask("Zoom IN (max zoom)", default=13)
    if min_z < 0 or max_z > 19 or min_z > max_z:
        raise typer.BadParameter("Zoom range must be within 0..19 and min<=max")

    # Style selection
    console.print("\n[bold]Select a map style[/bold]")
    style_keys = list(STYLES.keys())
    for i, k in enumerate(style_keys, start=1):
        console.print(f"  {i}) {k} -> {STYLES[k]}")
    sidx = IntPrompt.ask("Style", choices=[str(i) for i in range(1, len(style_keys) + 1)], default="1")
    style = style_keys[int(sidx) - 1]
    url_tmpl = STYLES[style]

    # Estimate tiles
    total_tiles = 0
    tiles_by_zoom: dict[int, list[Tile]] = {}
    for z in range(min_z, max_z + 1):
        tz = tiles_for_bbox(z=z, west=west, south=south, east=east, north=north)
        tiles_by_zoom[z] = tz
        total_tiles += len(tz)

    console.print(f"\nThis will download/convert about [bold]{total_tiles}[/bold] tiles.")
    go = Prompt.ask("Continue?", choices=["y", "n"], default="y")
    if go.lower() != "y":
        raise typer.Exit(0)

    # Run
    grand_dl = grand_conv = grand_fail = 0
    for z in range(min_z, max_z + 1):
        console.print(f"\n[bold]Zoom {z}[/bold] tiles={len(tiles_by_zoom[z])}")
        dl, conv, fail = download_convert_tiles(
            tiles=tiles_by_zoom[z],
            url_tmpl=url_tmpl,
            out=out,
            keep_png=keep_png,
            delay_ms=delay_ms,
        )
        grand_dl += dl
        grand_conv += conv
        grand_fail += fail

    console.print(
        f"\n[bold]done[/bold] downloaded={grand_dl} converted={grand_conv} failed={grand_fail}"
    )
    console.print(f"SD-ready folder: {out / 'map'}")


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
