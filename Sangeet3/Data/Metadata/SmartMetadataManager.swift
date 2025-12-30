//
//  SmartMetadataManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 30/12/24.
//

import Foundation
import SwiftUI
import Combine

struct ITunesSearchResponse: Codable {
    let resultCount: Int
    let results: [ITunesTrack]
}

struct ITunesTrack: Codable {
    let trackName: String?
    let artistName: String?
    let collectionName: String? // Album
    let artworkUrl100: String?
    let releaseDate: String?
    
    var artworkUrlHighRes: String? {
        // modify 100x100 to 1400x1400 for high quality
        artworkUrl100?.replacingOccurrences(of: "100x100bb", with: "1400x1400bb")
    }
}

@MainActor
class SmartMetadataManager: ObservableObject {
    static let shared = SmartMetadataManager()
    
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var isBulkFixing: Bool = false
    
    @Published var isSearching = false
    
    private init() {}
    
    func searchITunes(query: String) async throws -> ITunesTrack? {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=song&limit=5") else {
            return nil
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        return response.results.first
    }
    
    // Bulk Fix
    func fixAllMetadata(libraryManager: LibraryManager) async {
        let tracks = await MainActor.run { libraryManager.tracks }
        
        await MainActor.run {
            totalCount = tracks.count
            processedCount = 0
            isBulkFixing = true
            isSearching = true // Keep global flag for UI disabled state elsewhere
        }
        
        for track in tracks {
            // Check for cancellation? (Not implemented for MVP)
            
            await fixMetadata(for: track, libraryManager: libraryManager)
            
            await MainActor.run {
                processedCount += 1
            }
            
            // Polite delay to avoid rate limiting
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay
        }
        
        await MainActor.run {
            isBulkFixing = false
            isSearching = false
        }
    }

    func fixMetadata(for track: Track, libraryManager: LibraryManager) async {
        await MainActor.run {
             if !isBulkFixing { isSearching = true } // Only toggle single search flag if not bulk
        }

        // ... existing logic ...
        // BUT I need to remove the `isSearching = false` calls inside fixMetadata if I call it in a loop?
        // Actually, `isSearching` property is shared. If I call it in a loop, it might flicker.
        // I should refactor `fixMetadata` to NOT touch `isSearching` if I pass a flag, or just ignore it.
        // Or better: Extract the CORE logic into `private func performFix(...)` and have `fixMetadata` wrap it with state.
        
        await performFix(for: track, libraryManager: libraryManager)
        
        await MainActor.run {
             if !isBulkFixing { isSearching = false }
        }
    }
    
    private func performFix(for track: Track, libraryManager: LibraryManager) async {
        // 1. Construct Search Query
        // ... (Logic from previous fixMetadata)
        var query = "\(track.title) \(track.artist)"
        if track.artist == "Unknown Artist" {
             query = track.title
        }
        
        if query.lowercased().hasSuffix(".mp3") || query.lowercased().hasSuffix(".flac") {
            query = String(query.dropLast(4))
        }
        
        do {
            if let match = try await searchITunes(query: query) {
                // Download Artwork
                var artworkData: Data? = nil
                if let artUrl = match.artworkUrlHighRes, let url = URL(string: artUrl) {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    artworkData = data
                }
                
                // Update Track
                var updatedTrack = track
                updatedTrack.title = match.trackName ?? track.title
                updatedTrack.artist = match.artistName ?? track.artist
                updatedTrack.album = match.collectionName ?? track.album
                if let art = artworkData {
                    updatedTrack.artworkData = art
                }
                
                // Persist logic needs to call LibraryManager
                // Since performFix is async, we need to jump to MainActor to call updateTrackMetadata
                await MainActor.run {
                    libraryManager.updateTrackMetadata(track: updatedTrack)
                }
            }
        } catch {
            print("Metadata search failed: \(error)")
        }
    }
    // fetchArtistImage removed as it was unused and accessed missing properties.

    
    // MARK: - Artist Artwork Cache
    
    private let fileManager = FileManager.default
    private var cacheDirectory: URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("Sangeet3/ArtistCache")
    }
    
    // Fetch with Disk Cache
    func getArtistArtwork(artist: String) async -> URL? {
        guard let cacheDir = cacheDirectory else { return await fetchArtistImageURL(artist: artist) }
        
        // Ensure cache dir exists
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
        
        // Sanitize filename
        let safeName = artist.components(separatedBy: .init(charactersIn: "/\\?%*|\"<>:")).joined()
        let fileURL = cacheDir.appendingPathComponent("\(safeName).jpg")
        
        // 1. Check Cache
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        // 2. Fetch Network
        guard let remoteURL = await fetchArtistImageURL(artist: artist) else { return nil }
        
        // 3. Download & Save
        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            // Optional: Compress/Resize here? For now, raw save is fine.
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to cache artist image: \(error)")
            return remoteURL // Fallback to remote if cache write fails
        }
    }
    
    // Helper: Network Fetch (Internal)
    private func fetchArtistImageURL(artist: String) async -> URL? {
        guard let encodedQuery = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encodedQuery)&media=music&entity=album&limit=1") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let firstAlbum = response.results.first, let artUrl = firstAlbum.artworkUrl100 else { return nil }
            // Get High Res
            let highRes = artUrl.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return URL(string: highRes)
        } catch {
            return nil
        }
    }
}
