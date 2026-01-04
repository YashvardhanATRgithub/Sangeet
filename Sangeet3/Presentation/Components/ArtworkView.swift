//
//  ArtworkView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Album artwork display with loading and placeholder states
//

import SwiftUI
import AppKit
import Combine

struct ArtworkView: View {
    let track: Track?
    let size: CGFloat
    var cornerRadius: CGFloat = 12
    var showGlow: Bool = false
    
    @StateObject private var loader = ArtworkLoader()
    
    var body: some View {
        ZStack {
            // Glow effect
            if showGlow, loader.artwork != nil {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(SangeetTheme.primary.opacity(0.3))
                    .frame(width: size, height: size)
                    .blur(radius: 30)
            }
            
            // Main artwork
            Group {
                if let artwork = loader.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let url = track?.artworkURL {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        placeholderView
                    }
                } else {
                    placeholderView
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .onChange(of: track) { _, _ in
            loadArtwork()
        }
        .onAppear {
            loadArtwork()
        }
    }
    
    var placeholderView: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [SangeetTheme.surfaceElevated, SangeetTheme.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(SangeetTheme.textMuted)
            )
    }
    
    private func loadArtwork() {
        guard let track = track else {
            loader.artwork = nil
            return
        }
        Task {
            await loader.load(for: track)
        }
    }
}

// MARK: - Artwork Cache
actor ArtworkCache {
    static let shared = ArtworkCache()
    
    private var cache: [UUID: NSImage] = [:]
    private let maxCacheSize = 100
    
    func get(_ trackId: UUID) -> NSImage? {
        cache[trackId]
    }
    
    func set(_ image: NSImage, for trackId: UUID) {
        if cache.count >= maxCacheSize {
            // Remove oldest entries
            let keysToRemove = Array(cache.keys.prefix(20))
            for key in keysToRemove {
                cache.removeValue(forKey: key)
            }
        }
        cache[trackId] = image
    }
    
    func clear() {
        cache.removeAll()
    }
}

// MARK: - Async Artwork Loader
@MainActor
class ArtworkLoader: ObservableObject {
    @Published var artwork: NSImage?
    
    func load(for track: Track) async {
        // Reset state immediately to prevent stale artwork from showing
        self.artwork = nil
        
        // Check cache first
        if let cached = await ArtworkCache.shared.get(track.id) {
            self.artwork = cached
            return
        }
        
        // Load from track data
        if let data = track.artworkData, let image = NSImage(data: data) {
            await ArtworkCache.shared.set(image, for: track.id)
            self.artwork = image
            return
        }
        
        // Extract from file
        let accessing = track.fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { track.fileURL.stopAccessingSecurityScopedResource() } }
        
        if let image = await MetadataExtractor.shared.extractArtwork(from: track.fileURL) {
            await ArtworkCache.shared.set(image, for: track.id)
            self.artwork = image
        }
    }
}
