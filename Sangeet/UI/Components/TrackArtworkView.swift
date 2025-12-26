import SwiftUI
import AppKit

struct TrackArtworkView: View {
    let track: Track?
    let size: CGFloat?
    let maxSize: CGFloat?
    let cornerRadius: CGFloat
    let iconSize: CGFloat
    let showsGlow: Bool
    
    @State private var artworkImage: NSImage?
    
    init(
        track: Track?,
        size: CGFloat? = nil,
        maxSize: CGFloat? = nil,
        cornerRadius: CGFloat = 12,
        iconSize: CGFloat = 32,
        showsGlow: Bool = true
    ) {
        self.track = track
        self.size = size
        self.maxSize = maxSize
        self.cornerRadius = cornerRadius
        self.iconSize = iconSize
        self.showsGlow = showsGlow
    }
    
    var body: some View {
        let content = ZStack {
            if let artworkImage {
                Image(nsImage: artworkImage)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        
        Group {
            if let size {
                content
                    .frame(width: size, height: size)
            } else {
                content
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: maxSize)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: track?.id) {
            await loadArtwork()
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.panel)
            
            LinearGradient(
                colors: [Theme.accent.opacity(0.5), Theme.accentWarm.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(0.6)
            .blur(radius: 20)
            
            Image(systemName: "music.note")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .white.opacity(showsGlow ? 0.4 : 0), radius: 6)
        }
    }
    
    @MainActor
    private func loadArtwork() async {
        artworkImage = nil
        guard let track else { return }
        
        if let data = await AppServices.shared.database.getArtwork(for: track),
           let image = NSImage(data: data) {
            self.artworkImage = image
        }
    }
}

struct SongGridItem: View {
    let track: Track
    var playlistContext: UUID? = nil
    @EnvironmentObject var playlists: PlaylistStore
    @EnvironmentObject var services: AppServices
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TrackArtworkView(track: track, cornerRadius: 14, iconSize: 44, showsGlow: true)
                .frame(maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit) // ensure square
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 18)
        .drawingGroup()
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                services.playback.addToQueue(track)
            } label: {
                Label("Add to Queue", systemImage: "text.append")
            }
            
            Button {
                  Task {
                      if let id = track.trackId {
                          try? await services.database.toggleFavorite(for: id)
                          NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
                      }
                  }
             } label: {
                Label(track.isFavorite ? "Unfavorite" : "Favorite", systemImage: track.isFavorite ? "heart.slash" : "heart")
            }
            
            Divider()
            
            Divider()
            
            KaraokeContextMenu(track: track)
            
            Divider()
            
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([track.url])
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            
            Divider()
            
            if let playlistContext = playlistContext {
                Button(role: .destructive) {
                    if let id = track.trackId {
                        playlists.remove(tracks: [id], from: playlistContext)
                    }
                } label: {
                    Label("Remove from Playlist", systemImage: "trash")
                }
                Divider()
            }

            Menu("Add to Playlist") {
                ForEach(playlists.playlists.filter { $0.id != playlistContext }) { playlist in
                    Button(playlist.name) {
                        if let id = track.trackId {
                            playlists.add(tracks: [id], to: playlist.id)
                        }
                    }
                }
                Divider()
                Button("New Playlist...") {
                    if let id = track.trackId,
                       let _ = playlists.create(name: "New Playlist", trackIDs: [id]) {
                        
                    }
                }
            }
        }
    }
}
