# Mesh Maps Studio

Download **OpenStreetMap** tiles and convert to **LVGL `.bin` (RGB565, no alpha)** in the folder layout MUI expects. macOS 14+ only. Output is SD-card ready:

```
map/<z>/<x>/<y>.bin
```

Copy the `map/` folder onto your device SD (or Portduino FS) and MUI will load the `.bin` tiles.

![Mesh Maps Studio screenshot](docs/mui-maps.png)

## Features
- macOS app (14+): point-and-click downloader/converter for MUI/MeshOS/Ripple tiles (PNG → LVGL `.bin`, RGB565)
- Provider: **OpenStreetMap only** (no custom providers in this build)
- Interactive MapKit preview: Control-click / long-press to drop a pin; overlays show tile grid for your zoom & radius
- Inputs: zoom min/max, radius, delay ms, keep-PNG toggle; estimates tile count + size before you run
- Progress UI with counts (downloaded / converted / failed), cancel button
- Output: SD-card-ready tree `map/<z>/<x>/<y>.bin` (or `maps/<style>/...` if styles are used)
- Sandbox-friendly: choose a writable output folder
- Swift-only conversion (no Python dependency bundled)

## Quick start (app)
1) macOS 14+ only. Download/build the app.
2) Choose output folder (e.g., `~/Downloads/mui-tiles-export`).
3) Pick zoom min/max and radius. Map style: OpenStreetMap.
4) Click **Start Download**. (Optional: keep PNGs.)
5) Copy the exported `map/` folder to your SD card root.

## Notes
- Respect OpenStreetMap’s tile usage policy; this build does **not** support custom providers.
- Be gentle with download rates (use delay if pulling many tiles).
- Output layout is SD-card ready for MUI.

### 1) Requirements

- Python 3.10+
- `LVGLImage.py` available from an LVGL checkout (we auto-detect it from a Meshtastic `standalone-ui` build if you have that locally).

This tool uses LVGL’s official converter script:
- `lvgl/scripts/LVGLImage.py`

### 2) Install deps (recommended: venv)

```bash
git clone https://github.com/ItsLimitlezz/mui-tiles.git
cd mui-tiles

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

### 3) Run (download + convert)

#### Easiest: interactive wizard (recommended)

```bash
./mui_tiles.py wizard
```

It walks you through:
- Country (USA / Canada / Mexico)
- Region (menu)
- Zoom mode (Recommended / Fast / Detailed / Custom)
- Style (menu)

#### Direct mode: center+radius

Example: download a 9×9 grid around Sydney at zoom 13:

```bash
./mui_tiles.py run \
  --lat -33.8688 --lon 151.2093 \
  --z 13 --radius 4 \
  --style osm \
  --out ./export
```

You’ll get:

```text
./export/map/13/<x>/<y>.bin
```

### 4) Copy to SD

Copy the `map/` folder to your SD card root:

```bash
cp -r ./export/map /Volumes/MESHTASTIC_SD/
```

(Or in Portduino, point `S:/map` at that folder.)

---

## Styles

List built-in styles:

```bash
./mui_tiles.py list-styles
```

Built-ins:
- `osm` (OpenStreetMap)
- `carto-light`
- `carto-dark`

You can also pass a custom URL template:

```bash
./mui_tiles.py run ... \
  --template 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
```

---

## Verify a tile tree

Check that a zoom level has full coverage for an x/y range:

```bash
./mui_tiles.py verify \
  --root ./export/map \
  --z 13 --ext bin \
  --x 7532..7540 --y 4911..4919
```

---

## LVGLImage.py path (if auto-detect doesn’t work)

By default we try to find LVGLImage.py at:

```
../standalone-ui/.pio/libdeps/native-mui/lvgl/scripts/LVGLImage.py
```

Override with env vars:

```bash
export MUI_TILES_LVGLIMAGE=/path/to/LVGLImage.py
export MUI_TILES_STANDALONE_UI=/path/to/standalone-ui
export MUI_TILES_PYTHON=/path/to/python
```

---

## Notes

- Be nice to tile servers: don’t hammer them. Use `--delay-ms` if you’re doing larger pulls.
- This is intentionally simple and “SD-card-first”: folder tree output, no archives.

## License

TBD
