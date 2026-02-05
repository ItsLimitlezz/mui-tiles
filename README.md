# Mesh Maps Studio

macOS 14+ app to download **OpenStreetMap** tiles and convert them to **LVGL `.bin` (RGB565, no alpha)** in the folder layout MUI expects. Output is SD-card ready:

```
maps/<style>/<z>/<x>/<y>.bin
```

Copy the `maps/` folder onto your SD card root (or Portduino FS). MUI supports `/maps/...`; our firmware also falls back to `/map/...` if needed.

![Mesh Maps Studio screenshot](docs/mui-maps.png)

## Features
- macOS app (14+), Swift-only converter (no Python dependency)
- Provider: **OpenStreetMap only** (no custom providers in this build)
- Output: `maps/<style>/<z>/<x>/<y>.bin` (RGB565 LVGL); optional keep-PNG toggle
- Map preview: Control-click / long-press to drop a pin; grid overlays for zoom/radius
- Inputs: zoom min/max, radius, delay ms, keep-PNG toggle; estimates tile count + size
- Progress UI with counts (downloaded/converted/failed) and cancel
- Sandbox-friendly output folder picker

## Quick start (app)
1) macOS 14+ only. Build/run the app.
2) Choose output folder (e.g., `~/Downloads/mui-tiles-export`).
3) Pick zoom min/max and radius. Map style: OpenStreetMap.
4) Click **Start Download**. (Optional: keep PNGs.)
5) Copy the exported `maps/` folder to your SD card root (`/maps/<style>/z/x/y.bin`).

## Notes
- Respect OpenStreetMap’s tile usage policy; this build does **not** support custom providers.
- Be gentle with download rates (use delay if pulling many tiles).
- Firmware/Portduino will also accept `/map/...` thanks to a fallback, but the recommended layout is `/maps/<style>/...`.
