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

/// Lightweight struct for storing remote track metadata for state restoration
struct RemoteTrackInfo: Codable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let fileURL: String // tidal://ID
    let artworkURL: String?
    let externalID: String?
    
    init(from track: Track) {
        self.id = track.id.uuidString
        self.title = track.title
        self.artist = track.artist
        self.album = track.album
        self.duration = track.duration
        self.fileURL = track.fileURL.absoluteString
        self.artworkURL = track.artworkURL?.absoluteString
        self.externalID = track.externalID
    }
    
    func toTrack() -> Track {
        Track(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: URL(string: fileURL) ?? URL(string: "file:///invalid")!,
            artworkURL: artworkURL.flatMap { URL(string: $0) },
            externalID: externalID
        )
    }
}

/// Database record for queue state persistence
struct QueueStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "queueState"
    
    var id: Int = 1  // Always use ID 1 (singleton record)
    var trackIds: String  // JSON array of UUIDs
    var currentIndex: Int
    var currentTime: TimeInterval
    var remoteTracksMetadata: String? // JSON array of RemoteTrackInfo for remote tracks
    
    init(trackIds: [UUID], currentIndex: Int, currentTime: TimeInterval, remoteTracks: [Track] = []) {
        self.trackIds = (try? JSONEncoder().encode(trackIds.map { $0.uuidString }))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.currentIndex = currentIndex
        self.currentTime = currentTime
        
        // Store metadata for remote tracks
        if !remoteTracks.isEmpty {
            let infos = remoteTracks.map { RemoteTrackInfo(from: $0) }
            self.remoteTracksMetadata = (try? JSONEncoder().encode(infos))
                .flatMap { String(data: $0, encoding: .utf8) }
        } else {
            self.remoteTracksMetadata = nil
        }
    }
    
    func getTrackIds() -> [UUID] {
        guard let data = trackIds.data(using: .utf8),
              let strings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return strings.compactMap { UUID(uuidString: $0) }
    }
    
    func getRemoteTracks() -> [Track] {
        guard let metaString = remoteTracksMetadata,
              let data = metaString.data(using: .utf8),
              let infos = try? JSONDecoder().decode([RemoteTrackInfo].self, from: data) else {
            return []
        }
        return infos.map { $0.toTrack() }
    }
}

// MARK: - Database Operations

extension QueueStateRecord {
    
    /// Save current queue state (upsert)
    static func save(trackIds: [UUID], currentIndex: Int, currentTime: TimeInterval, remoteTracks: [Track] = [], db: Database) throws {
        let record = QueueStateRecord(
            trackIds: trackIds,
            currentIndex: currentIndex,
            currentTime: currentTime,
            remoteTracks: remoteTracks
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
