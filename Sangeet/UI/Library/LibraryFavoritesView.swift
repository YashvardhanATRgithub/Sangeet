import SwiftUI

struct LibraryFavoritesView: View {
    @EnvironmentObject var services: AppServices
    @State private var tracks: [Track] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Favorites")
                .font(.largeTitle.bold())
                .padding(.horizontal)
            
            if !tracks.isEmpty {
                Button(action: playAllFavorites) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
            
            if tracks.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "heart", description: Text("Mark songs as favorite to see them here."))
                    .glassCard()
                    .padding(.horizontal)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track)
                                .onTapGesture {
                                    playAndQueue(track)
                                }
                                .contextMenu {
                                    Button("Remove from Favorites") {
                                        Task {
                                            await services.database.toggleFavorite(for: track.id)
                                            loadFavorites()
                                        }
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(.vertical, 12)
        .nowPlayingBarPadding()
        .background(Theme.background)
        .task {
            loadFavorites()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadFavorites()
        }
    }
    
    func loadFavorites() {
        Task { @MainActor in
            do {
                // We need to implement fetchFavorites in DatabaseService
                // Using a temporary filter on fetchAll for now if specific method doesn't exist
                // check DatabaseService... it has toggleFavorite but maybe not fetchFavorites
                let all = try await services.database.fetchAllTracks()
                self.tracks = all.filter { $0.isFavorite }
            } catch {
                print("Error loading favorites: \(error)")
            }
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func playAllFavorites() {
        guard let first = tracks.first else { return }
        services.playback.play(first)
        for track in tracks.dropFirst() {
            services.playback.addToQueue(track)
        }
    }

    private func playAndQueue(_ track: Track) {
        services.playback.play(track)
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let nextTracks = tracks.dropFirst(index + 1)
            for t in nextTracks {
                services.playback.addToQueue(t)
            }
        }
    }
}
