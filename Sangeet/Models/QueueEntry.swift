//
//  QueueEntry.swift
//  HiFidelity
//
//  Persistent queue management
//

import Foundation
import GRDB

struct QueueEntry: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var trackId: Int64
    var position: Int
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "queue"
    
    enum Columns {
        static let id = Column("id")
        static let trackId = Column("track_id")
        static let position = Column("position")
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case position
    }
    
    // MARK: - Relationships
    
    static let track = belongsTo(Track.self)
    var track: QueryInterfaceRequest<Track> {
        request(for: QueueEntry.track)
    }
    
    // Auto-increment id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

