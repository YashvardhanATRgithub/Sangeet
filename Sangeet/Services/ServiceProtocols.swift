import Foundation
import AVFoundation

// MARK: - Library Scanning
protocol LibraryScanService {
    func startScan(directories: [URL]) async throws
    func cancelScan()
    var isScanning: Bool { get }
}

// MARK: - Metadata
protocol MetadataService {
    func metadata(for url: URL) async throws -> Track
    func loadArtwork(for track: Track) async -> URL? // Returns local path to cached image
}

// MARK: - Database / Persistence
protocol DatabaseLayer {
    func saveTrack(_ track: Track) async throws
    func fetchAllTracks() async throws -> [Track]
    func fetchRecentTracks(limit: Int) async throws -> [Track]
    func fetchAlbums() async throws -> [Album]
    func fetchArtists() async throws -> [Artist]
    func searchTracks(query: String) async -> [Track]
    func updatePlayCount(for trackID: UUID) async
    func toggleFavorite(for trackID: UUID) async
    func fetchFavorites() async throws -> [Track]
}

// MARK: - Playback
enum PlaybackState {
    case playing
    case paused
    case stopped
    case buffering
}

enum LoopMode {
    case off
    case all
    case one
}

@MainActor
protocol PlaybackService {
    var currentTrack: Track? { get }
    var state: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var loopMode: LoopMode { get set }
    var isShuffling: Bool { get set }
    
    func play(_ track: Track)
    func pause()
    func resume()
    func stop()
    func seek(to time: TimeInterval)
    func next()
    func previous()
    func togglePlayPause()
    func toggleFavorite()
    
    // Queue Management
    func addToQueue(_ track: Track)
    func removeFromQueue(at index: Int)
}
