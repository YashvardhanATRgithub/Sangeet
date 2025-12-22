import Foundation

struct Track: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var url: URL
    var title: String
    var artist: String
    var album: String
    var albumArtist: String
    var genre: String
    var duration: TimeInterval
    var trackNumber: Int?
    var discNumber: Int?
    var year: Int?
    var dateAdded: Date
    var playCount: Int
    var isFavorite: Bool
    
    // For fuzzy matching/search
    var searchKeywords: String {
        "\(title) \(artist) \(album) \(albumArtist)".lowercased()
    }
}

struct Album: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var title: String
    var artist: String
    var artworkPath: String? // Path to cached image on disk
    var releaseDate: Date?
    var tracks: [Track]
}

struct Artist: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var genre: String
    var albums: [Album]
    var tracks: [Track]
}

struct Playlist: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var tracks: [Track]
    var folderName: String? // For grouping in UI
    var isSmart: Bool
}
