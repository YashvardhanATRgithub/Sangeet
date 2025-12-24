//
//  Playlist.swift
//  HiFidelity
//
//  User-created and smart playlists
//

import Foundation
import GRDB

struct Playlist: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var name: String
    var description: String?
    var createdDate: Date
    var modifiedDate: Date
    var trackCount: Int
    var totalDuration: Double
    var customArtworkData: Data?
    var colorScheme: String?
    var isFavorite: Bool
    var sortOrder: Int
    var isSmart: Bool
    var dateLastPlayed: Date?
    var playCount: Int
    
    // MARK: - Initialization
    
    init(name: String, description: String? = nil, isSmart: Bool = false) {
        self.id = nil
        self.name = name
        self.description = description
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.trackCount = 0
        self.totalDuration = 0
        self.isFavorite = false
        self.sortOrder = 0
        self.isSmart = isSmart
        self.playCount = 0
    }
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "playlists"
    
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let description = Column("description")
        static let createdDate = Column("created_date")
        static let modifiedDate = Column("modified_date")
        static let trackCount = Column("track_count")
        static let totalDuration = Column("total_duration")
        static let customArtworkData = Column("custom_artwork_data")
        static let colorScheme = Column("color_scheme")
        static let isFavorite = Column("is_favorite")
        static let sortOrder = Column("sort_order")
        static let isSmart = Column("is_smart")
        static let dateLastPlayed = Column("date_last_played")
        static let playCount = Column("play_count")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case createdDate = "created_date"
        case modifiedDate = "modified_date"
        case trackCount = "track_count"
        case totalDuration = "total_duration"
        case customArtworkData = "custom_artwork_data"
        case colorScheme = "color_scheme"
        case isFavorite = "is_favorite"
        case sortOrder = "sort_order"
        case isSmart = "is_smart"
        case dateLastPlayed = "date_last_played"
        case playCount = "play_count"
    }
    
    // MARK: - Relationships
    
    // Playlist has many playlist_tracks
    static let playlistTracks = hasMany(PlaylistTrack.self)
    var playlistTracks: QueryInterfaceRequest<PlaylistTrack> {
        request(for: Playlist.playlistTracks)
    }
    
    // Get actual tracks through the junction table
    static let tracks = hasMany(Track.self, through: playlistTracks, using: PlaylistTrack.track)
    var tracks: QueryInterfaceRequest<Track> {
        request(for: Playlist.tracks)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

