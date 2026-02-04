# MUI-Maps - macOS Tile Downloader

A native macOS application for downloading OpenStreetMap tiles and converting them to LVGL RGB565 binary format for use with MUI (Meshtastic User Interface).

## Overview

This Swift application replicates the functionality of the Python `mui-tiles` tools, providing a user-friendly macOS interface for:

- Downloading map tiles from various tile servers (OpenStreetMap, Carto Light/Dark)
- Converting PNG tiles to RGB565 .bin format suitable for LVGL/MUI
- Managing tile grids around a center point
- Progress tracking and error handling

## Architecture

### Core Components

1. **Tile.swift**
   - `Tile` struct: Represents a map tile with z/x/y coordinates
   - `deg2num()`: Converts lat/lon to tile coordinates
   - `tilesAround()`: Generates tiles in a radius around a center point
   - `tilesForBBox()`: Generates tiles within a bounding box
   - `TileStyle` enum: Predefined tile server URLs

2. **TileDownloader.swift**
   - Actor-based async downloader
   - Handles HTTP requests with retry logic
   - Validates PNG data before saving
   - Implements politeness delays between requests

3. **TileConverter.swift**
   - Converts PNG images to RGB565 binary format
   - Uses Core Graphics for image processing
   - Outputs LVGL-compatible .bin files
   - Pixel format: RRRRRGGGGGGBBBBB (5-6-5 bits)

4. **TileDownloadViewModel.swift**
   - Main view model with `@Published` properties
   - Coordinates download and conversion workflow
   - Tracks progress and statistics
   - Manages cancellation and error handling

5. **ContentView.swift**
   - SwiftUI interface with grouped sections
   - Real-time progress updates
   - File picker for output directory
   - Parameter validation and feedback

## Usage

### Basic Operation

1. **Set Location**: Enter latitude and longitude (e.g., Sydney: -33.8688, 151.2093)
2. **Configure Tiles**: 
   - Set zoom level (0-19)
   - Set radius (creates a (2r+1)×(2r+1) grid)
   - Choose map style
3. **Select Output**: Choose where to save tiles (defaults to Desktop/mui-tiles-export)
4. **Download**: Click "Start Download" to begin

### Output Structure

Tiles are saved in the following structure:
```
<output-directory>/
  map/
    <zoom>/
      <x>/
        <y>.bin
        <y>.png (if "Keep PNG files" is enabled)
```

### Settings

- **Keep PNG files**: Retain original PNG alongside .bin files
- **Delay (ms)**: Milliseconds to wait between downloads (default: 50ms for politeness)

## Technical Details

### RGB565 Conversion

The converter transforms PNG images to 16-bit RGB565 format:
- Red: 5 bits (0-31)
- Green: 6 bits (0-63)  
- Blue: 5 bits (0-31)

Each pixel is stored as 2 bytes in little-endian format.

### Tile Coordinate System

Uses Web Mercator projection (EPSG:3857):
- Zoom level 0: 1 tile covers entire world
- Each zoom level doubles the number of tiles in each dimension
- Formula: `n = 2^zoom` tiles per side

### Comparison to Python Version

| Feature | Python | Swift |
|---------|--------|-------|
| Download | ✓ requests | ✓ URLSession |
| Conversion | ✓ LVGLImage.py | ✓ Core Graphics |
| UI | ✓ CLI (typer/rich) | ✓ SwiftUI |
| Progress | ✓ Terminal | ✓ Real-time UI |
| Async | ✓ sync with delays | ✓ async/await |

## Requirements

- macOS 13.0 or later
- Xcode 15 or later
- Internet connection for tile downloads

## Building

1. Open `MUI-Maps.xcodeproj` in Xcode
2. Select your target device/Mac
3. Build and run (Cmd+R)

## Tile Server Etiquette

Please respect tile server usage policies:
- Use appropriate delays between requests (50-100ms minimum)
- Cache tiles locally (don't re-download)
- Consider self-hosting for heavy usage
- Review server terms of service

### Default Tile Servers

- **OpenStreetMap**: https://tile.openstreetmap.org
- **Carto Light**: Cartodb basemaps
- **Carto Dark**: Cartodb basemaps

## License

Similar to the Python mui-tiles tool - for Meshtastic MUI development.

## Credits

- Original Python implementation: mui-tiles
- Map data: © OpenStreetMap contributors
- Tile rendering: Various tile server providers
