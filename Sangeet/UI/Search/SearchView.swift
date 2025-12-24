import SwiftUI

import SwiftUI

struct SearchView: View {
    @EnvironmentObject var services: AppServices
    @ObservedObject var theme = AppTheme.shared
    @State private var searchResults = DatabaseManager.SearchResults()
    @State private var isSearching = false
    
    // HiFidelity uses a debounced search or an explicit task. We use Task with cancellation.
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Stats
            if !searchResults.isEmpty {
                HStack {
                    Text("\(searchResults.totalCount) results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Theme.background)
            }
            
            if isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty && !services.searchQuery.isEmpty {
                 ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different term."))
            } else if searchResults.isEmpty {
                 ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
            } else {
                List {
                    // Tracks (Top Priority)
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
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Artists
                    if !searchResults.artists.isEmpty {
                        Section("Artists") {
                            ForEach(searchResults.artists) { artist in
                                NavigationLink(value: artist) {
                                    HStack {
                                        Image(systemName: "music.mic")
                                            .foregroundStyle(theme.currentTheme.primaryColor)
                                        Text(artist.name)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Albums
                    if !searchResults.albums.isEmpty {
                         Section("Albums") {
                            ForEach(searchResults.albums) { album in
                                NavigationLink(value: album) {
                                    HStack {
                                        Image(systemName: "square.stack")
                                            .foregroundStyle(theme.currentTheme.primaryColor)
                                        VStack(alignment: .leading) {
                                            Text(album.title)
                                            Text(album.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                         }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Theme.background)
        .onChange(of: services.searchQuery) { _, newValue in
            performSearch(newValue)
        }
        .onAppear {
            if !services.searchQuery.isEmpty {
                performSearch(services.searchQuery)
            }
        }
    }
    
    func performSearch(_ text: String) {
        searchTask?.cancel()
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = DatabaseManager.SearchResults()
            isSearching = false
            return
        }
        
        isSearching = true
        searchTask = Task {
            // Debounce slightly
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            
            do {
                let results = try await services.database.search(query: trimmed)
                if !Task.isCancelled {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                print("Search failed: \(error)")
                if !Task.isCancelled {
                    self.isSearching = false
                }
            }
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

