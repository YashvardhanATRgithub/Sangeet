
import Foundation
import Combine
import SwiftUI

@MainActor
class OnlineViewModel: ObservableObject {
    
    // MARK: - State
    @Published var searchText = ""
    @Published var searchResults: [TidalTrack] = []
    @Published var isSearching = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    private let tidalService = TidalDLService.shared
    private let playbackManager = PlaybackManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Debounce search
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if !query.isEmpty {
                    Task { await self.performSearch(query) }
                } else {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    
    func performSearch(_ query: String) async {
        // 1. Network Check
        guard NetworkMonitor.shared.isConnected else {
            self.errorMessage = "No Internet Connection. Please check your network."
            self.isLoading = false
            return
        }
    
        isSearching = true
        isLoading = true
        errorMessage = nil
        
        do {
            var results = try await tidalService.search(query: query)
            
            // 2. Smart Lyrics Fallback
            // If results are empty OR the query looks like lyrics (> 4 words), try iTunes Resolve
            let isLongQuery = query.split(separator: " ").count >= 4
            
            if results.isEmpty || isLongQuery {
                print("[OnlineVM] Attempting Smart Lyrics Resolve via iTunes...")
                if let resolvedQuery = await resolveLyricsToSong(query) {
                    print("[OnlineVM] Resolved Lyrics to: '\(resolvedQuery)'")
                    // Search again with the Resolved Title
                    let refinedResults = try await tidalService.search(query: resolvedQuery)
                    if !refinedResults.isEmpty {
                        // Merge: Put refined results AT THE TOP
                        results.insert(contentsOf: refinedResults, at: 0)
                        
                        // Deduplicate by ID
                        var seen = Set<Int>()
                        results = results.filter { track in
                            guard !seen.contains(track.id) else { return false }
                            seen.insert(track.id)
                            return true
                        }
                    }
                }
            }
            
            if results.isEmpty {
                self.errorMessage = "No results found for '\(query)'."
            }
            self.searchResults = results
        } catch {
            print("[OnlineVM] Search Error: \(error)")
            self.errorMessage = "Unable to connect to server. Please try again later."
            self.searchResults = []
        }
        
        self.isLoading = false
    }
    
    /// Helper: Uses iTunes API to resolve lyrics/random text to a proper Song Title + Artist
    private func resolveLyricsToSong(_ text: String) async -> String? {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&limit=1") else {
            return nil
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Reuse ITunes structure if possible, or simple local struct
            struct ITunesResponse: Codable {
                let results: [ITunesItem]
            }
            struct ITunesItem: Codable {
                let trackName: String
                let artistName: String
            }
            
            let wrapper = try JSONDecoder().decode(ITunesResponse.self, from: data)
            if let first = wrapper.results.first {
                return "\(first.trackName) \(first.artistName)"
            }
        } catch {
            print("[OnlineVM] iTunes Resolve Failed: \(error)")
        }
        return nil
    }
    
    func playTidalTrack(_ track: TidalTrack) {
        // 1. Check for local copy first
        if LibraryManager.shared.hasTrack(title: track.title, artist: track.artistName) {
            // Find the actual track object to play
            if let localTrack = LibraryManager.shared.tracks.first(where: {
                // Use strict match for retrieval, or basic fuzzy if strict fails
                let localTitle = $0.title.lowercased()
                let targetTitle = track.title.lowercased()
                return localTitle.contains(targetTitle) || targetTitle.contains(localTitle)
            }) {
                print("[OnlineVM] Playing local copy: \(localTrack.title)")
                playbackManager.play(localTrack)
                return
            }
        }
    
        Task {
            isLoading = true
            do {
                if let url = try await tidalService.getStreamURL(trackID: track.id) {
                    // Create a temporary Track object with artworkURL for display
                    let tempTrack = Track(
                        title: track.title,
                        artist: track.artistName,
                        album: track.albumName,
                        duration: TimeInterval(track.duration),
                        fileURL: url,
                        artworkData: nil,
                        artworkURL: track.coverURL,
                        externalID: String(track.id)
                    )
                    
                    playbackManager.play(tempTrack)
                    
                } else {
                    errorMessage = "Could not get stream URL"
                }
            } catch {
                errorMessage = "Playback error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    func playTrending(_ track: TidalTrack) {
        // Direct play - no "JIT Search" needed because we already have the Tidal metadata!
        // This guarantees that what you click is what you prevent.
        
        // 1. Check for local copy FIRST (Fuzzy Match)
        if LibraryManager.shared.hasTrack(title: track.title, artist: track.artistName) {
            // Find the actual track object to play
            if let localTrack = LibraryManager.shared.tracks.first(where: {
                let localTitle = $0.title.lowercased()
                let targetTitle = track.title.lowercased()
                return localTitle.contains(targetTitle) || targetTitle.contains(localTitle)
            }) {
                print("[OnlineVM] Local match found for trending: \(localTrack.title)")
                playbackManager.play(localTrack)
                return
            }
        }
        
        // 2. Play Stream directly
        playTidalTrack(track)
    }
    
    func downloadTrack(_ track: TidalTrack) {
        DownloadManager.shared.download(track: track)
        // Optionally show a toast or feedback
        print("Download started for: \(track.title)")
    }
}
