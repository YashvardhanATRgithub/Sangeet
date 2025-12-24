import SwiftUI

struct LibraryFavoritesView: View {
    @EnvironmentObject var services: AppServices
    @State private var tracks: [Track] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Title (Always Visible or part of content?)
            // To mimic other views, we'll put it inside the scroll/content areas or keep it fixed.
            // Let's keep it consistent: Content moves.
            
            if tracks.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Favorites")
                        .font(.largeTitle.bold())
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    
                    ContentUnavailableView("No Favorites", systemImage: "heart", description: Text("Mark songs as favorite to see them here."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Favorites")
                            .font(.largeTitle.bold())
                            .padding(.horizontal)
                        
                        Button(action: playAllFavorites) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                            ForEach(tracks) { track in
                                SongGridItem(track: track)
                                    .onTapGesture {
                                        playAndQueue(track)
                                    }
                                    .contextMenu {
                                        Button("Remove from Favorites") {
                                            Task {
                                                if let id = track.trackId {
                                                    try? await services.database.toggleFavorite(for: id)
                                                    loadFavorites()
                                                }
                                            }
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                    .padding(.top, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .nowPlayingBarPadding()
        .background(Theme.background)
        .task {
            loadFavorites()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadFavorites()
        }
        .navigationBarBackButtonHidden(true)
    }
    
    func loadFavorites() {
        Task { @MainActor in
            do {
                self.tracks = try await services.database.fetchFavorites()
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
        services.playback.play(track: first)
        for track in tracks.dropFirst() {
            services.playback.addToQueue(track)
        }
    }

    private func playAndQueue(_ track: Track) {
        services.playback.play(track: track)
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let nextTracks = tracks.dropFirst(index + 1)
            for t in nextTracks {
                services.playback.addToQueue(t)
            }
        }
    }
}
