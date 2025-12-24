//
//  DBSongFeatures.swift
//  HiFidelity
//
//  Database operations for song features and embeddings
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Insert/Update Features
    
    /// Insert or update song features for a track
    func saveSongFeatures(_ features: SongFeatures) async throws {
        try await dbQueue.write { db in
            var mutableFeatures = features
            try mutableFeatures.save(db)
        }
        Logger.debug("Saved song features for track ID: \(features.trackId)")
    }
    
    /// Batch insert/update song features
    func batchSaveSongFeatures(_ featuresArray: [SongFeatures]) async throws {
        try await dbQueue.write { db in
            for var features in featuresArray {
                try features.save(db)
            }
        }
        Logger.info("Batch saved \(featuresArray.count) song features")
    }
    
    // MARK: - Fetch Features
    
    /// Get song features for a specific track
    func getSongFeatures(forTrackId trackId: Int64) async throws -> SongFeatures? {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.trackId == trackId)
                .fetchOne(db)
        }
    }
    
    /// Get song features for multiple tracks
    func getSongFeatures(forTrackIds trackIds: [Int64]) async throws -> [SongFeatures] {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(trackIds.contains(SongFeatures.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Get all tracks that have features extracted
    func getTracksWithFeatures() async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .joining(required: Track.hasOne(SongFeatures.self, key: "features"))
                .fetchAll(db)
        }
    }
    
    /// Get tracks without features (need extraction)
    func getTracksWithoutFeatures(limit: Int = 100) async throws -> [Track] {
        try await dbQueue.read { db in
            // Get track IDs that have features
            let tracksWithFeatures = try SongFeatures
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            // Get tracks that don't have features
            return try Track
                .filter(!tracksWithFeatures.contains(Track.Columns.trackId))
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    /// Get features that need update
    func getFeaturesNeedingUpdate(limit: Int = 100) async throws -> [SongFeatures] {
        try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.needsUpdate == true)
                .limit(limit)
                .fetchAll(db)
        }
    }
    
    // MARK: - Similarity Search
    
    /// Find similar tracks based on embedding cosine similarity
    /// - Parameters:
    ///   - trackId: Source track ID
    ///   - limit: Number of similar tracks to return
    ///   - threshold: Minimum similarity threshold (0.0 to 1.0)
    /// - Returns: Array of (Track, similarity score) tuples
    func findSimilarTracks(
        toTrackId trackId: Int64,
        limit: Int = 10,
        threshold: Double = 0.5
    ) async throws -> [(track: Track, similarity: Double)] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId),
              let sourceEmbedding = sourceFeatures.embedding else {
            Logger.warning("No embedding found for track ID: \(trackId)")
            return []
        }
        
        // Get all tracks with embeddings
        let allFeatures = try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.embedding != nil)
                .filter(SongFeatures.Columns.trackId != trackId) // Exclude source
                .fetchAll(db)
        }
        
        // Calculate similarities
        var similarities: [(trackId: Int64, similarity: Double)] = []
        
        for features in allFeatures {
            guard let embedding = features.embedding else { continue }
            
            if let similarity = SongFeatures.cosineSimilarity(sourceEmbedding, embedding),
               similarity >= threshold {
                similarities.append((trackId: features.trackId, similarity: similarity))
            }
        }
        
        // Sort by similarity and get top N
        similarities.sort { $0.similarity > $1.similarity }
        let topSimilar = Array(similarities.prefix(limit))
        
        // Fetch tracks
        let trackIds = topSimilar.map { $0.trackId }
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
        
        // Map tracks with their similarity scores
        return topSimilar.compactMap { similar in
            guard let track = tracks.first(where: { $0.trackId == similar.trackId }) else {
                return nil
            }
            return (track: track, similarity: similar.similarity)
        }
    }
    
    /// Find tracks with similar audio features (not embeddings)
    func findTracksWithSimilarFeatures(
        toTrackId trackId: Int64,
        limit: Int = 10,
        threshold: Double = 0.7
    ) async throws -> [(track: Track, similarity: Double)] {
        // Get source track features
        guard let sourceFeatures = try await getSongFeatures(forTrackId: trackId) else {
            return []
        }
        
        // Get all other features
        let allFeatures = try await dbQueue.read { db in
            try SongFeatures
                .filter(SongFeatures.Columns.trackId != trackId)
                .fetchAll(db)
        }
        
        // Calculate feature similarities
        var similarities: [(trackId: Int64, similarity: Double)] = []
        
        for features in allFeatures {
            let similarity = sourceFeatures.featureSimilarity(to: features)
            if similarity >= threshold {
                similarities.append((trackId: features.trackId, similarity: similarity))
            }
        }
        
        // Sort and get top N
        similarities.sort { $0.similarity > $1.similarity }
        let topSimilar = Array(similarities.prefix(limit))
        
        // Fetch tracks
        let trackIds = topSimilar.map { $0.trackId }
        let tracks = try await dbQueue.read { db in
            try Track
                .filter(trackIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
        
        return topSimilar.compactMap { similar in
            guard let track = tracks.first(where: { $0.trackId == similar.trackId }) else {
                return nil
            }
            return (track: track, similarity: similar.similarity)
        }
    }
    
    // MARK: - Feature-based Queries
    
    /// Find high-energy tracks
    func getHighEnergyTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.energy >= threshold)
                .order(SongFeatures.Columns.energy.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find calm/chill tracks
    func getCalmTracks(energyThreshold: Double = 0.4, valenceThreshold: Double = 0.3, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.energy <= energyThreshold)
                .filter(SongFeatures.Columns.valence <= valenceThreshold)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find happy/upbeat tracks
    func getHappyTracks(valenceThreshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.valence >= valenceThreshold)
                .order(SongFeatures.Columns.valence.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find danceable tracks
    func getDanceableTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.danceability >= threshold)
                .order(SongFeatures.Columns.danceability.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    /// Find acoustic tracks
    func getAcousticTracks(threshold: Double = 0.7, limit: Int = 50) async throws -> [Track] {
        try await dbQueue.read { db in
            let featureIds = try SongFeatures
                .filter(SongFeatures.Columns.acousticness >= threshold)
                .order(SongFeatures.Columns.acousticness.desc)
                .limit(limit)
                .select(SongFeatures.Columns.trackId)
                .fetchSet(db) as Set<Int64>
            
            return try Track
                .filter(featureIds.contains(Track.Columns.trackId))
                .fetchAll(db)
        }
    }
    
    // MARK: - Delete Features
    
    /// Delete song features for a track
    func deleteSongFeatures(forTrackId trackId: Int64) async throws {
        try await dbQueue.write { db in
            _ = try SongFeatures
                .filter(SongFeatures.Columns.trackId == trackId)
                .deleteAll(db)
        }
        Logger.debug("Deleted song features for track ID: \(trackId)")
    }
    
    /// Mark features as needing update
    func markFeaturesForUpdate(trackIds: [Int64]) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE song_features
                SET needs_update = 1
                WHERE track_id IN (\(trackIds.map { String($0) }.joined(separator: ",")))
                """
            )
        }
    }
    
    // MARK: - Statistics
    
    /// Get count of tracks with features
    func getFeaturesCount() async throws -> Int {
        try await dbQueue.read { db in
            try SongFeatures.fetchCount(db)
        }
    }
    
    /// Get extraction coverage percentage
    func getFeaturesCoverage() async throws -> Double {
        try await dbQueue.read { db in
            let totalTracks = try Track.fetchCount(db)
            let tracksWithFeatures = try SongFeatures.fetchCount(db)
            
            guard totalTracks > 0 else { return 0.0 }
            return Double(tracksWithFeatures) / Double(totalTracks) * 100.0
        }
    }
}

// MARK: - Track Extension for Features

extension Track {
    static let features = hasOne(SongFeatures.self, key: "features")
    
    var features: QueryInterfaceRequest<SongFeatures> {
        request(for: Track.features)
    }
}

