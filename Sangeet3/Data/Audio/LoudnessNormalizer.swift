//
//  LoudnessNormalizer.swift
//  Sangeet3
//
//  Created by Yashvardhan on 30/12/24.
//
//  Library-based loudness normalization - calculates loudness from library tracks
//

import Foundation
import Bass

/// Calculates loudness normalization using library statistics
final class LoudnessNormalizer {
    
    static let shared = LoudnessNormalizer()
    
    /// Target loudness in dB (similar to -14 LUFS used by Spotify)
    private let targetLoudness: Float = -14.0
    
    /// Cached loudness values for tracks (URL path -> dB)
    private var loudnessCache: [String: Float] = [:]
    
    /// Library average loudness
    private var libraryAverage: Float = -14.0
    
    private init() {
        loadCache()
    }
    
    // MARK: - Public API
    
    /// Get normalization gain for a track
    /// Returns the dB adjustment needed to normalize this track
    func getGainForTrack(url: URL) -> Float? {
        let path = url.path
        
        // Check cache first
        if let cached = loudnessCache[path] {
            return targetLoudness - cached
        }
        
        // Calculate on demand
        if let loudness = calculateLoudness(url: url) {
            loudnessCache[path] = loudness
            saveCache()
            return targetLoudness - loudness
        }
        
        return nil
    }
    
    /// Calculate loudness for a single track using RMS
    /// Returns loudness in dB
    func calculateLoudness(url: URL) -> Float? {
        // Create decode stream
        let stream = BASS_StreamCreateFile(
            BOOL32(truncating: false),
            url.path,
            0,
            0,
            DWORD(BASS_STREAM_DECODE | BASS_SAMPLE_FLOAT)
        )
        
        guard stream != 0 else {
            print("[LoudnessNormalizer] Failed to open: \(url.lastPathComponent)")
            return nil
        }
        
        defer { BASS_StreamFree(stream) }
        
        // Read samples and calculate RMS
        var sumSquares: Float = 0
        var sampleCount: Int64 = 0
        let bufferSize = 65536  // 64KB chunks
        var buffer = [Float](repeating: 0, count: bufferSize / 4)
        
        while true {
            let bytesRead = BASS_ChannelGetData(stream, &buffer, DWORD(bufferSize))
            if bytesRead == UInt32.max { break }  // End of stream
            
            let floatsRead = Int(bytesRead) / 4
            for i in 0..<floatsRead {
                sumSquares += buffer[i] * buffer[i]
            }
            sampleCount += Int64(floatsRead)
        }
        
        guard sampleCount > 0 else { return nil }
        
        // Calculate RMS
        let rms = sqrt(sumSquares / Float(sampleCount))
        
        // Convert to dB (reference: 1.0 = 0 dB)
        let loudnessDB: Float
        if rms > 0 {
            loudnessDB = 20 * log10(rms)
        } else {
            loudnessDB = -60  // Very quiet
        }
        
        print("[LoudnessNormalizer] \(url.lastPathComponent): \(loudnessDB) dB")
        return loudnessDB
    }
    
    /// Scan library and calculate average loudness
    func scanLibrary(tracks: [Track], progress: ((Double) -> Void)? = nil) {
        print("[LoudnessNormalizer] Scanning \(tracks.count) tracks...")
        
        var validLoudness: [Float] = []
        
        for (index, track) in tracks.enumerated() {
            if let loudness = calculateLoudness(url: track.fileURL) {
                loudnessCache[track.fileURL.path] = loudness
                validLoudness.append(loudness)
            }
            
            progress?(Double(index + 1) / Double(tracks.count))
        }
        
        // Calculate average
        if !validLoudness.isEmpty {
            libraryAverage = validLoudness.reduce(0, +) / Float(validLoudness.count)
            print("[LoudnessNormalizer] Library average: \(libraryAverage) dB")
        }
        
        saveCache()
    }
    
    /// Get cached loudness count
    var cachedCount: Int {
        return loudnessCache.count
    }
    
    /// Clear all cached data
    func clearCache() {
        loudnessCache.removeAll()
        UserDefaults.standard.removeObject(forKey: "loudnessCache")
    }
    
    // MARK: - Persistence
    
    private func loadCache() {
        if let data = UserDefaults.standard.data(forKey: "loudnessCache"),
           let cache = try? JSONDecoder().decode([String: Float].self, from: data) {
            loudnessCache = cache
            print("[LoudnessNormalizer] Loaded \(cache.count) cached entries")
        }
        
        libraryAverage = UserDefaults.standard.float(forKey: "libraryAverageLoudness")
        if libraryAverage == 0 {
            libraryAverage = -14.0
        }
    }
    
    private func saveCache() {
        if let data = try? JSONEncoder().encode(loudnessCache) {
            UserDefaults.standard.set(data, forKey: "loudnessCache")
        }
        UserDefaults.standard.set(libraryAverage, forKey: "libraryAverageLoudness")
    }
}
