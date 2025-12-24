//
//  DBLyrics.swift
//  HiFidelity
//
//  Database operations for lyrics management
//

import Foundation
import GRDB

// MARK: - Lyrics Database Operations

extension DatabaseManager {
    
    // MARK: - Create
    
    /// Insert new lyrics for a track
    func insertLyrics(_ lyrics: TrackLyrics) async throws -> TrackLyrics {
        try await dbQueue.write { db in
            var mutable = lyrics
            try mutable.insert(db)
            Logger.info("Inserted lyrics for track ID \(lyrics.trackId)")
            return mutable
        }
    }
    
    /// Insert lyrics from LRC content
    func insertLyrics(
        trackId: Int64,
        lrcContent: String,
        language: String? = nil,
        source: String? = "user"
    ) async throws -> TrackLyrics {
        let lyrics = TrackLyrics(
            trackId: trackId,
            lrcContent: lrcContent,
            language: language,
            source: source
        )
        return try await insertLyrics(lyrics)
    }
    
    /// Import lyrics from LRC file
    func importLyricsFromFile(
        trackId: Int64,
        fileURL: URL,
        language: String? = nil
    ) async throws -> TrackLyrics {
        // Request access to security-scoped resource
        let needsAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DatabaseError.fileNotFound(path: fileURL.path)
        }
        
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        
        return try await insertLyrics(
            trackId: trackId,
            lrcContent: content,
            language: language,
            source: "file"
        )
    }
    
    // MARK: - Read
    
    /// Get lyrics by ID
    func getLyrics(id: Int64) async throws -> TrackLyrics? {
        try await dbQueue.read { db in
            try TrackLyrics.fetchOne(db, id: id)
        }
    }
    
    /// Get lyrics for a track (returns first/default if multiple exist)
    func getLyrics(forTrackId trackId: Int64) async throws -> TrackLyrics? {
        try await dbQueue.read { db in
            try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .order(TrackLyrics.Columns.dateAdded.desc)
                .fetchOne(db)
        }
    }
    
    /// Get lyrics for a track in specific language
    func getLyrics(
        forTrackId trackId: Int64,
        language: String
    ) async throws -> TrackLyrics? {
        try await dbQueue.read { db in
            try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .filter(TrackLyrics.Columns.language == language)
                .fetchOne(db)
        }
    }
    
    /// Get all lyrics for a track (useful if multiple languages exist)
    func getAllLyrics(forTrackId trackId: Int64) async throws -> [TrackLyrics] {
        try await dbQueue.read { db in
            try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .order(TrackLyrics.Columns.dateAdded.desc)
                .fetchAll(db)
        }
    }
    
    /// Check if lyrics exist for a track
    func hasLyrics(forTrackId trackId: Int64) async throws -> Bool {
        try await dbQueue.read { db in
            try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .fetchCount(db) > 0
        }
    }
    
    /// Get all tracks with lyrics
    func getTracksWithLyrics() async throws -> [Track] {
        try await dbQueue.read { db in
            // Get distinct track IDs that have lyrics
            let trackIds = try Int64
                .fetchAll(db,
                    sql: "SELECT DISTINCT track_id FROM lyrics ORDER BY track_id")
            
            // Fetch tracks
            return try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Get track with its lyrics
    func getTrackWithLyrics(trackId: Int64) async throws -> (Track, TrackLyrics?) {
        try await dbQueue.read { db in
            guard let track = try Track
                .filter(Track.Columns.trackId == trackId)
                .fetchOne(db) else {
                throw DatabaseError.trackNotFound(id: trackId)
            }
            
            let lyrics = try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .order(TrackLyrics.Columns.dateAdded.desc)
                .fetchOne(db)
            
            return (track, lyrics)
        }
    }
    
    // MARK: - Update
    
    /// Update lyrics content
    func updateLyrics(_ lyrics: TrackLyrics) async throws {
        try await dbQueue.write { db in
            var mutable = lyrics
            mutable.dateModified = Date()
            
            try mutable.update(db)
            Logger.info("Updated lyrics ID \(lyrics.id ?? 0)")
        }
    }
    
    /// Update lyrics content only
    func updateLyricsContent(
        id: Int64,
        lrcContent: String
    ) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE lyrics
                SET lrc_content = ?, date_modified = ?
                WHERE id = ?
                """,
                arguments: [lrcContent, Date(), id]
            )
            Logger.info("Updated lyrics content for ID \(id)")
        }
    }
    
    /// Update lyrics language
    func updateLyricsLanguage(
        id: Int64,
        language: String
    ) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE lyrics
                SET language = ?, date_modified = ?
                WHERE id = ?
                """,
                arguments: [language, Date(), id]
            )
        }
    }
    
    // MARK: - Delete
    
    /// Delete lyrics by ID
    func deleteLyrics(id: Int64) async throws {
        try await dbQueue.write { db in
            let deleted = try TrackLyrics.deleteOne(db, id: id)
            if deleted {
                Logger.info("Deleted lyrics ID \(id)")
            }
        }
    }
    
    /// Delete all lyrics for a track
    func deleteAllLyrics(forTrackId trackId: Int64) async throws {
        try await dbQueue.write { db in
            let count = try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .deleteAll(db)
            
            if count > 0 {
                Logger.info("Deleted \(count) lyrics for track \(trackId)")
            }
        }
    }
    
    /// Delete lyrics for specific track and language
    func deleteLyrics(
        forTrackId trackId: Int64,
        language: String
    ) async throws {
        try await dbQueue.write { db in
            let count = try TrackLyrics
                .filter(TrackLyrics.Columns.trackId == trackId)
                .filter(TrackLyrics.Columns.language == language)
                .deleteAll(db)
            
            if count > 0 {
                Logger.info("Deleted lyrics for track \(trackId) language \(language)")
            }
        }
    }
    
    // MARK: - Export
    
    /// Export lyrics to LRC file
    func exportLyrics(
        id: Int64,
        to destinationURL: URL
    ) async throws {
        guard let lyrics = try await getLyrics(id: id) else {
            throw DatabaseError.recordNotFound(table: "lyrics", id: id)
        }
        
        // Request access to security-scoped resource
        let needsAccess = destinationURL.startAccessingSecurityScopedResource()
        defer {
            if needsAccess {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }
        
        try lyrics.lrcContent.write(
            to: destinationURL,
            atomically: true,
            encoding: .utf8
        )
        
        Logger.info("Exported lyrics ID \(id) to \(destinationURL.path)")
    }
    
    /// Export lyrics for a track
    func exportLyrics(
        forTrackId trackId: Int64,
        to destinationURL: URL
    ) async throws {
        guard let lyrics = try await getLyrics(forTrackId: trackId) else {
            throw DatabaseError.lyricsNotFound(trackId: trackId)
        }
        
        try await exportLyrics(id: lyrics.id!, to: destinationURL)
    }
    
    // MARK: - Statistics
    
    /// Get total count of tracks with lyrics
    func getLyricsCount() async throws -> Int {
        try await dbQueue.read { db in
            try TrackLyrics.fetchCount(db)
        }
    }
    
    /// Get count of lyrics by source
    func getLyricsCountBySource() async throws -> [String: Int] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT source, COUNT(*) as count
                FROM lyrics
                GROUP BY source
                ORDER BY count DESC
            """)
            
            var result: [String: Int] = [:]
            for row in rows {
                let source = row["source"] as? String ?? "unknown"
                let count = row["count"] as? Int ?? 0
                result[source] = count
            }
            return result
        }
    }
    
    /// Get count of lyrics by language
    func getLyricsCountByLanguage() async throws -> [String: Int] {
        try await dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT language, COUNT(*) as count
                FROM lyrics
                WHERE language IS NOT NULL
                GROUP BY language
                ORDER BY count DESC
            """)
            
            var result: [String: Int] = [:]
            for row in rows {
                let language = row["language"] as? String ?? "unknown"
                let count = row["count"] as? Int ?? 0
                result[language] = count
            }
            return result
        }
    }
}
