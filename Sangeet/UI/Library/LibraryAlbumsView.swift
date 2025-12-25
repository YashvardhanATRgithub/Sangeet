import SwiftUI

struct LibraryAlbumsView: View {
    @EnvironmentObject var services: AppServices
    @State private var albums: [Album] = []
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title always visible
            Text("Albums")
                .font(.largeTitle.bold())
                .padding(.horizontal, 24)
                .padding(.top, 24)
            
            if albums.isEmpty {
                // Empty state - centered like Favorites
                EmptyStateView(
                    icon: "square.stack",
                    title: "No Albums",
                    message: "Import music folders to see your albums here."
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 30) {
                        ForEach(albums) { album in
                            NavigationLink(value: album) {
                                AlbumGridItem(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadAlbums()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDataDidChange)) { _ in
            Task { await loadAlbums() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .foldersDataDidChange)) { _ in
            Task { await loadAlbums() }
        }
        .nowPlayingBarPadding()
        .background(Theme.background)
    }
    
    @MainActor
    private func loadAlbums() async {
        do {
            self.albums = try await services.database.fetchAlbums()
        } catch {
            print("Failed to load albums: \(error)")
        }
    }
}

struct AlbumGridItem: View {
    let album: Album
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.panel)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accentWarm.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .blur(radius: 25)
                }
                .overlay {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            
            Text(album.title)
                .font(.headline)
                .lineLimit(1)
            Text(album.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
        .drawingGroup()
        .contentShape(Rectangle())
    }
}
