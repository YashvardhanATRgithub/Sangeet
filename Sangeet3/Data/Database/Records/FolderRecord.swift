//
//  FolderRecord.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  GRDB record for folder bookmarks
//

import Foundation
import GRDB

/// Database record for imported folders with security bookmarks
struct FolderRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "folder"
    
    var id: String
    var path: String
    var bookmark: Data?
    var dateAdded: Date
    
    init(url: URL, bookmark: Data?) {
        self.id = UUID().uuidString
        self.path = url.path
        self.bookmark = bookmark
        self.dateAdded = Date()
    }
    
    func toURL() -> URL {
        URL(fileURLWithPath: path)
    }
}

// MARK: - Database Queries

extension FolderRecord {
    
    /// Fetch all folders
    static func fetchAll(db: Database) throws -> [FolderRecord] {
        try FolderRecord.fetchAll(db)
    }
    
    /// Check if folder exists
    static func exists(path: String, db: Database) throws -> Bool {
        try FolderRecord
            .filter(Column("path") == path)
            .fetchCount(db) > 0
    }
    
    /// Delete folder by path
    static func delete(path: String, db: Database) throws {
        try FolderRecord
            .filter(Column("path") == path)
            .deleteAll(db)
    }
}
