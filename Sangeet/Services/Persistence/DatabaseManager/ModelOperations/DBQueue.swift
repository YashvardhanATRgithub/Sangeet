//
//  DBQueue.swift
//  HiFidelity
//
//  Queue persistence operations
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Save Queue
    
    /// Save the current playback queue to database
    /// - Parameters:
    ///   - tracks: Array of tracks in queue
    ///   - currentIndex: Index of currently playing track
    func saveQueue(
        tracks: [Track],
        currentIndex: Int
    ) async throws {
        try await dbQueue.write { db in
            // Clear existing queue
            try QueueEntry.deleteAll(db)
            
            // Insert all tracks in queue
            for (index, track) in tracks.enumerated() {
                guard let trackId = track.trackId else {
                    Logger.warning("Skipping track without ID: \(track.title)")
                    continue
                }
                
                var entry = QueueEntry(
                    id: nil,
                    trackId: trackId,
                    position: index
                )
                
                try entry.insert(db)
            }
            
            Logger.info("Saved queue with \(tracks.count) tracks (current: \(currentIndex))")
        }
    }
    
    // MARK: - Load Queue
    
    /// Load the saved queue from database
    /// - Returns: Tuple of (tracks, currentIndex)
    func loadQueue() async throws -> (tracks: [Track], currentIndex: Int) {
        return try await dbQueue.read { db in
            // Load queue entries ordered by position
            let entries = try QueueEntry
                .order(QueueEntry.Columns.position)
                .fetchAll(db)
            
            guard !entries.isEmpty else {
                Logger.info("No saved queue found")
                return ([], 0)
            }
            
            // Extract tracks using trackId
            let tracks = entries.compactMap { entry -> Track? in
                DatabaseCache.shared.track(entry.trackId)
            }
            
            // Load current index from UserDefaults
            let currentIndex = UserDefaults.standard.integer(forKey: "queueCurrentIndex")
            
            Logger.info("Loaded queue with \(tracks.count) tracks (current: \(currentIndex))")
            
            return (tracks, currentIndex)
        }
    }
    
    /// Save the current queue index to UserDefaults
    /// - Parameter index: Current queue index
    func saveQueueCurrentIndex(_ index: Int) {
        UserDefaults.standard.set(index, forKey: "queueCurrentIndex")
    }
    
    // MARK: - Add to Queue
    
    /// Add a track to the end of the queue
    /// - Parameter track: Track to add
    func addTrackToQueue(_ track: Track) async throws {
        guard let trackId = track.trackId else {
            throw DatabaseError.invalidTrackId
        }
        
        try await dbQueue.write { db in
            // Get next position
            let maxPosition = try QueueEntry
                .select(max(QueueEntry.Columns.position))
                .fetchOne(db) ?? -1
            
            var entry = QueueEntry(
                id: nil,
                trackId: trackId,
                position: maxPosition + 1
            )
            
            try entry.insert(db)
            Logger.info("Added \(track.title) to queue at position \(maxPosition + 1)")
        }
    }
    
    // MARK: - Remove from Queue
    
    /// Remove a track from the queue by position
    /// - Parameter position: Position to remove
    func removeFromQueue(at position: Int) async throws {
        try await dbQueue.write { db in
            // Delete the entry
            try QueueEntry
                .filter(QueueEntry.Columns.position == position)
                .deleteAll(db)
            
            // Reorder remaining entries
            try db.execute(sql: """
                UPDATE queue 
                SET position = position - 1
                WHERE position > ?
                """,
                arguments: [position])
            
            Logger.info("Removed track at position \(position) from queue")
        }
    }
    
    // MARK: - Clear Queue
    
    /// Clear the entire queue
    func clearQueue() async throws {
        try await dbQueue.write { db in
            let count = try QueueEntry.deleteAll(db)
            Logger.info("Cleared queue (\(count) tracks removed)")
        }
    }
    
    // MARK: - Queue Info
    
    /// Get queue count
    /// - Returns: Total number of tracks in queue
    func getQueueCount() async throws -> Int {
        return try await dbQueue.read { db in
            try QueueEntry.fetchCount(db)
        }
    }
}

