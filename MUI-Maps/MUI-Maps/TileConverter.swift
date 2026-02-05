//
//  TileConverter.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation
import AppKit

/// Service for converting PNG tiles to LVGL RGB565 binary format
/// Swift-native: writes the LVGL BIN header + RGB565 pixels (no Python dependency).
final class TileConverter {
    
    /// LVGL header layout (v9, little endian, 12 bytes total):
    /// magic (0x19), cf (0x12 = RGB565), flags (u16), width (u16), height (u16), stride (u16), reserved (u16)
    /// followed by RGB565 little-endian pixel data
    private func writeLVGLBin(pixelsRGB565: Data, width: Int, height: Int, to url: URL) throws {
        guard width <= 0xFFFF && height <= 0xFFFF else {
            throw ConverterError.invalidImage
        }
        let magic: UInt8 = 0x19
        let cf: UInt8 = 0x12 // ColorFormat.RGB565
        let flags: UInt16 = 0
        let stride: UInt16 = UInt16(width * 2) // bytes per row for RGB565
        var out = Data()
        out.reserveCapacity(12 + pixelsRGB565.count)
        out.append(magic)
        out.append(cf)
        out.append(contentsOf: withUnsafeBytes(of: flags.littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: UInt16(width).littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: UInt16(height).littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: stride.littleEndian, Array.init))
        out.append(contentsOf: withUnsafeBytes(of: UInt16(0).littleEndian, Array.init)) // reserved
        out.append(pixelsRGB565)
        try out.write(to: url)
    }

    /// Convert PNG to RGB565 pixel buffer + LVGL BIN wrapper
    private func convertPNGToRGB565Bin(pngPath: URL, binPath: URL) throws -> Bool {
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
        var rgb565Data = Data()
        rgb565Data.reserveCapacity(width * height * 2)
        let pixels = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                let r5 = UInt16(r >> 3) & 0x1F
                let g6 = UInt16(g >> 2) & 0x3F
                let b5 = UInt16(b >> 3) & 0x1F
                let rgb565 = (r5 << 11) | (g6 << 5) | b5
                rgb565Data.append(UInt8(rgb565 & 0xFF))
                rgb565Data.append(UInt8(rgb565 >> 8))
            }
        }
        try writeLVGLBin(pixelsRGB565: rgb565Data, width: width, height: height, to: binPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: binPath.path)
        if let size = attrs[.size] as? Int64, size > 1024 { return true }
        return false
    }

    /// Convert a PNG file to RGB565 .bin format for LVGL/MUI
    /// - Parameters:
    ///   - pngPath: Path to source PNG file
    ///   - binPath: Path to destination .bin file
    /// - Returns: true if conversion successful
    func convertPNGToBin(pngPath: URL, binPath: URL) async throws -> Bool {
        return try convertPNGToRGB565Bin(pngPath: pngPath, binPath: binPath)
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
