//
//  StreamCache.swift
//  Sangeet3
//
//  Caches streamed audio files locally for offline resume.
//

import Foundation

/// Manages caching of streamed audio files for offline playback resume.
actor StreamCache {
    static let shared = StreamCache()
    
    private let cacheDirectory: URL
    private let maxCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB
    
    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("StreamCache", isDirectory: true)
        
        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        Task {
            await cleanupIfNeeded()
        }
    }
    
    /// Get cached file URL for a Tidal track ID, if it exists.
    func getCachedFileURL(for trackID: Int) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent("\(trackID).flac")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            print("[StreamCache] Cache HIT for trackID \(trackID)")
            return fileURL
        }
        return nil
    }
    
    /// Download and cache a stream URL in the background.
    /// This runs asynchronously and does not block playback.
    func cacheStreamInBackground(from remoteURL: URL, trackID: Int) {
        let destinationURL = cacheDirectory.appendingPathComponent("\(trackID).flac")
        
        // Don't re-download if already cached
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            print("[StreamCache] Track \(trackID) already cached.")
            return
        }
        
        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(from: remoteURL)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    print("[StreamCache] Failed to download stream for \(trackID): Invalid response")
                    return
                }
                
                try data.write(to: destinationURL)
                print("[StreamCache] Successfully cached trackID \(trackID) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)))")
                
                // Trigger cleanup after caching
                await StreamCache.shared.cleanupIfNeeded()
                
            } catch {
                print("[StreamCache] Cache error for \(trackID): \(error.localizedDescription)")
            }
        }
    }
    
    /// Remove oldest files if cache exceeds max size.
    private func cleanupIfNeeded() async {
        do {
            let fm = FileManager.default
            let files = try fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            var totalSize: Int64 = 0
            var fileInfos: [(url: URL, size: Int64, date: Date)] = []
            
            for file in files {
                let resources = try file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let size = Int64(resources.fileSize ?? 0)
                let date = resources.creationDate ?? Date.distantPast
                totalSize += size
                fileInfos.append((file, size, date))
            }
            
            guard totalSize > maxCacheSize else { return }
            
            // Sort by oldest first
            fileInfos.sort { $0.date < $1.date }
            
            var currentSize = totalSize
            for info in fileInfos {
                guard currentSize > maxCacheSize else { break }
                try? fm.removeItem(at: info.url)
                currentSize -= info.size
                print("[StreamCache] Evicted old cache file: \(info.url.lastPathComponent)")
            }
            
        } catch {
            print("[StreamCache] Cleanup error: \(error)")
        }
    }
    
    /// Purge the entire cache.
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("[StreamCache] Cache cleared.")
    }
}
