//
//  AdvancedSettingsView.swift
//  Sangeet
//
//  Created for Sangeet
//

import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var services: AppServices
    @AppStorage("artworkCacheSize") private var cacheSize: Double = 500
    @State private var showResetConfirm = false
    @State private var isRebuildingFTS = false
    @State private var isOptimizing = false
    
    // Helper to access database manager from services
    private var databaseManager: DatabaseManager {
        services.database
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Performance
            performanceSection
            
            Divider()
            
            // Database
            databaseSection
            
            Divider()
            
            // Danger Zone
            dangerZone
            
            Spacer()
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Performance")
                .font(.title3)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Artwork Cache Size")
                    Spacer()
                    Text("\(Int(cacheSize)) MB")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                
                HStack {
                    ModernSlider(value: $cacheSize, range: 100...1000, step: 100)
                    Text("\(Int(cacheSize)) MB")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                    .onChange(of: cacheSize) { newValue in
                        applyCacheSize(Int(newValue))
                    }
                
                Text("Memory limit for caching album artwork. Larger cache = smoother scrolling.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Database")
                .font(.title3)
                .fontWeight(.semibold)
            
            // Database size and optimize
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Size")
                        .font(.subheadline)
                    if let size = databaseManager.getDatabaseSize() {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    isOptimizing = true
                    Task {
                        try? await databaseManager.vacuumDatabase()
                        await MainActor.run {
                            isOptimizing = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isOptimizing {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text(isOptimizing ? "Optimizing..." : "Optimize")
                            .font(.subheadline)
                    }
                }
                .disabled(isOptimizing)
            }
            
            // FTS rebuild
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Index")
                        .font(.subheadline)
                    Text("Rebuild full-text search tables for better results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    isRebuildingFTS = true
                    Task {
                        try? await databaseManager.rebuildFTS()
                        await MainActor.run {
                            isRebuildingFTS = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isRebuildingFTS {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        }
                        Text(isRebuildingFTS ? "Rebuilding..." : "Rebuild FTS")
                            .font(.subheadline)
                    }
                }
                .disabled(isRebuildingFTS)
                .help("Rebuild full-text search indexes to apply enhanced search configuration")
            }
        }
    }
    
    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Danger Zone")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.red)
            
            Button {
                showResetConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash.fill")
                    Text("Reset Database")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .alert("Reset Database?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task {
                        try? databaseManager.resetDatabase()
                    }
                }
            } message: {
                Text("This will delete all your music library data. This action cannot be undone.")
            }
            
            Text("⚠️ This will permanently delete all your library data including folders, tracks, and playlists.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func applyCacheSize(_ sizeMB: Int) {
        ArtworkCache.shared.updateCacheSize(sizeMB: sizeMB)
    }

} 
