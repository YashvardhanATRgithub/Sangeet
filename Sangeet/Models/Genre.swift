//
//  Genre.swift
//  HiFidelity
//
//  Normalized genre entity
//

import Foundation
import GRDB

struct Genre: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    
    // Core metadata (from TagLib)
    var name: String
    var normalizedName: String     // For searching and deduplication
    var sortName: String            // For proper alphabetical sorting
    
    // Professional music player fields (MEDIUM PRIORITY)
    var style: String?             // Sub-genre or style (e.g., "Alternative Rock" for "Rock")
    
    // Aggregated from tracks
    var trackCount: Int
    
    // Timestamps
    var dateAdded: Date
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "genres"
    
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let normalizedName = Column("normalized_name")
        static let sortName = Column("sort_name")
        static let style = Column("style")
        static let trackCount = Column("track_count")
        static let dateAdded = Column("date_added")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case normalizedName = "normalized_name"
        case sortName = "sort_name"
        case style
        case trackCount = "track_count"
        case dateAdded = "date_added"
    }
    
    // MARK: - Relationships
    
    static let tracks = hasMany(Track.self)
    var tracks: QueryInterfaceRequest<Track> {
        request(for: Genre.tracks)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

