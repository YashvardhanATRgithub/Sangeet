//
//  QueueStateRecord.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  GRDB record for persisting queue state
//

import Foundation
import GRDB

/// Database record for queue state persistence
struct QueueStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "queueState"
    
    var id: Int = 1  // Always use ID 1 (singleton record)
    var trackIds: String  // JSON array of UUIDs
    var currentIndex: Int
    var currentTime: TimeInterval
    
    init(trackIds: [UUID], currentIndex: Int, currentTime: TimeInterval) {
        self.trackIds = (try? JSONEncoder().encode(trackIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.currentIndex = currentIndex
        self.currentTime = currentTime
    }
    
    func getTrackIds() -> [UUID] {
        guard let data = trackIds.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return strings.compactMap { UUID(uuidString: $0) }
    }
}

// MARK: - Database Operations

extension QueueStateRecord {
    
    /// Save current queue state (upsert)
    static func save(trackIds: [UUID], currentIndex: Int, currentTime: TimeInterval, db: Database) throws {
        let record = QueueStateRecord(
            trackIds: trackIds,
            currentIndex: currentIndex,
            currentTime: currentTime
        )
        try record.save(db, onConflict: .replace)
    }
    
    /// Load queue state
    static func load(db: Database) throws -> QueueStateRecord? {
        try QueueStateRecord.fetchOne(db, key: 1)
    }
    
    /// Clear queue state
    static func clear(db: Database) throws {
        try QueueStateRecord.deleteOne(db, key: 1)
    }
}
