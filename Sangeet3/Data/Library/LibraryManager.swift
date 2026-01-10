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
        
        // Listen for new downloads to instantly update UI
        NotificationCenter.default.addObserver(
            forName: .init("DownloadDidFinish"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            // Quickly re-scan or add to tracks manually if we have full metadata
            // For now, rely on scanAllFolders which is triggered by DownloadManager, 
            // but we can also force a UI refresh of 'recentlyAdded' here if needed.
            // The isScanning flag will handle some UI state.
            
            // Just ensure we notify observers
            self.objectWillChange.send()
        }
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
    

    
    // MARK: - Helper Methods
    
    /// Check if a track exists in library with fuzzy matching
    func hasTrack(title: String, artist: String) -> Bool {
        // 1. Try exact match (fast)
        let exactMatch = tracks.contains {
            $0.title.caseInsensitiveCompare(title) == .orderedSame &&
            $0.artist.caseInsensitiveCompare(artist) == .orderedSame &&
            !$0.isRemote
        }
        if exactMatch { return true }
        
        // 2. Fuzzy match
        // Often Tidal titles have "(feat. X)" or "Remastered" that local files might miss or have differently
        // Or "The Beatles" vs "Beatles"
        
        let targetTitle = sanitizeString(title)
        let targetArtist = sanitizeString(artist)
        
        return tracks.contains { local in
            if local.isRemote { return false }
            
            let localTitle = sanitizeString(local.title)
            let localArtist = sanitizeString(local.artist)
            
            // Check if one contains the other (e.g. "Orbit" inside "Orbit (Remix)")
            let titleMatch = localTitle.contains(targetTitle) || targetTitle.contains(localTitle)
            let artistMatch = localArtist.contains(targetArtist) || targetArtist.contains(localArtist)
            
            return titleMatch && artistMatch
        }
    }
    
    private func sanitizeString(_ str: String) -> String {
        var s = str.lowercased()
        
        // Remove parens and brackets: "Song (From X)" -> "Song "
        s = s.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
        
        // Remove common suffixes often found in titles
        // "Song feat. X", "Song from X", "Song Remix", "Song Version"
        // Note: We use a loop or multiple replacements to catch them all.
        // The regex ` (feat\\.|from|track|remix|version).*` is good but might miss edge cases.
        s = s.replacingOccurrences(of: " feat\\..*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " from .*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " remix.*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " version.*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "the ", with: "")
        
        // Remove non-alphanumeric (keep spaces for splitting?) No, simple filter is better.
        // "Aayi Nai" -> "aayinai"
        let alphanum = s.filter { $0.isLetter || $0.isNumber }
        
        return alphanum.isEmpty ? s : alphanum
    }
    
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
    
    // Create default ~/Music/Sangeet folder
    func createDefaultFolder() async -> URL? {
        // 1. Get Music Directory
        guard let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first else { return nil }
        
        let target = musicDir.appendingPathComponent("Sangeet")
        
        // 2. Create if needed
        if !FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } catch {
                print("[LibraryManager] Failed to create default folder: \(error)")
                return nil
            }
        }
        
        // 3. Register
        if !folders.contains(target) {
            await addFolder(url: target)
        }
        
        return target
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
        // 1. Check if track is already in library (by ID)
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            // Track Exists
            tracks[index].isFavorite.toggle()
            let newValue = tracks[index].isFavorite
            
            // Smart Download: If marking as Favorite AND it's a Remote track -> Download it
            if newValue && tracks[index].isRemote {
                print("[LibraryManager] Smart Favorite: Auto-downloading '\(track.title)'")
                triggerDownload(for: tracks[index])
            }
            
            // Interaction & DB Update
            if newValue {
                RecommendationEngine.shared.recordInteraction(for: track, type: .liked)
            } else {
                RecommendationEngine.shared.recordInteraction(for: track, type: .unliked)
            }
            
            DatabaseManager.shared.writeAsync { db in
                let record = TrackRecord(from: self.tracks[index])
                try record.update(db)
            }
        } else {
            // 2. Track NOT in library (e.g. from Search/Trending)
            // Add to library, Mark Favorite, and Download
            print("[LibraryManager] Smart Favorite: Adding & Downloading new track '\(track.title)'")
            
            var newTrack = track
            newTrack.isFavorite = true
            newTrack.dateAdded = Date()
            
            // Add to memory
            tracks.append(newTrack)
            rebuildIndexes()
            
            // Add to DB
            DatabaseManager.shared.writeAsync { db in
                try TrackRecord(from: newTrack).insert(db)
            }
            
            // Trigger Download if Remote
            if newTrack.isRemote {
                triggerDownload(for: newTrack)
            }
            
            RecommendationEngine.shared.recordInteraction(for: newTrack, type: .liked)
        }
    }
    
    private func triggerDownload(for track: Track) {
        guard let url = track.fileURL.absoluteString.removingPercentEncoding,
              url.starts(with: "tidal://"),
              let idStr = track.fileURL.host,
              let id = Int(idStr) else { return }
        
        // Construct Proxy TidalTrack
        // We assume valid metadata is present in the Track object
        let artistObj = TidalArtist(id: 0, name: track.artist)
        let albumObj = TidalAlbum(id: 0, title: track.album, cover: nil) // We don't need cover ID for download if we have cover URL?
        // Actually DownloadManager uses `track.coverURL` which is computed from `track.album.cover`.
        // The `Track` object stores `artworkData` or we might fetch it?
        // Wait, `DownloadManager` expects `TidalTrack`. `TidalTrack` computes coverURL from `album.cover` path.
        // `Track` doesn't store the specific Tidal cover ID.
        
        // Let's create a partial TidalTrack.
        // DownloadManager uses: id, title, artist.name, album.title, coverURL (optional).
        
        // If we don't have the cover path, we might miss the cover art in the download unless we fetch full metadata.
        // For "Smart Favorites", speed is key. We can download audio first.
        // OR: We can construct `TidalTrack` better if the original `Track` came from `TidalTrack` conversion.
        // But `Track` struct loses the specific Tidal cover ID.
        
        let tidalTrack = TidalTrack(
            id: id,
            title: track.title,
            duration: Int(track.duration),
            artist: artistObj,
            artists: [artistObj],
            album: albumObj,
            releaseDate: nil,
            popularity: nil
        )
        
        DownloadManager.shared.download(track: tidalTrack)
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
    
    /// Delete a track from disk, database, and memory
    func deleteTrack(_ track: Track) {
        // 1. Remove from memory immediately for instant UI feedback
        tracks.removeAll { $0.id == track.id }
        rebuildIndexes()
        
        // 2. Delete from database
        DatabaseManager.shared.writeAsync { db in
            try TrackRecord
                .filter(Column("id") == track.id.uuidString)
                .deleteAll(db)
            
            // Also remove from any playlists
            try PlaylistTrackRecord
                .filter(Column("trackId") == track.id.uuidString)
                .deleteAll(db)
        }
        
        // 3. Delete file from disk (only for local files)
        if !track.isRemote {
            let fileURL = track.fileURL
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
            
            do {
                try FileManager.default.removeItem(at: fileURL)
                print("[LibraryManager] Deleted file: \(fileURL.lastPathComponent)")
                
                // Also delete any sidecar files (artwork, metadata)
                let basePath = fileURL.deletingPathExtension()
                let sidecarExtensions = ["jpg", "png", "json"]
                for ext in sidecarExtensions {
                    let sidecarURL = basePath.appendingPathExtension(ext)
                    try? FileManager.default.removeItem(at: sidecarURL)
                }
            } catch {
                print("[LibraryManager] Delete file error: \(error)")
            }
        }
        
        // 4. Notify UI
        objectWillChange.send()
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
                    // 1. Ensure Track exists in DB (especially for Remote tracks)
                    // If it's a Tidal track, it might not be in our DB yet.
                    let trackRecord = TrackRecord(from: track)
                    // Use upsert mechanism (insert or replace)
                    if try TrackRecord.filter(Column("id") == track.id.uuidString).fetchCount(db) == 0 {
                        try trackRecord.insert(db)
                    }
                    
                    // 2. Check if track already exists in playlist
                    let existing = try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlist.id)
                        .filter(Column("trackId") == track.id.uuidString)
                        .fetchCount(db)
                    
                    guard existing == 0 else {
                        print("[LibraryManager] Track already in playlist: \(playlist.name)")
                        return
                    }
                    
                    // 3. Get max position
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
                    // We must also refresh the main tracks list if we added a new remote track?
                    // No, generally we only show local tracks in "Library", but playlists can have remote.
                    // But we likely need to reload the specific playlist view.
                    self.objectWillChange.send()
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
    
    // MARK: - Smart Queue Recommendations
    
    /// Fast: Returns top tracks for the seed artist immediately
    /// excludeTracks: List of tracks to strictly exclude (e.g. current queue + detailed history)
    func getFastRecommendations(for seedTrack: Track, exclude: [Track] = []) async -> [Track] {
        print("[LibraryManager] Smart Queue (Fast): Fetching Top Tracks for '\(seedTrack.artist)'")
        do {
            let query = seedTrack.artist
            let results = try await TidalDLService.shared.search(query: query)
            
            // Build exclusion set (Titles lowercased)
            let excludedTitles = Set(exclude.map { sanitizeString($0.title) })
            let seedTitle = sanitizeString(seedTrack.title)
            
            let filtered = results.filter { candidate in
                let candTitle = sanitizeString(candidate.title)
                
                // 1. Strict Self Exclusion
                if candTitle == seedTitle { return false }
                if candTitle.contains(seedTitle) || seedTitle.contains(candTitle) { return false }
                
                // 2. Queue Exclusion
                if excludedTitles.contains(candTitle) { return false }
                
                return true
            }
            
            // Increased to 5
            return resolveTracks(Array(filtered.prefix(5)))
        } catch {
            print("[LibraryManager] Smart Queue (Fast) Error: \(error)")
            return []
        }
    }
    
    /// Deep: Returns a mix of Track Radio (Mood/Genre) OR Similar Artists
    func getDeepRecommendations(for seedTrack: Track, exclude: [Track] = []) async -> [Track] {
        print("[LibraryManager] Smart Queue (Deep): Generating mix for '\(seedTrack.title)'")
        
        let excludedTitles = Set(exclude.map { sanitizeString($0.title) })
        let seedTitle = sanitizeString(seedTrack.title)
        
        // Helper to filter and deduplicate
        let filterCandidates: ([TidalTrack]) -> [TidalTrack] = { candidates in
            var seen = Set<String>()
            return candidates.filter { candidate in
                let candTitle = self.sanitizeString(candidate.title)
                
                // 1. Check against Seed and Excludes
                if candTitle == seedTitle { return false }
                if candTitle.contains(seedTitle) || seedTitle.contains(candTitle) { return false }
                if excludedTitles.contains(candTitle) { return false }
                
                // 2. Check internal duplicates (e.g. "Song" vs "Song (OST)")
                if seen.contains(candTitle) { return false }
                seen.insert(candTitle)
                
                return true
            }
        }
        
        var rawCandidates: [Track] = []
        
        // 1. Try Track Radio
        if seedTrack.isRemote, let seedID = Int(seedTrack.fileURL.host ?? "") {
             do {
                 let radioTracks = try await TidalDLService.shared.getTrackRadio(trackID: seedID)
                 
                 // VARIETY CHECK:
                 // If Track Radio is dominated by the same artist, we MUST mix in Similar Artists.
                 let uniqueRadio = filterCandidates(radioTracks)
                 let seedArtistNorm = sanitizeString(seedTrack.artist)
                 
                 let sameArtistCount = uniqueRadio.filter { sanitizeString($0.artistName) == seedArtistNorm }.count
                 let varietyRatio = Double(sameArtistCount) / Double(max(1, uniqueRadio.count))
                 
                 if !radioTracks.isEmpty && varietyRatio < 0.4 {
                     // Good Variety: Use Radio directly
                     print("[LibraryManager] Smart Queue (Deep): Using Track Radio (Values: \(radioTracks.count), Variety: \(1.0 - varietyRatio))")
                     rawCandidates = resolveTracks(Array(uniqueRadio.prefix(25)))
                 } else {
                     // Low Variety or Empty: We need to mix in Similar Artists
                     print("[LibraryManager] Smart Queue (Deep): Track Radio too homogenous (\(Int(varietyRatio * 100))% same artist). Mixing in Similar Artists.")
                     
                     // Keep some radio tracks (Max 3 from seed artist)
                     // Low Variety or Empty: We need to mix in Similar Artists
                     print("[LibraryManager] Smart Queue (Deep): Track Radio too homogenous (\(Int(varietyRatio * 100))% same artist). Mixing in Similar Artists.")
                     
                     // Keep more radio tracks as backup (Max 10 from seed artist)
                     let radioFiltered = uniqueRadio.filter { sanitizeString($0.artistName) != seedArtistNorm }
                     let radioSame = uniqueRadio.filter { sanitizeString($0.artistName) == seedArtistNorm }.prefix(10)
                     
                     rawCandidates = resolveTracks(Array(radioFiltered + radioSame))
                 }
             } catch {
                 print("[LibraryManager] Smart Queue (Deep): Track Radio unavailable.")
             }
        }
        
        let radioBackup = rawCandidates // Store what we found from Radio for fallback
        
        // 2. Similar Artists Injection (If needed)
        // If we have < 10 candidates after Radio, or if we ignored Radio due to low variety
        if rawCandidates.count < 15 {
            do {
                // Get Artist ID
                var artistID: Int?
                if seedTrack.isRemote, let t = try? await TidalDLService.shared.search(query: "\(seedTrack.title) \(seedTrack.artist)").first {
                     artistID = t.artist?.id ?? t.artists?.first?.id
                } else if let t = try? await TidalDLService.shared.search(query: seedTrack.artist).first {
                    artistID = t.artist?.id ?? t.artists?.first?.id
                }
                
                if let id = artistID {
                    let similarArtists = try await TidalDLService.shared.getSimilarArtists(id: id)
                    
                    var similarCandidates: [TidalTrack] = []
                    
                    await withTaskGroup(of: [TidalTrack].self) { group in
                        for artist in similarArtists.prefix(7) { 
                             group.addTask {
                                do {
                                    // Fetch top tracks for this similar artist
                                    let tracks = try await TidalDLService.shared.search(query: artist.name)
                                    return Array(tracks.prefix(3))
                                } catch { return [] }
                            }
                        }
                        
                        for await tracks in group {
                            similarCandidates.append(contentsOf: tracks)
                        }
                    }
                    
                    if !similarCandidates.isEmpty {
                         let uniqueSimilar = filterCandidates(similarCandidates)
                         let resolvedSimilar = resolveTracks(uniqueSimilar)
                         
                         // Merge
                         if rawCandidates.isEmpty {
                             rawCandidates = resolvedSimilar
                         } else {
                             // Interleave / Append
                             rawCandidates.append(contentsOf: resolvedSimilar)
                         }
                    } else {
                        // Similar Artists returned empty (Maybe API issue)
                        // If we aggressively filtered Radio earlier, RESTORE IT!
                        if rawCandidates.count < 5, let radioTracks = try? await TidalDLService.shared.getTrackRadio(trackID: Int(seedTrack.fileURL.host ?? "") ?? 0) {
                            print("[LibraryManager] Similar Artists failed. Restoring original Track Radio.")
                            let unique = filterCandidates(radioTracks)
                            rawCandidates = resolveTracks(Array(unique.prefix(25)))
                        }
                    }
                }
            } catch {
                 print("[LibraryManager] Similar Artists fallback failed: \(error)")
                 // Restore Backup if needed
                 if rawCandidates.count < 5 && radioBackup.count > rawCandidates.count {
                      rawCandidates = radioBackup
                 }
            }
        }
        
        // 3. Final Shuffle & Recommendations
        if !rawCandidates.isEmpty {
            // Shuffle to mix Radio vs Similar
            rawCandidates.shuffle()
            
            // Apply Recommendation Engine Ranking
            print("[LibraryManager] Ranking \(rawCandidates.count) candidates with Recommendation Engine...")
            // We request rank, but engine might prioritize "Liked" artists.
            let ranked = await RecommendationEngine.shared.rank(candidates: rawCandidates)
            
            // 4. Final Variety Enforcer (Post-Ranking)
            // Ensure no more than 3 songs from Seed Artist appear in total.
            let seedArtistNorm = sanitizeString(seedTrack.artist)
            
            // Soft Limit: Try to limit to 4. If total < 5, allow more.
            var seedCount = 0
            var filtered: [Track] = []
            
            // First pass: Add non-seed songs and up to 4 seed songs
            for t in ranked {
                if sanitizeString(t.artist) == seedArtistNorm {
                    seedCount += 1
                    if seedCount > 4 { continue }
                }
                filtered.append(t)
            }
            
            // Emergency Check: If we filtered too much and have < 5 songs, put them back!
            if filtered.count < 5 {
                let currentIDs = Set(filtered.map { $0.id })
                for t in ranked {
                    if !currentIDs.contains(t.id) {
                        filtered.append(t)
                        if filtered.count >= 10 { break }
                    }
                }
            }
            
            return filtered
        }
        
        return []
    }
    
    // Deterministic UUID generation
    private func resolveTracks(_ tidalTracks: [TidalTrack]) -> [Track] {
        var references: [Track] = []
        for tidalTrack in tidalTracks {
            if let localTrack = findLocalTrack(title: tidalTrack.title, artist: tidalTrack.artistName) {
                references.append(localTrack)
            } else {
                // Generate Deterministic UUID based on Tidal ID
                // UUID from string hash is reliable for duplicates
                let uuidString = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", tidalTrack.id))") ?? UUID()
                
                references.append(Track(
                    id: uuidString,
                    title: tidalTrack.title,
                    artist: tidalTrack.artistName,
                    album: tidalTrack.albumName,
                    duration: TimeInterval(tidalTrack.duration),
                    fileURL: URL(string: "tidal://\(tidalTrack.id)")!,
                    artworkURL: tidalTrack.coverURL,
                    externalID: String(tidalTrack.id)
                ))
            }
        }
        return references
    }
    
    /// Helper to find local track fuzzy
    private func findLocalTrack(title: String, artist: String) -> Track? {
        return tracks.first { track in
             !track.isRemote &&
             sanitizeString(track.title) == sanitizeString(title) &&
             sanitizeString(track.artist) == sanitizeString(artist)
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
    
    /// Check which playlists a track belongs to
    func getPlaylistIds(for track: Track) -> Set<String> {
        do {
            let ids = try DatabaseManager.shared.read { db in
                try PlaylistTrackRecord
                    .filter(Column("trackId") == track.id.uuidString)
                    .fetchAll(db)
                    .map { $0.playlistId }
            }
            return Set(ids)
        } catch {
            print("[LibraryManager] Failed to get playlist IDs for track: \(error)")
            return []
        }
    }
    
    // MARK: - Trending / Top Songs
    
    @Published var topSongs: [TidalTrack] = []
    @Published var isLoadingTopSongs = false
    
    // Explicitly for India
    @Published var trendingIndiaSongs: [TidalTrack] = []
    
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
        if topSongs.isEmpty { isLoadingTopSongs = true }
        
        // 1. Fetch High-Quality curated list from iTunes RSS
        let countryCode = Locale.current.region?.identifier ?? "us"
        let iTunesSongs = await fetchITunesTrends(country: countryCode)
        
        // 2. Resolve to Tidal Tracks in parallel
        let resolvedTracks = await resolveToTidal(iTunesSongs)
        
        await MainActor.run {
            if !resolvedTracks.isEmpty {
                self.topSongs = resolvedTracks
            }
            self.isLoadingTopSongs = false
        }
    }
    
    func fetchTrendingIndia() async {
        // 1. Fetch India Trends
        let iTunesSongs = await fetchITunesTrends(country: "in")
        
        // 2. Resolve to Tidal
        let resolvedTracks = await resolveToTidal(iTunesSongs)
        
        await MainActor.run {
            if !resolvedTracks.isEmpty {
                self.trendingIndiaSongs = resolvedTracks
            }
        }
    }
    
    // MARK: - Hybrid Resolution Logic
    
    private func fetchITunesTrends(country: String) async -> [ITunesSimpleSong] {
        let urlString = "https://itunes.apple.com/\(country)/rss/topsongs/limit=15/json" // Fetch top 15
        guard let url = URL(string: urlString) else { return [] }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let feed = try JSONDecoder().decode(ITunesFeedRoot.self, from: data)
            return feed.feed.entry.map {
                ITunesSimpleSong(title: $0.title.label, artist: $0.artist.label)
            }
        } catch {
            print("[LibraryManager] iTunes RSS Error: \(error)")
            return []
        }
    }
    
    private func resolveToTidal(_ songs: [ITunesSimpleSong]) async -> [TidalTrack] {
        await withTaskGroup(of: TidalTrack?.self) { group in
            for song in songs {
                group.addTask {
                    let query = "\(song.title) \(song.artist)"
                    do {
                        let results = try await TidalDLService.shared.search(query: query)
                        // Heuristic: Try to find exact match
                        return results.first
                    } catch {
                        return nil
                    }
                }
            }
            
            var resolved: [TidalTrack] = []
            for await track in group {
                if let track = track {
                    resolved.append(track)
                }
            }
            // Sort by relevance? Hard since async returns largely random order. 
            // Ideally we'd map indices but for "Trending" a bit of shuffle is fine.
            return resolved
        }
    }
    
    // Removed legacy iTunes fetch methods
    
    // MARK: - Caching Helpers
    
    // MARK: - Caching Helpers
    
    // Updated to cache TidalTrack instead of ITunesSong
    private func saveTrendingCache(_ songs: [TidalTrack], url: URL) {
        Task.detached(priority: .background) {
            do {
                let data = try JSONEncoder().encode(songs)
                try data.write(to: url)
            } catch {
                print("[LibraryManager] Cache save error: \(error)")
            }
        }
    }
    
    private func loadTrendingCache(url: URL) -> [TidalTrack]? {
        do {
            let data = try Data(contentsOf: url)
            let songs = try JSONDecoder().decode([TidalTrack].self, from: data)
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

// MARK: - Private Helper Structs for Hybrid Fetching

struct ITunesSimpleSong {
    let title: String
    let artist: String
}

private struct ITunesFeedRoot: Codable {
    let feed: ITunesFeed
}

private struct ITunesFeed: Codable {
    let entry: [ITunesEntry]
}

private struct ITunesEntry: Codable {
    let title: ITunesLabel
    let artist: ITunesLabel
    
    enum CodingKeys: String, CodingKey {
        case title = "im:name"
        case artist = "im:artist"
    }
}

private struct ITunesLabel: Codable {
    let label: String
}



// MARK: - Recommendation Engine

enum UserInteractionType {
    case liked
    case unliked
    case playedFully
    case skippedImmediate // < 10s
    case skippedEarly     // < 30s
}

/// A local "Lightweight" ML Engine that ranks tracks based on User Affinity.
class RecommendationEngine {
    static let shared = RecommendationEngine()
    
    struct TasteProfile: Codable {
        /// Artist Name -> Affinity Score (Higher is better)
        var artistScores: [String: Double] = [:]
    }
    
    private var profile: TasteProfile
    private let queue = DispatchQueue(label: "com.sangeet.recommendation", qos: .background)
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: "userTasteProfile"),
           let decoded = try? JSONDecoder().decode(TasteProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = TasteProfile()
        }
    }
    
    func recordInteraction(for track: Track, type: UserInteractionType) {
        queue.async {
            self.updateScore(for: track.artist, type: type)
            self.saveProfile()
        }
    }
    
    func rank(candidates: [Track]) async -> [Track] {
        let currentProfile = self.profile
        return candidates.sorted { trackA, trackB in
            let scoreA = self.calculateScore(for: trackA, profile: currentProfile)
            let scoreB = self.calculateScore(for: trackB, profile: currentProfile)
            return scoreA > scoreB
        }
    }
    
    private func updateScore(for artist: String, type: UserInteractionType) {
        let key = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var current = profile.artistScores[key] ?? 0.0
        
        switch type {
        case .liked: current += 5.0
        case .unliked: current -= 5.0
        case .playedFully: current += 1.0
        case .skippedImmediate: current -= 3.0
        case .skippedEarly: current -= 1.0
        }
        
        current = max(-20.0, min(50.0, current))
        profile.artistScores[key] = current
        print("[RecommendationEngine] Updated score for '\(artist)': \(current)")
    }
    
    private func calculateScore(for track: Track, profile: TasteProfile) -> Double {
        let key = track.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let affinity = profile.artistScores[key] ?? 0.0
        let noise = Double.random(in: 0...0.1)
        return affinity + noise
    }
    
    private func saveProfile() {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "userTasteProfile")
        }
    }
}
