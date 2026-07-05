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
    nonisolated static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "ogg", "opus"
    ]

    nonisolated static func isSupportedAudioFile(_ url: URL) -> Bool {
        url.isFileURL && supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Singleton
    static let shared = LibraryManager()

    private init() {
        Task { await setupLibrary() }

        // Re-sync when the user returns to the app: catches files added to
        // subfolders, which the per-folder monitors can't observe.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.folders.isEmpty else { return }
                await self.scanAllFolders()
            }
        }
    }

    // MARK: - Database Loading

    private func setupLibrary() async {
        // Load folders from DB
        let folderRecords = try? DatabaseManager.shared.read { db in
            try FolderRecord.fetchAll(db)
        }

        var resolvedFolders: [URL] = []
        for record in folderRecords ?? [] {
            if let bookmark = record.bookmark {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    // Hold security-scoped access for the app's lifetime.
                    // Without this the sandbox blocks every file under the
                    // folder after a relaunch (playback, scanning, monitoring).
                    beginPersistentAccess(url)
                    resolvedFolders.append(url)
                    startMonitoring(folder: url)
                    // Refresh stale bookmarks so access keeps working next launch
                    if isStale {
                        refreshBookmark(for: url)
                    }
                } else {
                    // Bookmark failed to resolve; fall back to the stored path
                    let url = record.toURL()
                    resolvedFolders.append(url)
                    startMonitoring(folder: url)
                }
            } else {
                let url = record.toURL()
                resolvedFolders.append(url)
                startMonitoring(folder: url)
            }
        }

        self.folders = resolvedFolders

        // Load tracks from database
        let trackRecords = try? DatabaseManager.shared.read { db in
            try TrackRecord.fetchAll(db: db)
        }

        self.tracks = trackRecords?.map { $0.toTrack() } ?? []
        self.tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        rebuildIndexes()

        await loadPlaylists()

        // Scan folders to detect new/removed files
        if !folders.isEmpty {
            Task.detached(priority: .utility) { [weak self] in
                await self?.scanAllFolders()
            }
        }
    }

    /// Folders we hold security-scoped access to (kept for the app's lifetime)
    private var activeScopedFolders: Set<URL> = []

    private func beginPersistentAccess(_ url: URL) {
        guard !activeScopedFolders.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() {
            activeScopedFolders.insert(url)
        }
    }

    private func endPersistentAccess(_ url: URL) {
        if activeScopedFolders.remove(url) != nil {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func refreshBookmark(for url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        let path = url.path
        DatabaseManager.shared.writeAsync { db in
            try db.execute(
                sql: "UPDATE folder SET bookmark = ? WHERE path = ?",
                arguments: [bookmarkData, path]
            )
        }
    }

    // MARK: - Folders

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
                    await addFolder(url: url)
                }
            }
        }
    }

    // Create default ~/Music/Sangeet folder
    func createDefaultFolder() async -> URL? {
        guard let musicDir = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first else { return nil }

        let target = musicDir.appendingPathComponent("Sangeet")

        if !FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            } catch {
                print("[LibraryManager] Failed to create default folder: \(error)")
                return nil
            }
        }

        if !folders.contains(target) {
            await addFolder(url: target)
        }

        return target
    }

    // Programmatic add folder
    func addFolder(url: URL) async {
        guard !folders.contains(url) else { return }

        await addFolderToDatabase(url)
        beginPersistentAccess(url)
        folders.append(url)
        startMonitoring(folder: url)
        await scanFolder(url)
    }

    private func addFolderToDatabase(_ url: URL) async {
        do {
            let bookmarkData = try? url.bookmarkData(
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
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"

        folders.removeAll { $0 == url }
        tracks.removeAll { $0.fileURL.path.hasPrefix(prefix) || $0.fileURL.path == url.path }
        rebuildIndexes()

        stopMonitoring(folder: url)
        endPersistentAccess(url)

        // Remove from database (all tracks under the folder, including subfolders)
        let folderPath = url.path
        DatabaseManager.shared.writeAsync { db in
            try FolderRecord.delete(path: folderPath, db: db)
            let records = try TrackRecord.fetchAll(db: db)
            let idsToDelete = records
                .filter { $0.filePath.hasPrefix(prefix) || $0.filePath == folderPath }
                .map { $0.id }
            if !idsToDelete.isEmpty {
                try TrackRecord
                    .filter(idsToDelete.contains(Column("id")))
                    .deleteAll(db)
            }
        }
    }

    // MARK: - Folder Monitoring

    private var folderMonitors: [URL: FolderMonitor] = [:]
    private var pendingFolderScans: Set<URL> = []

    private func startMonitoring(folder: URL) {
        stopMonitoring(folder: folder)

        let monitor = FolderMonitor(url: folder)
        monitor.onDidChange = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleScan(for: folder)
            }
        }
        monitor.start()
        folderMonitors[folder] = monitor
    }

    /// Debounces file-system events: at most one pending scan per folder.
    private func scheduleScan(for folder: URL) {
        guard !pendingFolderScans.contains(folder) else { return }
        pendingFolderScans.insert(folder)

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            pendingFolderScans.remove(folder)
            await scanFolder(folder)
        }
    }

    private func stopMonitoring(folder: URL) {
        folderMonitors[folder]?.stop()
        folderMonitors[folder] = nil
    }

    // MARK: - Scanning

    private var foldersBeingScanned: Set<URL> = []

    func scanAllFolders() async {
        isScanning = true
        scanProgress = "Syncing library..."

        for folder in folders {
            await scanFolder(folder)
        }

        isScanning = false
        scanProgress = ""
    }

    private func scanFolder(_ url: URL) async {
        // Serialize scans per folder to avoid duplicate inserts
        guard !foldersBeingScanned.contains(url) else { return }
        foldersBeingScanned.insert(url)
        defer { foldersBeingScanned.remove(url) }

        isScanning = true
        defer { isScanning = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"

        // 1. All DB tracks under this folder (including subfolders) for pruning
        let dbTracks = (try? DatabaseManager.shared.read { db in
            try TrackRecord.fetchAll(db: db)
        })?.filter { $0.filePath.hasPrefix(prefix) } ?? []

        var dbPaths = Set(dbTracks.map { $0.filePath })

        // Paths already loaded in memory (from any folder) - prevents duplicates
        let inMemoryPaths = Set(tracks.map { $0.fileURL.path })

        // 2. Scan file system
        let audioFiles = enumerateAudioFiles(in: url)

        var newTracks: [Track] = []

        for fileURL in audioFiles {
            let path = fileURL.path

            // Known in DB: not a deletion, not new
            if dbPaths.contains(path) {
                dbPaths.remove(path)
                continue
            }

            // Already loaded in memory (e.g. overlapping folders)
            guard !inMemoryPaths.contains(path) else { continue }

            newTracks.append(createTrackFast(from: fileURL))
        }

        // 3. Prune deletions: dbPaths now contains files that no longer exist
        if !dbPaths.isEmpty {
            let pathsToRemove = dbPaths
            tracks.removeAll { pathsToRemove.contains($0.fileURL.path) }

            DatabaseManager.shared.writeAsync { db in
                try TrackRecord
                    .filter(pathsToRemove.contains(Column("filePath")))
                    .deleteAll(db)
            }
        }

        // 4. Additions
        if !newTracks.isEmpty {
            tracks.append(contentsOf: newTracks)
            tracks.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

            let records = newTracks.map { TrackRecord(from: $0) }
            DatabaseManager.shared.writeAsync { db in
                for record in records {
                    try record.save(db, onConflict: .replace)
                }
            }

            // Background metadata extraction
            let tracksToExtract = newTracks
            Task.detached(priority: .background) { [weak self] in
                await self?.extractMetadataInBackground(for: tracksToExtract)
            }
        }

        if !dbPaths.isEmpty || !newTracks.isEmpty {
            rebuildIndexes()
        }
    }

    /// Synchronous recursive enumeration of supported audio files.
    nonisolated private func enumerateAudioFiles(in url: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[LibraryManager] Failed to enumerate \(url.path)")
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                files.append(fileURL)
            }
        }
        return files
    }

    nonisolated private func createTrackFast(from url: URL) -> Track {
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

        // Use file creation date for correct "Recently Added" sorting
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
            dateAdded: dateAdded
        )
    }

    // MARK: - Metadata Extraction

    private func extractMetadataInBackground(for newTracks: [Track]) async {
        for track in newTracks {
            let accessing = track.fileURL.startAccessingSecurityScopedResource()
            defer { if accessing { track.fileURL.stopAccessingSecurityScopedResource() } }

            let metadata = await MetadataExtractor.shared.extractMetadata(from: track.fileURL)

            if let index = tracks.firstIndex(where: { $0.id == track.id }) {
                tracks[index].duration = metadata.duration
                if let title = metadata.title, !title.isEmpty, title != "Unknown" {
                    tracks[index].title = title
                }
                if let artist = metadata.artist, !artist.isEmpty, artist != "Unknown Artist" {
                    tracks[index].artist = artist
                }
                if let album = metadata.album, !album.isEmpty, album != "Unknown Album" {
                    tracks[index].album = album
                }
                if let artworkData = metadata.artworkData {
                    tracks[index].artworkData = artworkData
                }

                let record = TrackRecord(from: tracks[index])
                DatabaseManager.shared.writeAsync { db in
                    try record.update(db)
                }
            }
        }

        rebuildIndexes()
    }

    func updateTrackMetadata(track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
            rebuildIndexes()

            let record = TrackRecord(from: track)
            DatabaseManager.shared.writeAsync { db in
                try record.update(db)
            }
        }
    }

    // MARK: - Track Operations

    func toggleFavorite(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }

        tracks[index].isFavorite.toggle()
        let newValue = tracks[index].isFavorite

        if newValue {
            RecommendationEngine.shared.recordInteraction(for: track, type: .liked)
        } else {
            RecommendationEngine.shared.recordInteraction(for: track, type: .unliked)
        }

        let record = TrackRecord(from: tracks[index])
        DatabaseManager.shared.writeAsync { db in
            try record.update(db)
        }

        rebuildIndexes()
    }

    func incrementPlayCount(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }

        tracks[index].playCount += 1
        tracks[index].lastPlayed = Date()

        let record = TrackRecord(from: tracks[index])
        DatabaseManager.shared.writeAsync { db in
            try record.update(db)
        }

        rebuildIndexes()
    }

    /// Delete a track from disk, database, and memory
    func deleteTrack(_ track: Track) {
        // 1. Remove from memory immediately for instant UI feedback
        tracks.removeAll { $0.id == track.id }
        rebuildIndexes()

        // 2. Delete from database (and any playlist references)
        let trackId = track.id.uuidString
        DatabaseManager.shared.writeAsync { db in
            try TrackRecord
                .filter(Column("id") == trackId)
                .deleteAll(db)

            try PlaylistTrackRecord
                .filter(Column("trackId") == trackId)
                .deleteAll(db)
        }

        // 3. Delete file from disk
        let fileURL = track.fileURL
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.removeItem(at: fileURL)

            // Also delete any sidecar files (artwork, lyrics, metadata)
            let basePath = fileURL.deletingPathExtension()
            let sidecarExtensions = ["jpg", "png", "json", "lrc", "txt"]
            for ext in sidecarExtensions {
                let sidecarURL = basePath.appendingPathExtension(ext)
                try? FileManager.default.removeItem(at: sidecarURL)
            }
        } catch {
            print("[LibraryManager] Delete file error: \(error)")
        }
    }

    // MARK: - Favorites

    var favorites: [Track] {
        tracks.filter { $0.isFavorite }
    }

    // MARK: - Playlist Management

    @Published var playlists: [PlaylistRecord] = []

    @discardableResult
    func createPlaylist(name: String) async -> PlaylistRecord? {
        let playlist = PlaylistRecord(name: name, isSystem: false)
        do {
            _ = try DatabaseManager.shared.write { db in
                try playlist.insert(db)
            }
            await loadPlaylists()
            return playlist
        } catch {
            print("[LibraryManager] Create playlist error: \(error)")
            return nil
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
        let trackRecord = TrackRecord(from: track)
        let trackId = track.id.uuidString
        let playlistId = playlist.id

        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    // Ensure the track exists in DB
                    if try TrackRecord.filter(Column("id") == trackId).fetchCount(db) == 0 {
                        try trackRecord.insert(db)
                    }

                    // Skip if already in playlist
                    let existing = try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlistId)
                        .filter(Column("trackId") == trackId)
                        .fetchCount(db)

                    guard existing == 0 else { return }

                    // Append at the end
                    let count = try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlistId)
                        .fetchCount(db)

                    let record = PlaylistTrackRecord(
                        playlistId: playlistId,
                        trackId: trackId,
                        position: count,
                        dateAdded: Date()
                    )
                    try record.insert(db)
                }

                NotificationCenter.default.post(name: .playlistUpdated, object: playlistId)
                objectWillChange.send()
            } catch {
                print("[LibraryManager] Add to playlist error: \(error)")
            }
        }
    }

    func removeTrackFromPlaylist(_ track: Track, playlist: PlaylistRecord) {
        let trackId = track.id.uuidString
        let playlistId = playlist.id

        Task {
            do {
                _ = try DatabaseManager.shared.write { db in
                    try PlaylistTrackRecord
                        .filter(Column("playlistId") == playlistId)
                        .filter(Column("trackId") == trackId)
                        .deleteAll(db)
                }

                NotificationCenter.default.post(name: .playlistUpdated, object: playlistId)
                objectWillChange.send()
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
            self.playlists = records
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
            return trackIds.compactMap { id in
                tracks.first(where: { $0.id.uuidString == id })
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

    // MARK: - External Files (opened via Finder / "Open With")

    /// Plays audio files opened from outside the app. Files already in the
    /// library play as their library tracks; others play as one-off tracks
    /// with metadata read from the file.
    func playExternalFiles(_ urls: [URL]) async {
        var queueTracks: [Track] = []

        for url in urls {
            // Prefer the library's copy so favorites/play counts keep working
            if let existing = tracks.first(where: { $0.fileURL.path == url.path }) {
                queueTracks.append(existing)
                continue
            }

            let metadata = await MetadataExtractor.shared.extractMetadata(from: url)
            var track = metadata.toTrack()
            track.fileURL = url
            queueTracks.append(track)
        }

        guard !queueTracks.isEmpty else { return }
        PlaybackManager.shared.playQueue(tracks: queueTracks)
    }

    // MARK: - Local Recommendations (Smart Queue / Radio)

    /// Returns similar tracks from the local library, ranked by artist/album
    /// affinity and the user's taste profile. Fully offline.
    func getLocalRecommendations(for seed: Track, excluding: [Track], limit: Int) -> [Track] {
        guard limit > 0 else { return [] }

        var excludedIds = Set(excluding.map { $0.id })
        excludedIds.insert(seed.id)

        let seedArtist = sanitizeString(seed.artist)
        let seedAlbum = seed.album.lowercased()
        let seedTitle = sanitizeString(seed.title)

        // Signatures already queued (avoids "Song" vs "Song (Remastered)" dupes)
        var seenSignatures = Set(excluding.map { sanitizeString($0.title + $0.artist) })
        seenSignatures.insert(sanitizeString(seed.title + seed.artist))

        struct Candidate {
            let track: Track
            let score: Double
            let sameArtist: Bool
        }

        var candidates: [Candidate] = []
        for track in tracks {
            guard !excludedIds.contains(track.id) else { continue }

            let title = sanitizeString(track.title)
            // Skip alternate versions of the seed itself
            if title == seedTitle { continue }

            let signature = sanitizeString(track.title + track.artist)
            guard !seenSignatures.contains(signature) else { continue }
            seenSignatures.insert(signature)

            let artist = sanitizeString(track.artist)
            let sameArtist = !artist.isEmpty && artist == seedArtist

            var score = RecommendationEngine.shared.affinity(forArtist: track.artist)
            if sameArtist { score += 4 }
            if track.album.lowercased() == seedAlbum && !seedAlbum.isEmpty { score += 2 }
            if track.isFavorite { score += 2 }
            score += min(Double(track.playCount), 5) * 0.4
            score += Double.random(in: 0...2) // variety

            candidates.append(Candidate(track: track, score: score, sameArtist: sameArtist))
        }

        candidates.sort { $0.score > $1.score }

        // Variety cap: at most half the picks from the seed artist,
        // unless there's nothing else to pick from.
        let maxSameArtist = max(2, limit / 2)
        var sameArtistCount = 0
        var picks: [Track] = []
        var overflow: [Track] = []

        for candidate in candidates {
            if picks.count >= limit { break }
            if candidate.sameArtist {
                if sameArtistCount < maxSameArtist {
                    sameArtistCount += 1
                    picks.append(candidate.track)
                } else {
                    overflow.append(candidate.track)
                }
            } else {
                picks.append(candidate.track)
            }
        }

        // Backfill from overflow if the library lacks variety
        if picks.count < limit {
            picks.append(contentsOf: overflow.prefix(limit - picks.count))
        }

        return picks
    }

    nonisolated private func sanitizeString(_ str: String) -> String {
        var s = str.lowercased()

        // Remove parenthesized/bracketed qualifiers: "Song (Remastered)" -> "Song"
        s = s.replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)

        // Remove common suffixes
        s = s.replacingOccurrences(of: " feat\\..*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " from .*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " remix.*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: " version.*", with: "", options: .regularExpression)

        let alphanum = s.filter { $0.isLetter || $0.isNumber }
        return alphanum.isEmpty ? s.trimmingCharacters(in: .whitespacesAndNewlines) : alphanum
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

        // Most Listened - only tracks that were actually played
        mostListenedSongs = Array(
            tracks.filter { $0.playCount > 0 }
                .sorted { $0.playCount > $1.playCount }
                .prefix(20)
        )

        // Recently Played
        recentlyPlayedSongs = Array(
            tracks.compactMap { track -> (Track, Date)? in
                guard let lastPlayed = track.lastPlayed else { return nil }
                return (track, lastPlayed)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(25)
            .map { $0.0 }
        )
    }
}

// MARK: - Recommendation Engine

enum UserInteractionType {
    case liked
    case unliked
    case playedFully
    case skippedImmediate // < 10s
    case skippedEarly     // < 30s
}

/// A lightweight local engine that tracks artist affinity from listening behavior.
final class RecommendationEngine {
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

    /// Current affinity score for an artist (0 if unknown).
    func affinity(forArtist artist: String) -> Double {
        let key = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return queue.sync { profile.artistScores[key] ?? 0.0 }
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
    }

    private func saveProfile() {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "userTasteProfile")
        }
    }
}
