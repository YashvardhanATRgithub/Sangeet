//
//  HomeView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var body: some View {
        ZStack {
            if appState.homeNavigationPath.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Good \(timeOfDay)")
                                .font(.largeTitle.bold()).foregroundStyle(.white)
                            Text("What would you like to listen to?")
                                .font(.title3).foregroundStyle(SangeetTheme.textSecondary)
                        }
                        .padding(.horizontal, 24).padding(.top, 24)
                        
                        HStack(spacing: 16) {
                            QuickActionCard(title: "Favorites", subtitle: "\(libraryManager.favorites.count) songs", icon: "heart.fill", color: .red) {
                                // Favorites still navigates to Playlists tab
                                let favRecord = PlaylistRecord(id: "favorites", name: "Favorites", isSystem: true)
                                if appState.playlistNavigationPath.isEmpty {
                                    appState.playlistNavigationPath.append(favRecord)
                                }
                                appState.changeTab(to: .playlists)
                            }
                            
                            QuickActionCard(title: "History", subtitle: "Recently played", icon: "clock.arrow.circlepath", color: .orange) {
                                // Navigate locally in Home
                                let historyRecord = PlaylistRecord(id: "recentlyPlayed", name: "Recently Played", isSystem: true)
                                withAnimation {
                                    appState.homeNavigationPath.append(historyRecord)
                                }
                            }
                            
                            QuickActionCard(title: "Recently Added", subtitle: "\(libraryManager.recentlyAddedSongs.count) songs", icon: "folder.badge.plus", color: SangeetTheme.primary) {
                                // Navigate locally in Home
                                let recentRecord = PlaylistRecord(id: "recentlyAdded", name: "Recently Added", isSystem: true)
                                withAnimation {
                                    appState.homeNavigationPath.append(recentRecord)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Sections...
                        homeSections
                        
                        Spacer(minLength: 120)
                    }
                }
                .contentMargins(.bottom, 24, for: .scrollContent) // Add safe area for scrolling
                .transition(.move(edge: .leading))
            } else if let selectedPlaylist = appState.homeNavigationPath.last {
                PlaylistDetailView(playlist: selectedPlaylist, isFavorites: false)
                    .transition(.move(edge: .trailing))
            }
        }
        .onAppear {
            Task { await libraryManager.fetchTopSongs() }
        }
    }
    
    @ViewBuilder
    private var homeSections: some View {
        // Recently Played (History)
        if !libraryManager.recentlyPlayedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recently Played")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(libraryManager.recentlyPlayedSongs) { track in
                            SongCard(track: track) {
                                playbackManager.startRadio(from: track)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        
        // Recently Added
        if !libraryManager.recentlyAddedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recently Added")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(libraryManager.recentlyAddedSongs) { track in
                            SongCard(track: track) {
                                playbackManager.startRadio(from: track)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        
        // Most Listened Section (Replaces All Songs)
        if !libraryManager.mostListenedSongs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Most Listened")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(libraryManager.mostListenedSongs) { track in
                            SongCard(track: track) {
                                playbackManager.startRadio(from: track)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
    
    private var timeOfDay: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour { case 5..<12: return "Morning"; case 12..<17: return "Afternoon"; case 17..<21: return "Evening"; default: return "Night" }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(color).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(SangeetTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).background(SangeetTheme.surfaceElevated).clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct TrendingSongCard: View {
    let song: TidalTrack
    @State private var isHovering = false
    @EnvironmentObject var libraryManager: LibraryManager
    
    /// Check if this song is already downloaded
    private var isDownloaded: Bool {
        libraryManager.hasTrack(title: song.title, artist: song.artistName)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: song.coverURL) { phase in
                    switch phase {
                    case .empty: Color.gray.opacity(0.3)
                    case .success(let image): image.resizable()
                    case .failure: Color.gray.opacity(0.3)
                    @unknown default: Color.gray.opacity(0.3)
                    }
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Overlay for download button
                if isHovering {
                    TidalDownloadButton(track: song, size: 28, color: SangeetTheme.primary)
                        .padding(6)
                }
                
                // Downloaded indicator (if not hovering and already downloaded) - Optional, 
                // but TidalDownloadButton handles state well. 
                // Let's rely on TidalDownloadButton which shows Checkmark if downloaded.
            }
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artistName)
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
    }
}

// SongRow struct removed as it is replaced by UniversalSongRow

struct SongCard: View {
    let track: Track
    var onPlay: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                ArtworkView(track: track, size: 140, cornerRadius: 12)
                
                if isHovering {
                    Circle().fill(SangeetTheme.primary.opacity(0.9)).frame(width: 48, height: 48)
                        .overlay(Image(systemName: "play.fill").foregroundStyle(.white))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { isHovering = $0 }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay()
        }
    }
}

struct EmptyLibraryView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.house.fill").font(.system(size: 60)).foregroundStyle(SangeetTheme.primaryGradient)
            Text("Your Library is Empty").font(.title2.bold()).foregroundStyle(.white)
            Text("Add music folders to get started").foregroundStyle(SangeetTheme.textSecondary)
            Button(action: { libraryManager.addFolder() }) {
                HStack { Image(systemName: "folder.badge.plus"); Text("Add Folder") }
                    .font(.headline).foregroundStyle(.white).padding(.horizontal, 24).padding(.vertical, 14)
                    .background(SangeetTheme.primaryGradient).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}
