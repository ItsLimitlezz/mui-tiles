# Quick Start Guide - MUI-Maps

## Setup

1. Open the project in Xcode:
   ```bash
   cd /Users/juanpena/Documents/Git/mui-tiles/MUI-Maps
   open MUI-Maps.xcodeproj
   ```

2. The project includes these Swift files:
   - `Tile.swift` - Tile coordinate system and conversions
   - `TileDownloader.swift` - Async tile downloading
   - `TileConverter.swift` - PNG to RGB565 conversion
   - `TileDownloadViewModel.swift` - Main business logic
   - `ContentView.swift` - SwiftUI interface
   - `MUI_MapsApp.swift` - App entry point

3. Build and run (⌘R)

## Using the App

### Example: Download Sydney Area

1. **Location**:
   - Latitude: `-33.8688`
   - Longitude: `151.2093`

2. **Tile Settings**:
   - Zoom: `13`
   - Radius: `4` (creates 9×9 grid = 81 tiles)
   - Style: `OpenStreetMap`

3. **Output**:
   - Click "Choose..." to select output directory
   - Default: `~/Desktop/mui-tiles-export`
   - Enable "Keep PNG files" if you want to inspect originals

4. **Download**:
   - Click "Start Download"
   - Watch progress in real-time
   - Tiles will be saved to `<output>/map/<z>/<x>/<y>.bin`

### Common Zoom Levels

- **Zoom 6-8**: Country/state level (few tiles)
- **Zoom 10-12**: City level (moderate tiles)
- **Zoom 13-15**: Neighborhood level (many tiles)
- **Zoom 16+**: Street level (very many tiles)

### Tile Estimates

The app shows estimated tile count and size:
- Radius 2 @ z13 = 25 tiles (~3.2 MB)
- Radius 4 @ z13 = 81 tiles (~10.4 MB)
- Radius 8 @ z13 = 289 tiles (~37.1 MB)

Each RGB565 .bin tile is approximately 131 KB (256×256 pixels × 2 bytes).

## Differences from Python Version

### Features Implemented
- ✅ Tile coordinate conversion (`deg2num`, `tilesAround`)
- ✅ Multiple tile styles (OSM, Carto Light/Dark)
- ✅ PNG download with retry logic
- ✅ RGB565 .bin conversion (native Swift, no Python dependency)
- ✅ Progress tracking
- ✅ Politeness delays
- ✅ Output directory structure (`map/z/x/y.bin`)

### Features Not Yet Implemented
- ❌ Wizard mode with country/region selection
- ❌ Bounding box mode
- ❌ Geocoding (Nominatim integration)
- ❌ Multi-zoom level downloads
- ❌ Verification tool

### Advantages of Swift Version
- Native macOS UI with real-time feedback
- No external dependencies (no Python, pip, LVGL scripts)
- Faster RGB565 conversion using Core Graphics
- Modern async/await concurrency
- Better error handling and cancellation

## Troubleshooting

### Xcode Build Issues

If you see "Cannot find type 'Tile'" or similar:
1. Make sure all .swift files are in the project
2. Check that files are in the correct target membership
3. Clean build folder (Shift+⌘K) and rebuild

### Runtime Issues

**Downloads failing**: 
- Check internet connection
- Verify tile server is accessible
- Try increasing delay (100ms+)

**Conversion failing**:
- Check that PNG files are valid
- Verify write permissions to output directory
- Check available disk space

**App not responding**:
- UI updates are on main thread
- Heavy downloads might slow UI slightly
- Use "Stop Download" button to cancel

## Next Steps

### Future Enhancements
1. Add geocoding support (find locations by name)
2. Implement multi-zoom downloads
3. Add tile verification tool
4. Support custom tile server URLs
5. Add tile preview/inspection
6. Export progress logs
7. Batch processing support

### Testing

Test with small areas first:
```
Latitude: -33.8688
Longitude: 151.2093
Zoom: 10
Radius: 2
```

This downloads only 25 tiles and completes quickly.

## Output Format

The `.bin` files are raw RGB565 data:
- Width: 256 pixels
- Height: 256 pixels
- Format: 16-bit RGB565 (little-endian)
- Size: 131,072 bytes (256 × 256 × 2)
- Structure: Row-major order, top-to-bottom, left-to-right

Compatible with LVGL `lv_img_dsc_t` when properly wrapped with header.
