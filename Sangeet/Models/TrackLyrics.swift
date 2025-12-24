//
//  TrackLyrics.swift
//  HiFidelity
//
//  Database model for synchronized lyrics storage
//

import Foundation
import GRDB

/// Database model for track lyrics
struct TrackLyrics: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var trackId: Int64
    var lrcContent: String  // Full LRC file content
    var language: String?   // ISO 639-1 code (e.g., "en", "es", "ja")
    var source: String?     // "user", "api", "embedded", etc.
    var dateAdded: Date
    var dateModified: Date
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "lyrics"
    
    enum Columns {
        static let id = Column("id")
        static let trackId = Column("track_id")
        static let lrcContent = Column("lrc_content")
        static let language = Column("language")
        static let source = Column("source")
        static let dateAdded = Column("date_added")
        static let dateModified = Column("date_modified")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case lrcContent = "lrc_content"
        case language
        case source
        case dateAdded = "date_added"
        case dateModified = "date_modified"
    }
    
    // MARK: - Initialization
    
    init(trackId: Int64, lrcContent: String, language: String? = nil, source: String? = "user") {
        self.trackId = trackId
        self.lrcContent = lrcContent
        self.language = language
        self.source = source
        self.dateAdded = Date()
        self.dateModified = Date()
    }
    
    // MARK: - Relationships
    
    static let track = belongsTo(Track.self)
    var track: QueryInterfaceRequest<Track> {
        request(for: TrackLyrics.track)
    }
    
    // MARK: - Auto-incrementing ID
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    // MARK: - Computed Properties
    
    /// Parse LRC content into Lyrics object
    var parsedLyrics: Lyrics {
        Lyrics(lrcContent: lrcContent)
    }
    
    /// Check if lyrics have content
    var isEmpty: Bool {
        parsedLyrics.lines.isEmpty
    }
    
    /// Get line count
    var lineCount: Int {
        parsedLyrics.lines.count
    }
    
    /// Display name for language
    var languageDisplayName: String {
        guard let language = language else {
            return "Unknown"
        }
        
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: language)?.capitalized ?? language.uppercased()
    }
}

// MARK: - Track Extension

extension Track {
    /// Relationship to lyrics
    static let lyrics = hasMany(TrackLyrics.self)
    var lyrics: QueryInterfaceRequest<TrackLyrics> {
        request(for: Track.lyrics)
    }
}

