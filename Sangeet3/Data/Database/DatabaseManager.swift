//
//  DatabaseManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  GRDB database manager for persistent storage
//

import Foundation
import Combine
import GRDB

/// Singleton managing all database operations
final class DatabaseManager: ObservableObject {
    
    static let shared = DatabaseManager()
    
    /// The database connection pool
    private var dbPool: DatabasePool?
    
    /// Published state for UI binding
    @Published private(set) var isReady = false
    
    private init() {
        setupDatabase()
    }
    
    // MARK: - Setup
    
    private func setupDatabase() {
        do {
            let databaseURL = try getDatabaseURL()
            
            // Create database pool with configuration
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable foreign keys
                db.trace { print("SQL: \($0)") } // Debug logging, remove in production
            }
            
            dbPool = try DatabasePool(path: databaseURL.path, configuration: config)
            
            // Run migrations
            try migrator.migrate(dbPool!)
            
            isReady = true
            print("Database initialized at: \(databaseURL.path)")
            
        } catch {
            print("Database setup failed: \(error)")
        }
    }
    
    private func getDatabaseURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Sangeet3", isDirectory: true)
        
        // Create directory if needed
        try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        return appFolder.appendingPathComponent("library.sqlite")
    }
    
    // MARK: - Migrations
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // Version 1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Tracks table
            try db.create(table: "track") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull().defaults(to: "Unknown Artist")
                t.column("album", .text).notNull().defaults(to: "Unknown Album")
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("filePath", .text).notNull().unique()
                t.column("artworkData", .blob)
                t.column("isFavorite", .boolean).notNull().defaults(to: false)
                t.column("playCount", .integer).notNull().defaults(to: 0)
                t.column("lastPlayed", .datetime)
                t.column("dateAdded", .datetime).notNull()
                t.column("folderPath", .text).notNull()
            }
            
            // Folders table (security bookmarks)
            try db.create(table: "folder") { t in
                t.column("id", .text).primaryKey()
                t.column("path", .text).notNull().unique()
                t.column("bookmark", .blob)
                t.column("dateAdded", .datetime).notNull()
            }
            
            // Playlists table
            try db.create(table: "playlist") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("dateCreated", .datetime).notNull()
                t.column("dateModified", .datetime).notNull()
            }
            
            // Playlist tracks (many-to-many)
            try db.create(table: "playlistTrack") { t in
                t.column("playlistId", .text).notNull().references("playlist", onDelete: .cascade)
                t.column("trackId", .text).notNull().references("track", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.primaryKey(["playlistId", "trackId"])
            }
            
            // Queue state
            try db.create(table: "queueState") { t in
                t.column("id", .integer).primaryKey().check { $0 == 1 }
                t.column("trackIds", .text).notNull()
                t.column("currentIndex", .integer).notNull().defaults(to: 0)
                t.column("currentTime", .double).notNull().defaults(to: 0)
            }
            
            // Indexes for performance
            try db.create(index: "idx_track_artist", on: "track", columns: ["artist"])
            try db.create(index: "idx_track_album", on: "track", columns: ["album"])
            try db.create(index: "idx_track_folder", on: "track", columns: ["folderPath"])
            try db.create(index: "idx_track_favorite", on: "track", columns: ["isFavorite"])
        }
        
        // Version 2: EQ Presets
        migrator.registerMigration("v2_eq_presets") { db in
            try db.create(table: "eqPreset") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull().unique()
                t.column("gains", .text).notNull()  // JSON array of 8 floats
            }
        }
        
        // Version 3: Playlists Update
        migrator.registerMigration("v3_playlists_update") { db in
            if try db.tableExists("playlist") {
                try db.alter(table: "playlist") { t in
                    t.add(column: "isSystem", .boolean).notNull().defaults(to: false)
                }
            }
            
            if try db.tableExists("playlistTrack") {
                try db.alter(table: "playlistTrack") { t in
                    t.add(column: "dateAdded", .datetime).defaults(to: Date())
                }
            }
        }
        
        // Version 4: Add dateCreated to eqPreset
        migrator.registerMigration("v4_eq_preset_date") { db in
            if try db.tableExists("eqPreset") {
                // Check if column already exists
                let columns = try db.columns(in: "eqPreset")
                if !columns.contains(where: { $0.name == "dateCreated" }) {
                    try db.alter(table: "eqPreset") { t in
                        t.add(column: "dateCreated", .datetime).notNull().defaults(to: Date())
                    }
                }
            }
        }
        
        return migrator
    }
    
    // MARK: - Database Operations
    
    /// Read operation
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        guard let dbPool = dbPool else {
            throw DatabaseError.notInitialized
        }
        return try dbPool.read(block)
    }
    
    /// Write operation
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        guard let dbPool = dbPool else {
            throw DatabaseError.notInitialized
        }
        return try dbPool.write(block)
    }
    
    /// Async write operation
    func writeAsync(_ block: @escaping (Database) throws -> Void) {
        guard let dbPool = dbPool else { return }
        dbPool.asyncWrite({ db in
            try block(db)
        }, completion: { _, result in
            if case .failure(let error) = result {
                print("Database write error: \(error)")
            }
        })
    }
}

// MARK: - Errors

enum DatabaseError: Error {
    case notInitialized
    case recordNotFound
}
