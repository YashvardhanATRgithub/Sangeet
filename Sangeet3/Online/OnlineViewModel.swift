
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
        isSearching = true
        isLoading = true
        errorMessage = nil
        
        do {
            let results = try await tidalService.search(query: query)
            self.searchResults = results
        } catch {
            self.errorMessage = "Search failed: \(error.localizedDescription)"
            self.searchResults = []
        }
        
        self.isLoading = false
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
                        artworkURL: track.coverURL
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
