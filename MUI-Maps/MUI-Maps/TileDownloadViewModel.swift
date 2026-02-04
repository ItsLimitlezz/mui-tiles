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
    @Published var latitude: String = "-33.8688"
    @Published var longitude: String = "151.2093"
    @Published var zoom: Int = 13
    @Published var radius: Int = 4
    @Published var selectedStyle: TileStyle = .osm
    @Published var keepPNG: Bool = false
    @Published var delayMs: Int = 50
    
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
        // Set default output directory to Desktop/mui-tiles-export
        if let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first {
            outputDirectory = desktop.appendingPathComponent("mui-tiles-export")
        }
    }
    
    /// Calculate estimated tiles and size
    func estimateTiles() -> (count: Int, sizeMB: Double) {
        guard let lat = Double(latitude),
              let lon = Double(longitude) else {
            return (0, 0)
        }
        
        let tiles = Tile.tilesAround(lat: lat, lon: lon, zoom: zoom, radius: radius)
        let count = tiles.count
        let sizeMB = Double(count * 131_084) / (1024.0 * 1024.0)
        
        return (count, sizeMB)
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
        
        let tiles = Tile.tilesAround(lat: lat, lon: lon, zoom: zoom, radius: radius)
        totalTiles = tiles.count
        
        statusMessage = "Starting download of \(totalTiles) tiles..."
        isDownloading = true
        
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
        let mapRoot = outputDir.appendingPathComponent("map")
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
                            await converter.deleteFile(at: pngPath)
                        }
                    } else {
                        await MainActor.run {
                            failedCount += 1
                        }
                    }
                } else {
                    await MainActor.run {
                        failedCount += 1
                    }
                }
            } catch {
                await MainActor.run {
                    failedCount += 1
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

