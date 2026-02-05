//
//  ContentView.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import SwiftUI
import MapKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit

struct DoubleClickCatcher: NSViewRepresentable {
    var onDoubleClick: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let recognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        recognizer.numberOfClicksRequired = 1
        recognizer.delaysPrimaryMouseButtonEvents = false
        recognizer.buttonMask = 0x1 // primary button only
        view.addGestureRecognizer(recognizer)

        let longPress = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowableMovement = 6
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator: NSObject {
        let onDoubleClick: (CGPoint) -> Void
        init(onDoubleClick: @escaping (CGPoint) -> Void) {
            self.onDoubleClick = onDoubleClick
        }

        @objc func handleClick(_ sender: NSClickGestureRecognizer) {
            guard let view = sender.view else { return }
            // Require Control-click to avoid interfering with normal pan/zoom gestures
            if let event = NSApp.currentEvent, !event.modifierFlags.contains(.control) {
                return
            }
            let location = sender.location(in: view)
            onDoubleClick(location)
        }

        @objc func handleLongPress(_ sender: NSPressGestureRecognizer) {
            guard let view = sender.view else { return }
            if sender.state == .began {
                let location = sender.location(in: view)
                onDoubleClick(location)
            }
        }
    }
}

struct MKMapViewContainer: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var pins: [DroppedPin]
    var zoom: Int
    var radius: Int
    var maxZoom: Int
    var onPlacePin: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .standard
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true

        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        click.numberOfClicksRequired = 1
        click.delaysPrimaryMouseButtonEvents = false
        click.buttonMask = 0x1
        mapView.addGestureRecognizer(click)

        let longPress = NSPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowableMovement = 6
        mapView.addGestureRecognizer(longPress)

        // Add a compass button in the bottom-right
        let compass = MKCompassButton(mapView: mapView)
        compass.compassVisibility = .visible
        compass.translatesAutoresizingMaskIntoConstraints = false
        mapView.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -8),
            compass.bottomAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -8)
        ])

        return mapView
    }

    func updateNSView(_ mapView: MKMapView, context: Context) {
        // Update visible region if needed
        if !regionsEqual(mapView.region, region) {
            mapView.setRegion(region, animated: false)
        }
        // Sync annotations with pins
        if mapView.annotations.count != pins.count || !annotationsMatch(mapView.annotations, pins: pins) {
            mapView.removeAnnotations(mapView.annotations)
            let annotations: [MKPointAnnotation] = pins.map { pin in
                let a = MKPointAnnotation()
                a.coordinate = pin.coordinate
                return a
            }
            mapView.addAnnotations(annotations)
        }
        // Update export overlay based on center (pin if available) + zoom + radius
        let centerCoord = pins.first?.coordinate ?? region.center
        context.coordinator.updateExportOverlay(on: mapView, center: centerCoord, zoom: zoom, radius: radius)
        context.coordinator.updateMaxGridOverlay(on: mapView, center: centerCoord, minZoom: zoom, radius: radius, maxZoom: maxZoom)
    }

    private func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion, epsilon: CLLocationDegrees = 1e-6) -> Bool {
        abs(a.center.latitude - b.center.latitude) < epsilon &&
        abs(a.center.longitude - b.center.longitude) < epsilon &&
        abs(a.span.latitudeDelta - b.span.latitudeDelta) < epsilon &&
        abs(a.span.longitudeDelta - b.span.longitudeDelta) < epsilon
    }

    private func annotationsMatch(_ annotations: [MKAnnotation], pins: [DroppedPin]) -> Bool {
        guard annotations.count == pins.count else { return false }
        for (anno, pin) in zip(annotations, pins) {
            if abs(anno.coordinate.latitude - pin.coordinate.latitude) > 1e-8 ||
                abs(anno.coordinate.longitude - pin.coordinate.longitude) > 1e-8 {
                return false
            }
        }
        return true
    }

    private func lonForTileX(_ x: Int, zoom z: Int) -> Double {
        let n = pow(2.0, Double(z))
        return (Double(x) / n) * 360.0 - 180.0
    }

    private func latForTileY(_ y: Int, zoom z: Int) -> Double {
        let n = pow(2.0, Double(z))
        let latRad = atan(sinh(.pi * (1.0 - 2.0 * Double(y) / n)))
        return latRad * 180.0 / .pi
    }

    private func tileXY(for coord: CLLocationCoordinate2D, zoom z: Int) -> (x: Int, y: Int) {
        let n = pow(2.0, Double(z))
        let latRad = coord.latitude * .pi / 180.0
        var x = Int(floor((coord.longitude + 180.0) / 360.0 * n))
        var y = Int(floor((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n))
        // Clamp to valid range
        let maxIndex = Int(n) - 1
        x = max(0, min(maxIndex, x))
        y = max(0, min(maxIndex, y))
        return (x, y)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MKMapViewContainer
        private var glowOverlay: MKPolygon?
        private var outlineOverlay: MKPolygon?
        private var gridOverlays: [MKPolyline] = []
        private var maxGridOverlays: [MKPolyline] = []

        init(_ parent: MKMapViewContainer) { self.parent = parent }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }

        @objc func handleClick(_ sender: NSClickGestureRecognizer) {
            guard let view = sender.view as? MKMapView else { return }
            // Require Control-click
            if let event = NSApp.currentEvent, !event.modifierFlags.contains(.control) { return }
            let point = sender.location(in: view)
            let coord = view.convert(point, toCoordinateFrom: view)
            parent.onPlacePin(coord)
        }

        @objc func handleLongPress(_ sender: NSPressGestureRecognizer) {
            guard let view = sender.view as? MKMapView else { return }
            if sender.state == .began {
                let point = sender.location(in: view)
                let coord = view.convert(point, toCoordinateFrom: view)
                parent.onPlacePin(coord)
            }
        }

        func updateExportOverlay(on mapView: MKMapView, center: CLLocationCoordinate2D, zoom: Int, radius: Int) {
            // Compute tile bounds around center tile
            let n = Int(pow(2.0, Double(zoom)))
            let centerTile = parent.tileXY(for: center, zoom: zoom)
            let minX = max(0, centerTile.x - radius)
            let maxX = min(n - 1, centerTile.x + radius)
            let minY = max(0, centerTile.y - radius)
            let maxY = min(n - 1, centerTile.y + radius)

            // Convert tile edges to geographic bounds
            let leftLon = parent.lonForTileX(minX, zoom: zoom)
            let rightLon = parent.lonForTileX(maxX + 1, zoom: zoom)
            let topLat = parent.latForTileY(minY, zoom: zoom)
            let bottomLat = parent.latForTileY(maxY + 1, zoom: zoom)

            let coords: [CLLocationCoordinate2D] = [
                CLLocationCoordinate2D(latitude: topLat, longitude: leftLon),    // top-left
                CLLocationCoordinate2D(latitude: topLat, longitude: rightLon),   // top-right
                CLLocationCoordinate2D(latitude: bottomLat, longitude: rightLon),// bottom-right
                CLLocationCoordinate2D(latitude: bottomLat, longitude: leftLon)  // bottom-left
            ]

            // Remove old overlays first
            if let g = glowOverlay { mapView.removeOverlay(g) }
            if let o = outlineOverlay { mapView.removeOverlay(o) }
            for overlay in gridOverlays { mapView.removeOverlay(overlay) }
            gridOverlays.removeAll()

            // Build new overlays
            let outline = MKPolygon(coordinates: coords, count: coords.count)
            let glow = MKPolygon(coordinates: coords, count: coords.count)

            // Build grid lines for tile boundaries inside the rectangle
            var newGrid: [MKPolyline] = []
            // Vertical grid lines at each tile boundary lon
            for x in minX...maxX+1 {
                let lon = parent.lonForTileX(x, zoom: zoom)
                let lineCoords = [
                    CLLocationCoordinate2D(latitude: topLat, longitude: lon),
                    CLLocationCoordinate2D(latitude: bottomLat, longitude: lon)
                ]
                let line = MKPolyline(coordinates: lineCoords, count: 2)
                newGrid.append(line)
            }
            // Horizontal grid lines at each tile boundary lat
            for y in minY...maxY+1 {
                let lat = parent.latForTileY(y, zoom: zoom)
                let lineCoords = [
                    CLLocationCoordinate2D(latitude: lat, longitude: leftLon),
                    CLLocationCoordinate2D(latitude: lat, longitude: rightLon)
                ]
                let line = MKPolyline(coordinates: lineCoords, count: 2)
                newGrid.append(line)
            }

            // Save and add overlays in order: glow (under), grid, outline (top)
            glowOverlay = glow
            outlineOverlay = outline
            gridOverlays = newGrid

            mapView.addOverlay(glow)
            for grid in gridOverlays { mapView.addOverlay(grid) }
            mapView.addOverlay(outline)
        }

        func updateMaxGridOverlay(on mapView: MKMapView, center: CLLocationCoordinate2D, minZoom: Int, radius: Int, maxZoom: Int) {
            // Remove old max grid overlays
            for overlay in maxGridOverlays { mapView.removeOverlay(overlay) }
            maxGridOverlays.removeAll()

            // Compute geographic bounds from min zoom + radius
            let nMin = Int(pow(2.0, Double(minZoom)))
            let centerTileMin = parent.tileXY(for: center, zoom: minZoom)
            let minXMin = max(0, centerTileMin.x - radius)
            let maxXMin = min(nMin - 1, centerTileMin.x + radius)
            let minYMin = max(0, centerTileMin.y - radius)
            let maxYMin = min(nMin - 1, centerTileMin.y + radius)

            let leftLon = parent.lonForTileX(minXMin, zoom: minZoom)
            let rightLon = parent.lonForTileX(maxXMin + 1, zoom: minZoom)
            let topLat = parent.latForTileY(minYMin, zoom: minZoom)
            let bottomLat = parent.latForTileY(maxYMin + 1, zoom: minZoom)

            // Convert geographic bounds to max-zoom boundary indices
            let nMax = Int(pow(2.0, Double(maxZoom)))
            let nMaxD = Double(nMax)
            let xStart = max(0, Int(floor((leftLon + 180.0) / 360.0 * nMaxD)))
            let xEnd = min(nMax, Int(ceil((rightLon + 180.0) / 360.0 * nMaxD)))
            func yBoundaryIndex(for lat: Double) -> Int {
                let latRad = lat * .pi / 180.0
                let y = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0
                return Int(floor(y * nMaxD))
            }
            func yBoundaryIndexCeil(for lat: Double) -> Int {
                let latRad = lat * .pi / 180.0
                let y = (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0
                return Int(ceil(y * nMaxD))
            }
            let yStart = max(0, yBoundaryIndex(for: topLat))
            let yEnd = min(nMax, yBoundaryIndexCeil(for: bottomLat))

            // Build green grid lines within these bounds at max zoom
            var newGrid: [MKPolyline] = []
            if xStart <= xEnd {
                for x in xStart...xEnd {
                    let lon = parent.lonForTileX(x, zoom: maxZoom)
                    let lineCoords = [
                        CLLocationCoordinate2D(latitude: topLat, longitude: lon),
                        CLLocationCoordinate2D(latitude: bottomLat, longitude: lon)
                    ]
                    newGrid.append(MKPolyline(coordinates: lineCoords, count: 2))
                }
            }
            if yStart <= yEnd {
                for y in yStart...yEnd {
                    let lat = parent.latForTileY(y, zoom: maxZoom)
                    let lineCoords = [
                        CLLocationCoordinate2D(latitude: lat, longitude: leftLon),
                        CLLocationCoordinate2D(latitude: lat, longitude: rightLon)
                    ]
                    newGrid.append(MKPolyline(coordinates: lineCoords, count: 2))
                }
            }

            maxGridOverlays = newGrid
            for grid in maxGridOverlays { mapView.addOverlay(grid) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                if let g = glowOverlay, polygon === g {
                    renderer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
                    renderer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.05)
                    renderer.lineWidth = 18
                } else if let o = outlineOverlay, polygon === o {
                    renderer.strokeColor = NSColor.controlAccentColor
                    renderer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.08)
                    renderer.lineWidth = 2
                }
                return renderer
            }
            if let line = overlay as? MKPolyline {
                if gridOverlays.contains(where: { $0 === line }) {
                    let renderer = MKPolylineRenderer(polyline: line)
                    renderer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.35)
                    renderer.lineWidth = 1.0
                    renderer.lineDashPattern = [2, 3]
                    return renderer
                } else if maxGridOverlays.contains(where: { $0 === line }) {
                    let renderer = MKPolylineRenderer(polyline: line)
                    renderer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.7)
                    renderer.lineWidth = 1.2
                    return renderer
                }
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
#endif

struct DroppedPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ContentView: View {
    @StateObject private var viewModel = TileDownloadViewModel()
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25.8177, longitude: -80.1227),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isDropTarget: Bool = false
    @State private var pins: [DroppedPin] = []
    @State private var maxZoom: Int = 15

    private func updateRegionFromViewModel() {
        if let lat = Double(viewModel.latitude), let lon = Double(viewModel.longitude) {
            region.center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            cameraPosition = .region(region)
            pins = [DroppedPin(coordinate: region.center)]
        }
    }

    private func tileCenterLatLon(x: Int, y: Int, z: Int) -> (lat: Double, lon: Double) {
        let n = pow(2.0, Double(z))
        let lon = (Double(x) + 0.5) / n * 360.0 - 180.0
        let latRad = atan(sinh(Double.pi * (1.0 - 2.0 * (Double(y) + 0.5) / n)))
        let lat = latRad * 180.0 / Double.pi
        return (lat, lon)
    }

    private func tryExtractTileFromURL(_ url: URL) -> (z: Int, x: Int, y: Int)? {
        // Expecting path like .../maps/<style>/<z>/<x>/<y>.bin (or /map/z/x/y.bin)
        guard url.pathExtension.lowercased() == "bin" else { return nil }
        let yName = url.deletingPathExtension().lastPathComponent
        let xName = url.deletingLastPathComponent().lastPathComponent
        let zName = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        guard let y = Int(yName), let x = Int(xName), let z = Int(zName) else { return nil }
        return (z, x, y)
    }

    private func handleDroppedURL(_ url: URL) {
        guard let (z, x, y) = tryExtractTileFromURL(url) else { return }
        let center = tileCenterLatLon(x: x, y: y, z: z)
        let latStr = String(format: "%.6f", center.lat)
        let lonStr = String(format: "%.6f", center.lon)
        viewModel.latitude = latStr
        viewModel.longitude = lonStr
        updateRegionFromViewModel()
        pins = [DroppedPin(coordinate: CLLocationCoordinate2D(latitude: center.lat, longitude: center.lon))]
        cameraPosition = .region(region)
    }

    // Extracted to reduce type-checker complexity
    @ViewBuilder
    private func MapPreview() -> some View {
        GroupBox(label: Label("Map Preview", systemImage: "map")) {
            MapReader { proxy in
                ZStack {
                    mapBaseView
                        .overlay(mapDropOverlay)
                    DoubleClickCatcher { point in
                        guard let coord = proxy.convert(point, from: .local) else { return }
                        pins = [DroppedPin(coordinate: coord)]
                        viewModel.latitude = String(format: "%.6f", coord.latitude)
                        viewModel.longitude = String(format: "%.6f", coord.longitude)
                        region.center = coord
                        cameraPosition = .region(region)
                    }
                    .background(Color.clear)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(8)
            
            HStack(spacing: 8) {
                Button {
                    // Zoom in by halving span deltas
                    region.span = MKCoordinateSpan(latitudeDelta: max(region.span.latitudeDelta / 2, 0.0005),
                                                   longitudeDelta: max(region.span.longitudeDelta / 2, 0.0005))
                    cameraPosition = .region(region)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                Button {
                    // Zoom out by doubling span deltas
                    region.span = MKCoordinateSpan(latitudeDelta: min(region.span.latitudeDelta * 2, 180),
                                                   longitudeDelta: min(region.span.longitudeDelta * 2, 360))
                    cameraPosition = .region(region)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                HStack {
                    Text("Latitude:")
                        .frame(width: 60, alignment: .trailing)
                    TextField("e.g., 25.8177", text: $viewModel.latitude)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Longitude:")
                        .frame(width: 70, alignment: .trailing)
                    TextField("e.g., -80.1227", text: $viewModel.longitude)
                        .textFieldStyle(.roundedBorder)
                }
                //Spacer()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 8)

            Text("Double-click to drop a pin and set Latitude/Longitude. Or drop a .bin tile file (maps/<style>/z/x/y.bin or map/z/x/y.bin).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    // Split out base Map view and its heavy modifiers
    private var mapBaseView: some View {
        #if os(macOS)
        MKMapViewContainer(region: $region, pins: pins, zoom: viewModel.zoom, radius: viewModel.radius, maxZoom: maxZoom) { coord in
            // Replace old pin with the new one and sync UI
            pins = [DroppedPin(coordinate: coord)]
            viewModel.latitude = String(format: "%.6f", coord.latitude)
            viewModel.longitude = String(format: "%.6f", coord.longitude)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(8)
        #else
        Map(position: $cameraPosition) {
            ForEach(pins) { pin in
                Marker("", coordinate: pin.coordinate)
                    .tint(.red)
            }
        }
        .mapControlsPlacement(.bottomTrailing)
        .mapControls {
            MapCompass()
        }
        .onMapCameraChange { context in
            if let newRegion = context.region { region = newRegion }
        }
        .mapStyle(.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(8)
        #endif
    }

    private var mapDropOverlay: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isDropTarget ? 3 : 1)
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async { self.handleDroppedURL(url) }
                    } else if let url = item as? URL {
                        DispatchQueue.main.async { self.handleDroppedURL(url) }
                    }
                }
                return true
            }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Full-window map background
            mapBaseView
                .ignoresSafeArea()

            // Floating control panel on the right
            VStack(spacing: 16) {
                // Header
                VStack {
                    Image(systemName: "map.fill")
                        .imageScale(.large)
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("Mesh Maps Studio")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Download OpenStreetMap tiles and convert to LVGL RGB565 .bin format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Scrollable controls
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Map Preview Section (keep for double-click & drop help UI, smaller since map is background)
                        //MapPreview()

                        // Tile Settings Section
                        GroupBox(label: Label("Tile Settings", systemImage: "square.grid.3x3.fill")) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Min Zoom:")
                                        .frame(width: 100, alignment: .trailing)
                                    Stepper("\(viewModel.zoom)", value: $viewModel.zoom, in: 0...19)
                                        .frame(maxWidth: 150)
                                    Spacer()
                                }
                                HStack {
                                    Text("Max Zoom:")
                                        .frame(width: 100, alignment: .trailing)
                                    Stepper("\(maxZoom)", value: $maxZoom, in: viewModel.zoom...19)
                                        .frame(maxWidth: 150)
                                    Spacer()
                                }
                                HStack {
                                    Text("Radius:")
                                        .frame(width: 100, alignment: .trailing)
                                    Stepper("\(viewModel.radius)", value: $viewModel.radius, in: 0...50)
                                        .frame(maxWidth: 150)
                                    Text("(\((viewModel.radius * 2 + 1))×\((viewModel.radius * 2 + 1)) grid)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                HStack {
                                    Text("Map Style:")
                                        .frame(width: 100, alignment: .trailing)
                                    Picker("", selection: $viewModel.selectedStyle) {
                                        ForEach(TileStyle.allCases) { style in
                                            Text(style.rawValue).tag(style)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: 200)
                                    Spacer()
                                }
                            }
                            .padding(8)
                        }

                        // Output Settings Section
                        GroupBox(label: Label("Output Settings", systemImage: "folder.fill")) {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Output Directory:")
                                        .frame(width: 120, alignment: .trailing)
                                    Text(viewModel.outputDirectory?.path ?? "Not selected")
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button("Choose...") {
                                        viewModel.selectOutputDirectory()
                                    }
                                }
                                HStack {
                                    Text("Keep PNG files:")
                                        .frame(width: 120, alignment: .trailing)
                                    Toggle("", isOn: $viewModel.keepPNG)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                    Text("(Keep original PNG alongside .bin)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                HStack {
                                    Text("Delay (ms):")
                                        .frame(width: 120, alignment: .trailing)
                                    TextField("50", value: $viewModel.delayMs, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 100)
                                    Text("politeness delay between downloads")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                            .padding(8)
                        }

                        // Estimate
                        let estimate = viewModel.estimateTiles(minZoom: viewModel.zoom, maxZoom: maxZoom)
                        if estimate.count > 0 {
                            HStack {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Estimated: \(estimate.count) tiles (~\(String(format: "%.1f", estimate.sizeMB)) MB)")
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }

                        // Progress Section
                        if viewModel.isDownloading {
                            GroupBox(label: Label("Progress", systemImage: "arrow.down.circle.fill")) {
                                VStack(spacing: 12) {
                                    ProgressView(value: viewModel.progress) {
                                        HStack {
                                            Text("Overall Progress")
                                            Spacer()
                                            Text("\(Int(viewModel.progress * 100))%")
                                        }
                                        .font(.caption)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Current: \(viewModel.currentTile)")
                                            .font(.caption)
                                        Text("Downloaded: \(viewModel.downloadedCount) | Converted: \(viewModel.convertedCount) | Failed: \(viewModel.failedCount)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                            }
                        }

                        // Status Message
                        if !viewModel.statusMessage.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text(viewModel.statusMessage)
                                    .font(.subheadline)
                            }
                            .padding(.horizontal)
                        }

                        // Error Message
                        if !viewModel.errorMessage.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(viewModel.errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                    .onAppear {
                        updateRegionFromViewModel()
                        cameraPosition = .region(region)
                        maxZoom = max(maxZoom, viewModel.zoom)
                        viewModel.maxZoom = maxZoom
                    }
                    .onChange(of: viewModel.latitude) { oldValue, newValue in
                        updateRegionFromViewModel()
                        cameraPosition = .region(region)
                    }
                    .onChange(of: viewModel.longitude) { oldValue, newValue in
                        updateRegionFromViewModel()
                        cameraPosition = .region(region)
                    }
                    .onChange(of: viewModel.zoom) { oldValue, newValue in
                        updateRegionFromViewModel()
                        cameraPosition = .region(region)
                        if maxZoom < viewModel.zoom { maxZoom = viewModel.zoom }
                    }
                    .onChange(of: maxZoom) { oldValue, newValue in
                        viewModel.maxZoom = newValue
                    }
                }

                Divider()

                // Action Buttons
                HStack(spacing: 16) {
                    if viewModel.isDownloading {
                        Button(action: {
                            viewModel.stopDownload()
                        }) {
                            Label("Stop Download", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(action: {
                            viewModel.startDownload()
                        }) {
                            Label("Start Download", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.outputDirectory == nil)
                    }
                    if let outputDir = viewModel.outputDirectory {
                        Button(action: {
                            NSWorkspace.shared.open(outputDir)
                        }) {
                            Label("Open Output Folder", systemImage: "folder")
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: 420)
            .frame(maxHeight: 750)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding()
        }
        .frame(minHeight: 700)
    }
}

#Preview {
    ContentView()
}

