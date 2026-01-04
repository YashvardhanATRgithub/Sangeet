//
//  Track.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import Foundation

struct Track: Identifiable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var fileURL: URL
    var artworkData: Data?
    var artworkURL: URL? // For remote or lazy loading
    var isFavorite: Bool
    var playCount: Int
    var lastPlayed: Date?
    var dateAdded: Date
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    init(id: UUID = UUID(), title: String, artist: String = "Unknown Artist", album: String = "Unknown Album", duration: TimeInterval = 0, fileURL: URL, artworkData: Data? = nil, artworkURL: URL? = nil, isFavorite: Bool = false, playCount: Int = 0, lastPlayed: Date? = nil, dateAdded: Date = Date()) {
        self.id = id; self.title = title; self.artist = artist; self.album = album; self.duration = duration; self.fileURL = fileURL; self.artworkData = artworkData; self.artworkURL = artworkURL; self.isFavorite = isFavorite; self.playCount = playCount; self.lastPlayed = lastPlayed; self.dateAdded = dateAdded
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        // We generally hash ID for set/dict performance, but == determines view updates
    }
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        return lhs.id == rhs.id &&
               lhs.artworkURL == rhs.artworkURL &&
               lhs.artworkData == rhs.artworkData &&
               lhs.title == rhs.title &&
               lhs.artist == rhs.artist && 
               lhs.album == rhs.album
    }
}
