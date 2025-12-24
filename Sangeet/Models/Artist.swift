//
//  Artist.swift
//  HiFidelity
//
//  Normalized artist entity
//

import Foundation
import GRDB

struct Artist: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    
    // Core metadata (from TagLib)
    var name: String
    var normalizedName: String     // For searching and deduplication
    var sortName: String            // For proper alphabetical sorting
    
    // Professional music player fields (HIGH PRIORITY)
    var musicbrainzArtistId: String? // MusicBrainz Artist ID for lookups
    var artistType: String?        // Person, Group, Orchestra, Choir, etc.
    
    // Extended metadata (MEDIUM PRIORITY)
    var country: String?           // ISO country code (e.g., "US", "GB")
    
    // Aggregated from tracks
    var trackCount: Int
    var albumCount: Int
    
    // Artwork (stored from tracks)
    var artworkData: Data?
    var artworkSourceType: String?  // "album", "track", or "custom"
    
    // Timestamps
    var dateAdded: Date
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "artists"
    
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let normalizedName = Column("normalized_name")
        static let sortName = Column("sort_name")
        static let musicbrainzArtistId = Column("musicbrainz_artist_id")
        static let artistType = Column("artist_type")
        static let country = Column("country")
        static let trackCount = Column("track_count")
        static let albumCount = Column("album_count")
        static let artworkData = Column("artwork_data")
        static let artworkSourceType = Column("artwork_source_type")
        static let dateAdded = Column("date_added")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName = "normalized_name"
        case sortName = "sort_name"
        case musicbrainzArtistId = "musicbrainz_artist_id"
        case artistType = "artist_type"
        case country
        case trackCount = "track_count"
        case albumCount = "album_count"
        case artworkData = "artwork_data"
        case artworkSourceType = "artwork_source_type"
        case dateAdded = "date_added"
    }
    
    // MARK: - Relationships
    
    static let tracks = hasMany(Track.self)
    var tracks: QueryInterfaceRequest<Track> {
        request(for: Artist.tracks)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

