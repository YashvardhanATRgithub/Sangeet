import SwiftUI

struct LibraryAlbumsView: View {
    @EnvironmentObject var services: AppServices
    @State private var albums: [Album] = []
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Albums")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom)
                
                LazyVGrid(columns: columns, spacing: 30) {
                    ForEach(albums) { album in
                        NavigationLink(destination: AlbumDetailView(album: album)) {
                            AlbumGridItem(album: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .task {
            do {
                self.albums = try await services.database.fetchAlbums()
            } catch {
                print("Failed to load albums: \(error)")
            }
        }
        .nowPlayingBarPadding()
        .background(Theme.background)
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
