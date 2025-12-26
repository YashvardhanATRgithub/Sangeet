import SwiftUI
// Removed AppKit import

struct HomeView: View {
    @EnvironmentObject var services: AppServices
    @State private var recentTracks: [Track] = []
    @State private var favoriteTracks: [Track] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title always visible
            Text("Home")
                .font(.largeTitle.bold())
                .padding(.horizontal, 24)
                .padding(.top, 24)
            
            if recentTracks.isEmpty && favoriteTracks.isEmpty {
                // Empty state - centered like Favorites
                EmptyStateView(
                    icon: "music.note",
                    title: "No Music",
                    message: "Import music folders to get started."
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        // Recently Added
                        if !recentTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Recently Added")
                                    .font(.title2.weight(.semibold))
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 18) {
                                        ForEach(recentTracks) { track in
                                            SongGridItem(track: track)
                                                .frame(width: 170)
                                                .onTapGesture {
                                                    playAndQueue(track: track, from: recentTracks)
                                                }
                                                .contextMenu {
                                                    Button {
                                                        playAndQueue(track: track, from: recentTracks)
                                                    } label: {
                                                        Label("Play", systemImage: "play")
                                                    }
                                                    
                                                    Divider()
                                                    
                                                    // Karaoke
                                                    KaraokeContextMenu(track: track)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                        
                        // Favorites
                        if !favoriteTracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Favorites")
                                    .font(.title2.weight(.semibold))
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 18) {
                                        ForEach(favoriteTracks) { track in
                                            SongGridItem(track: track)
                                                .frame(width: 170)
                                                .onTapGesture {
                                                    playAndQueue(track: track, from: favoriteTracks)
                                                }
                                                .contextMenu {
                                                    Button {
                                                        playAndQueue(track: track, from: favoriteTracks)
                                                    } label: {
                                                        Label("Play", systemImage: "play")
                                                    }
                                                    
                                                    Divider()
                                                    
                                                    // Karaoke
                                                    KaraokeContextMenu(track: track)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 12)
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nowPlayingBarPadding()
        .background(Theme.background)
        .task {
            await loadHomeData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            Task {
                await loadHomeData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            Task {
                await loadHomeData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldersDataDidChange)) { _ in
            Task {
                await loadHomeData()
            }
        }
    }
    
    // Hero and importFolder removed
    
    private func playAndQueue(track: Track, from list: [Track]) {
        services.playback.play(track: track)
        if let index = list.firstIndex(where: { $0.id == track.id }) {
            let nextTracks = list.dropFirst(index + 1)
            for t in nextTracks {
                services.playback.addToQueue(t)
            }
        }
    }
    
    @MainActor
    private func loadHomeData() async {
        do {
            self.recentTracks = try await services.database.fetchRecentTracks(limit: 10)
            self.favoriteTracks = try await services.database.fetchFavorites()
        } catch {
            print("Failed to load home data: \(error)")
        }
    }
}
