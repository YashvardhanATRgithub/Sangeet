import SwiftUI

struct LibraryDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var appState: AppState
    
    let item: LibraryPathItem
    
    @State private var tracks: [Track] = []
    @State private var selectedTrack: Track? // Added for UniversalSongRow
    
    var title: String {
        switch item {
        case .album(let name): return name
        case .artist(let name): return name
        }
    }
    
    var subtitle: String {
        switch item {
        case .album: return "Album"
        case .artist: return "Artist"
        }
    }
    
    var icon: String {
        switch item {
        case .album: return "square.stack"
        case .artist: return "person.fill"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(SangeetTheme.surfaceElevated)
                            .frame(width: 160, height: 160)
                            .overlay(
                                Image(systemName: icon)
                                    .font(.system(size: 64))
                                    .foregroundStyle(SangeetTheme.textMuted)
                            )
                        
                        // Try to load artwork from first track
                        if let firstTrack = tracks.first, let _ = firstTrack.artworkData {
                            ArtworkView(track: firstTrack, size: 160, cornerRadius: 12)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(subtitle.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SangeetTheme.primary)
                        
                        Text(title)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        
                        Text("\(tracks.count) songs")
                            .foregroundStyle(SangeetTheme.textSecondary)
                        
                        Button(action: {
                            if !tracks.isEmpty {
                                playbackManager.playQueue(tracks: tracks)
                            }
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Play All")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(SangeetTheme.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                // Track List
                LazyVStack(spacing: 0) {
                    ForEach(tracks) { track in
                        UniversalSongRow(track: track, selectedTrack: $selectedTrack)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
        }
        .background(SangeetTheme.background.ignoresSafeArea())
        .onAppear {
            loadTracks()
        }
    }
    
    private func loadTracks() {
        switch item {
        case .album(let name):
            tracks = libraryManager.albums[name] ?? []
            // Sort by track number if possible, currently database doesn't strictly enforce it but we can try sorting by title or file name as fallback
            tracks.sort { $0.title < $1.title } 
        case .artist(let name):
            tracks = libraryManager.artists[name] ?? []
            tracks.sort { $0.title < $1.title }
        }
    }
}
