import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var services: AppServices
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            Button(action: playAll) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            
            if artist.tracks.isEmpty {
                ContentUnavailableView("No songs", systemImage: "music.note", description: Text("Add tracks for \(artist.name) to see them here."))
                    .glassCard()
            } else {

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(artist.tracks) { track in
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
                    .padding()
                }
            }
        }
        .padding()
        .nowPlayingBarPadding()
        .background(Theme.background)
        .navigationTitle(artist.name)
    }
    
    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.panel)
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: "music.mic")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(artist.name)
                    .font(.title2.bold())
                Text("\(artist.tracks.count) songs")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }
    
    private func playAll() {
        guard let first = artist.tracks.first else { return }
        services.playback.play(first)
        for track in artist.tracks.dropFirst() {
            services.playback.addToQueue(track)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func playAndQueue(_ track: Track) {
        services.playback.play(track)
        if let index = artist.tracks.firstIndex(where: { $0.id == track.id }) {
            let nextTracks = artist.tracks.dropFirst(index + 1)
            for t in nextTracks {
                 services.playback.addToQueue(t)
            }
        }
    }
}
