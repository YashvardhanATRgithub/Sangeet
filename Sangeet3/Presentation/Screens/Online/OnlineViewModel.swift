
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
        Task {
            isLoading = true
            do {
                if let url = try await tidalService.getStreamURL(trackID: track.id) {
                    // Create a temporary Track object
                    let tempTrack = Track(
                        title: track.title,
                        artist: track.artistName,
                        album: track.albumName,
                        duration: TimeInterval(track.duration),
                        fileURL: url, // Remote URL
                        artworkData: nil,
                        artworkURL: track.coverURL
                    )
                    
                    // Start playback immediately with what we have
                    playbackManager.play(tempTrack)
                    
                    // Asynchronously load artwork data and update the track
                    if let coverURL = track.coverURL {
                        Task.detached {
                            if let data = try? Data(contentsOf: coverURL) {
                                await MainActor.run {
                                    // Update providing the track ID currently playing matches
                                    if self.playbackManager.currentTrack?.id == tempTrack.id {
                                        var updatedTrack = tempTrack
                                        updatedTrack.artworkData = data
                                        self.playbackManager.updateCurrentTrack(updatedTrack)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    errorMessage = "Could not get stream URL"
                }
            } catch {
                errorMessage = "Playback error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    func playTrending(_ song: ITunesSong) {
        // JIT Search and Play
        let query = "\(song.name) \(song.artistName)"
        print("[OnlineVM] JIT Search for: \(query)")
        
        Task {
            isLoading = true
            do {
                let results = try await tidalService.search(query: query)
                if let first = results.first {
                    playTidalTrack(first)
                } else {
                    errorMessage = "Song not found on Tidal"
                }
            } catch {
                errorMessage = "JIT Search error: \(error.localizedDescription)"
            }
            // Note: playTidalTrack handles isLoading = false
            if searchResults.isEmpty { isLoading = false } 
        }
    }
    
    func downloadTrack(_ track: TidalTrack) {
        DownloadManager.shared.download(track: track)
        // Optionally show a toast or feedback
        print("Download started for: \(track.title)")
    }
}
