//
//  DownloadButton.swift
//  Sangeet3
//
//  Download button for online tracks
//

import SwiftUI

struct DownloadButton: View {
    let track: Track
    var size: CGFloat = 20
    var color: Color = .white
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var libraryManager: LibraryManager
    
    /// Check if track is already downloaded (exists in local library)
    private var isDownloaded: Bool {
        libraryManager.hasTrack(title: track.title, artist: track.artist)
    }
    
    /// Get download state if actively downloading
    private var downloadState: DownloadManager.DownloadState? {
        // We need to match by title since Track ID won't match TidalTrack ID
        // For now, we won't show progress for Track-based downloads
        nil
    }
    
    var body: some View {
        Button(action: downloadAction) {
            Group {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let state = downloadState {
                     switch state {
                     case .preparing:
                         ProgressView().scaleEffect(0.6)
                     case .downloading(let progress):
                         ProgressView(value: progress).progressViewStyle(.circular).scaleEffect(0.6)
                     case .finished:
                         Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                     case .failed:
                         Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                     case .cancelled:
                         Image(systemName: "arrow.down.circle").foregroundStyle(color)
                     }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(color)
                }
            }
            .font(.system(size: size))
        }
        .buttonStyle(.plain)
        .disabled(isDownloaded)
        .help(isDownloaded ? "Already Downloaded" : "Download to Library")
    }
    
    private func downloadAction() {
        guard !isDownloaded else { return }
        
        // Strategy 1: Direct ID Download (Reliable)
        if let idStr = track.externalID, let tidalID = Int(idStr) {
             print("[DownloadButton] Direct Download via ID: \(tidalID)")
            
             Task {
                 // Reconstruct Cover String from URL
                 var coverID: String? = nil
                 if let urlStr = track.artworkURL?.absoluteString {
                     // Extract uuid parts from tidal url
                     // Format: .../images/a/b/c/d/640x640.jpg
                     // We want a-b-c-d
                     let components = urlStr.components(separatedBy: "/")
                     if components.count >= 5 {
                         // Likely valid.
                         // Find parts that look like hex dash hex...
                         // Actually, simplistic approach:
                         // Path contains /uuid-parts/resolution.jpg
                         if let range = urlStr.range(of: "images/"), let end = urlStr.range(of: "/640x640") {
                             let uuidPart = String(urlStr[range.upperBound..<end.lowerBound])
                             coverID = uuidPart.replacingOccurrences(of: "/", with: "-")
                         }
                     }
                 }
                 
                 let tidalTrack = TidalTrack(
                     id: tidalID,
                     title: track.title,
                     duration: Int(track.duration),
                     artist: TidalArtist(id: 0, name: track.artist),
                     artists: nil,
                     album: TidalAlbum(id: 0, title: track.album, cover: coverID),
                     releaseDate: nil,
                     popularity: nil
                 )
                 
                 await MainActor.run {
                     downloadManager.download(track: tidalTrack)
                 }
             }
             return
        }
        
        // Strategy 2: Fallback Search (Ambiguous)
        Task {
            // Create a TidalTrack-like object to pass to download manager
            // We need to search first to get the Tidal track ID
            let query = "\(track.title) \(track.artist)"
            do {
                let results = try await TidalDLService.shared.search(query: query)
                // Filter by title match to avoid "Shake It Off" vs "Lover" popularity trap
                if let tidalTrack = results.first(where: { $0.title.lowercased().contains(track.title.lowercased()) }) ?? results.first {
                    await MainActor.run {
                        downloadManager.download(track: tidalTrack)
                    }
                }
            } catch {
                print("[DownloadButton] Search error: \(error)")
            }
        }
    }
}

// MARK: - Download Button for TidalTrack (used in trending cards)
struct TidalDownloadButton: View {
    let track: TidalTrack
    var size: CGFloat = 20
    var color: Color = .white
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var libraryManager: LibraryManager
    
    /// Check if track is already downloaded
    private var isDownloaded: Bool {
        libraryManager.hasTrack(title: track.title, artist: track.artistName)
    }
    
    /// Get current download state
    private var downloadState: DownloadManager.DownloadState? {
        downloadManager.activeDownloads[track.id]?.state
    }
    
    var body: some View {
        Button(action: downloadAction) {
            Group {
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let state = downloadState {
                    switch state {
                    case .preparing:
                        ProgressView()
                            .scaleEffect(0.6)
                    case .downloading(let progress):
                        Button {
                            downloadManager.cancelDownload(trackID: track.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(SangeetTheme.primary, lineWidth: 2)
                                    .rotationEffect(.degrees(-90))
                                Image(systemName: "xmark")
                                    .font(.system(size: size * 0.5))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: size, height: size)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Download")
                        
                    case .finished:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            
                    case .failed:
                        Button {
                            downloadManager.retryDownload(trackID: track.id)
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Retry Download")
                        
                    case .cancelled:
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(color)
                    }
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(color)
                }
            }
            .font(.system(size: size))
        }
        .buttonStyle(.plain)
        .disabled(isDownloaded || (downloadState != nil && !isRetryable(downloadState)))
        .help(isDownloaded ? "Already Downloaded" : "Download to Library")
    }
    
    private func isRetryable(_ state: DownloadManager.DownloadState?) -> Bool {
        if case .failed = state { return true }
        if case .cancelled = state { return true }
        return false
    }
    
    private func downloadAction() {
        if case .failed = downloadState {
             downloadManager.retryDownload(trackID: track.id)
             return
        }
        guard !isDownloaded && downloadState == nil else { return }
        downloadManager.download(track: track)
    }
}
