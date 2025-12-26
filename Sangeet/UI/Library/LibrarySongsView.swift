import SwiftUI
import AppKit
import Combine

class LibraryViewModel: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    
    init() {
        loadTracks()
        
        NotificationCenter.default.addObserver(forName: .libraryDidUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.loadTracks()
        }
    }
    
    func loadTracks() {
        isLoading = true
        Task {
            do {
                let allTracks = try await AppServices.shared.database.getAllTracks()
                await MainActor.run {
                    self.tracks = allTracks
                    self.isLoading = false
                }
            } catch {
                print("Error loading tracks: \(error)")
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}

struct LibrarySongsView: View {
    @EnvironmentObject var services: AppServices
    @EnvironmentObject var playlists: PlaylistStore
    @StateObject var libraryStore = LibraryViewModel()
    
    @State private var searchResults: [Track] = []
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var pendingPlaylistTrackIDs: [Int64] = []
    
    // Derived Data Source
    var tracks: [Track] {
        if searchText.isEmpty {
            return libraryStore.tracks
        } else {
            return searchResults
        }
    }
    
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
                Spacer()
                Spacer()
            }
            
            // ... (rest of view) ...

            
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
                        searchResults = []
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
            if libraryStore.isLoading && tracks.isEmpty {
                 ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tracks.isEmpty {
                 // Empty State Logic
                 if !searchText.isEmpty {
                     ContentUnavailableView.search(text: searchText)
                 } else {
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundStyle(.tertiary)
                        Text("No songs found")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        
                        Button("Manage Library") {
                           manageLibrary()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accentWarm)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard()
                 }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                        ForEach(tracks) { track in
                            SongGridItem(track: track)
                                .onTapGesture {
                                    playAndAutoQueue(track: track)
                                }
                                .contextMenu {
                                    Button {
                                        playAndAutoQueue(track: track)
                                    } label: {
                                        Label("Play", systemImage: "play")
                                    }
                                    
                                    Divider()
                                    
                                    KaraokeContextMenu(track: track)
                                    
                                    Divider()
                                    
                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([track.url])
                                    } label: {
                                        Label("Show in Finder", systemImage: "folder")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        deleteTrack(track)
                                    } label: {
                                        Label("Delete from Library", systemImage: "trash")
                                    }
                                    
                                    Button(role: .destructive) {
                                        deleteFile(track)
                                    } label: {
                                        Label("Move to Trash", systemImage: "trash.fill")
                                    }
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
        // Removed .task { loadTracks() } -> Data is loaded by LibraryStore init
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
            // LibraryStore handles its own updates, but if search is active, re-run search
            if !searchText.isEmpty {
                performSearch(query: searchText)
            }
        }
        .onAppear {
            // No-op
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
        .popover(isPresented: $showingLibrarySettings) {
             LibrarySettingsView()
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // Removed loadTracks()
    
    func performSearch(query: String) {
        Task { @MainActor in
            if query.isEmpty {
                searchResults = []
            } else {
                let textConfig = query.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    self.searchResults = try await services.database.searchTracks(query: textConfig)
                } catch {
                    print("Search error: \(error)")
                    self.searchResults = []
                }
            }
        }
    }
    
    @State private var showingLibrarySettings = false
    
    func manageLibrary() {
        showingLibrarySettings = true
    }
    
    func playAndAutoQueue(track: Track) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            let queue = Array(tracks.dropFirst(index))
            services.playback.startPlaylist(queue)
        } else {
            services.playback.play(track: track)
        }
    }
    
    func deleteTrack(_ track: Track) {
        guard let id = track.trackId else { return }
        Task {
            try? await services.database.deleteTrack(trackId: id)
            // Post update
            await MainActor.run { libraryStore.loadTracks() }
        }
    }
    
    func deleteFile(_ track: Track) {
        Task {
            do {
                try FileManager.default.trashItem(at: track.url, resultingItemURL: nil)
                if let id = track.trackId {
                    try await services.database.deleteTrack(trackId: id)
                    await MainActor.run { libraryStore.loadTracks() }
                }
            } catch {
                print("Error deleting file: \(error)")
            }
        }
    }
    



}

