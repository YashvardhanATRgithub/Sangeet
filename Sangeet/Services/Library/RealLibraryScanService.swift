import Foundation
import Combine

class RealLibraryScanService: LibraryScanService {
    @Published var isScanning: Bool = false
    
    // Supported extensions
    private let allowedExtensions = Set([
        "mp3", "m4a", "aac", "wav", "aiff", "caf", "flac", "ogg", "opus", "wma", "ape"
    ])
    
    private let database: DatabaseLayer
    private let metadataService: MetadataService
    private let searchService: SearchService?
    private let directoryWatcher = DirectoryWatcher()
    private let stateQueue = DispatchQueue(label: "com.sangeet.libraryscan.state")
    private var isScanningFlag = false
    private var pendingDirectories = Set<URL>()
    private var monitoredDirectories = Set<URL>()
    private var queuedChangeDirectories = Set<URL>()
    private var rescanTask: Task<Void, Never>?
    
    init(database: DatabaseLayer, metadataService: MetadataService, searchService: SearchService? = nil) {
        self.database = database
        self.metadataService = metadataService
        self.searchService = searchService
        self.directoryWatcher.onChanges = { [weak self] url in
            self?.scheduleRescan(for: url)
        }
    }
    
    func startScan(directories: [URL]) async throws {
        let normalized = normalizedDirectories(from: directories)
        let directoriesToWatch = stateQueue.sync { () -> [URL]? in
            let didUpdate = updateMonitoring(with: normalized)
            return didUpdate ? Array(monitoredDirectories) : nil
        }
        if let directoriesToWatch {
            directoryWatcher.startMonitoring(directories: directoriesToWatch)
        }
        
        let shouldStart = stateQueue.sync { () -> Bool in
            if isScanningFlag {
                pendingDirectories.formUnion(normalized)
                return false
            }
            isScanningFlag = true
            return true
        }
        
        guard shouldStart else { return }
        await MainActor.run { self.isScanning = true }
        defer {
            Task { @MainActor in self.isScanning = false }
            Task { await searchService?.buildIndex() }
            
            // Prune missing files
            Task {
                await self.pruneMissingTracks()
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
            }
            
            let pending = stateQueue.sync { () -> [URL] in
                let queued = pendingDirectories
                pendingDirectories.removeAll()
                isScanningFlag = false
                return Array(queued)
            }
            
            if !pending.isEmpty {
                Task {
                    try? await self.startScan(directories: pending)
                }
            }
        }
        
        for directory in normalized {
            // Start accessing security scoped resource if needed
            let accessing = directory.startAccessingSecurityScopedResource()
            defer { 
                if accessing { directory.stopAccessingSecurityScopedResource() }
            }
            
            let fileManager = FileManager.default
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            
            // 1. Collect files first (Fast IO)
            var filesToProcess: [URL] = []
            while let fileURL = enumerator?.nextObject() as? URL {
                if allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                    filesToProcess.append(fileURL)
                }
            }
            
            // 2. Process in Parallel (throttled to 5 concurrent tasks to prevent network saturation)
            await withTaskGroup(of: Void.self) { group in
                var activeTasks = 0
                for fileURL in filesToProcess {
                    if Task.isCancelled { break }
                    
                    if activeTasks >= 5 {
                        await group.next()
                        activeTasks -= 1
                    }
                    
                    group.addTask {
                        do {
                            // This now includes Network Calls (Lyrics/Metadata)
                            let track = try await self.metadataService.metadata(for: fileURL)
                            try await self.database.saveTrack(track)
                        } catch {
                            print("Failed to process \(fileURL.lastPathComponent): \(error)")
                        }
                    }
                    activeTasks += 1
                }
            }
        }
    }
    
    func cancelScan() {
        // Implementation for cancellation token would go here
        // For now, simple boolean flag check in loop (not shown above for brevity)
    }
    
    func startMonitoring(directories: [URL]) {
        let normalized = normalizedDirectories(from: directories)
        let directoriesToWatch = stateQueue.sync { () -> [URL] in
            _ = updateMonitoring(with: normalized)
            return Array(monitoredDirectories)
        }
        directoryWatcher.startMonitoring(directories: directoriesToWatch)
    }
    
    // Security Bookmarks Helpers
    func saveBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    
    func resolveBookmark(data: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return url
    }
    
    private func scheduleRescan(for url: URL) {
        let normalized = normalizedDirectories(from: [url])
        stateQueue.sync {
            self.queuedChangeDirectories.formUnion(normalized)
        }
        
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            let pending = self.stateQueue.sync { () -> [URL] in
                let queued = self.queuedChangeDirectories
                self.queuedChangeDirectories.removeAll()
                return Array(queued)
            }
            guard !pending.isEmpty else { return }
            try? await self.startScan(directories: pending)
        }
    }
    
    private func normalizedDirectories(from urls: [URL]) -> [URL] {
        let directories = urls.map { url -> URL in
            url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        }
        return Array(Set(directories.map { $0.standardizedFileURL }))
    }
    
    private func updateMonitoring(with directories: [URL]) -> Bool {
        let beforeCount = monitoredDirectories.count
        monitoredDirectories.formUnion(directories)
        return monitoredDirectories.count != beforeCount
    }
    
    private func pruneMissingTracks() async {
        guard let allTracks = try? await database.fetchAllTracks() else { return }
        
        print("DEBUG: Pruning library. Checking \(allTracks.count) tracks...")
        var deletedCount = 0
        
        for track in allTracks {
            // Check if file exists. 
            // Note: security scoped resource access might be needed if not in a monitored folder, 
            // but for simple existence check in a standard user folder, fileExists usually works 
            // if we have read access to parent. If access is lost, we might delete valid tracks.
            // Safe bet: accessing.
            
            let accessing = track.url.startAccessingSecurityScopedResource()
            let exists = FileManager.default.fileExists(atPath: track.url.path)
            if accessing { track.url.stopAccessingSecurityScopedResource() }
            
            if !exists {
                print("DEBUG: removing missing track: \(track.title) (\(track.url.path))")
                await database.deleteTrack(for: track.id)
                deletedCount += 1
            }
        }
        
        if deletedCount > 0 {
            print("DEBUG: Pruned \(deletedCount) missing tracks.")
        }
    }
}



