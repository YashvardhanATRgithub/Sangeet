//
//  RecommendationEngine.swift
//  HiFidelity
//
//  Created by Varun Rathod

import Foundation
import GRDB
import Combine

/// Engine for generating track recommendations based on listening history and track similarity
final class RecommendationEngine {
    static let shared = RecommendationEngine()
    
    private let database: DatabaseManager
    
    private init(database: DatabaseManager = .shared) {
        self.database = database
    }
    
    // MARK: - Recommendation Strategies
    
    /// Get recommended tracks based on a seed track
    /// - Parameters:
    ///   - seedTrack: The track to base recommendations on
    ///   - count: Number of recommendations to return
    ///   - excludeTrackIds: Track IDs to exclude from recommendations
    /// - Returns: Array of recommended tracks
    func getRecommendations(
        basedOn seedTrack: Track,
        count: Int = 10,
        excludeTrackIds: Set<Int64> = []
    ) async throws -> [Track] {
        var recommendations: [Track] = []
        var excludedIds = excludeTrackIds
        
        // Add seed track to excluded list
        if let seedId = seedTrack.trackId {
            excludedIds.insert(seedId)
        }
        
        // Strategy 1: Same artist (40% weight)
        let artistTracks = try await getTracksBySameArtist(
            seedTrack,
            count: max(4, count / 2),
            excludeIds: excludedIds
        )
        recommendations.append(contentsOf: artistTracks)
        excludedIds.formUnion(artistTracks.compactMap { $0.trackId })
        
        // Strategy 2: Same genre (30% weight)
        if recommendations.count < count {
            let genreTracks = try await getTracksBySameGenre(
                seedTrack,
                count: max(3, count / 3),
                excludeIds: excludedIds
            )
            recommendations.append(contentsOf: genreTracks)
            excludedIds.formUnion(genreTracks.compactMap { $0.trackId })
        }
        
        // Strategy 3: Same album (20% weight)
        if recommendations.count < count {
            let albumTracks = try await getTracksBySameAlbum(
                seedTrack,
                count: max(2, count / 5),
                excludeIds: excludedIds
            )
            recommendations.append(contentsOf: albumTracks)
            excludedIds.formUnion(albumTracks.compactMap { $0.trackId })
        }
        
        // Strategy 4: Popular tracks if still need more
        if recommendations.count < count {
            let popularTracks = try await getPopularTracks(
                count: count - recommendations.count,
                excludeIds: excludedIds
            )
            recommendations.append(contentsOf: popularTracks)
        }
        
        // Fallback: If still don't have enough (cold start: no history, no matches)
        // Just return random tracks from library
        if recommendations.count < count {
            Logger.info("Using random fallback for recommendations (cold start)")
            let randomTracks = try await getRandomTracks(
                count: count - recommendations.count,
                excludeIds: excludedIds
            )
            recommendations.append(contentsOf: randomTracks)
        }
        
        // Shuffle to mix strategies and return requested count
        return Array(recommendations.shuffled().prefix(count))
    }
    
    /// Get recommendations for autoplay queue
    /// - Parameters:
    ///   - recentTracks: Recently played tracks to base recommendations on
    ///   - count: Number of recommendations
    /// - Returns: Array of recommended tracks
    func getAutoplayRecommendations(
        basedOnRecent recentTracks: [Track],
        count: Int = 5
    ) async throws -> [Track] {
        guard let lastTrack = recentTracks.last else {
            // No history, return popular tracks (which falls back to random if needed)
            Logger.info("No recent tracks, using popular/random tracks for autoplay")
            return try await getPopularTracks(count: count, excludeIds: [])
        }
        
        // Get recommendations based on last track
        let excludedIds = Set(recentTracks.compactMap { $0.trackId })
        return try await getRecommendations(
            basedOn: lastTrack,
            count: count,
            excludeTrackIds: excludedIds
        )
    }
    
    // MARK: - Strategy Implementations
    
    /// Get tracks by the same artist
    private func getTracksBySameArtist(
        _ seedTrack: Track,
        count: Int,
        excludeIds: Set<Int64>
    ) async throws -> [Track] {
        guard !seedTrack.artist.isEmpty else { return [] }
        
        return try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.artist == seedTrack.artist)
                .filter(!excludeIds.contains(Track.Columns.trackId))
                .order(Track.Columns.playCount.desc)
                .limit(count)
                .fetchAll(db)
        }
    }
    
    /// Get tracks from the same genre
    private func getTracksBySameGenre(
        _ seedTrack: Track,
        count: Int,
        excludeIds: Set<Int64>
    ) async throws -> [Track] {
        guard !seedTrack.genre.isEmpty else { return [] }
        
        return try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.genre == seedTrack.genre)
                .filter(!excludeIds.contains(Track.Columns.trackId))
                .order(Track.Columns.playCount.desc)
                .limit(count)
                .fetchAll(db)
        }
    }
    
    /// Get other tracks from the same album
    private func getTracksBySameAlbum(
        _ seedTrack: Track,
        count: Int,
        excludeIds: Set<Int64>
    ) async throws -> [Track] {
        guard !seedTrack.album.isEmpty else { return [] }
        
        return try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.album == seedTrack.album)
                .filter(!excludeIds.contains(Track.Columns.trackId))
                .order(Track.Columns.trackNumber.asc)
                .limit(count)
                .fetchAll(db)
        }
    }
    
    /// Get popular tracks (most played)
    /// Falls back to random tracks if no tracks have been played yet (cold start)
    private func getPopularTracks(
        count: Int,
        excludeIds: Set<Int64>
    ) async throws -> [Track] {
        return try await database.dbQueue.read { db in
            let popularTracks = try Track
                .filter(!excludeIds.contains(Track.Columns.trackId))
                .filter(Track.Columns.playCount > 0)
                .order(Track.Columns.playCount.desc)
                .limit(count)
                .fetchAll(db)
            
            // Fallback to random if no tracks have play counts (cold start)
            if popularTracks.isEmpty {
                Logger.info("No popular tracks found, using random tracks")
                return try Track
                    .filter(!excludeIds.contains(Track.Columns.trackId))
                    .order(sql: "RANDOM()")
                    .limit(count)
                    .fetchAll(db)
            }
            
            return popularTracks
        }
    }
    
    /// Get random tracks from library
    /// Used for cold start when no listening history exists
    private func getRandomTracks(
        count: Int,
        excludeIds: Set<Int64>
    ) async throws -> [Track] {
        return try await database.dbQueue.read { db in
            try Track
                .filter(!excludeIds.contains(Track.Columns.trackId))
                .order(sql: "RANDOM()")
                .limit(count)
                .fetchAll(db)
        }
    }
    
    // MARK: - Smart Recommendations
    
    /// Get recommendations for favorites playlist continuation
    func getFavoritesContinuation(count: Int = 10) async throws -> [Track] {
        return try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.isFavorite == true)
                .order(sql: "RANDOM()")
                .limit(count)
                .fetchAll(db)
        }
    }
    
    /// Get recommendations for recently played continuation
    func getRecentlyPlayedContinuation(count: Int = 10) async throws -> [Track] {
        // Get recently played tracks
        let recentTracks = try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.lastPlayedDate != nil)
                .order(Track.Columns.lastPlayedDate.desc)
                .limit(5)
                .fetchAll(db)
        }
        
        guard let seedTrack = recentTracks.first else {
            // No play history, return popular tracks (which falls back to random if needed)
            Logger.info("No play history, using popular/random tracks")
            return try await getPopularTracks(count: count, excludeIds: [])
        }
        
        let excludedIds = Set(recentTracks.compactMap { $0.trackId })
        return try await getRecommendations(
            basedOn: seedTrack,
            count: count,
            excludeTrackIds: excludedIds
        )
    }
    
    /// Get recommendations for a specific genre
    func getGenreMix(genre: String, count: Int = 20) async throws -> [Track] {
        return try await database.dbQueue.read { db in
            try Track
                .filter(Track.Columns.genre == genre)
                .order(sql: "RANDOM()")
                .limit(count)
                .fetchAll(db)
        }
    }
}

// MARK: - Recommendation Weights

extension RecommendationEngine {
    /// Weights for different recommendation strategies
    enum RecommendationWeight {
        static let sameArtist: Double = 0.40  // 40% - Find similar sound/style
        static let sameGenre: Double = 0.30   // 30% - Genre consistency
        static let sameAlbum: Double = 0.20   // 20% - Album discovery
        static let popular: Double = 0.10     // 10% - Popular tracks fallback
    }
}


