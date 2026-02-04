//
//  TileConverter.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation
import AppKit

/// Service for converting PNG tiles to LVGL RGB565 binary format
/// Note: use as a plain class (was previously an actor); call convertPNGToBin from async contexts.
final class TileConverter {
    
    private var warnedAboutFallback = false

    /// Locate a Python interpreter to run LVGLImage.py
    private func locatePython() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let py = env["MUI_TILES_PYTHON"], !py.isEmpty {
            let url = URL(fileURLWithPath: py)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Common macOS default
        let candidates = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3", "/usr/bin/python"]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return URL(fileURLWithPath: c) }
        }
        return nil
    }

    /// Locate LVGL's LVGLImage.py script
    private func locateLVGLImage() -> URL? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["MUI_TILES_LVGLIMAGE"], !p.isEmpty {
            let url = URL(fileURLWithPath: p)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        // Optionally look for a bundled resource named LVGLImage.py
        if let bundled = Bundle.main.url(forResource: "LVGLImage", withExtension: "py") {
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return nil
    }

    /// Try converting using LVGL's official LVGLImage.py script. Returns true on success.
    private func convertWithLVGLImage(pngPath: URL, binPath: URL) async -> Bool {
        guard let py = locatePython(), let lvgl = locateLVGLImage() else {
            return false
        }
        let outDir = binPath.deletingLastPathComponent()
        let name = binPath.deletingPathExtension().lastPathComponent
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = py
            process.arguments = [
                lvgl.path,
                pngPath.path,
                "--ofmt", "BIN",
                "--cf", "RGB565",
                "-o", outDir.path,
                "--name", name
            ]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                // LVGLImage writes the file into outDir using the provided name
                if FileManager.default.fileExists(atPath: binPath.path) {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: binPath.path),
                       let size = attrs[.size] as? Int64, size > 1024 {
                        return true
                    }
                }
            }
        } catch {
            // fall through to fallback
        }
        return false
    }

    /// Fallback: Convert to raw RGB565 little-endian without LVGL header (not ideal for MUI)
    private func convertPNGToRawRGB565Fallback(pngPath: URL, binPath: URL) throws -> Bool {
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
        try rgb565Data.write(to: binPath)
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
        // Ensure parent dir exists
        let parentDir = binPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        // Prefer LVGL official converter for correct .bin header/format
        if await convertWithLVGLImage(pngPath: pngPath, binPath: binPath) {
            return true
        }
        // Fallback to raw RGB565 if LVGLImage.py is not available
        if !warnedAboutFallback {
            warnedAboutFallback = true
            print("[TileConverter] Warning: Falling back to raw RGB565 .bin without LVGL header. Set MUI_TILES_LVGLIMAGE and MUI_TILES_PYTHON to use LVGL's converter.")
        }
        return try convertPNGToRawRGB565Fallback(pngPath: pngPath, binPath: binPath)
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
