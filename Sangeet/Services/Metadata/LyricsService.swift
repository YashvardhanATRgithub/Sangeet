import Foundation
import RegexBuilder



struct LRCLibResponse: Codable {
    let syncedLyrics: String?
    let plainLyrics: String?
    let duration: TimeInterval?
    let albumName: String?
    let trackName: String?
    let artistName: String?
}

actor LyricsService {
    static let shared = LyricsService()
    
    // MARK: - Local File Search
    
    func findLyrics(for url: URL) async -> String? {
        let folder = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        
        let lrcURL = folder.appendingPathComponent(filename + ".lrc")
        if FileManager.default.fileExists(atPath: lrcURL.path),
           let content = try? String(contentsOf: lrcURL, encoding: .utf8) {
            return content
        }
        
        let txtURL = folder.appendingPathComponent(filename + ".txt")
        if FileManager.default.fileExists(atPath: txtURL.path),
           let content = try? String(contentsOf: txtURL, encoding: .utf8) {
            return content
        }
        
        return nil
    }
    
    // MARK: - Online Search (LRCLIB)
    
    /// Search for lyrics online. Uses exact-match endpoint first, then falls back to fuzzy search.
    func searchOnline(title: String, artist: String, album: String? = nil, duration: TimeInterval) async -> String? {
        // Step 1: Try exact match endpoint
        if let exactMatch = await fetchExactMatch(title: title, artist: artist, album: album, duration: duration) {
            return exactMatch
        }
        
        // Step 2: Try multiple search strategies (most specific to least)
        let searchQueries = buildSearchQueries(title: title, artist: artist)
        
        for query in searchQueries {
            print("DEBUG: Trying query: '\(query)'")
            if let result = await performSearch(query: query, targetDuration: duration) {
                return result
            }
        }
        
        return nil
    }
    
    /// Build multiple search queries in order of preference
    private func buildSearchQueries(title: String, artist: String) -> [String] {
        var queries: [String] = []
        
        // 1. Full query (title + all artists)
        queries.append("\(title) \(artist)")
        
        // 2. Title + Primary artist only (first name before comma/&)
        let primaryArtist = extractPrimaryArtist(from: artist)
        if primaryArtist != artist {
            queries.append("\(title) \(primaryArtist)")
        }
        
        // 3. Title only (sometimes works better for Bollywood songs)
        queries.append(title)
        
        // 4. Cleaned versions
        let cleanedTitle = clean(string: title)
        if cleanedTitle != title {
            queries.append("\(cleanedTitle) \(primaryArtist)")
            queries.append(cleanedTitle)
        }
        
        return queries
    }
    
    /// Extract primary artist from compound artist strings
    private func extractPrimaryArtist(from artist: String) -> String {
        // Split by common separators: ", ", " & ", " | ", " x ", " feat. "
        let separators = [", ", " & ", " | ", " x ", " feat. ", " ft. "]
        
        var result = artist
        for separator in separators {
            if let range = result.range(of: separator, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
                break
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// LRCLIB's `/api/get` endpoint for exact matching.
    private func fetchExactMatch(title: String, artist: String, album: String?, duration: TimeInterval) async -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: clean(string: title)),
            URLQueryItem(name: "artist_name", value: clean(string: artist)),
            URLQueryItem(name: "duration", value: String(Int(duration)))
        ]
        
        // Add album if available (helps distinguish Live vs Studio versions)
        if let album = album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: clean(string: album)))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // api/get returns 404 if no exact match
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                print("DEBUG: No exact match found for '\(title)' by '\(artist)'")
                return nil
            }
            
            let match = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            
            if let syncedLyrics = match.syncedLyrics {
                print("DEBUG: Exact match found for '\(title)' (Duration: \(match.duration ?? 0)s)")
                return syncedLyrics
            }
        } catch {
            print("Exact Match Error: \(error)")
        }
        
        return nil
    }
    
    /// Fallback fuzzy search with duration filtering.
    private func performSearch(query: String, targetDuration: TimeInterval) async -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [ URLQueryItem(name: "q", value: query) ]
        
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let responses = try JSONDecoder().decode([LRCLibResponse].self, from: data)
            
            // Filter: Must have synced lyrics AND duration within +/- 3 seconds
            let validMatches = responses.filter { match in
                guard match.syncedLyrics != nil else { return false }
                
                if let dur = match.duration {
                    return abs(dur - targetDuration) < 5.0 // Relaxed tolerance for rounding differences
                }
                return true // Allow if no duration (last resort)
            }
            
            // Sort by closest duration match
            let sorted = validMatches.sorted { lhs, rhs in
                let lhsDiff = abs((lhs.duration ?? 1000) - targetDuration)
                let rhsDiff = abs((rhs.duration ?? 1000) - targetDuration)
                return lhsDiff < rhsDiff
            }
            
            if let bestMatch = sorted.first {
                print("DEBUG: Fuzzy match found for '\(query)' (Duration: \(bestMatch.duration ?? 0)s vs \(targetDuration)s)")
                return bestMatch.syncedLyrics
            }
        } catch {
            print("Lyrics Search Error for '\(query)': \(error)")
        }
        return nil
    }
    
    // MARK: - Helpers
    
    private func clean(string: String) -> String {
        // Only remove known noise patterns, NOT important suffixes like "(Title Track)"
        let noisePatterns = [
            "(Remastered)",
            "(Remaster)",
            "[Remastered]",
            "(Deluxe)",
            "(Deluxe Edition)",
            "(Live)",
            "[Live]",
            "(Bonus Track)",
            "(Explicit)",
            "(Clean)",
        ]
        
        var result = string
        for pattern in noisePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    nonisolated func parse(_ content: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        
        let pattern = "\\[(\\d+):(\\d+)(?:\\.(\\d+))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        content.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            
            let nsString = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: trimmed.utf16.count))
            
            guard !matches.isEmpty else { return }
            
            let lastMatch = matches.last!
            let textStartIndex = lastMatch.range.location + lastMatch.range.length
            let text = textStartIndex < trimmed.utf16.count ? nsString.substring(from: textStartIndex).trimmingCharacters(in: .whitespaces) : ""
            
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))
                
                guard let min = Int(minStr), let sec = Int(secStr) else { continue }
                
                var frac = 0
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound {
                    let fracStr = nsString.substring(with: match.range(at: 3))
                    frac = Int(fracStr) ?? 0
                }
                
                let time = TimeInterval(min * 60 + sec) + (TimeInterval(frac) / 100.0)
                
                lines.append(LyricLine(timestamp: time, text: text))
            }
        }
        
        return lines.sorted { $0.timestamp < $1.timestamp }
    }
}
