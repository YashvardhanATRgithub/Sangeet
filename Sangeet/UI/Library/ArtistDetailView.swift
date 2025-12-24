import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @EnvironmentObject var services: AppServices
    @Environment(\.dismiss) private var dismiss
    
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Back Button (Manual)
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
            .padding(.leading, 4)
            
            header
            
            Button(action: playAll) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                ContentUnavailableView("No songs", systemImage: "music.note", description: Text("Add tracks for \(artist.name) to see them here."))
                    .glassCard()
            } else {

                ScrollView {
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
                    .padding()
                }
            }
        }
        .padding()
        .nowPlayingBarPadding()
        .background(Theme.background)
        .navigationBarBackButtonHidden(true)
        .task {
            isLoading = true
            await loadTracks()
            isLoading = false
        }
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
                Text("\(tracks.count) songs")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .glassCard()
    }
    
    func loadTracks() async {
        do {
            self.tracks = try await services.database.getTracks(for: artist)
        } catch {
            print("Failed to load artist tracks: \(error)")
        }
    }
    
    private func playAll() {
        services.playback.startPlaylist(tracks)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func playAndQueue(_ track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let queue = Array(tracks.dropFirst(index))
            services.playback.startPlaylist(queue)
        }
    }
}
