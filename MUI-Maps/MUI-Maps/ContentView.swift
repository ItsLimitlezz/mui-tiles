//
//  ContentView.swift
//  MUI-Maps
//
//  Created by Juan Pena on 2026-02-04.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TileDownloadViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack {
                Image(systemName: "map.fill")
                    .imageScale(.large)
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                
                Text("MUI Map Tiles Downloader")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Download OpenStreetMap tiles and convert to LVGL RGB565 .bin format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Location Section
                    GroupBox(label: Label("Location", systemImage: "location.fill")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Latitude:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("e.g., -33.8688", text: $viewModel.latitude)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            HStack {
                                Text("Longitude:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("e.g., 151.2093", text: $viewModel.longitude)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(8)
                    }
                    
                    // Tile Settings Section
                    GroupBox(label: Label("Tile Settings", systemImage: "square.grid.3x3.fill")) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Zoom Level:")
                                    .frame(width: 100, alignment: .trailing)
                                Stepper("\(viewModel.zoom)", value: $viewModel.zoom, in: 0...19)
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
                    let estimate = viewModel.estimateTiles()
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
            .padding(.bottom)
        }
        .frame(minWidth: 700, minHeight: 800)
    }
}

#Preview {
    ContentView()
}
