//
//  MetadataExtractor.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Hybrid metadata extractor: BASS for audio info, AVFoundation for artwork
//

import Foundation
import AppKit
import Bass
import AVFoundation

/// Metadata extractor using BASS for text tags and AVFoundation for artwork
/// AVFoundation is required for reliable FLAC/MP4 artwork extraction
final class MetadataExtractor {
    
    static let shared = MetadataExtractor()
    private init() {}
    
    private let extractionQueue = DispatchQueue(label: "com.sangeet.metadata", qos: .utility)
    
    // MARK: - Main Extraction
    
    /// Extract all metadata from an audio file
    func extractMetadata(from url: URL) async -> TrackMetadata {
        var metadata = TrackMetadata()
        metadata.fileURL = url
        
        // Extract text metadata using BASS (fast, accurate for text tags)
        let bassMetadata = await extractWithBASS(from: url)
        metadata.title = bassMetadata.title
        metadata.artist = bassMetadata.artist
        metadata.album = bassMetadata.album
        metadata.year = bassMetadata.year
        metadata.duration = bassMetadata.duration
        
        // Extract artwork using AVFoundation (most reliable for all formats)
        metadata.artworkData = await extractArtworkWithAVFoundation(from: url)
        
        // Fallback to folder artwork if no embedded artwork
        if metadata.artworkData == nil {
            metadata.artworkData = findFolderArtwork(for: url)
        }
        
        // Parse filename for missing fields
        metadata = parseFilename(url: url, metadata: metadata)
        
        return metadata
    }
    
    // MARK: - BASS Text Extraction
    
    private func extractWithBASS(from url: URL) async -> TrackMetadata {
        await withCheckedContinuation { continuation in
            extractionQueue.async {
                var meta = TrackMetadata()
                meta.fileURL = url
                
                let path = url.path
                let stream = BASS_StreamCreateFile(
                    BOOL32(truncating: false),
                    path,
                    0,
                    0,
                    DWORD(BASS_STREAM_DECODE)
                )
                
                defer {
                    if stream != 0 { BASS_StreamFree(stream) }
                }
                
                guard stream != 0 else {
                    continuation.resume(returning: meta)
                    return
                }
                
                // Duration
                let bytes = BASS_ChannelGetLength(stream, DWORD(BASS_POS_BYTE))
                meta.duration = BASS_ChannelBytes2Seconds(stream, bytes)
                
                // ID3v1 tags
                if let tags = self.extractID3v1(from: stream) {
                    meta.title = tags.title
                    meta.artist = tags.artist
                    meta.album = tags.album
                    meta.year = tags.year
                }
                
                // Modern tags (ID3v2/MP4/OGG) - override ID3v1
                if let tags = self.extractModernTags(from: stream) {
                    if let t = tags["title"], !t.isEmpty { meta.title = t }
                    if let a = tags["artist"], !a.isEmpty { meta.artist = a }
                    if let al = tags["album"], !al.isEmpty { meta.album = al }
                    if let y = tags["year"], let year = Int(y.prefix(4)) { meta.year = year }
                }
                
                continuation.resume(returning: meta)
            }
        }
    }
    
    private func extractID3v1(from stream: HSTREAM) -> (title: String?, artist: String?, album: String?, year: Int?)? {
        guard let ptr = BASS_ChannelGetTags(stream, DWORD(BASS_TAG_ID3)) else { return nil }
        
        let tag = ptr.withMemoryRebound(to: TAG_ID3.self, capacity: 1) { $0.pointee }
        
        func getString(_ tuple: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                 CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                 CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)) -> String {
            var arr = [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7, tuple.8, tuple.9,
                       tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15, tuple.16, tuple.17, tuple.18, tuple.19,
                       tuple.20, tuple.21, tuple.22, tuple.23, tuple.24, tuple.25, tuple.26, tuple.27, tuple.28, tuple.29, 0]
            return String(cString: &arr).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        func getYear(_ tuple: (CChar, CChar, CChar, CChar)) -> Int? {
            var arr = [tuple.0, tuple.1, tuple.2, tuple.3, 0]
            let str = String(cString: &arr).trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(str)
        }
        
        return (getString(tag.title), getString(tag.artist), getString(tag.album), getYear(tag.year))
    }
    
    private func extractModernTags(from stream: HSTREAM) -> [String: String]? {
        // Try MP4 tags
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_MP4))) {
            return tags
        }
        // Try OGG tags (also used by FLAC)
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_OGG))) {
            return tags
        }
        // Try APE tags
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_APE))) {
            return tags
        }
        return nil
    }
    
    private func parseNullTerminatedTags(_ ptr: UnsafePointer<CChar>?) -> [String: String]? {
        guard let ptr = ptr else { return nil }
        
        var result = [String: String]()
        var current = ptr
        
        while true {
            let str = String(cString: current)
            if str.isEmpty { break }
            
            if let eq = str.firstIndex(of: "=") {
                let key = String(str[..<eq]).lowercased()
                let value = String(str[str.index(after: eq)...])
                result[key] = value
            }
            
            current = current.advanced(by: str.utf8.count + 1)
        }
        
        return result.isEmpty ? nil : result
    }
    
    // MARK: - AVFoundation Artwork Extraction
    
    private func extractArtworkWithAVFoundation(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)
        
        do {
            // Load all metadata formats
            let formats = try await asset.load(.availableMetadataFormats)
            
            for format in formats {
                let items = try await asset.loadMetadata(for: format)
                
                for item in items {
                    // Check for artwork by common key
                    if let commonKey = item.commonKey, commonKey == .commonKeyArtwork {
                        if let data = try? await item.load(.dataValue) {
                            return data
                        }
                    }
                    
                    // Also check specific keys for different formats
                    if let key = item.key as? String {
                        let lowercaseKey = key.lowercased()
                        if lowercaseKey.contains("artwork") || 
                           lowercaseKey.contains("cover") || 
                           lowercaseKey.contains("apic") ||
                           lowercaseKey.contains("pic") {
                            if let data = try? await item.load(.dataValue) {
                                return data
                            }
                        }
                    }
                }
            }
        } catch {
            // Silently fail - artwork is optional
        }
        
        return nil
    }
    
    // MARK: - Folder Artwork Fallback
    
    private func findFolderArtwork(for url: URL) -> Data? {
        let folder = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        
        // Priority 1: Exact sidecar match (e.g. "Song.flac" -> "Song.jpg")
        let sidecarURL = folder.appendingPathComponent("\(filename).jpg")
        if let data = try? Data(contentsOf: sidecarURL) {
            return data
        }
        
        // Priority 2: Standard folder names
        let names = ["cover.jpg", "cover.png", "folder.jpg", "folder.png", 
                     "artwork.jpg", "artwork.png", "front.jpg", "front.png",
                     "Cover.jpg", "Cover.png", "Folder.jpg", "Folder.png"]
        
        for name in names {
            let artworkURL = folder.appendingPathComponent(name)
            if let data = try? Data(contentsOf: artworkURL) {
                return data
            }
        }
        
        return nil
    }
    
    // MARK: - Filename Parsing
    
    private func parseFilename(url: URL, metadata: TrackMetadata) -> TrackMetadata {
        var result = metadata
        
        if result.title == nil || result.title?.isEmpty == true {
            let filename = url.deletingPathExtension().lastPathComponent
            let parts = filename.components(separatedBy: " - ")
            if parts.count >= 2 {
                result.artist = result.artist ?? parts[0].trimmingCharacters(in: .whitespaces)
                result.title = parts.dropFirst().joined(separator: " - ")
            } else {
                result.title = filename
            }
        }
        
        if result.album == nil || result.album?.isEmpty == true {
            result.album = url.deletingLastPathComponent().lastPathComponent
        }
        
        if result.artist == nil || result.artist?.isEmpty == true {
            result.artist = "Unknown Artist"
        }
        
        return result
    }
    
    // MARK: - Public Artwork Extraction
    
    func extractArtwork(from url: URL) async -> NSImage? {
        if let data = await extractArtworkWithAVFoundation(from: url) {
            return NSImage(data: data)
        }
        
        if let data = findFolderArtwork(for: url) {
            return NSImage(data: data)
        }
        
        return nil
    }
    
    // MARK: - ReplayGain Extraction
    
    /// Extract ReplayGain from BASS tags
    func extractReplayGain(from url: URL) -> Float? {
        let path = url.path
        let stream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            path,
            0,
            0,
            DWORD(BASS_STREAM_DECODE)
        )
        
        guard stream != 0 else { return nil }
        defer { BASS_StreamFree(stream) }
        
        // Check OGG/FLAC tags
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_OGG))) {
            if let gain = parseReplayGainValue(tags["REPLAYGAIN_TRACK_GAIN"]) { return gain }
            if let gain = parseReplayGainValue(tags["replaygain_track_gain"]) { return gain }
        }
        
        // Check APE tags
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_APE))) {
            if let gain = parseReplayGainValue(tags["REPLAYGAIN_TRACK_GAIN"]) { return gain }
            if let gain = parseReplayGainValue(tags["replaygain_track_gain"]) { return gain }
        }
        
        // Check MP4 tags (iTunes Sound Check - convert to ReplayGain)
        if let tags = parseNullTerminatedTags(BASS_ChannelGetTags(stream, DWORD(BASS_TAG_MP4))) {
            if let gain = parseReplayGainValue(tags["REPLAYGAIN_TRACK_GAIN"]) { return gain }
        }
        
        return nil
    }
    
    private func parseReplayGainValue(_ value: String?) -> Float? {
        guard let value = value else { return nil }
        // Format: "-3.5 dB" or "+2.1 dB"
        let cleaned = value.replacingOccurrences(of: " dB", with: "")
                           .replacingOccurrences(of: "dB", with: "")
                           .trimmingCharacters(in: .whitespaces)
        return Float(cleaned)
    }
    
    // MARK: - Sample Rate Extraction
    
    /// Get source file sample rate
    func getSourceSampleRate(from url: URL) -> Double {
        let path = url.path
        let stream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            path,
            0,
            0,
            DWORD(BASS_STREAM_DECODE)
        )
        
        guard stream != 0 else { return 0 }
        defer { BASS_StreamFree(stream) }
        
        var info = BASS_CHANNELINFO()
        if BASS_ChannelGetInfo(stream, &info) != 0 {
            return Double(info.freq)
        }
        return 0
    }
}

// MARK: - Track Metadata

struct TrackMetadata {
    var title: String?
    var artist: String?
    var album: String?
    var duration: TimeInterval = 0
    var year: Int?
    var artworkData: Data?
    var fileURL: URL?
    var replayGainDB: Float?  // ReplayGain value in dB
    var sampleRate: Double = 0  // Source sample rate
    
    func toTrack() -> Track {
        Track(
            title: title ?? "Unknown",
            artist: artist ?? "Unknown Artist",
            album: album ?? "Unknown Album",
            duration: duration,
            fileURL: fileURL ?? URL(fileURLWithPath: "/"),
            artworkData: artworkData
        )
    }
}
