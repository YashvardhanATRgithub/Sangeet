import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track] = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Back Button
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(
                            Circle().fill(Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 0)
                
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    if let data = album.artworkData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 10)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 200, height: 200)
                            .overlay {
                                Image(systemName: "square.stack")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100)
                                    .foregroundStyle(.secondary)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(radius: 10)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Album")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(album.title)
                            .font(.system(size: 48, weight: .bold))
                            .lineLimit(2)
                        Text(album.artist)
                            .font(.title2)
                        
                        Text("\(tracks.count) songs")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    // Controls
                    HStack(spacing: 16) {
                        Button(action: { playAlbum() }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            services.playback.isShuffleEnabled = true
                            playAlbum()
                        }) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.accent)
                                .padding(10)
                                .background(Circle().fill(Theme.accent.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 6)
                    
                    Divider()
                    
                    // Tracklist
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track)
                                .onTapGesture {
                                    playAndQueue(track)
                                }
                                .contextMenu {
                                    Button {
                                        services.playback.addToQueue(track)
                                    } label: {
                                        Label("Add to Queue", systemImage: "text.append")
                                    }
                                }
                        }
                    }
                }
            }
            .padding()
        }
        .nowPlayingBarPadding()
        .background(Theme.background)
        .navigationBarBackButtonHidden(true)
        .task {
            isLoading = true
            await loadTracks()
            isLoading = false
        }
    }
    
    @State private var isLoading = true
    
    func loadTracks() async {
        do {
            self.tracks = try await services.database.getTracks(for: album)
        } catch {
            print("Failed to load album tracks: \(error)")
        }
    }
    
    func playAlbum() {
        services.playback.startPlaylist(tracks)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Helper to play selected track and queue the rest of the album
    private func playAndQueue(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let queue = Array(tracks.dropFirst(index))
            services.playback.startPlaylist(queue)
        }
    }
}
