import SwiftUI
import AppKit

struct LibrarySongsView: View {
    @EnvironmentObject var services: AppServices
    @EnvironmentObject var playlists: PlaylistStore
    @State private var tracks: [Track] = []
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTrackIDs: [UUID] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header / Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Songs")
                        .font(.largeTitle.bold())
                    Text("Your entire collection, ready to play.")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search library...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
                    .padding(.vertical, 8)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        performSearch(query: "")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.accent.opacity(0.35), lineWidth: 1)
            )
            
            // List
            if tracks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 50))
                        .foregroundStyle(.tertiary)
                    Text("No songs found")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    
                    Button("Import Music") {
                       importFolder()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accentWarm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCard()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track)
                                .onTapGesture {
                                    playAndAutoQueue(track: track)
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
        .onTapGesture {
            searchFocused = false
        }
        .task {
            loadTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            loadTracks()
        }
        .onAppear {
            // keep search keyboard active when entering the screen
            // self.searchFocused = true 
            // Disabled auto-focus to prevent stealing focus from global shortcuts
        }
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                if let _ = playlists.create(name: newPlaylistName, trackIDs: pendingPlaylistTrackIDs) {
                    pendingPlaylistTrackIDs = []
                }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingPlaylistTrackIDs = []
                newPlaylistName = ""
            }
        } message: {
            Text("Add selected songs to a new playlist.")
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    func loadTracks() {
        Task { @MainActor in
            do {
                self.tracks = try await services.database.fetchAllTracks()
            } catch {
                print("Error loading tracks: \(error)")
            }
        }
    }
    
    func performSearch(query: String) {
        Task { @MainActor in
            if query.isEmpty {
                loadTracks()
            } else {
                let textConfig = query.trimmingCharacters(in: .whitespacesAndNewlines)
                // Use SearchService or Database for full text
                // For now, Database simple search:
                self.tracks = await services.database.searchTracks(query: textConfig)
            }
        }
    }
    
    func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true // User requested file import support
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                let directories = services.libraryAccess.directoryURLs(from: urls)
                services.libraryAccess.addBookmarks(for: directories)
                try? await services.library.startScan(directories: urls)
                await services.search.buildIndex()
                loadTracks()
            }
        }
    }
    
    func playAndAutoQueue(track: Track) {
        services.playback.play(track)
        
        // Auto-queue logic: find index and queue subsequent tracks
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            // Queue next 50 songs to ensure continuous playback
            let nextTracks = tracks.dropFirst(index + 1).prefix(50)
            for t in nextTracks {
                 services.playback.addToQueue(t)
            }
        }
    }
}
