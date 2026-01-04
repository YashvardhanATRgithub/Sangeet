
import SwiftUI

struct OnlineView: View {
    @StateObject private var viewModel = OnlineViewModel()
    @ObservedObject private var downloadManager = DownloadManager.shared
    @EnvironmentObject var libraryManager: LibraryManager // For trending data
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Search Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SangeetTheme.textSecondary)
                    TextField("Search Tidal...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SangeetTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(SangeetTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            }
            .padding(16)
            .frame(height: 80) // Fixed height to prevent layout shift
            .background(SangeetTheme.background)
            
            // Content
            ZStack {
                if viewModel.isSearching && !viewModel.searchText.isEmpty {
                    // Search Results
                    if viewModel.isLoading && viewModel.searchResults.isEmpty {
                        ProgressView().scaleEffect(1.5)
                    } else if viewModel.searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(SangeetTheme.textSecondary)
                            Text("No results found").foregroundStyle(SangeetTheme.textSecondary)
                        }
                    } else {
                        List {
                            ForEach(viewModel.searchResults) { track in
                                OnlineSongRow(track: track, downloadState: downloadManager.activeDownloads[track.id]?.state, onPlay: {
                                    viewModel.playTidalTrack(track)
                                }, onDownload: {
                                    viewModel.downloadTrack(track)
                                })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    // Roaming / Trending
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            
                            // International
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Trending International")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(libraryManager.topSongs) { song in
                                            TrendingSongCard(song: song)
                                                .onTapGesture {
                                                    viewModel.playTrending(song)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                            
                            // India
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Trending India")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(libraryManager.trendingIndiaSongs) { song in
                                            TrendingSongCard(song: song)
                                                .onTapGesture {
                                                    viewModel.playTrending(song)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                            
                            // Legal Disclaimer
                            VStack(spacing: 8) {
                                Divider().background(Color.white.opacity(0.2))
                                
                                Text("Disclaimer")
                                    .font(.caption.bold())
                                    .foregroundStyle(SangeetTheme.textSecondary)
                                    .padding(.top, 8)
                                
                                Text("This tool is provided for educational research purposes only. The developer assumes no liability for copyright infringement or misuse. Users are solely responsible for compliance with local laws and terms of service.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .lineSpacing(4)
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 20)
                            
                            // Bottom Spacer for Dock
                            Spacer()
                                .frame(height: 120)
                        }
                        .padding(.vertical, 24)
                    }
                }
                
                // Loading Overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.4)
                        .overlay(
                            VStack {
                                ProgressView()
                                Text("Loading...").font(.caption).padding(.top, 8)
                            }
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        )
                }
                
                // Error Toast (Simple)
                if let error = viewModel.errorMessage {
                    VStack {
                        HStack {
                            Spacer()
                            Text(error)
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .padding(.top, 60)
                                .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                             if viewModel.errorMessage == error { viewModel.errorMessage = nil }
                        }
                    }
                }
                
                // Download Manager Error
                if let error = downloadManager.lastError {
                    VStack {
                        HStack {
                            Spacer()
                            Text("Download Error: \(error)")
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .padding(.top, 120) // Below other toasts
                                .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                             if downloadManager.lastError == error { downloadManager.lastError = nil }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SangeetTheme.background)
        .onAppear {
            if libraryManager.topSongs.isEmpty {
                Task { await libraryManager.fetchTopSongs() }
            }
            if libraryManager.trendingIndiaSongs.isEmpty {
                Task { await libraryManager.fetchTrendingIndia() }
            }
        }
    }
}

struct OnlineSongRow: View {
    let track: TidalTrack
    let downloadState: DownloadManager.DownloadState?
    let onPlay: () -> Void
    let onDownload: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Artwork Placeholder
            AsyncImage(url: track.coverURL) { phase in
                switch phase {
                case .empty: Color.gray.opacity(0.3)
                case .success(let image): image.resizable()
                case .failure: Color.gray.opacity(0.3)
                @unknown default: Color.gray.opacity(0.3)
                }
            }
            .frame(width: 48, height: 48)
            .cornerRadius(6)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text("\(track.artistName) • \(track.albumName)")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions
            if isHovering || downloadState != nil {
                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(SangeetTheme.primary)
                    }
                    .buttonStyle(.plain)
                    .opacity(downloadState != nil ? 0.5 : 1)
                    
                    if let state = downloadState {
                        switch state {
                        case .preparing:
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 20, height: 20)
                        case .downloading(let progress):
                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                                Circle()
                                    .trim(from: 0, to: CGFloat(progress))
                                    .stroke(SangeetTheme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .frame(width: 20, height: 20)
                        case .finished:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red)
                        }
                    } else {
                        Button(action: onDownload) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            // Duration
            Text(formatDuration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(SangeetTheme.textSecondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? SangeetTheme.surfaceElevated : Color.clear)
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
