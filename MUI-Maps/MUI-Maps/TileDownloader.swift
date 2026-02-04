//
//  TileDownloader.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation
import AppKit

/// Service for downloading map tiles from tile servers
actor TileDownloader {
    private let session: URLSession
    private let userAgent = "mui-tiles/0.1 (Meshtastic MUI bin tile tool)"
    
    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }
    
    /// Download a single tile from the URL template
    func downloadTile(
        tile: Tile,
        urlTemplate: String,
        outputPath: URL,
        retries: Int = 3
    ) async throws -> Bool {
        // Create parent directories if needed
        let parentDir = outputPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Skip if already exists and has reasonable size
        if FileManager.default.fileExists(atPath: outputPath.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath.path),
               let size = attrs[.size] as? Int64,
               size > 256 {
                return true
            }
        }
        
        // Substitute subdomain if present
        let subdomain = ["a", "b", "c", "d"].randomElement() ?? "a"
        let urlString = urlTemplate
            .replacingOccurrences(of: "{s}", with: subdomain)
            .replacingOccurrences(of: "{z}", with: "\(tile.z)")
            .replacingOccurrences(of: "{x}", with: "\(tile.x)")
            .replacingOccurrences(of: "{y}", with: "\(tile.y)")
        
        guard let url = URL(string: urlString) else {
            throw TileError.invalidURL
        }
        
        var lastError: Error?
        
        for attempt in 1...retries {
            do {
                let (data, response) = try await session.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TileError.invalidResponse
                }
                
                if httpResponse.statusCode == 200, !data.isEmpty {
                    // Validate it's actually PNG data
                    if data.count > 256 || isPNG(data) {
                        try data.write(to: outputPath)
                        return true
                    } else {
                        throw TileError.invalidImageData
                    }
                } else if [429, 500, 502, 503, 504].contains(httpResponse.statusCode) {
                    // Retry on server errors
                    try await Task.sleep(nanoseconds: UInt64(0.7 * Double(attempt) * 1_000_000_000))
                    lastError = TileError.serverError(httpResponse.statusCode)
                    continue
                } else {
                    throw TileError.httpError(httpResponse.statusCode)
                }
            } catch {
                lastError = error
                if attempt < retries {
                    try await Task.sleep(nanoseconds: UInt64(0.7 * Double(attempt) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? TileError.unknownError
    }
    
    /// Check if data starts with PNG signature
    private func isPNG(_ data: Data) -> Bool {
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 8 else { return false }
        return data.prefix(8).elementsEqual(pngSignature)
    }
}

/// Errors that can occur during tile download
enum TileError: LocalizedError {
    case invalidURL
    case invalidResponse
    case invalidImageData
    case serverError(Int)
    case httpError(Int)
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid tile URL"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidImageData:
            return "Downloaded data is not valid PNG"
        case .serverError(let code):
            return "Server error: \(code)"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
}
