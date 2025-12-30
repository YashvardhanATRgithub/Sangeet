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
        
        // Try search first for better matching
        if let result = await searchLyrics(title: title, artist: artist) {
            cache[cacheKey] = result
            return result
        }
        
        // Fallback to get endpoint
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
                return nil
            }
            
            let result = try JSONDecoder().decode(LRCLibResponse.self, from: data)
            let lyricsResult = LyricsResult(from: result)
            cache[cacheKey] = lyricsResult
            return lyricsResult
        } catch {
            print("[LyricsService] Error: \(error)")
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
}

// MARK: - Models
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
}
