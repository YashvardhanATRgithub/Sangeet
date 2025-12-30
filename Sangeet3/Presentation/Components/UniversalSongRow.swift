//
//  UniversalSongRow.swift
//  Sangeet3
//
//  Created by Yashvardhan on 30/12/24.
//

import SwiftUI

struct UniversalSongRow: View {
    let track: Track
    @Binding var selectedTrack: Track?
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var isHovering = false
    
    // Reactive Favorite State
    var isFavorite: Bool {
        libraryManager.tracks.first(where: { $0.id == track.id })?.isFavorite ?? false
    }
    
    var isCurrentTrack: Bool {
        playbackManager.currentTrack?.id == track.id
    }
    
    var isSelected: Bool {
        selectedTrack?.id == track.id
    }
    
    var dateFormatter: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // Artwork & Title (Flexible)
            HStack(spacing: 16) {
                // Artwork with playing indicator
                ZStack {
                    ArtworkView(track: track, size: 56, cornerRadius: 8)
                    
                    if isCurrentTrack && playbackManager.isPlaying {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.5))
                            .frame(width: 56, height: 56)
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundStyle(SangeetTheme.primary)
                            .symbolEffect(.variableColor.iterative, isActive: true)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isCurrentTrack ? SangeetTheme.primary : .white)
                        .lineLimit(1)
                    Text("\(track.artist) • \(track.album)")
                        .font(.callout)
                        .foregroundStyle(SangeetTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Professional Columns
            
            // Duration
            Text(track.formattedDuration)
                .font(.subheadline)
                .foregroundStyle(SangeetTheme.textSecondary)
                .frame(width: 80, alignment: .trailing)
                .monospacedDigit()
            
            // Format (e.g., MP3 • 44.1)
            Text(track.fileURL.pathExtension.uppercased())
                .font(.caption.bold())
                .foregroundStyle(SangeetTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SangeetTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 80, alignment: .trailing)
            
            // Date Added
            Text(dateFormatter.string(from: track.dateAdded))
                .font(.caption)
                .foregroundStyle(SangeetTheme.textSecondary)
                .frame(width: 100, alignment: .trailing)
            
            // Liked Status (Using reactive isFavorite)
            ZStack {
                if isFavorite {
                     Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(SangeetTheme.primary)
                        .onTapGesture {
                             libraryManager.toggleFavorite(track)
                        }
                } else if isHovering {
                    Button(action: {
                        libraryManager.toggleFavorite(track)
                    }) {
                        Image(systemName: "heart")
                            .font(.title3)
                            .foregroundStyle(SangeetTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 30) // Fixed Action column
            
        }
        .padding(.vertical, 10).padding(.horizontal, 16)
        .background(
            ZStack {
                if isSelected {
                    SangeetTheme.surfaceElevated
                } else if isHovering {
                    SangeetTheme.surface.opacity(0.6)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            // Single Tap Plays Immediately
            if let index = libraryManager.tracks.firstIndex(of: track) {
                playbackManager.playQueue(tracks: libraryManager.tracks, startIndex: index)
                selectedTrack = track
            } else {
                // Fallback for isolated tracks (e.g. from search results outside main list)
                playbackManager.playQueue(tracks: [track], startIndex: 0)
                selectedTrack = track
            }
        }
        .contextMenu {
            Button {
                libraryManager.toggleFavorite(track)
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart")
            }
            
            Menu("Add to Playlist") {
                ForEach(libraryManager.playlists) { playlist in
                    Button(playlist.name) {
                        libraryManager.addTrackToPlaylist(track, playlist: playlist)
                    }
                }
            }
            Divider()
            Button("Add to Queue") { playbackManager.addToQueue(track) }
        }
    }
}
