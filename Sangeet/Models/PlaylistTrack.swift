//
//  PlaylistTrack.swift
//  HiFidelity
//
//  Junction table between playlists and tracks
//

import Foundation
import GRDB

struct PlaylistTrack: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var playlistId: Int64
    var trackId: Int64
    var position: Int
    var dateAdded: Date
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "playlist_tracks"
    
    enum Columns {
        static let id = Column("id")
        static let playlistId = Column("playlist_id")
        static let trackId = Column("track_id")
        static let position = Column("position")
        static let dateAdded = Column("date_added")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case playlistId = "playlist_id"
        case trackId = "track_id"
        case position
        case dateAdded = "date_added"
    }
    
    // MARK: - Relationships
    
    static let playlist = belongsTo(Playlist.self)
    static let track = belongsTo(Track.self)
    
    var playlist: QueryInterfaceRequest<Playlist> {
        request(for: PlaylistTrack.playlist)
    }
    
    var track: QueryInterfaceRequest<Track> {
        request(for: PlaylistTrack.track)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

