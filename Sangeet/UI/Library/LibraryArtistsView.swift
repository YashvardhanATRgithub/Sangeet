import SwiftUI

struct LibraryArtistsView: View {
    @EnvironmentObject var services: AppServices
    @State private var artists: [Artist] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title always visible
            Text("Artists")
                .font(.largeTitle.bold())
                .padding(.horizontal, 24)
                .padding(.top, 24)
            
            if artists.isEmpty {
                // Empty state - centered like Favorites
                EmptyStateView(
                    icon: "person.2",
                    title: "No Artists",
                    message: "Import music folders to see your artists here."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 24)], spacing: 24) {
                        ForEach(artists) { artist in
                            NavigationLink(value: artist) {
                                ArtistGridItem(artist: artist)
                            }
                            .buttonStyle(.plain)
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
            await loadArtists()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            Task { await loadArtists() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldersDataDidChange)) { _ in
            Task { await loadArtists() }
        }
    }
    
    @MainActor
    private func loadArtists() async {
        do {
            self.artists = try await services.database.fetchArtists()
        } catch {
            print("Failed to load artists: \(error)")
        }
    }
}

struct ArtistGridItem: View {
    let artist: Artist
    
    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Theme.panel)
                .frame(width: 120, height: 120) // Large circle
                .overlay {
                    Image(systemName: "music.mic")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            VStack(spacing: 4) {
                Text(artist.name)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                Text("\(artist.trackCount) Songs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .contentShape(Rectangle()) // Make tappable area larger if needed
    }
}
