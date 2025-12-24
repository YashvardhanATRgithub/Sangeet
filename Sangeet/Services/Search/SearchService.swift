import Foundation

class SearchService {
    private let database: DatabaseManager
    
    // In-memory index: [Term: [TrackID]] or just valid list of SearchItems
    private struct SearchItem {
        let id: UUID
        let text: String
        let score: Int // Base score (e.g. play count)
    }
    
    private var items: [SearchItem] = []
    
    init(database: DatabaseManager) {
        self.database = database
    }
    
    func buildIndex() async {
        do {
            // Use getAllTracks() from DatabaseManager
            let tracks = try await database.getAllTracks()
            self.items = tracks.map { track in
                // Manually construct search keywords since Track doesn't calculate it
                let keywords = [
                    track.title,
                    track.artist,
                    track.album,
                    track.albumArtist ?? "",
                    track.composer
                ].joined(separator: " ").lowercased()
                
                return SearchItem(id: track.id, text: keywords, score: track.playCount)
            }
            Logger.info("Search index built with \(items.count) tracks")
        } catch {
            Logger.error("Failed to build search index: \(error)")
        }
    }
    
    func search(query: String) -> [UUID] {
        let terms = query.lowercased().split(separator: " ")
        guard !terms.isEmpty else { return [] }
        
        // Simple linear scan of in-memory list (fast enough for 10k-50k items in Swift)
        return items.filter { item in
            terms.allSatisfy { term in
                item.text.contains(term)
            }
        }
        .sorted {
            // Prioritize: Exact match > Starts with > Contains
            let lhsExact = $0.text == query.lowercased()
            let rhsExact = $1.text == query.lowercased()
            if lhsExact != rhsExact { return lhsExact }
            
            let lhsPrefix = $0.text.hasPrefix(query.lowercased())
            let rhsPrefix = $1.text.hasPrefix(query.lowercased())
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            
            return $0.score > $1.score
        }
        .map { $0.id }
    }
}
