//
//  LyricsService.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Offline-first lyrics with online word-synced fallback:
//  1. .lrc sidecar file (synced, supports enhanced word timing)
//  2. .txt sidecar file (plain)
//  3. Lyrics embedded in the file's metadata (ID3 USLT / iTunes lyrics atom)
//  4. Disk cache of previously fetched lyrics (works offline)
//  5. LyricsPlus API (word-by-word synced)
//  6. LRCLib API (line synced)
//

import Foundation
import AVFoundation

actor LyricsService {

    static let shared = LyricsService()
    private init() {}

    private var cache: [UUID: LyricsResult] = [:]

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    // MARK: - Fetch Lyrics

    func fetchLyrics(for track: Track) async -> LyricsResult? {
        if let cached = cache[track.id] {
            return cached
        }

        let result = await loadLyrics(for: track)

        if let result {
            cache[track.id] = result
        }
        return result
    }

    private func loadLyrics(for track: Track) async -> LyricsResult? {
        let fileURL = track.fileURL
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let base = fileURL.deletingPathExtension()

        // 1. LRC sidecar (synced)
        for ext in ["lrc", "LRC"] {
            let lrcURL = base.appendingPathExtension(ext)
            if let text = try? String(contentsOf: lrcURL, encoding: .utf8) {
                let result = LyricsResult(lrcText: text)
                if result.hasSyncedLyrics || result.plainLyrics != nil {
                    return result
                }
            }
        }

        // 2. TXT sidecar (plain)
        for ext in ["txt", "TXT"] {
            let txtURL = base.appendingPathExtension(ext)
            if let text = try? String(contentsOf: txtURL, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return LyricsResult(plainText: text)
            }
        }

        // 3. Embedded metadata lyrics
        if let embedded = await extractEmbeddedLyrics(from: fileURL) {
            // Embedded lyrics may themselves be LRC-formatted
            let result = LyricsResult(lrcText: embedded)
            if result.hasSyncedLyrics {
                return result
            }
            return LyricsResult(plainText: embedded)
        }

        // 4. Disk cache of previous online fetches (works offline)
        if let cached = loadCachedResult(for: track) {
            return cached
        }

        // 5. LyricsPlus (word-by-word synced)
        if let result = await fetchLyricsPlus(title: track.title, artist: track.artist, duration: track.duration) {
            saveCachedResult(result, for: track)
            return result
        }

        // 6. LRCLib (line synced)
        if let result = await fetchLRCLib(title: track.title, artist: track.artist, album: track.album, duration: track.duration) {
            saveCachedResult(result, for: track)
            return result
        }

        return nil
    }

    private func extractEmbeddedLyrics(from url: URL) async -> String? {
        let asset = AVURLAsset(url: url)

        let identifiers: [AVMetadataIdentifier] = [
            .iTunesMetadataLyrics,
            .id3MetadataUnsynchronizedLyric
        ]

        do {
            let formats = try await asset.load(.availableMetadataFormats)
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                for item in items {
                    guard let identifier = item.identifier else { continue }
                    if identifiers.contains(identifier) || identifier.rawValue.lowercased().contains("lyric") {
                        if let text = try? await item.load(.stringValue),
                           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            return text
                        }
                    }
                }
            }

            // Fallback: the asset-level lyrics property (covers most MP4/M4A files)
            if let lyrics = try await asset.load(.lyrics),
               !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lyrics
            }
        } catch {
            // Lyrics are optional; ignore extraction errors
        }

        return nil
    }

    // MARK: - Online: LyricsPlus (word-by-word)

    /// Known LyricsPlus deployments; individual instances rate-limit or go
    /// down, so each is tried in order and the first working one is remembered.
    private let lyricsPlusMirrors = [
        "https://lyricsplus.prjktla.workers.dev",
        "https://lyricsplus.atomix.one",
        "https://lyricsplus.binimum.org"
    ]
    private var preferredMirrorIndex = 0

    private func fetchLyricsPlus(title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        // Try the last known working mirror first, then the rest in order
        var order = Array(lyricsPlusMirrors.indices)
        order.removeAll { $0 == preferredMirrorIndex }
        order.insert(preferredMirrorIndex, at: 0)

        for index in order {
            if let result = await fetchLyricsPlus(
                from: lyricsPlusMirrors[index], title: title, artist: artist, duration: duration
            ) {
                preferredMirrorIndex = index
                return result
            }
        }
        return nil
    }

    private func fetchLyricsPlus(from host: String, title: String, artist: String, duration: TimeInterval?) async -> LyricsResult? {
        var components = URLComponents(string: "\(host)/v2/lyrics/get")
        var items = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "artist", value: artist)
        ]
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Sangeet/3.4", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 6  // fail fast so mirror + LRCLib fallback stays snappy
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            let decoded = try JSONDecoder().decode(LyricsPlusResponse.self, from: data)
            guard let lines = decoded.lyrics, !lines.isEmpty else { return nil }

            let synced = lines.map { line -> SyncedLine in
                var words: [SyncedWord]? = nil
                if let syllabus = line.syllabus, !syllabus.isEmpty {
                    words = syllabus.map { word in
                        SyncedWord(
                            text: word.text,
                            start: word.time / 1000.0,
                            end: (word.time + word.duration) / 1000.0
                        )
                    }
                }
                return SyncedLine(time: line.time / 1000.0, text: line.text, words: words)
            }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.time < $1.time }

            guard !synced.isEmpty else { return nil }
            return LyricsResult(plain: nil, synced: synced)
        } catch {
            return nil
        }
    }

    // MARK: - Online: LRCLib (line synced)

    private func fetchLRCLib(title: String, artist: String, album: String?, duration: TimeInterval?) async -> LyricsResult? {
        // Exact match endpoint first
        var getComponents = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let album, !album.isEmpty, album != "Unknown Album" {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        getComponents?.queryItems = items

        if let url = getComponents?.url,
           let response: LRCLibResponse = await requestJSON(url),
           let result = makeResult(from: response) {
            return result
        }

        // Fuzzy search fallback
        var searchComponents = URLComponents(string: "https://lrclib.net/api/search")
        searchComponents?.queryItems = [URLQueryItem(name: "q", value: "\(artist) \(title)")]

        if let url = searchComponents?.url,
           let responses: [LRCLibResponse] = await requestJSON(url) {
            let best = responses.first(where: { $0.syncedLyrics?.isEmpty == false }) ?? responses.first
            if let best, let result = makeResult(from: best) {
                return result
            }
        }

        return nil
    }

    private func requestJSON<T: Decodable>(_ url: URL) async -> T? {
        do {
            var request = URLRequest(url: url)
            request.setValue("Sangeet/3.4", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }

    private func makeResult(from response: LRCLibResponse) -> LyricsResult? {
        if let synced = response.syncedLyrics, !synced.isEmpty {
            let result = LyricsResult(lrcText: synced)
            if result.hasSyncedLyrics { return result }
        }
        if let plain = response.plainLyrics,
           !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return LyricsResult(plainText: plain)
        }
        return nil
    }

    // MARK: - Disk Cache

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sangeet3/LyricsCache", isDirectory: true)
    }

    private func cachedFileURL(for track: Track) -> URL? {
        guard let dir = cacheDirectory else { return nil }
        let raw = "\(track.artist)-\(track.title)".lowercased()
        let key = String(raw.map { $0.isLetter || $0.isNumber ? $0 : "-" })
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !key.isEmpty else { return nil }
        return dir.appendingPathComponent(key + ".json")
    }

    private func loadCachedResult(for track: Track) -> LyricsResult? {
        guard let url = cachedFileURL(for: track),
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data) else { return nil }
        return cached.toResult()
    }

    private func saveCachedResult(_ result: LyricsResult, for track: Track) {
        guard let dir = cacheDirectory, let url = cachedFileURL(for: track) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(CachedLyrics(from: result)) {
            try? data.write(to: url)
        }
    }
}

// MARK: - Online API Models

private nonisolated struct LyricsPlusResponse: Codable {
    let lyrics: [LyricsPlusLine]?
    let type: String?
}

private nonisolated struct LyricsPlusLine: Codable {
    let time: Double        // milliseconds
    let text: String
    let duration: Double?
    let syllabus: [LyricsPlusWord]?
}

private nonisolated struct LyricsPlusWord: Codable {
    let time: Double        // milliseconds
    let duration: Double    // milliseconds
    let text: String
}

private nonisolated struct LRCLibResponse: Codable {
    let plainLyrics: String?
    let syncedLyrics: String?
}

// MARK: - Disk Cache Model

private nonisolated struct CachedLyrics: Codable {
    struct Word: Codable {
        let text: String
        let start: Double
        let end: Double
    }
    struct Line: Codable {
        let time: Double
        let text: String
        let words: [Word]?
    }

    let plain: String?
    let lines: [Line]

    init(from result: LyricsResult) {
        plain = result.plainLyrics
        lines = result.syncedLyrics.map { line in
            Line(
                time: line.time,
                text: line.text,
                words: line.words?.map { Word(text: $0.text, start: $0.start, end: $0.end) }
            )
        }
    }

    func toResult() -> LyricsResult {
        LyricsResult(
            plain: plain,
            synced: lines.map { line in
                SyncedLine(
                    time: line.time,
                    text: line.text,
                    words: line.words?.map { SyncedWord(text: $0.text, start: $0.start, end: $0.end) }
                )
            }
        )
    }
}

// MARK: - Models

nonisolated struct LyricsResult {
    let plainLyrics: String?
    let syncedLyrics: [SyncedLine]

    var hasSyncedLyrics: Bool { !syncedLyrics.isEmpty }

    init(plain: String?, synced: [SyncedLine]) {
        self.plainLyrics = plain
        self.syncedLyrics = synced
    }

    /// Parse LRC text (synced). Falls back to treating content as plain text.
    init(lrcText: String) {
        let synced = Self.parseSyncedLyrics(lrcText)
        self.syncedLyrics = synced
        if synced.isEmpty {
            let trimmed = lrcText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.plainLyrics = trimmed.isEmpty ? nil : trimmed
        } else {
            self.plainLyrics = nil
        }
    }

    init(plainText: String) {
        self.plainLyrics = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.syncedLyrics = []
    }

    // MARK: - LRC Parsing

    /// Parses standard LRC `[mm:ss.xx]text` lines, including multiple timestamps
    /// per line and enhanced LRC word timing `<mm:ss.xx>word`.
    static func parseSyncedLyrics(_ lrc: String?) -> [SyncedLine] {
        guard let lrc = lrc else { return [] }

        var lines: [SyncedLine] = []
        let linePattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else { return [] }

        for rawLine in lrc.components(separatedBy: .newlines) {
            let nsLine = rawLine as NSString
            let matches = lineRegex.matches(in: rawLine, range: NSRange(location: 0, length: nsLine.length))
            guard !matches.isEmpty else { continue }

            // Text is everything after the last leading timestamp
            let lastMatch = matches.last!
            let textStart = lastMatch.range.location + lastMatch.range.length
            let rawText = nsLine.substring(from: textStart)

            let (text, words) = parseEnhancedWords(rawText)
            let cleanText = text.trimmingCharacters(in: .whitespaces)
            guard !cleanText.isEmpty else { continue }

            for match in matches {
                guard let time = timestamp(from: match, in: nsLine) else { continue }
                lines.append(SyncedLine(time: time, text: cleanText, words: words))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    private static func timestamp(from match: NSTextCheckingResult, in line: NSString) -> TimeInterval? {
        guard match.numberOfRanges >= 3 else { return nil }
        let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
        let seconds = Double(line.substring(with: match.range(at: 2))) ?? 0

        var fraction = 0.0
        if match.range(at: 3).location != NSNotFound {
            let fracString = line.substring(with: match.range(at: 3))
            let fracValue = Double(fracString) ?? 0
            fraction = fracValue / pow(10, Double(fracString.count))
        }

        return minutes * 60 + seconds + fraction
    }

    /// Parses enhanced LRC word timing: `<mm:ss.xx>word <mm:ss.xx>word`.
    /// Returns the plain text and per-word timing when available.
    private static func parseEnhancedWords(_ text: String) -> (String, [SyncedWord]?) {
        let wordPattern = #"<(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?>"#
        guard let regex = try? NSRegularExpression(pattern: wordPattern) else { return (text, nil) }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard matches.count >= 2 else {
            // Not enhanced LRC; strip any stray tags
            let stripped = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: nsText.length), withTemplate: "")
            return (stripped, nil)
        }

        var words: [SyncedWord] = []
        var plain = ""

        for (index, match) in matches.enumerated() {
            guard let start = timestamp(from: match, in: nsText) else { continue }

            let segmentStart = match.range.location + match.range.length
            let segmentEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            guard segmentEnd >= segmentStart else { continue }

            let segment = nsText.substring(with: NSRange(location: segmentStart, length: segmentEnd - segmentStart))
            guard !segment.isEmpty else { continue }

            let end: TimeInterval
            if index + 1 < matches.count, let nextStart = timestamp(from: matches[index + 1], in: nsText) {
                end = nextStart
            } else {
                end = start + 1.0
            }

            words.append(SyncedWord(text: segment, start: start, end: end))
            plain += segment
        }

        guard !words.isEmpty else { return (text, nil) }
        return (plain, words)
    }
}

nonisolated struct SyncedLine: Identifiable {
    let id = UUID()
    let time: TimeInterval
    let text: String
    var words: [SyncedWord]? = nil
}

nonisolated struct SyncedWord: Identifiable {
    let id = UUID()
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}
