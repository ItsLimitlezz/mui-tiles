# mui-tiles

Download slippy-map tiles and convert them to **LVGL `.bin` (RGB565, no alpha)** in the exact folder layout MUI expects. Includes a **macOS app (MUI-Maps)** and Python CLIs for bulk download/convert.

**Output layout (SD-card ready):**

```
map/<z>/<x>/<y>.bin
```

Copy the `map/` folder onto your device SD (or Portduino FS) and MUI will load the `.bin` tiles.

## macOS app (MUI-Maps)
- Point-and-click downloader/converter for MUI tiles (PNG → LVGL `.bin`, RGB565)
- BYO tile provider/template (OSM, Carto, etc.) with attribution; supports style folders and custom URL templates
- Interactive MapKit preview: Control-click / long-press to drop a pin; overlays show the tile grid for your zoom & radius (and max-zoom grid)
- Inputs: lat/lon, zoom, radius, style picker, custom template, delay ms, keep-PNG toggle; estimates tile count + size before you run
- Progress UI with counts (downloaded / converted / failed) and cancel button; outputs SD-card-ready tree: `map/<z>/<x>/<y>.bin` (or `maps/<style>/...`)
- Choose a writable output folder (sandbox-friendly)

### Screenshot
_Add your screenshot here (e.g., `docs/mui-maps.png`):_

```markdown
![MUI-Maps screenshot](docs/mui-maps.png)
```

---

## Quick start

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
