//
//  LyricLine.swift
//  HiFidelity
//
//  LRC lyrics support with time-synchronized display
//

import Foundation

/// Represents a single line of lyrics with timestamp
struct LyricLine: Identifiable, Codable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval  // Time in seconds
    let text: String
    
    enum CodingKeys: String, CodingKey {
        case timestamp
        case text
    }
    
    /// Create a lyric line from LRC format: [mm:ss.xx]text
    init?(lrcLine: String) {
        let pattern = #"\[(\d+):(\d+)\.(\d+)\](.+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lrcLine, range: NSRange(lrcLine.startIndex..., in: lrcLine)) else {
            return nil
        }
        
        // Extract time components
        guard let minutesRange = Range(match.range(at: 1), in: lrcLine),
              let secondsRange = Range(match.range(at: 2), in: lrcLine),
              let centisecondsRange = Range(match.range(at: 3), in: lrcLine),
              let textRange = Range(match.range(at: 4), in: lrcLine) else {
            return nil
        }
        
        let minutes = Double(lrcLine[minutesRange]) ?? 0
        let seconds = Double(lrcLine[secondsRange]) ?? 0
        let centiseconds = Double(lrcLine[centisecondsRange]) ?? 0
        
        self.timestamp = minutes * 60 + seconds + centiseconds / 100
        self.text = String(lrcLine[textRange]).trimmingCharacters(in: .whitespaces)
    }
    
    /// Direct initializer
    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
    
    /// Format timestamp as [mm:ss.xx]
    var lrcTimestamp: String {
        let minutes = Int(timestamp) / 60
        let seconds = Int(timestamp) % 60
        let centiseconds = Int((timestamp.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }
    
    /// Format as LRC line
    var lrcFormat: String {
        "\(lrcTimestamp)\(text)"
    }
}

/// Complete lyrics with metadata
struct Lyrics: Codable, Equatable {
    var lines: [LyricLine]
    var metadata: LyricsMetadata?
    
    /// Parse LRC file content
    init(lrcContent: String) {
        var parsedLines: [LyricLine] = []
        var meta = LyricsMetadata()
        
        let lines = lrcContent.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            // Parse metadata tags
            if trimmed.hasPrefix("[ti:") {
                meta.title = Self.extractMetadata(from: trimmed, tag: "ti")
            } else if trimmed.hasPrefix("[ar:") {
                meta.artist = Self.extractMetadata(from: trimmed, tag: "ar")
            } else if trimmed.hasPrefix("[al:") {
                meta.album = Self.extractMetadata(from: trimmed, tag: "al")
            } else if trimmed.hasPrefix("[by:") {
                meta.creator = Self.extractMetadata(from: trimmed, tag: "by")
            } else if trimmed.hasPrefix("[offset:") {
                if let offsetStr = Self.extractMetadata(from: trimmed, tag: "offset"),
                   let offset = Int(offsetStr) {
                    meta.offset = Double(offset) / 1000.0  // Convert ms to seconds
                }
            } else if let lyricLine = LyricLine(lrcLine: trimmed) {
                parsedLines.append(lyricLine)
            }
        }
        
        // Sort by timestamp
        self.lines = parsedLines.sorted { $0.timestamp < $1.timestamp }
        self.metadata = meta.isEmpty ? nil : meta
    }
    
    /// Empty lyrics
    init() {
        self.lines = []
        self.metadata = nil
    }
    
    private static func extractMetadata(from line: String, tag: String) -> String? {
        let pattern = "\\[\(tag):(.+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[range]).trimmingCharacters(in: .whitespaces)
    }
    
    /// Get lyric line for specific playback time
    func currentLine(at time: TimeInterval) -> LyricLine? {
        // Apply offset if present
        let adjustedTime = time - (metadata?.offset ?? 0)
        
        // Find the line that should be displayed at this time
        // Returns the line with the highest timestamp that is <= current time
        var currentLine: LyricLine?
        
        for line in lines {
            if line.timestamp <= adjustedTime {
                currentLine = line
            } else {
                break  // Lines are sorted, so we can stop here
            }
        }
        
        return currentLine
    }
    
    /// Get index of current line
    func currentLineIndex(at time: TimeInterval) -> Int? {
        let adjustedTime = time - (metadata?.offset ?? 0)
        
        for (index, line) in lines.enumerated() {
            if index == lines.count - 1 {
                // Last line
                if line.timestamp <= adjustedTime {
                    return index
                }
            } else {
                let nextLine = lines[index + 1]
                if line.timestamp <= adjustedTime && adjustedTime < nextLine.timestamp {
                    return index
                }
            }
        }
        
        return nil
    }
    
    /// Export as LRC format
    func toLRC() -> String {
        var lrc = ""
        
        // Add metadata
        if let meta = metadata {
            if let title = meta.title {
                lrc += "[ti:\(title)]\n"
            }
            if let artist = meta.artist {
                lrc += "[ar:\(artist)]\n"
            }
            if let album = meta.album {
                lrc += "[al:\(album)]\n"
            }
            if let creator = meta.creator {
                lrc += "[by:\(creator)]\n"
            }
            if meta.offset != 0 {
                lrc += "[offset:\(Int(meta.offset * 1000))]\n"
            }
            lrc += "\n"
        }
        
        // Add lyric lines
        for line in lines {
            lrc += line.lrcFormat + "\n"
        }
        
        return lrc
    }
}

/// LRC metadata
struct LyricsMetadata: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var creator: String?  // Person who created the LRC file
    var offset: TimeInterval = 0  // Time offset in seconds
    
    var isEmpty: Bool {
        title == nil && artist == nil && album == nil && creator == nil && offset == 0
    }
}

