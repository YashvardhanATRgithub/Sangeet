import Foundation
import Combine

@MainActor
class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    // MARK: - State
    struct DownloadTask: Identifiable {
        let id: Int
        let track: TidalTrack
        var state: DownloadState
        var task: URLSessionDownloadTask? // Hold reference to cancel
    }
    
    enum DownloadState: Equatable {
        case preparing
        case downloading(progress: Double)
        case finished
        case failed(String)
        case cancelled
    }
    
    // TrackID -> DownloadTask
    @Published var activeDownloads: [Int: DownloadTask] = [:] 
    @Published var lastError: String? // For global error reporting
    
    private var downloadSession: URLSession!
    
    // MARK: - Dependencies
    private let tidalService = TidalDLService.shared
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        // Create session with self as delegate for progress updates
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    // MARK: - Actions
    
    func download(track: TidalTrack) {
        // Prevent duplicate starts
        if activeDownloads[track.id] != nil { return }
        
        // Immediate UI Feedback
        activeDownloads[track.id] = DownloadTask(id: track.id, track: track, state: .preparing)
        
        Task { @MainActor in
            // Determine download directory
            var targetDir: URL? = LibraryManager.shared.folders.first
            
            if targetDir == nil {
                if let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first {
                     let dir = music.appendingPathComponent("Sangeet Downloads")
                     do {
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        targetDir = dir
                     } catch {
                         print("[DownloadManager] Failed to create dir: \(error)")
                         self.lastError = "Could not create download folder: \(error.localizedDescription)"
                         // Update state to failed
                         if var task = activeDownloads[track.id] {
                             task.state = .failed("Dir Error")
                             activeDownloads[track.id] = task
                         }
                         return
                     }
                }
            }
            
            guard let downloadDir = targetDir else {
                print("[DownloadManager] No download directory available")
                 if var task = activeDownloads[track.id] {
                     task.state = .failed("No Folder")
                     activeDownloads[track.id] = task
                 }
                return
            }
            
            // Add folder to library tracking if mostly new
             if let path = targetDir {
                 await LibraryManager.shared.addFolder(url: path)
             }
            
            // Start Download Process
            await startDownload(track: track, to: downloadDir)
        }
    }
    
    func cancelDownload(trackID: Int) {
        guard var task = activeDownloads[trackID] else { return }
        
        task.task?.cancel()
        task.state = .cancelled
        activeDownloads[trackID] = task
        
        // Remove after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if self.activeDownloads[trackID]?.state == .cancelled {
                self.activeDownloads.removeValue(forKey: trackID)
            }
        }
    }
    
    func retryDownload(trackID: Int) {
        guard let task = activeDownloads[trackID] else { return }
        // Reset and restart
        download(track: task.track)
    }
    
    @MainActor
    private func startDownload(track: TidalTrack, to directory: URL) async {
        do {
            // 1. Get Stream URL (Use LOSSLESS - HI_RES returns DASH manifest requiring segment assembly)
            guard let streamURL = try await tidalService.getStreamURL(trackID: track.id, quality: .LOSSLESS) else {
                throw NSError(domain: "TidalDL", code: 404, userInfo: [NSLocalizedDescriptionKey: "Stream URL not found"])
            }
            
            // 2. Prepare Destination
            let safeArtistName = track.artist?.name ?? "Unknown Artist"
            let safeAlbumName = track.album.title
            
            let fileName = "\(safeArtistName) - \(track.title).flac"
                .replacingOccurrences(of: "/", with: "-") // Sanitize
            let destinationURL = directory.appendingPathComponent(fileName)
            
            // 3. Start Download Task (using delegate for progress)
            let downloadTask = downloadSession.downloadTask(with: streamURL)
            downloadTask.taskDescription = "\(track.id)" // Store ID to find task later
            
            // Store task reference
            if var currentTask = activeDownloads[track.id] {
                currentTask.task = downloadTask
                currentTask.state = .downloading(progress: 0)
                activeDownloads[track.id] = currentTask
            }
            
            downloadTask.resume()
            
            // Note: Progress updates will come via delegate methods below
            
             // 4. Handle Metadata (concurrently)
             Task {
                 // Save Sidecar Metadata
                 let metadataFile = destinationURL.deletingPathExtension().appendingPathExtension("json")
                 // Simple metadata format for now
                 let meta = ["id": "\(track.id)", "title": track.title, "artist": safeArtistName, "album": safeAlbumName]
                 if let data = try? JSONSerialization.data(withJSONObject: meta) {
                     try? data.write(to: metadataFile)
                 }
                 
                 // Save Artwork Sidecar
                 if let coverURL = track.coverURL, let data = try? Data(contentsOf: coverURL) {
                     let artworkFile = destinationURL.deletingPathExtension().appendingPathExtension("jpg")
                     try? data.write(to: artworkFile)
                 }
             }
            
        } catch {
            print("[DownloadManager] Error: \(error)")
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                if var task = self.activeDownloads[track.id] {
                    task.state = .failed("Error")
                    self.activeDownloads[track.id] = task
                }
            }
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let idStr = downloadTask.taskDescription, let id = Int(idStr) else { return }
        
        Task { @MainActor in
            if var task = self.activeDownloads[id] {
                let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                task.state = .downloading(progress: progress)
                self.activeDownloads[id] = task
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let idStr = downloadTask.taskDescription, let id = Int(idStr) else { return }
        
        // Move file immediately in case location is temporary and deleted after return?
        // URLSession documentation says location is temporary. We must move valid data out.
        // But doing it on MainActor might block UI.
        // We should move it here (background) then notify UI.
        
        let tempLocation = location
        
        Task { @MainActor in
             if let task = self.activeDownloads[id] {
                 // Re-determine directory (simplified)
                 if let targetDir = LibraryManager.shared.folders.first ?? 
                    FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?.appendingPathComponent("Sangeet Downloads") {
                     
                     let safeArtistName = task.track.artist?.name ?? "Unknown Artist"
                     let fileName = "\(safeArtistName) - \(task.track.title).flac"
                         .replacingOccurrences(of: "/", with: "-")
                     let destinationURL = targetDir.appendingPathComponent(fileName)
                     
                     do {
                         // Remove old if exists
                         try? FileManager.default.removeItem(at: destinationURL)
                         // We must copy because 'location' might trigger permission issues if moved?
                         // Actually move is fine.
                         // But wait, 'location' is only valid during the delegate call? 
                         // Yes. If we switch threads, we might lose it?
                         // "The file at location... is removed when this delegate message returns."
                         // CRITICAL: We MUST move it BEFORE returning from this function, or COPY it.
                         // Since we are in 'nonisolated', we can do file IO.
                     } catch {}
                 }
             }
        }
        
        // Correct approach: Move file to a temp "staging" area that we control, THEN switch to MainActor to process it.
        // Or just copy it to a temp path.
        // For simplicity given constraints: use a temporary copy.
        
        let tempDst = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tempDst)
        
        Task { @MainActor in
            // Move file to final destination
             if let task = self.activeDownloads[id] {
                 // Re-determine directory (simplified)
                 if let targetDir = LibraryManager.shared.folders.first ?? 
                    FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first?.appendingPathComponent("Sangeet Downloads") {
                     
                     let safeArtistName = task.track.artist?.name ?? "Unknown Artist"
                     let fileName = "\(safeArtistName) - \(task.track.title).flac"
                         .replacingOccurrences(of: "/", with: "-")
                     let destinationURL = targetDir.appendingPathComponent(fileName)
                     
                     do {
                         // Remove old if exists
                         try? FileManager.default.removeItem(at: destinationURL)
                         try FileManager.default.moveItem(at: tempDst, to: destinationURL)
                         
                         // Success
                         var finishedTask = task
                         finishedTask.state = .finished
                         self.activeDownloads[id] = finishedTask
                         
                         // Notify LibraryManager
                         NotificationCenter.default.post(name: .init("DownloadDidFinish"), object: nil, userInfo: ["track": task.track])
                         
                         // Trigger Library Scan
                         Task {
                             await LibraryManager.shared.scanAllFolders()
                         }
                         
                         // Clear state after delay
                         DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                             self.activeDownloads.removeValue(forKey: id)
                         }
                         
                     } catch {
                         print("Move error: \(error)")
                         var failedTask = task
                         failedTask.state = .failed("Save Error")
                         self.activeDownloads[id] = failedTask
                     }
                 }
             }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, let idStr = task.taskDescription, let id = Int(idStr) {
            Task { @MainActor in
                if var dlTask = self.activeDownloads[id] {
                    dlTask.state = .failed(error.localizedDescription)
                    self.activeDownloads[id] = dlTask
                }
            }
        }
    }
}
