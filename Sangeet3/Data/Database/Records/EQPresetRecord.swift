//
//  EQPresetRecord.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  GRDB record for custom EQ presets
//

import Foundation
import GRDB

/// Database record for custom EQ presets
struct EQPresetRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "eqPreset"
    
    var id: String
    var name: String
    var gains: String  // JSON array of 8 floats
    var dateCreated: Date
    
    init(name: String, gains: [Float]) {
        self.id = UUID().uuidString
        self.name = name
        self.gains = (try? JSONEncoder().encode(gains))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.dateCreated = Date()
    }
    
    func getGains() -> [Float] {
        guard let data = gains.data(using: .utf8),
              let values = try? JSONDecoder().decode([Float].self, from: data) else {
            return Array(repeating: 0, count: 8)
        }
        return values
    }
}

// MARK: - Database Operations

extension EQPresetRecord {
    
    /// Fetch all custom presets
    static func fetchAll(db: Database) throws -> [EQPresetRecord] {
        try EQPresetRecord.order(Column("name")).fetchAll(db)
    }
    
    /// Delete preset by id
    static func delete(id: String, db: Database) throws {
        try EQPresetRecord.filter(Column("id") == id).deleteAll(db)
    }
}
