//
//  LyricsService.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  LRCLib API integration for synced lyrics
//

import Foundation

/// Synced lyrics service using LRCLib API
final class LyricsService {
    
    static let shared = LyricsService()
    private init() {}
    
    private let baseURL = "https://lrclib.net/api"
    private var cache: [String: LyricsResult] = [:]
    
    // MARK: - Fetch Lyrics
    func fetchLyrics(title: String, artist: String, album: String? = nil, duration: TimeInterval? = nil) async -> LyricsResult? {
        let cacheKey = "\(artist)-\(title)".lowercased()
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        // 1. Priority: LyricsPlus (Aggregator)
        // High quality synced lyrics from Apple/Spotify/Musixmatch
        if let result = await fetchLyricsPlus(title: title, artist: artist, duration: duration) {
            cache[cacheKey] = result
            return result
        }
        
        // 2. Fallback: Search LRCLib
        if let result = await searchLyrics(title: title, artist: artist) {
            cache[cacheKey] = result
            return result
        }
        
        // 3. Fallback: GET LRCLib
        // Let's keep the existing logic structure: Search (Step 2) -> Get (Step 3) if we want? 
        // Actually, the original code looked like: Cache -> Search -> Get.
        // We will insert LyricsPlus BEFORE Search.
        
        // Fallback to LRCLib GET endpoint
        guard var components = URLComponents(string: "\(baseURL)/get") else { return nil }
        
        var queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        
        if let album = album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        
        if let duration = duration, duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Sangeet/3.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // If Get fails, we proceed to Tidal Fallback below
                throw URLError(.badServerResponse)
            }
            
            let result = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            let lyricsResult = LyricsResult(from: result)
            cache[cacheKey] = lyricsResult
            return lyricsResult
        } catch {
            print("[LyricsService] LRCLib Error: \(error)")
        }
        
        // 3. Fallback to Tidal Lyrics
        print("[LyricsService] LRCLib failed, trying Tidal fallback...")
        if let tidalResult = await fetchTidalLyrics(title: title, artist: artist) {
            cache[cacheKey] = tidalResult
            return tidalResult
        }
        
        return nil
    }
    
    private func fetchTidalLyrics(title: String, artist: String) async -> LyricsResult? {
        do {
            // 1. Search for the track on Tidal
            let query = "\(artist) \(title)"
            let results = try await TidalDLService.shared.search(query: query)
            
            // Get best match
            guard let bestMatch = results.first else { return nil }
            
            // 2. Get Lyrics
            guard let tidalLyrics = try await TidalDLService.shared.getLyrics(trackID: bestMatch.id) else { return nil }
            
            return LyricsResult(from: tidalLyrics)
        } catch {
            print("[LyricsService] Tidal Fallback Error: \(error)")
            return nil
        }
    }
    
    private func searchLyrics(title: String, artist: String) async -> LyricsResult? {
        guard var components = URLComponents(string: "\(baseURL)/search") else { return nil }
        
        components.queryItems = [
            URLQueryItem(name: "q", value: "\(artist) \(title)")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("Sangeet/3.0", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let results = try JSONDecoder().decode([LRCLibResponse].self, from: data)
            
            // Find best match
            if let best = results.first(where: { $0.syncedLyrics != nil }) ?? results.first {
                return LyricsResult(from: best)
            }
        } catch {
            print("[LyricsService] Search error: \(error)")
        }
        
        return nil
    }
    // MARK: - LyricsPlus Integration
    
    private func fetchLyricsPlus(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        // Construct standard query
        // https://lyricsplus.prjktla.workers.dev/v2/lyrics/get?title=...&artist=...&duration=...
        var components = URLComponents(string: "https://lyricsplus.prjktla.workers.dev/v2/lyrics/get")
        var queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist)
        ]
        if let d = duration {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(d))))
        }
        components?.queryItems = queryItems
        
        guard let url = components?.url else { return nil }
        
        print("[LyricsService] Fetching from LyricsPlus: \(url.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let result = try JSONDecoder().decode(LyricsPlusResponse.self, from: data)
            return LyricsResult(from: result)
        } catch {
            print("[LyricsService] LyricsPlus Error: \(error)")
            return nil
        }
    }
}

// MARK: - Models

struct LyricsPlusResponse: Codable {
    let lyrics: [LyricsPlusLine]?
    let type: String?
}

struct LyricsPlusLine: Codable {
    let time: Double // Milliseconds
    let text: String
    let duration: Double?
    let syllabus: [LyricsPlusWord]? // Added syllabus support
}

struct LyricsPlusWord: Codable {
    let time: Double
    let duration: Double
    let text: String
}

struct LRCLibResponse: Codable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: Double?
    let plainLyrics: String?
    let syncedLyrics: String?
}

struct LyricsResult {
    let plainLyrics: String?
    let syncedLyrics: [SyncedLine]
    
    var hasSyncedLyrics: Bool { !syncedLyrics.isEmpty }
    
    init(from response: LRCLibResponse) {
        self.plainLyrics = response.plainLyrics
        self.syncedLyrics = Self.parseSyncedLyrics(response.syncedLyrics)
    }
    
    init(from tidal: TidalLyrics) {
        self.plainLyrics = tidal.lyrics
        if let synced = tidal.syncLyrics {
             self.syncedLyrics = synced.compactMap { line in
                 guard let text = line.text, let time = line.time else { return nil }
                 return SyncedLine(time: time, text: text)
             }.sorted { $0.time < $1.time }
        } else {
             self.syncedLyrics = []
        }
    }
    
    init(from plus: LyricsPlusResponse) {
        self.plainLyrics = nil // LyricsPlus is specialized for synced
        if let lines = plus.lyrics {
            self.syncedLyrics = lines.compactMap { line in
                let time = line.time / 1000.0 // Convert ms to seconds
                
                // Parse words if available
                var words: [SyncedWord]? = nil
                if let syllabus = line.syllabus {
                    words = syllabus.map { word in
                        let start = word.time / 1000.0
                        let end = start + (word.duration / 1000.0)
                        return SyncedWord(text: word.text, start: start, end: end)
                    }
                }
                
                return SyncedLine(time: time, text: line.text, words: words)
            }.sorted { $0.time < $1.time }
        } else {
            self.syncedLyrics = []
        }
    }
    
    static func parseSyncedLyrics(_ lrc: String?) -> [SyncedLine] {
        guard let lrc = lrc else { return [] }
        
        var lines: [SyncedLine] = []
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        for line in lrc.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            
            if let match = regex.firstMatch(in: line, range: range) {
                if let minRange = Range(match.range(at: 1), in: line),
                   let secRange = Range(match.range(at: 2), in: line),
                   let msRange = Range(match.range(at: 3), in: line),
                   let textRange = Range(match.range(at: 4), in: line) {
                    
                    let minutes = Double(line[minRange]) ?? 0
                    let seconds = Double(line[secRange]) ?? 0
                    let ms = Double(line[msRange]) ?? 0
                    let text = String(line[textRange]).trimmingCharacters(in: .whitespaces)
                    
                    let msMultiplier = line[msRange].count == 2 ? 10.0 : 1.0
                    let time = minutes * 60 + seconds + (ms * msMultiplier / 1000)
                    
                    if !text.isEmpty {
                        lines.append(SyncedLine(time: time, text: text))
                    }
                }
            }
        }
        
        return lines.sorted { $0.time < $1.time }
    }
}

struct SyncedLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    var words: [SyncedWord]? = nil
}

struct SyncedWord: Identifiable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}
