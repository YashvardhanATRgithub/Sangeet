//
//  Album.swift
//  HiFidelity
//
//  Normalized album entity
//

import Foundation
import GRDB

struct Album: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    
    // Core metadata (from TagLib)
    var title: String
    var normalizedName: String     // For searching and deduplication
    var sortName: String            // For proper alphabetical sorting
    var albumArtist: String?
    var year: String?
    
    // Professional music player fields (HIGH PRIORITY)
    var releaseType: String?       // Album, EP, Single, Compilation, Live, etc.
    var recordLabel: String?       // Record label name
    var discCount: Int             // Number of discs in album
    var musicbrainzAlbumId: String? // MusicBrainz Album ID for lookups
    
    // Additional release information (MEDIUM PRIORITY)
    var releaseDate: String?       // Full release date (YYYY-MM-DD)
    var musicbrainzReleaseGroupId: String?
    
    // Extended metadata (LOW PRIORITY)
    var barcode: String?           // UPC/EAN barcode
    var catalogNumber: String?     // Catalog/Matrix number
    var releaseCountry: String?    // ISO country code
    
    // Aggregated from tracks
    var trackCount: Int
    var totalDuration: Double
    
    // Flags (from TagLib)
    var isCompilation: Bool
    
    // Artwork (from TagLib)
    var artworkData: Data?
    
    // Timestamps
    var dateAdded: Date
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "albums"
    
    enum Columns {
        static let id = Column("id")
        static let title = Column("title")
        static let normalizedName = Column("normalized_name")
        static let sortName = Column("sort_name")
        static let albumArtist = Column("album_artist")
        static let year = Column("year")
        static let releaseType = Column("release_type")
        static let recordLabel = Column("record_label")
        static let discCount = Column("disc_count")
        static let musicbrainzAlbumId = Column("musicbrainz_album_id")
        static let releaseDate = Column("release_date")
        static let musicbrainzReleaseGroupId = Column("musicbrainz_release_group_id")
        static let barcode = Column("barcode")
        static let catalogNumber = Column("catalog_number")
        static let releaseCountry = Column("release_country")
        static let trackCount = Column("track_count")
        static let totalDuration = Column("total_duration")
        static let isCompilation = Column("is_compilation")
        static let artworkData = Column("artwork_data")
        static let dateAdded = Column("date_added")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case normalizedName = "normalized_name"
        case sortName = "sort_name"
        case albumArtist = "album_artist"
        case year
        case releaseType = "release_type"
        case recordLabel = "record_label"
        case discCount = "disc_count"
        case musicbrainzAlbumId = "musicbrainz_album_id"
        case releaseDate = "release_date"
        case musicbrainzReleaseGroupId = "musicbrainz_release_group_id"
        case barcode
        case catalogNumber = "catalog_number"
        case releaseCountry = "release_country"
        case trackCount = "track_count"
        case totalDuration = "total_duration"
        case isCompilation = "is_compilation"
        case artworkData = "artwork_data"
        case dateAdded = "date_added"
    }
    
    // MARK: - Relationships
    
    static let tracks = hasMany(Track.self)
    var tracks: QueryInterfaceRequest<Track> {
        request(for: Album.tracks)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    // MARK: - Computed Properties
    
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
    
    var displayArtist: String {
        albumArtist ?? "Various Artists"
    }
    var artist: String {
        displayArtist
    }
}

