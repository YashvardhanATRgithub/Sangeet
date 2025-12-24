import Foundation

struct ITunesTrack: Codable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkUrl100: String?
    let releaseDate: String?
    let trackNumber: Int?
    let discNumber: Int?
    let primaryGenreName: String?
}

struct ITunesResponse: Codable {
    let resultCount: Int
    let results: [ITunesTrack]
}

actor OnlineMetadataService {
    static let shared = OnlineMetadataService()
    
    private let baseURL = "https://itunes.apple.com/search"
    
    func search(query: String) async -> ITunesTrack? {
        // Clean query for better results
        let cleanedQuery = query
            .replacingOccurrences(of: "(Remastered)", with: "")
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        guard !cleanedQuery.isEmpty else { return nil }
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "term", value: cleanedQuery),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesResponse.self, from: data)
            return response.results.first
        } catch {
            print("OnlineMetadataService Error: \(error)")
            return nil
        }
    }
}
