//
//  Tile.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import Foundation

/// Represents a map tile with zoom level and x/y coordinates
struct Tile: Identifiable, Hashable {
    let z: Int  // Zoom level
    let x: Int  // X coordinate
    let y: Int  // Y coordinate
    
    var id: String {
        "\(z)/\(x)/\(y)"
    }
    
    /// Convert lat/lon to tile coordinates at given zoom level
    static func deg2num(lat: Double, lon: Double, zoom: Int) -> (x: Int, y: Int) {
        let latRad = lat * .pi / 180.0
        let n = pow(2.0, Double(zoom))
        let xtile = Int((lon + 180.0) / 360.0 * n)
        let ytile = Int((1.0 - asinh(tan(latRad)) / .pi) / 2.0 * n)
        return (xtile, ytile)
    }
    
    /// Get all tiles in a radius around a center point
    static func tilesAround(lat: Double, lon: Double, zoom: Int, radius: Int) -> [Tile] {
        let (cx, cy) = deg2num(lat: lat, lon: lon, zoom: zoom)
        var tiles: [Tile] = []
        
        for dx in -radius...radius {
            for dy in -radius...radius {
                tiles.append(Tile(z: zoom, x: cx + dx, y: cy + dy))
            }
        }
        
        return tiles
    }
    
    /// Get all tiles within a bounding box at given zoom level
    static func tilesForBBox(
        zoom: Int,
        west: Double,
        south: Double,
        east: Double,
        north: Double
    ) -> [Tile] {
        // deg2num expects lat, lon. y increases southward
        let (x1, y1) = deg2num(lat: north, lon: west, zoom: zoom)  // top-left
        let (x2, y2) = deg2num(lat: south, lon: east, zoom: zoom)  // bottom-right
        
        let xmin = min(x1, x2)
        let xmax = max(x1, x2)
        let ymin = min(y1, y2)
        let ymax = max(y1, y2)
        
        var tiles: [Tile] = []
        for x in xmin...xmax {
            for y in ymin...ymax {
                tiles.append(Tile(z: zoom, x: x, y: y))
            }
        }
        
        return tiles
    }
}

/// Map tile style options
enum TileStyle: String, CaseIterable, Identifiable {
    case osm = "OpenStreetMap"
    
    var id: String { rawValue }
    
    var folderName: String {
        switch self {
        case .osm: return "osm"
        }
    }
    
    var urlTemplate: String {
        switch self {
        case .osm:
            // OSM default tile server; this build is OSM-only
            return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        }
    }
}
