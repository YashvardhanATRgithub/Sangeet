//
//  TrackRecord.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  GRDB record for Track entity
//

import Foundation
import GRDB

/// Database record for tracks - maps to Track entity
struct TrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "track"
    
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var filePath: String
    var artworkData: Data?
    var isFavorite: Bool
    var playCount: Int
    var lastPlayed: Date?
    var dateAdded: Date
    var folderPath: String
    
    // MARK: - Conversion to/from Track
    
    init(from track: Track) {
        self.id = track.id.uuidString
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.duration = track.duration
        self.filePath = track.fileURL.path
        self.artworkData = track.artworkData
        self.isFavorite = track.isFavorite
        self.playCount = track.playCount
        self.lastPlayed = track.lastPlayed
        self.lastPlayed = track.lastPlayed
        self.dateAdded = track.dateAdded
        self.folderPath = track.fileURL.deletingLastPathComponent().path
    }
    
    func toTrack() -> Track {
        Track(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: URL(fileURLWithPath: filePath),
            artworkData: artworkData,
            isFavorite: isFavorite,
            playCount: playCount,
            lastPlayed: lastPlayed,
            dateAdded: dateAdded
        )
    }
}

// MARK: - Database Queries

extension TrackRecord {
    
    /// Fetch all tracks
    static func fetchAll(db: Database) throws -> [TrackRecord] {
        try TrackRecord.fetchAll(db)
    }
    
    /// Fetch tracks in a folder
    static func fetchByFolder(_ folderPath: String, db: Database) throws -> [TrackRecord] {
        try TrackRecord
            .filter(Column("folderPath") == folderPath)
            .fetchAll(db)
    }
    
    /// Fetch favorites
    static func fetchFavorites(db: Database) throws -> [TrackRecord] {
        try TrackRecord
            .filter(Column("isFavorite") == true)
            .order(Column("title"))
            .fetchAll(db)
    }
    
    /// Search tracks
    static func search(_ query: String, db: Database) throws -> [TrackRecord] {
        let pattern = "%\(query)%"
        return try TrackRecord
            .filter(Column("title").like(pattern) || 
                    Column("artist").like(pattern) || 
                    Column("album").like(pattern))
            .limit(50)
            .fetchAll(db)
    }
    
    /// Check if track exists by file path
    static func exists(filePath: String, db: Database) throws -> Bool {
        try TrackRecord
            .filter(Column("filePath") == filePath)
            .fetchCount(db) > 0
    }
    
    /// Delete all tracks in a folder
    static func deleteByFolder(_ folderPath: String, db: Database) throws {
        try TrackRecord
            .filter(Column("folderPath") == folderPath)
            .deleteAll(db)
    }
    
    /// Increment play count
    mutating func incrementPlayCount(db: Database) throws {
        playCount += 1
        lastPlayed = Date()
        try update(db)
    }
    
    /// Toggle favorite
    mutating func toggleFavorite(db: Database) throws {
        isFavorite.toggle()
        try update(db)
    }
}
