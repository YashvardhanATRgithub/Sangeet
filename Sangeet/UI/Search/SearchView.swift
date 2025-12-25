import SwiftUI

struct SearchView: View {
    @EnvironmentObject var services: AppServices
    @ObservedObject var theme = AppTheme.shared
    
    // Local search state (same pattern as LibrarySongsView)
    @State private var searchText = ""
    @State private var searchResults = DatabaseManager.SearchResults()
    @FocusState private var searchFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.largeTitle.bold())
                Text("Find songs, artists, and albums")
                    .foregroundStyle(.secondary)
            }
            
            // Search Bar (copied exactly from LibrarySongsView)
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
                        searchResults = DatabaseManager.SearchResults()
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
            
            // Results
            if searchText.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Search Your Library",
                    message: "Type to find songs, artists, and albums."
                )
            } else if searchResults.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "Try a different search term."
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Songs Section
                        if !searchResults.tracks.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("Songs", count: searchResults.tracks.count)
                                
                                VStack(spacing: 4) {
                                    ForEach(searchResults.tracks) { track in
                                        SearchTrackRow(track: track) {
                                            services.playback.play(track: track)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Artists Section
                        if !searchResults.artists.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("Artists", count: searchResults.artists.count)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(searchResults.artists) { artist in
                                            NavigationLink(value: artist) {
                                                SearchArtistCard(artist: artist)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Albums Section
                        if !searchResults.albums.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                sectionHeader("Albums", count: searchResults.albums.count)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(searchResults.albums) { album in
                                            NavigationLink(value: album) {
                                                SearchAlbumCard(album: album)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(24)
        .nowPlayingBarPadding()
        .background(Theme.background)
        .onTapGesture {
            searchFocused = false
        }
        .onAppear {
            // Auto-focus search when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                searchFocused = true
            }
        }
    }
    
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    // Copied exactly from LibrarySongsView
    func performSearch(query: String) {
        Task { @MainActor in
            if query.isEmpty {
                searchResults = DatabaseManager.SearchResults()
            } else {
                let textConfig = query.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    self.searchResults = try await services.database.search(query: textConfig)
                } catch {
                    print("Search error: \(error)")
                    self.searchResults = DatabaseManager.SearchResults()
                }
            }
        }
    }
}

// MARK: - Search Track Row
struct SearchTrackRow: View {
    let track: Track
    let onTap: () -> Void
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.currentTheme.primaryColor.opacity(0.2))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "music.note")
                            .foregroundStyle(theme.currentTheme.primaryColor)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text(formatDuration(track.duration))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
                
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.currentTheme.primaryColor)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Search Artist Card
struct SearchArtistCard: View {
    let artist: Artist
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 10) {
            Circle()
                .fill(theme.currentTheme.primaryColor.opacity(0.25))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "music.mic")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.currentTheme.primaryColor)
                }
                .scaleEffect(isHovered ? 1.05 : 1.0)
            
            Text(artist.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            
            Text("\(artist.trackCount) songs")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(width: 100)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Search Album Card
struct SearchAlbumCard: View {
    let album: Album
    @ObservedObject var theme = AppTheme.shared
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.currentTheme.primaryColor.opacity(0.2))
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.currentTheme.primaryColor)
                }
                .scaleEffect(isHovered ? 1.03 : 1.0)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(album.artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}
