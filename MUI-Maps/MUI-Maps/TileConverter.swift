//
//  TileConverter.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation
import AppKit

/// Service for converting PNG tiles to LVGL RGB565 binary format
actor TileConverter {
    
    /// Convert a PNG file to RGB565 .bin format for LVGL/MUI
    /// - Parameters:
    ///   - pngPath: Path to source PNG file
    ///   - binPath: Path to destination .bin file
    /// - Returns: true if conversion successful
    func convertPNGToBin(pngPath: URL, binPath: URL) async throws -> Bool {
        // Create parent directories
        let parentDir = binPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        // Load the PNG image
        guard let nsImage = NSImage(contentsOf: pngPath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ConverterError.invalidImage
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Create bitmap context to read pixel data
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ConverterError.contextCreationFailed
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let pixelData = context.data else {
            throw ConverterError.noPixelData
        }
        
        // Convert to RGB565 format
        var rgb565Data = Data()
        rgb565Data.reserveCapacity(width * height * 2)
        
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                // Alpha channel at offset + 3 is ignored for RGB565
                
                // Convert 8-bit RGB to 5-6-5 format
                let r5 = UInt16(r >> 3) & 0x1F
                let g6 = UInt16(g >> 2) & 0x3F
                let b5 = UInt16(b >> 3) & 0x1F
                
                // Pack into 16-bit value: RRRRRGGGGGGBBBBB
                let rgb565 = (r5 << 11) | (g6 << 5) | b5
                
                // Write as little-endian
                rgb565Data.append(UInt8(rgb565 & 0xFF))
                rgb565Data.append(UInt8(rgb565 >> 8))
            }
        }
        
        // Write the binary data
        try rgb565Data.write(to: binPath)
        
        // Verify the file was written and has reasonable size
        let attrs = try FileManager.default.attributesOfItem(atPath: binPath.path)
        if let size = attrs[.size] as? Int64, size > 1024 {
            return true
        }
        
        return false
    }
    
    /// Delete a file if it exists
    func deleteFile(at path: URL) {
        try? FileManager.default.removeItem(at: path)
    }
}

/// Errors that can occur during tile conversion
enum ConverterError: LocalizedError {
    case invalidImage
    case contextCreationFailed
    case noPixelData
    case writeFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not load PNG image"
        case .contextCreationFailed:
            return "Failed to create bitmap context"
        case .noPixelData:
            return "Could not access pixel data"
        case .writeFailed:
            return "Failed to write binary file"
        }
    }
}
