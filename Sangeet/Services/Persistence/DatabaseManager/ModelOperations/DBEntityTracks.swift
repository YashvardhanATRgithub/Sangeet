//
//  DBEntityTracks.swift
//  HiFidelity
//
//  Database operations for getting tracks by entity (Album, Artist, Genre)
//

import Foundation
import GRDB

extension DatabaseManager {
    
    // MARK: - Get Tracks for Album
    
    func getTracksForAlbum(albumId: Int64) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.albumId == albumId)
                .order(Track.Columns.discNumber.asc, Track.Columns.trackNumber.asc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Get Tracks for Artist
    
    func getTracksForArtist(artistId: Int64) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.artistId == artistId)
                .order(Track.Columns.album.asc, Track.Columns.trackNumber.asc)
                .fetchAll(db)
        }
    }
    
    // MARK: - Get Tracks for Genre
    
    func getTracksForGenre(genreId: Int64) async throws -> [Track] {
        try await dbQueue.read { db in
            try Track
                .filter(Track.Columns.genreId == genreId)
                .order(Track.Columns.artist.asc, Track.Columns.album.asc, Track.Columns.trackNumber.asc)
                .fetchAll(db)
        }
    }
}

