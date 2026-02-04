# mui-tiles (WIP)

Goal: download map tiles and convert them to LVGL `.bin` (RGB565) for MUI.

Planned output layout:

```
map/<z>/<x>/<y>.bin
```

## Next steps
- Fork/port https://github.com/mattdrum/map-tile-downloader
- Replace/extend its conversion step to produce LVGL RGB565 `.bin`
- Add a CLI entrypoint for batch conversion
