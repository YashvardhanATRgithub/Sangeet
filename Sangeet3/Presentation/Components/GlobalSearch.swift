//
//  GlobalSearch.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Spotlight-style global search overlay
//

import SwiftUI

struct GlobalSearchOverlay: View {
    @Binding var isVisible: Bool
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return [] }
        return libraryManager.tracks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artist.localizedCaseInsensitiveContains(searchText) ||
            $0.album.localizedCaseInsensitiveContains(searchText)
        }
        .prefix(10)  // Limit to 10 results for performance
        .map { $0 }
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { closeSearch() }
            
            // Search panel
            VStack(spacing: 0) {
                // Search field
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(SangeetTheme.textMuted)
                    
                    TextField("Search songs, artists, albums...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if let first = filteredTracks.first {
                                playTrack(first)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SangeetTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { closeSearch() }) {
                        Text("ESC")
                            .font(.caption.monospaced())
                            .foregroundStyle(SangeetTheme.textMuted)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SangeetTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .background(SangeetTheme.surfaceElevated)
                
                // Results
                if !searchText.isEmpty {
                    Divider().background(Color.white.opacity(0.1))
                    
                    if filteredTracks.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title)
                                .foregroundStyle(SangeetTheme.textMuted)
                            Text("No results for \"\(searchText)\"")
                                .foregroundStyle(SangeetTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredTracks) { track in
                                    SearchResultRow(track: track) {
                                        playTrack(track)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 400)
                    }
                }
            }
            .frame(width: 600)
            .background(SangeetTheme.background)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 40)
            .offset(y: -50)  // Move up slightly
        }
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            closeSearch()
        }
    }
    
    private func playTrack(_ track: Track) {
        // Add all filtered results to queue and play selected
        let tracksToQueue = filteredTracks
        if let index = tracksToQueue.firstIndex(of: track) {
            playbackManager.playQueue(tracks: tracksToQueue, startIndex: index)
        } else {
            playbackManager.play(track)
        }
        closeSearch()
    }
    
    private func closeSearch() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
        }
        searchText = ""
    }
}

struct SearchResultRow: View {
    let track: Track
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Artwork placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(SangeetTheme.surface)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(SangeetTheme.textMuted)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text("\(track.artist) • \(track.album)")
                        .font(.caption)
                        .foregroundStyle(SangeetTheme.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isHovering {
                    Image(systemName: "play.fill")
                        .foregroundStyle(SangeetTheme.primary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(isHovering ? SangeetTheme.surface : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
