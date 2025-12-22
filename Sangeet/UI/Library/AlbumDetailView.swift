import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @EnvironmentObject var services: AppServices
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
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
                        .cornerRadius(8)
                        .shadow(radius: 10)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Album")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(album.title)
                            .font(.system(size: 48, weight: .bold))
                            .lineLimit(2)
                        Text(album.artist)
                            .font(.title2)
                        
                        Text("\(album.tracks.count) songs")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)
                
                // Controls
                HStack(spacing: 20) {
                    Button(action: { playAlbum() }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.green)
                            .background(Circle().fill(.white)) // Pop
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        services.playback.isShuffling = true
                        playAlbum()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.title)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.vertical)
                
                Divider()
                
                // Tracklist
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
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
            .padding()
        }
        .nowPlayingBarPadding()
        .background(Theme.background)
    }
    
    func playAlbum() {
        if let first = album.tracks.first {
            services.playback.play(first)
            // In real app, we'd replace the queue with the rest of the album
            for track in album.tracks.dropFirst() {
                services.playback.addToQueue(track)
            }
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Helper to play selected track and queue the rest of the album
    private func playAndQueue(_ track: Track) {
        services.playback.play(track)
        if let index = album.tracks.firstIndex(where: { $0.id == track.id }) {
            let nextTracks = album.tracks.dropFirst(index + 1)
            for t in nextTracks {
                 services.playback.addToQueue(t)
            }
        }
    }
}
