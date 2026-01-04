//
//  LibraryManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Library management with GRDB persistence
//

import Foundation
import Combine
import AppKit
import GRDB

/// Manages music library with GRDB persistence
@MainActor
final class LibraryManager: ObservableObject {
    
    // MARK: - Published State
    @Published var tracks: [Track] = []
    @Published var albums: [String: [Track]] = [:]
    @Published var artists: [String: [Track]] = [:]
    @Published var folders: [URL] = []
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    
    // Derived collections
    @Published var recentlyAddedSongs: [Track] = []
    @Published var mostListenedSongs: [Track] = []
    @Published var recentlyPlayedSongs: [Track] = []
    
    // MARK: - Supported Formats
    private let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "ogg", "opus"
    ]
    
    // MARK: - Singleton
    static let shared = LibraryManager()
    
    private init() {
        Task { await setupLibrary() }
    }
    
    // MARK: - Database Loading
    
    private func setupLibrary() async {
        // Load initial folders and tracks
        // Load folders from DB
        let folderRecords = try? DatabaseManager.shared.read { db in
            try FolderRecord.fetchAll(db)
        }
        
        var resolvedFolders: [URL] = []
        for record in folderRecords ?? [] {
            if let bookmark = record.bookmark {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale), !isStale {
                    resolvedFolders.append(url)
                    // Start monitoring
                    startMonitoring(folder: url)
                }
            } else {
                let url = record.toURL()
                resolvedFolders.append(url)
                startMonitoring(folder: url)
            }
        }
        
        await MainActor.run {
            self.folders = resolvedFolders
        }
        
        // Load tracks from database
        let trackRecords = try? DatabaseManager.shared.read { db in
            try TrackRecord.fetchAll(db: db)
        }
        
        await MainActor.run {
            self.tracks = trackRecords?.map { $0.toTrack() } ?? []
            self.rebuildIndexes()
        }
        
        // Always scan folders to detect new files
        if !folders.isEmpty {
            // Run in detached task to avoid blocking main thread initialization
            Task.detached(priority: .utility) { [weak self] in
                await self?.scanAllFolders()
            }
        }
        
        await loadPlaylists() // Ensure playlists are loaded
        
        await MainActor.run {
            self.loadInitialTrendingCache()
        }
    }
    

    
    // MARK: - Folder Management
    
    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select music folder(s) to import"
        panel.prompt = "Add Folder"
        
        if panel.runModal() == .OK {
            Task {
                for url in panel.urls {
                    if !folders.contains(url) {
                        await addFolderToDatabase(url)
                        folders.append(url)
                        startMonitoring(folder: url) // Watch for changes
                        await scanFolder(url)
                    }
                }
            }
        }
    }
    
    // Expose programmatic add folder
    func addFolder(url: URL) async {
        if !folders.contains(url) {
            await addFolderToDatabase(url)
            
            await MainActor.run {
                if !self.folders.contains(url) {
                     self.folders.append(url)
                }
            }
            
            startMonitoring(folder: url)
            await scanFolder(url)
        }
    }
    
    private func addFolderToDatabase(_ url: URL) async {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            let record = FolderRecord(url: url, bookmark: bookmarkData)
            _ = try DatabaseManager.shared.write { db in
                try record.insert(db)
            }
        } catch {
            print("[LibraryManager] Add folder error: \(error)")
        }
    }
    
    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
        tracks.removeAll { $0.fileURL.path.hasPrefix(url.path) }
        rebuildIndexes()
        
        stopMonitoring(folder: url) // Stop watching
        
        
        // Remove from database
        do {
            try DatabaseManager.shared.write { db in
                try FolderRecord.delete(path: url.path, db: db)
                try TrackRecord.deleteByFolder(url.path, db: db)
            }
        } catch {
            print("[LibraryManager] Remove folder error: \(error)")
        }
    }
    
    // MARK: - Folder Monitoring
    
    private var folderMonitors: [URL: FolderMonitor] = [:]
    
    private func startMonitoring(folder: URL) {
        // Stop existing if any
        stopMonitoring(folder: folder)
        
        let monitor = FolderMonitor(url: folder)
        monitor.onDidChange = { [weak self] in
            // Debounce scan: Wait 2 seconds
            // In a real app, use a Debouncer. For now, we'll just trigger task.
            // DispatchSource already coalesces events somewhat.
            Task {
                try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
                await self?.scanFolder(folder)
            }
        }
        monitor.start()
        folderMonitors[folder] = monitor
    }
    
    private func stopMonitoring(folder: URL) {
        folderMonitors[folder]?.stop()
        folderMonitors[folder] = nil
    }

    // MARK: - Scanning
    
    func scanAllFolders() async {
        await MainActor.run {
            self.isScanning = true
            self.scanProgress = "Syncing library..."
        }
        
        for folder in folders {
            await scanFolder(folder)
        }
        
        await MainActor.run {
            self.isScanning = false
            self.scanProgress = ""
        }
    }
    
    private func scanFolder(_ url: URL) async {
        await MainActor.run {
            self.isScanning = true
        }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        // 1. Get ALL DB tracks for this folder (for pruning)
        let dbTracks = (try? DatabaseManager.shared.read { db in
            try TrackRecord
                .filter(Column("folderPath") == url.path)
                .fetchAll(db)
        }) ?? []
        
        var dbPaths = Set(dbTracks.map { $0.filePath })
        
        // 2. Scan File System
        let fileManager = FileManager.default
        print("[LibraryManager] enumerating: \(url.path)")
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[LibraryManager] Failed to create enumerator for \(url.path)")
            return
        }
        
        // Manual iteration to debug
        var allFiles: [URL] = []
        for case let fileURL as URL in enumerator {
            allFiles.append(fileURL)
        }
        
        print("[LibraryManager] Scanning \(url.path): Found \(allFiles.count) files")
        if allFiles.isEmpty {
             // Fallback check
             let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
             print("[LibraryManager] Fallback check: contentsOfDirectory found \(contents?.count ?? 0) items")
        }
        
        var newTracks: [Track] = []
        var foundPaths: Set<String> = []
        
        for fileURL in allFiles {
            let ext = fileURL.pathExtension.lowercased()
            // Debug print for first few files
            if foundPaths.count < 3 { print("[LibraryManager] Checking: \(fileURL.lastPathComponent) (\(ext))") }
            
            guard supportedExtensions.contains(ext) else { continue }
            
            let path = fileURL.path
            foundPaths.insert(path)
            
            // If exists in DB, remove from dbPaths (so remaining dbPaths are deletions)
            if dbPaths.contains(path) {
                dbPaths.remove(path)
                continue
            }
            
            // It's a new track
            let track = createTrackFast(from: fileURL)
            newTracks.append(track)
            print("[LibraryManager] Created new track: \(track.title)")
        }
        
        // 3. Process Deletions (Pruning)
        // dbPaths now contains only paths that are in DB but NOT in File System
        if !dbPaths.isEmpty {
            await MainActor.run {
                // Remove from memory
                self.tracks.removeAll { dbPaths.contains($0.fileURL.path) }
            }
            // Remove from DB
            DatabaseManager.shared.writeAsync { db in
                try TrackRecord
                    .filter(dbPaths.contains(Column("filePath")))
                    .deleteAll(db)
            }
            print("[LibraryManager] Pruned \(dbPaths.count) deleted songs from \(url.lastPathComponent)")
        }
        
        // 4. Process Additions
        if !newTracks.isEmpty {
            await MainActor.run {
                self.tracks.append(contentsOf: newTracks)
                // Sort by Title for now; Date Added view handles its own sort
                self.tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                self.rebuildIndexes()
            }
            
            // Save to database
            DatabaseManager.shared.writeAsync { db in
                for track in newTracks {
                    try TrackRecord(from: track).insert(db)
                }
            }
            
            print("[LibraryManager] Added \(newTracks.count) new songs from \(url.lastPathComponent)")
            
            // Background metadata extraction
            Task.detached(priority: .background) { [weak self] in
                await self?.extractMetadataInBackground(for: newTracks)
            }
        }
        
        // Update indexes if we deleted stuff
        if !dbPaths.isEmpty || !newTracks.isEmpty {
            await MainActor.run { self.rebuildIndexes() }
        }
        
        await MainActor.run {
            self.isScanning = false
        }
    }
    
    private func createTrackFast(from url: URL) -> Track {
        let filename = url.deletingPathExtension().lastPathComponent
        let parts = filename.components(separatedBy: " - ")
        
        let title: String
        let artist: String
        
        if parts.count >= 2 {
            artist = parts[0].trimmingCharacters(in: .whitespaces)
            title = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
        } else {
            title = filename
            artist = "Unknown Artist"
        }
        
        let album = url.deletingLastPathComponent().lastPathComponent
        
        // Get Creation Date for correct "Recently Added" sorting
        var dateAdded = Date()
        if let resources = try? url.resourceValues(forKeys: [.creationDateKey]),
           let creationDate = resources.creationDate {
            dateAdded = creationDate
        }
        
        return Track(
            title: title,
            artist: artist,
            album: album,
            duration: 0,
            fileURL: url,
            dateAdded: dateAdded // Use actual file creation date
        )
    }
    
    // MARK: - Metadata Extraction
    
    private func extractMetadataInBackground(for newTracks: [Track]) async {
        for track in newTracks {
            let accessing = track.fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { track.fileURL.stopAccessingSecurityScopedResource() } }
            
            let metadata = await MetadataExtractor.shared.extractMetadata(from: track.fileURL)
            
            // Update in memory
            await MainActor.run {
                if let index = self.tracks.firstIndex(where: { $0.id == track.id }) {
                    self.tracks[index].duration = metadata.duration
                    if let title = metadata.title, !title.isEmpty, title != "Unknown" {
                        self.tracks[index].title = title
                    }
                    if let artist = metadata.artist, !artist.isEmpty, artist != "Unknown Artist" {
                        self.tracks[index].artist = artist
                    }
                    if let album = metadata.album, !album.isEmpty, album != "Unknown Album" {
                        self.tracks[index].album = album
                    }
                    if let artworkData = metadata.artworkData {
                        self.tracks[index].artworkData = artworkData
                    }
                    
                    // Update in database
                    let updatedTrack = self.tracks[index]
                    DatabaseManager.shared.writeAsync { db in
                        let record = TrackRecord(from: updatedTrack)
                        try record.update(db)
                    }
                }
            }
        }
        
        // Rebuild indexes after metadata update
        await MainActor.run {
            self.rebuildIndexes()
        }
    }
    
    func updateTrackMetadata(track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
            rebuildIndexes()
            
            DatabaseManager.shared.writeAsync { db in
                let record = TrackRecord(from: track)
                try record.update(db)
            }
        }
    }
    
    // MARK: - Track Operations
    
    func toggleFavorite(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index].isFavorite.toggle()
            
            // Update in database
            DatabaseManager.shared.writeAsync { db in
                let record = TrackRecord(from: self.tracks[index])
                try record.update(db)
            }
        }
    }
    
    func incrementPlayCount(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index].playCount += 1
            tracks[index].lastPlayed = Date()
            
            // Update in database
            DatabaseManager.shared.writeAsync { db in
                let record = TrackRecord(from: self.tracks[index])
                try record.update(db)
            }
            
            // Trigger UI update
            rebuildIndexes()
        }
    }
    
    // MARK: - Favorites
    
    var favorites: [Track] {
        tracks.filter { $0.isFavorite }
    }
    

    
    // MARK: - Playlist Management
    
    @Published var playlists: [PlaylistRecord] = []
    
    func createPlaylist(name: String) {
        let playlist = PlaylistRecord(name: name, isSystem: false)
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try playlist.insert(db)
                }
                print("[LibraryManager] Created playlist: '\(name)'")
                await loadPlaylists()
            } catch {
                print("[LibraryManager] Create playlist error: \(error)")
            }
        }
    }
    
    func deletePlaylist(_ playlist: PlaylistRecord) {
        guard !playlist.isSystem else { return }
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try playlist.delete(db)
                }
                await loadPlaylists()
            } catch {
                print("[LibraryManager] Delete playlist error: \(error)")
            }
        }
    }
    
    func addTrackToPlaylist(_ track: Track, playlist: PlaylistRecord) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    // Check if track already exists in playlist
                    let existing = try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlist.id)
                        .filter(Column("trackId") == track.id.uuidString)
                        .fetchCount(db)
                    
                    guard existing == 0 else {
                        print("[LibraryManager] Track already in playlist: \(playlist.name)")
                        return
                    }
                    
                    // Get max position
                    let count = try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlist.id)
                        .fetchCount(db)
                    
                    let record = PlaylistTrackRecord(
                        playlistId: playlist.id,
                        trackId: track.id.uuidString,
                        position: count,
                        dateAdded: Date()
                    )
                    try record.insert(db)
                    print("[LibraryManager] Added '\(track.title)' to playlist '\(playlist.name)'")
                }
                
                // Notify UI to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .playlistUpdated, object: playlist.id)
                    self.objectWillChange.send() // Force UI update for track counts
                }
            } catch {
                print("[LibraryManager] Add to playlist error: \(error)")
            }
        }
    }
    
    func removeTrackFromPlaylist(_ track: Track, playlist: PlaylistRecord) {
        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlist.id)
                        .filter(Column("trackId") == track.id.uuidString)
                        .deleteAll(db)
                }
                print("[LibraryManager] Removed '\(track.title)' from playlist '\(playlist.name)'")
                
                // Notify UI to refresh
                await MainActor.run {
                    NotificationCenter.default.post(name: .playlistUpdated, object: playlist.id)
                    self.objectWillChange.send() // Force UI update for track counts
                }
            } catch {
                print("[LibraryManager] Remove from playlist error: \(error)")
            }
        }
    }
    
    func loadPlaylists() async {
        do {
            let records = try DatabaseManager.shared.read { db in
                try PlaylistRecord.order(Column("name")).fetchAll(db)
            }
            await MainActor.run {
                self.playlists = records
                print("[LibraryManager] Loaded \(records.count) playlists: \(records.map { $0.name })")
            }
        } catch {
            print("[LibraryManager] Load playlists error: \(error)")
        }
    }
    
    func getTracks(for playlist: PlaylistRecord) async -> [Track] {
        do {
            let trackIds = try DatabaseManager.shared.read { db in
                try PlaylistTrackRecord
                    .filter(Column("playlistId") == playlist.id)
                    .order(Column("position"))
                    .fetchAll(db)
                    .map { $0.trackId }
            }
            
            // Map IDs to in-memory tracks to preserve object identity/state
            return await MainActor.run {
                trackIds.compactMap { id in
                    self.tracks.first(where: { $0.id.uuidString == id })
                }
            }
        } catch {
            print("[LibraryManager] Get playlist tracks error: \(error)")
            return []
        }
    }
    
    func getTrackCount(for playlist: PlaylistRecord) -> Int {
        do {
            return try DatabaseManager.shared.read { db in
                try PlaylistTrackRecord
                    .filter(Column("playlistId") == playlist.id)
                    .fetchCount(db)
            }
        } catch {
            return 0
        }
    }
    
    // MARK: - Trending / Top Songs
    
    @Published var topSongs: [ITunesSong] = []
    @Published var isLoadingTopSongs = false
    
    // Explicitly for India
    @Published var trendingIndiaSongs: [ITunesSong] = []
    
    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }
    
    private var topSongsCacheURL: URL {
        cacheDirectory.appendingPathComponent("top_songs_world.json")
    }
    
    private var trendingIndiaCacheURL: URL {
        cacheDirectory.appendingPathComponent("trending_india.json")
    }
    
    func loadInitialTrendingCache() {
        // Load cached data immediately on app launch
        if let cachedWorld = loadTrendingCache(url: topSongsCacheURL) {
            self.topSongs = cachedWorld
        }
        
        if let cachedIndia = loadTrendingCache(url: trendingIndiaCacheURL) {
            self.trendingIndiaSongs = cachedIndia
        }
        
        // Trigger background refresh
        Task {
            await fetchTopSongs()
            await fetchTrendingIndia()
        }
    }
    
    func fetchTopSongs() async {
        // If we have no data, show loading state (unless we have cache)
        if topSongs.isEmpty {
            isLoadingTopSongs = true
        }
        
        let countryCode = Locale.current.region?.identifier ?? "us"
        let songs = await fetchSongs(country: countryCode)
        
        await MainActor.run {
            if !songs.isEmpty {
                self.topSongs = songs
                self.saveTrendingCache(songs, url: topSongsCacheURL)
            }
            self.isLoadingTopSongs = false
        }
    }
    
    func fetchTrendingIndia() async {
        let songs = await fetchSongs(country: "in")
        
        await MainActor.run {
            if !songs.isEmpty {
                self.trendingIndiaSongs = songs
                self.saveTrendingCache(songs, url: trendingIndiaCacheURL)
            }
        }
    }
    
    private func fetchSongs(country: String) async -> [ITunesSong] {
        let urlString = "https://itunes.apple.com/\(country)/rss/topsongs/limit=25/json"
        
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let feed = try JSONDecoder().decode(ITunesFeedRoot.self, from: data)
            return feed.feed.entry
        } catch {
            print("[LibraryManager] Fetch songs (\(country)) error: \(error)")
            return []
        }
    }
    
    // MARK: - Caching Helpers
    
    private func saveTrendingCache(_ songs: [ITunesSong], url: URL) {
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(songs)
                try data.write(to: url)
            } catch {
                print("[LibraryManager] Cache save error: \(error)")
            }
        }
    }
    
    private func loadTrendingCache(url: URL) -> [ITunesSong]? {
        do {
            let data = try Data(contentsOf: url)
            let songs = try JSONDecoder().decode([ITunesSong].self, from: data)
            return songs
        } catch {
            return nil
        }
    }
    
    // MARK: - Indexes
    
    private func rebuildIndexes() {
        albums.removeAll()
        artists.removeAll()
        
        for track in tracks {
            albums[track.album, default: []].append(track)
            artists[track.artist, default: []].append(track)
        }
        
        // Update derived collections
        recentlyAddedSongs = Array(tracks.sorted { $0.dateAdded > $1.dateAdded }.prefix(25))
        
        // Most Listened - Played songs first, then fill with others to reach 20
        let played = tracks.filter { $0.playCount > 0 }
            .sorted { $0.playCount > $1.playCount }
        
        // If we have fewer than 20 played songs, fill with unplayed ones (A-Z)
        if played.count < 20 {
            let needed = 20 - played.count
            let unplayed = tracks.filter { $0.playCount == 0 }
                .sorted { $0.title < $1.title }
                .prefix(needed)
            mostListenedSongs = played + Array(unplayed)
        } else {
            mostListenedSongs = Array(played.prefix(20))
        }
        
        // Recently Played
        recentlyPlayedSongs = Array(tracks.filter { $0.lastPlayed != nil }
            .sorted { $0.lastPlayed! > $1.lastPlayed! }
            .prefix(25))
    }
}

// MARK: - iTunes Feed Models

struct ITunesFeedRoot: Codable {
    let feed: ITunesFeed
}

struct ITunesFeed: Codable {
    let entry: [ITunesSong]
}

struct ITunesSong: Codable, Identifiable {
    let id: ITunesID
    let title: ITunesLabel
    let artist: ITunesLabel
    let images: [ITunesImage]
    let link: [ITunesLink]
    
    var name: String { title.label }
    var artistName: String { artist.label }
    var artworkURL: URL? {
        // Get largest image
        guard let last = images.last else { return nil }
        return URL(string: last.label)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title = "im:name"
        case artist = "im:artist"
        case images = "im:image"
        case link
    }
}

struct ITunesID: Codable, Hashable {
    let label: String
    let attributes: ITunesAttributes
}

struct ITunesAttributes: Codable, Hashable {
    let id: String // Use this for Identifiable
    
    enum CodingKeys: String, CodingKey {
        case id = "im:id"
    }
}

struct ITunesLabel: Codable {
    let label: String
}

struct ITunesImage: Codable {
    let label: String // URL string
}

struct ITunesLink: Codable {
    let attributes: LinkAttributes
}

struct LinkAttributes: Codable {
    let href: String
}

extension ITunesSong {
    // Computed id for SwiftUI Identifiable conformance
    var identity: String { id.attributes.id }
}
