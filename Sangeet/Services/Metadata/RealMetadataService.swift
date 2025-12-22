import Foundation
import AVFoundation
import AppKit

class RealMetadataService: MetadataService {
    
    func metadata(for url: URL) async throws -> Track {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        let asset = AVURLAsset(url: url)
        
        // Load properties asynchronously
        let title = try? await loadMetadata(asset, for: .commonKeyTitle)
        let artist = try? await loadMetadata(asset, for: .commonKeyArtist)
        let album = try? await loadMetadata(asset, for: .commonKeyAlbumName)
        let duration = try? await asset.load(.duration).seconds
        let safeDuration = (duration ?? 0).isFinite ? (duration ?? 0) : 0
        
        // TODO: Handle FFmpeg metadata for non-native files here if AVAsset fails significantly
        
        return Track(
            id: UUID(), // In real app, generate consistent ID from path/hash to avoid dupes
            url: url,
            title: title ?? url.deletingPathExtension().lastPathComponent,
            artist: artist ?? "Unknown Artist",
            album: album ?? "Unknown Album",
            albumArtist: "", // Fetch 'albumArtist' if needed
            genre: "",
            duration: safeDuration,
            trackNumber: nil,
            discNumber: nil,
            year: nil,
            dateAdded: Date(),
            playCount: 0,
            isFavorite: false
        )
    }
    
    func loadArtwork(for track: Track) async -> URL? {
        let fileURL = track.url
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SangeetArtwork")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        
        let cachedURL = cacheDir.appendingPathComponent(track.id.uuidString + ".jpg")
        if FileManager.default.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        // 1. Try embedded artwork
        let asset = AVURLAsset(url: fileURL)
        if let data = await extractArtworkData(from: asset) {
            try? data.write(to: cachedURL, options: [.atomic])
            return cachedURL
        }
        
        // 2. Try local file in directory (cover.jpg, folder.jpg, artwork.png etc)
        let folderURL = fileURL.deletingLastPathComponent()
        let imageNames = ["cover.jpg", "cover.png", "folder.jpg", "folder.png", "artwork.jpg", "artwork.png", "album.jpg", "front.jpg"]
        
        for name in imageNames {
            let potentialImage = folderURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: potentialImage.path) {
                // Copy to cache to ensure consistent access and size? Or just return raw URL?
                // Better to optimize/resize in a real app, but for now cop/link.
                // We'll return the direct URL if it's accessible, or copy to cache.
                // Copying to cache is safer for sandbox.
                if let data = try? Data(contentsOf: potentialImage) {
                    try? data.write(to: cachedURL, options: [.atomic])
                    return cachedURL
                }
            }
        }
        
        // 3. Try to find *any* image in the folder if the specific names fail?
        // Maybe too aggressive.
        
        return nil
    }
    
    private func loadMetadata(_ asset: AVAsset, for key: AVMetadataKey) async throws -> String? {
        // ... (existing implementation)
        let items = try await asset.load(.commonMetadata)
        if let item = items.first(where: { $0.commonKey == key }),
           let value = try await item.load(.value) as? String {
            return value
        }
        return nil
    }
    
    private func extractArtworkData(from asset: AVURLAsset) async -> Data? {
        // ... (existing implementation)
        if let common = try? await asset.load(.commonMetadata),
           let data = await artworkData(in: common) {
            return data
        }
        
        if let metadata = try? await asset.load(.metadata),
           let data = await artworkData(in: metadata) {
            return data
        }
        
        if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                let items = try? await asset.loadMetadata(for: format)
                if let items, let data = await artworkData(in: items) {
                    return data
                }
            }
        }
        
        return nil
    }
    
    private func artworkData(in items: [AVMetadataItem]) async -> Data? {
        let candidates = items.filter { item in
            if item.commonKey == .commonKeyArtwork {
                return true
            }
            if let identifier = item.identifier {
                 if identifier == .id3MetadataAttachedPicture ||
                    identifier == .iTunesMetadataCoverArt ||
                    identifier == .quickTimeMetadataArtwork {
                     return true
                 }
                
                let raw = identifier.rawValue.lowercased()
                if raw.contains("artwork") || raw.contains("picture") || raw.contains("cover") {
                    return true
                }
            }
            return false
        }
        
        for item in candidates {
            if let data = item.dataValue {
                return data
            }
            if let value = try? await item.load(.value) {
                if let data = value as? Data {
                    return data
                }
                if let image = value as? NSImage, let data = image.tiffRepresentation {
                    return data
                }
            }
        }
        
        return nil
    }
}

