
import SwiftUI

struct OnlineView: View {
    @StateObject private var viewModel = OnlineViewModel()
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
                                OnlineSongRow(track: track, onPlay: {
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
            if isHovering {
                HStack(spacing: 12) {
                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(SangeetTheme.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
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
