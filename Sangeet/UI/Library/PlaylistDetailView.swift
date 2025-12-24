import SwiftUI

struct PlaylistDetailView: View {
    let playlistID: UUID
    
    @EnvironmentObject var services: AppServices
    @EnvironmentObject var playlists: PlaylistStore
    @State private var tracks: [Track] = []
    @State private var playlistName = "Playlist"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlistName)
                        .font(.largeTitle.bold())
                    Text("\(tracks.count) songs")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                if !tracks.isEmpty {
                    Button(action: playPlaylist) {
                        Image(systemName: "play.circle.fill")
                        // ...
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 6)
                }
                
                if tracks.isEmpty {
                     // Center the empty state vertically in the remaining space
                     VStack {
                         Spacer()
                         ContentUnavailableView("No Songs", systemImage: "music.note", description: Text("Add tracks to this playlist to start playing."))
                            .glassCard()
                         Spacer()
                     }
                     .frame(minHeight: 400) // Ensure it takes up space
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track, playlistContext: playlistID)
                                .onTapGesture {
                                    playAndQueue(track)
                                }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .navigationBarBackButtonHidden(true)
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
            // Map by trackId (Int64)
            var trackLookup: [Int64: Track] = [:]
            for track in allTracks {
                if let id = track.trackId {
                    trackLookup[id] = track
                }
            }
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
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let queue = Array(tracks.dropFirst(index))
            services.playback.startPlaylist(queue)
        }
    }
}
