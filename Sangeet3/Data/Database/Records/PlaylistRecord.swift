//
//  PlaylistRecord.swift
//  Sangeet3
//
//  Created for Sangeet
//

import Foundation
import GRDB

struct PlaylistRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "playlist"
    
    var id: String
    var name: String
    var dateCreated: Date
    var dateModified: Date
    var isSystem: Bool // Added in v3 migration
    
    init(id: String = UUID().uuidString, name: String, isSystem: Bool = false, dateCreated: Date = Date(), dateModified: Date = Date()) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
}

struct PlaylistTrackRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "playlistTrack"
    
    var playlistId: String
    var trackId: String
    var position: Int
    var dateAdded: Date // Added in v3 migration
    
    static let track = belongsTo(TrackRecord.self)
    static let playlist = belongsTo(PlaylistRecord.self)
}
