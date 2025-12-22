import SwiftUI

struct SearchView: View {
    @EnvironmentObject var services: AppServices
    @State private var query = ""
    @State private var results: [Track] = []
    @FocusState private var searchFocused: Bool
    
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
    
    var body: some View {
        VStack(spacing: 18) {
            // Search Bar
            searchField
                .padding(.horizontal)
                .onAppear { searchFocused = true }
            
            // Results
            if results.isEmpty && !query.isEmpty {
                ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("Try a different artist, song, or album name."))
            } else if results.isEmpty {
                ContentUnavailableView("Search your library", systemImage: "magnifyingglass")
            } else {
                List {
                    ForEach(results) { track in
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
                            
                            Button(action: { services.playback.play(track) }) {
                                Image(systemName: "play.fill")
                            }
                            .buttonStyle(.plain)
                            .padding(.leading)
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
                results = []
            } else {
                results = await services.database.searchTracks(query: trimmed)
            }
        }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
