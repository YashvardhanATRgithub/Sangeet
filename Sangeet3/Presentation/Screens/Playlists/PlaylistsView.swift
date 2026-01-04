//
//  PlaylistsView.swift
//  Sangeet3
//
//  Created for Sangeet
//

import SwiftUI

struct PlaylistsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var showingCreateAlert = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        ZStack {
            // Main Playlist List
            if appState.playlistNavigationPath.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header
                        HStack {
                            Text("Playlists")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Spacer()
                            Button(action: { showingCreateAlert = true }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("New Playlist")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(SangeetTheme.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)], spacing: 20) {
                            // Favorites Card
                            PlaylistCard(
                                name: "Favorites",
                                count: libraryManager.favorites.count,
                                icon: "heart.fill",
                                color: .red
                            )
                            .onTapGesture {
                                let favRecord = PlaylistRecord(id: "favorites", name: "Favorites", isSystem: true)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    appState.playlistNavigationPath.append(favRecord)
                                }
                            }
                            
                            // User Playlists
                            ForEach(libraryManager.playlists) { playlist in
                                PlaylistCard(
                                    name: playlist.name,
                                    count: libraryManager.getTrackCount(for: playlist),
                                    icon: "music.note.list",
                                    color: SangeetTheme.secondary
                                )
                                .contextMenu {
                                    Button("Delete Playlist", role: .destructive) {
                                        libraryManager.deletePlaylist(playlist)
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        appState.playlistNavigationPath.append(playlist)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 140)
                    }
                }
                .transition(.opacity)
            }
            // Detail View
            else if let selectedPlaylist = appState.playlistNavigationPath.last {
                PlaylistDetailView(playlist: selectedPlaylist, isFavorites: selectedPlaylist.id == "favorites")
                    .transition(.move(edge: .trailing))
            }
        }
        .background(SangeetTheme.background.ignoresSafeArea())
        .alert("New Playlist", isPresented: $showingCreateAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    libraryManager.createPlaylist(name: newPlaylistName)
                    newPlaylistName = ""
                }
            }
        }
    }
}

struct PlaylistCard: View {
    let name: String
    let count: Int
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(SangeetTheme.surfaceElevated)
                    .aspectRatio(1.0, contentMode: .fit)
                
                Image(systemName: icon)
                    .font(.system(size: 48))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                if count > 0 {
                    Text("\(count) songs")
                        .font(.caption)
                        .foregroundStyle(SangeetTheme.textSecondary)
                }
            }
        }
        .contentShape(Rectangle()) // Better tap area
    }
}

struct PlaylistDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var playlist: PlaylistRecord?
    var isFavorites: Bool = false
    
    @State private var tracks: [Track] = []
    @State private var selectedTrack: Track? // Added for UniversalSongRow
    
    var title: String {
        if isFavorites { return "Favorites" }
        if playlist?.id == "recentlyAdded" { return "Recently Added" }
        if playlist?.id == "recentlyPlayed" { return "Recently Played" }
        return playlist?.name ?? "Unknown"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack(alignment: .bottom, spacing: 20) {
                    ZStack {
                        RectangularArtwork(size: 160)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PLAYLIST")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SangeetTheme.primary)
                        
                        Text(title)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                        
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
                            .contextMenu {
                                Button {
                                    libraryManager.toggleFavorite(track)
                                } label: {
                                    let isFav = libraryManager.tracks.first(where: { $0.id == track.id })?.isFavorite ?? false
                                    Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "heart.slash" : "heart")
                                }
                                
                                // Remove from this playlist (only for custom playlists, not Favorites/system)
                                if let playlist = playlist, !playlist.isSystem && !isFavorites {
                                    Button(role: .destructive) {
                                        libraryManager.removeTrackFromPlaylist(track, playlist: playlist)
                                    } label: {
                                        Label("Remove from Playlist", systemImage: "minus.circle")
                                    }
                                }
                                
                                // Remove from Favorites
                                if isFavorites {
                                    Button(role: .destructive) {
                                        libraryManager.toggleFavorite(track)
                                    } label: {
                                        Label("Remove from Favorites", systemImage: "heart.slash")
                                    }
                                }
                                
                                Divider()
                                Button("Add to Queue") { playbackManager.addToQueue(track) }
                            }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
        }
        .background(SangeetTheme.background.ignoresSafeArea())
        .onAppear { loadTracks() }
        .onReceive(NotificationCenter.default.publisher(for: .playlistUpdated)) { notification in
            // Refresh if this playlist was updated
            if let updatedPlaylistId = notification.object as? String,
               updatedPlaylistId == playlist?.id {
                loadTracks()
            }
        }
        .onChange(of: libraryManager.favorites) { _, _ in
            if isFavorites { loadTracks() }
        }
        .onChange(of: libraryManager.recentlyAddedSongs) { _, _ in
            if playlist?.id == "recentlyAdded" { loadTracks() }
        }
        .onChange(of: libraryManager.recentlyPlayedSongs) { _, _ in
            if playlist?.id == "recentlyPlayed" { loadTracks() }
        }
    }
    
    private func loadTracks() {
        if isFavorites {
            tracks = libraryManager.favorites
        } else if playlist?.id == "recentlyAdded" {
            tracks = libraryManager.recentlyAddedSongs
        } else if playlist?.id == "recentlyPlayed" {
            tracks = libraryManager.recentlyPlayedSongs
        } else if let playlist = playlist {
            Task {
                tracks = await libraryManager.getTracks(for: playlist)
            }
        }
    }
    
    @ViewBuilder
    private func RectangularArtwork(size: CGFloat) -> some View {
        if let firstTrack = tracks.first, let _ = firstTrack.artworkData {
            ArtworkView(track: firstTrack, size: size, cornerRadius: 12)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(SangeetTheme.surfaceElevated)
                .frame(width: size, height: size)
                .overlay(
                    Image(
                        systemName: isFavorites ? "heart.fill" :
                                   playlist?.id == "recentlyAdded" ? "clock.fill" : 
                                   playlist?.id == "recentlyPlayed" ? "clock.arrow.circlepath" : "music.note.list"
                    )
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(
                        isFavorites ? .red : 
                        playlist?.id == "recentlyAdded" || playlist?.id == "recentlyPlayed" ? SangeetTheme.primary : 
                        SangeetTheme.textMuted
                    )
                )
        }
    }
}
