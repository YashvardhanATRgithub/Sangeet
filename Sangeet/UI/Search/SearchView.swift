import SwiftUI

struct SearchView: View {
    @EnvironmentObject var services: AppServices
    @State private var query = ""
    @State private var searchResults = DatabaseManager.SearchResults()
    @FocusState private var searchFocused: Bool
    @State private var isSearching = false
    
    // ... searchField remains similar ...
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar Area
            searchField
                .padding()
                .background(Theme.background)
                .onAppear { searchFocused = true }
            
            // Results
            if searchResults.isEmpty && !query.isEmpty {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different artist, song, or album name."))
                }
            } else if searchResults.isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
            } else {
                List {
                    // Artists Section
                    if !searchResults.artists.isEmpty {
                        Section("Artists") {
                            ForEach(searchResults.artists) { artist in
                                NavigationLink(value: artist) {
                                    HStack {
                                        Image(systemName: "music.mic.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(Theme.accent)
                                        Text(artist.name)
                                            .font(.body)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Albums Section
                    if !searchResults.albums.isEmpty {
                        Section("Albums") {
                            ForEach(searchResults.albums) { album in
                                NavigationLink(value: album) {
                                    HStack {
                                        Image(systemName: "square.stack.fill")
                                            .font(.title2)
                                            .foregroundStyle(Theme.accent)
                                        VStack(alignment: .leading) {
                                            Text(album.title)
                                                .font(.body)
                                            Text(album.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Songs Section
                    if !searchResults.tracks.isEmpty {
                        Section("Songs") {
                            ForEach(searchResults.tracks) { track in
                                Button(action: { services.playback.play(track: track) }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(track.title)
                                                .font(.headline)
                                            Text(track.artist)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(formatDuration(track.duration))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                            .opacity(0.8)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Search")
        .nowPlayingBarPadding()
        .background(Theme.background)
        .onAppear { searchFocused = true }
    }
    
    func performSearch(_ text: String) {
        Task { @MainActor in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                searchResults = DatabaseManager.SearchResults()
            } else {
                isSearching = true
                do {
                    // Search all categories
                    searchResults = try await services.database.search(query: trimmed)
                } catch {
                    print("Search error: \(error)")
                    searchResults = DatabaseManager.SearchResults()
                }
                isSearching = false
            }
        }
    }
    
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Artists, Songs, or Albums", text: $query)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)
                .onChange(of: query) { _, newValue in
                    performSearch(newValue)
                }
                .padding(.vertical, 8)
            
            if !query.isEmpty {
                Button(action: { query = "" }) {
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
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
