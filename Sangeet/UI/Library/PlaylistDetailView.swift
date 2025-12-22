import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID
    
    @EnvironmentObject var services: AppServices
    @EnvironmentObject var playlists: PlaylistStore
    @State private var tracks: [Track] = []
    @State private var playlistName = "Playlist"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlistName)
                        .font(.largeTitle.bold())
                    Text("\(tracks.count) songs")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !tracks.isEmpty {
                    Button(action: playPlaylist) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            
            if tracks.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add tracks to this playlist to start playing."))
                    .glassCard()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track, playlistContext: playlistID)
                                .onTapGesture {
                                    playAndQueue(track)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .padding(24)
        .nowPlayingBarPadding()
        .background(Theme.background)
        .task(id: playlistID) {
            await loadPlaylist()
        }
        .onReceive(playlists.$playlists) { _ in
            Task { await loadPlaylist() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            Task { await loadPlaylist() }
        }
    }
    
    @MainActor
    private func loadPlaylist() async {
        guard let playlist = playlists.playlist(id: playlistID) else {
            playlistName = "Playlist"
            tracks = []
            return
        }
        
        playlistName = playlist.name
        
        do {
            let allTracks = try await services.database.fetchAllTracks()
            let trackLookup = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.id, $0) })
            tracks = playlist.trackIDs.compactMap { trackLookup[$0] }
        } catch {
            print("Failed to load playlist tracks: \(error)")
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func playPlaylist() {
        services.playback.startPlaylist(tracks)
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
