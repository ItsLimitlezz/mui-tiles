# Adding Swift Files to Xcode Project

## Files Created

The following Swift files have been created in the `MUI-Maps/MUI-Maps/` directory:

1. `Tile.swift` - Tile model and coordinate utilities
2. `TileDownloader.swift` - Network download service
3. `TileConverter.swift` - PNG to RGB565 converter
4. `TileDownloadViewModel.swift` - Main view model
5. `ContentView.swift` - Updated SwiftUI interface (modified)

## Automatic Detection

Your Xcode project uses **File System Synchronized Groups** (objectVersion = 77), which means:

✅ **New files are automatically detected** when you open the project

The project file contains:
```
B65CE6FE2F33A4D600730866 /* MUI-Maps */ = {
    isa = PBXFileSystemSynchronizedRootGroup;
    path = "MUI-Maps";
    sourceTree = "<group>";
};
```

This means all `.swift` files in the `MUI-Maps/MUI-Maps/` directory will be automatically included.

## Verification Steps

1. **Open the project**:
   ```bash
   cd /Users/juanpena/Documents/Git/mui-tiles/MUI-Maps
   open MUI-Maps.xcodeproj
   ```

2. **Check the file navigator** (⌘1):
   - You should see all new Swift files under "MUI-Maps" folder
   - They should have target membership checkmarks

3. **Verify target membership**:
   - Select each new file in the navigator
   - Open the File Inspector (⌘⌥1)
   - Ensure "MUI-Maps" is checked under "Target Membership"

4. **Build the project** (⌘B):
   - Should compile without errors
   - All 5 Swift files should be included

## Manual Addition (If Needed)

If files don't appear automatically:

1. **Right-click on "MUI-Maps" folder** in Xcode
2. Select **"Add Files to 'MUI-Maps'..."**
3. Navigate to the `MUI-Maps/` directory
4. Select all new `.swift` files
5. Ensure these options are checked:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: MUI-Maps
6. Click "Add"

## Expected Project Structure

```
MUI-Maps/
├── MUI-Maps/
│   ├── MUI_MapsApp.swift ✅ (existing)
│   ├── ContentView.swift ✅ (modified)
│   ├── Tile.swift ✅ (new)
│   ├── TileDownloader.swift ✅ (new)
│   ├── TileConverter.swift ✅ (new)
│   ├── TileDownloadViewModel.swift ✅ (new)
│   └── Assets.xcassets/
├── MUI-Maps.xcodeproj/
├── MUI-MapsTests/
├── MUI-MapsUITests/
├── README.md ✅ (new)
└── QUICKSTART.md ✅ (new)
```

## Build Settings

No special build settings needed. The app uses:
- SwiftUI framework (built-in)
- Foundation framework (built-in)
- AppKit (for NSImage, NSOpenPanel)

Minimum deployment target: macOS 13.0

## Common Issues

### Issue: "Cannot find type 'Tile' in scope"

**Solution**: 
- Clean build folder (Shift+⌘K)
- Rebuild project (⌘B)
- Restart Xcode if needed

### Issue: Files show in red in navigator

**Solution**:
- Files are not found at expected path
- Check that files are in `MUI-Maps/MUI-Maps/` directory
- Use "Add Files to 'MUI-Maps'..." to re-add them

### Issue: Duplicate symbol errors

**Solution**:
- Check that files aren't added twice
- Select file → File Inspector → Target Membership
- Ensure each file is only checked once

## Next Steps

1. Open the project in Xcode
2. Build and run (⌘R)
3. Test the tile download functionality
4. Refer to QUICKSTART.md for usage instructions
