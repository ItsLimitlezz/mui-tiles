//
//  TileDownloadViewModel.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Main view model coordinating tile download and conversion
@MainActor
class TileDownloadViewModel: ObservableObject {
    // Input parameters
    @Published var latitude: String = "25.8177"
    @Published var longitude: String = "-80.1227"
    @Published var zoom: Int = 13
    @Published var maxZoom: Int = 15
    @Published var radius: Int = 4
    @Published var selectedStyle: TileStyle = .osm
    @Published var keepPNG: Bool = false
    @Published var delayMs: Int = 50
    @Published var includeWorld: Bool = false
    
    // Output settings
    @Published var outputDirectory: URL?
    
    // Progress tracking
    @Published var isDownloading: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentTile: String = ""
    @Published var downloadedCount: Int = 0
    @Published var convertedCount: Int = 0
    @Published var failedCount: Int = 0
    @Published var totalTiles: Int = 0
    
    // Status
    @Published var statusMessage: String = ""
    @Published var errorMessage: String = ""
    
    private let downloader = TileDownloader()
    private let converter = TileConverter()
    private var downloadTask: Task<Void, Never>?
    
    init() {
        // Set default output directory to the user's Downloads folder
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            outputDirectory = downloads
        }
        self.maxZoom = max(self.maxZoom, self.zoom)
    }
    
    /// Calculate estimated tiles and size across a zoom range
    /// - Parameters:
    ///   - minZoom: minimum zoom level (defaults to current `zoom`)
    ///   - maxZoom: maximum zoom level (if nil, uses `zoom` only)
    ///   - lat: center latitude (defaults to current `latitude`)
    ///   - lon: center longitude (defaults to current `longitude`)
    ///   - radius: radius at min zoom (defaults to current `radius`)
    func estimateTiles(minZoom: Int? = nil,
                       maxZoom: Int? = nil,
                       lat: Double? = nil,
                       lon: Double? = nil,
                       radius: Int? = nil) -> (count: Int, sizeMB: Double) {
        // Resolve inputs or fall back to current state
        let minZ = minZoom ?? zoom
        let maxZ = maxZoom ?? minZ
        guard let cLat = lat ?? Double(latitude),
              let cLon = lon ?? Double(longitude) else {
            return (0, 0)
        }
        let r = radius ?? self.radius

        // If min==max, keep the previous simple path for performance
        if minZ == maxZ {
            let tiles = Tile.tilesAround(lat: cLat, lon: cLon, zoom: minZ, radius: r)
            let count = tiles.count
            let sizeMB = Double(count * 131_084) / (1024.0 * 1024.0)
            return (count, sizeMB)
        }

        // Compute a geographic bounding box based on the min zoom radius around the center,
        // then count tiles that intersect this same bbox at each zoom in [minZ, maxZ].
        // This mirrors the CLI wizard's approach and avoids undercounting.
        func bboxFromCenterRadius(lat: Double, lon: Double, zoom: Int, radius: Int) -> (west: Double, south: Double, east: Double, north: Double) {
            // Get center tile at min zoom
            let (cx, cy) = Tile.deg2num(lat: lat, lon: lon, zoom: zoom)
            // Compute inclusive tile bounds at min zoom
            let xmin = cx - radius
            let xmax = cx + radius
            let ymin = cy - radius
            let ymax = cy + radius

            // Convert tile edges to geographic coordinates at min zoom
            func lonForTileX(_ x: Int, z: Int) -> Double {
                let n = pow(2.0, Double(z))
                return (Double(x) / n) * 360.0 - 180.0
            }
            func latForTileY(_ y: Int, z: Int) -> Double {
                let n = pow(2.0, Double(z))
                let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
                return latRad * 180.0 / .pi
            }

            let west = lonForTileX(xmin, z: zoom)
            let east = lonForTileX(xmax + 1, z: zoom)
            let north = latForTileY(ymin, z: zoom)
            let south = latForTileY(ymax + 1, z: zoom)
            return (west, south, east, north)
        }

        let bbox = bboxFromCenterRadius(lat: cLat, lon: cLon, zoom: minZ, radius: r)

        var total = 0
        for z in minZ...maxZ {
            let tilesAtZ = Tile.tilesForBBox(zoom: z, west: bbox.west, south: bbox.south, east: bbox.east, north: bbox.north)
            total += tilesAtZ.count
        }
        var adjustedTotal = total
        if includeWorld {
            // Add the single world tile at z=0
            adjustedTotal += 1
        }
        let sizeMB = Double(adjustedTotal * 131_084) / (1024.0 * 1024.0)
        return (adjustedTotal, sizeMB)
    }

    /// Convenience wrapper for UI that uses current state and expects ContentView to pass maxZoom via state.
    func estimateTiles() -> (count: Int, sizeMB: Double) {
        // Default single-zoom estimate; callers that need a range should call the overload.
        return estimateTiles(minZoom: zoom, maxZoom: zoom, lat: Double(latitude), lon: Double(longitude), radius: radius)
    }
    
    /// Start the download and conversion process
    func startDownload() {
        guard let lat = Double(latitude),
              let lon = Double(longitude),
              let outputDir = outputDirectory else {
            errorMessage = "Invalid input parameters"
            return
        }

        // Cancel any existing task
        downloadTask?.cancel()

        // Reset counters
        downloadedCount = 0
        convertedCount = 0
        failedCount = 0
        progress = 0.0
        errorMessage = ""

        // Build tiles across zoom range [zoom..maxZoom] using a bbox derived from min zoom + radius
        let minZ = zoom
        let maxZ = maxZoom
        func bboxFromCenterRadius(lat: Double, lon: Double, zoom: Int, radius: Int) -> (west: Double, south: Double, east: Double, north: Double) {
            // Center tile at min zoom
            let (cx, cy) = Tile.deg2num(lat: lat, lon: lon, zoom: zoom)
            let xmin = cx - radius
            let xmax = cx + radius
            let ymin = cy - radius
            let ymax = cy + radius
            func lonForTileX(_ x: Int, z: Int) -> Double {
                let n = pow(2.0, Double(z))
                return (Double(x) / n) * 360.0 - 180.0
            }
            func latForTileY(_ y: Int, z: Int) -> Double {
                let n = pow(2.0, Double(z))
                let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
                return latRad * 180.0 / .pi
            }
            let west = lonForTileX(xmin, z: zoom)
            let east = lonForTileX(xmax + 1, z: zoom)
            let north = latForTileY(ymin, z: zoom)
            let south = latForTileY(ymax + 1, z: zoom)
            return (west, south, east, north)
        }

        let bbox = bboxFromCenterRadius(lat: lat, lon: lon, zoom: minZ, radius: radius)
        var allTiles: [Tile] = []
        for z in minZ...maxZ {
            let tz = Tile.tilesForBBox(zoom: z, west: bbox.west, south: bbox.south, east: bbox.east, north: bbox.north)
            allTiles.append(contentsOf: tz)
        }

        // Optionally include the single world tile (z=0, x=0, y=0) separately from the min-max range
        if includeWorld {
            let worldTile = Tile(z: 0, x: 0, y: 0)
            // Avoid duplicates if minZoom is 0 and already included
            if !allTiles.contains(where: { $0.z == 0 && $0.x == 0 && $0.y == 0 }) {
                allTiles.insert(worldTile, at: 0)
            }
        }

        totalTiles = allTiles.count
        statusMessage = "Starting download of \(totalTiles) tiles..."
        isDownloading = true

        let tiles = allTiles
        downloadTask = Task {
            await processTiles(tiles, outputDir: outputDir)
        }
    }
    
    /// Stop the download process
    func stopDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusMessage = "Download cancelled"
    }
    
    /// Process all tiles: download PNG and convert to bin
    private func processTiles(_ tiles: [Tile], outputDir: URL) async {
        let mapRoot = outputDir
            .appendingPathComponent("maps")
            .appendingPathComponent(selectedStyle.folderName)
        let urlTemplate = selectedStyle.urlTemplate
        
        for (index, tile) in tiles.enumerated() {
            // Check for cancellation
            if Task.isCancelled {
                await MainActor.run {
                    statusMessage = "Download cancelled"
                    isDownloading = false
                }
                return
            }
            
            await MainActor.run {
                currentTile = "\(tile.z)/\(tile.x)/\(tile.y)"
            }
            
            let pngPath = mapRoot
                .appendingPathComponent("\(tile.z)")
                .appendingPathComponent("\(tile.x)")
                .appendingPathComponent("\(tile.y).png")
            
            let binPath = mapRoot
                .appendingPathComponent("\(tile.z)")
                .appendingPathComponent("\(tile.x)")
                .appendingPathComponent("\(tile.y).bin")
            
            // Download PNG
            do {
                let downloaded = try await downloader.downloadTile(
                    tile: tile,
                    urlTemplate: urlTemplate,
                    outputPath: pngPath
                )
                
                if downloaded {
                    await MainActor.run {
                        downloadedCount += 1
                    }
                    
                    // Convert to bin
                    let converted = try await converter.convertPNGToBin(
                        pngPath: pngPath,
                        binPath: binPath
                    )
                    
                    if converted {
                        await MainActor.run {
                            convertedCount += 1
                        }
                        
                        // Delete PNG if not keeping it
                        if !keepPNG {
                            converter.deleteFile(at: pngPath)
                        }
                    } else {
                        await MainActor.run {
                            failedCount += 1
                            errorMessage = "Conversion failed for tile \(tile.z)/\(tile.x)/\(tile.y)"
                        }
                    }
                } else {
                    await MainActor.run {
                        failedCount += 1
                        errorMessage = "Download failed for tile \(tile.z)/\(tile.x)/\(tile.y)"
                    }
                }
            } catch {
                await MainActor.run {
                    failedCount += 1
                    errorMessage = error.localizedDescription
                }
            }
            
            // Update progress
            await MainActor.run {
                progress = Double(index + 1) / Double(totalTiles)
                statusMessage = "Downloaded: \(downloadedCount), Converted: \(convertedCount), Failed: \(failedCount)"
            }
            
            // Delay between requests (politeness)
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            }
        }
        
        await MainActor.run {
            isDownloading = false
            statusMessage = "Complete! Downloaded: \(downloadedCount), Converted: \(convertedCount), Failed: \(failedCount)"
            
            if failedCount == 0 {
                let alert = NSAlert()
                alert.messageText = "Download Complete"
                alert.informativeText = "Successfully converted \(convertedCount) tiles to \(mapRoot.path)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    /// Select output directory using file picker
    func selectOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select output directory for map tiles"
        
        if let currentDir = outputDirectory {
            panel.directoryURL = currentDir
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }
}

