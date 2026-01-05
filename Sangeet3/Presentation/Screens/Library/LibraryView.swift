//
//  LibraryView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var appState: AppState // Restore appState
    
    @State private var selectedSection = 0 // Restore selectedSection
    @State private var inspectedTrack: Track?
    
    // Grid columns for the album view (adjusting for less width)
    let albumColumns = [GridItem(.adaptive(minimum: 140), spacing: 16)]
    
    var body: some View {
        ZStack { // Manual Navigation Stack
            if appState.libraryNavigationPath.isEmpty {
                    // LEFT: Main Library Content
                    VStack(spacing: 24) {
                        // Big Category Cards (Replacing Picker) - Moved to top
                        HStack(spacing: 16) {
                            LibraryCategoryCard(title: "Songs", subtitle: "\(libraryManager.tracks.count) songs", icon: "music.note", color: .blue, isSelected: selectedSection == 0) {
                                withAnimation { selectedSection = 0 }
                            }
                            
                            LibraryCategoryCard(title: "Albums", subtitle: "\(libraryManager.albums.count) albums", icon: "square.stack", color: .purple, isSelected: selectedSection == 1) {
                                withAnimation { selectedSection = 1 }
                            }
                            
                            LibraryCategoryCard(title: "Artists", subtitle: "\(libraryManager.artists.count) artists", icon: "person.2", color: .pink, isSelected: selectedSection == 2) {
                                withAnimation { selectedSection = 2 }
                            }
                        }
                        .padding(.horizontal, 24).padding(.top, 24)
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        Group {
                            switch selectedSection {
                            case 0: songsView
                            case 1: albumsView
                            case 2: artistsView
                            default: songsView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            } else if let selectedItem = appState.libraryNavigationPath.last {
                LibraryDetailView(item: selectedItem)
                    .transition(.move(edge: .trailing))
            }
        }
        // Removed Inspector .onChange logic
    }
    
    var songsView: some View {
        Group {
            if libraryManager.tracks.isEmpty {
                EmptyLibraryView()
            } else {
                ScrollView {
                    // Header Row - widths must match UniversalSongRow
                    HStack(spacing: 20) {
                        Text("Title").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Duration").frame(width: 80, alignment: .trailing)
                        Text("Format").frame(width: 60, alignment: .center)
                        Text("Size").frame(width: 70, alignment: .trailing)
                        // Heart button spacing
                        Color.clear.frame(width: 30)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .padding(.horizontal, 36) // Adjust for padding in row
                    .padding(.bottom, 8)
                    
                    LazyVStack(spacing: 0) {
                        ForEach(libraryManager.tracks) { track in
                            UniversalSongRow(track: track, selectedTrack: $inspectedTrack)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 140)
                }
            }
        }
    }
    
    var albumsView: some View {
        ScrollView {
            LazyVGrid(columns: albumColumns, spacing: 24) { // Increased spacing
                ForEach(Array(libraryManager.albums.keys.sorted()), id: \.self) { album in
                    if let tracks = libraryManager.albums[album], let firstTrack = tracks.first {
                        AlbumCard(name: album, artist: firstTrack.artist, trackCount: tracks.count, artworkTrack: firstTrack) { // Pass track for artwork
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                appState.libraryNavigationPath.append(.album(album))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 140)
        }
    }
    
    var artistsView: some View {
        ScrollView {
            LazyVGrid(columns: albumColumns, spacing: 24) { // Use Grid for Artists too
                ForEach(Array(libraryManager.artists.keys.sorted()), id: \.self) { artist in
                    if let tracks = libraryManager.artists[artist] {
                        VStack(spacing: 12) {
                            // Circular Artist Image
                            ArtistArtworkView(artist: artist)
                            
                            VStack(spacing: 4) { // ... text remains same
                                Text(artist)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("\(tracks.count) songs")
                                    .font(.caption)
                                    .foregroundStyle(SangeetTheme.textSecondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                appState.libraryNavigationPath.append(.artist(artist))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 140)
        }
    }
}

// LibrarySongRow struct removed as it is replaced by UniversalSongRow


struct AlbumCard: View {
    let name: String
    let artist: String
    let trackCount: Int
    let artworkTrack: Track? // Added optional track for artwork
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    if let track = artworkTrack {
                         ArtworkView(track: track, size: 160, cornerRadius: 12)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(SangeetTheme.surfaceElevated).frame(height: 160)
                            .overlay(Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(SangeetTheme.textMuted))
                    }
                    
                    // Hover effect
                    if isHovering {
                         RoundedRectangle(cornerRadius: 12)
                             .fill(Color.black.opacity(0.2))
                         Image(systemName: "play.circle.fill")
                             .font(.system(size: 40))
                             .foregroundStyle(.white)
                             .shadow(radius: 4)
                    }
                }
                .frame(width: 160, height: 160) // fixed size
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onHover { isHovering = $0 }
                .animation(.spring(response: 0.3), value: isHovering)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.medium)).foregroundStyle(.white).lineLimit(1)
                    Text("\(artist) • \(trackCount) songs").font(.caption).foregroundStyle(SangeetTheme.textSecondary).lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// LibraryCategoryCard stays same...
// LibraryCategoryCard stays same...
struct LibraryCategoryCard: View {
    // ... (existing code)
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isSelected: Bool
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
            .padding(16)
            .background(
                ZStack {
                    SangeetTheme.surfaceElevated
                    if isSelected {
                        SangeetTheme.primary.opacity(0.15)
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(SangeetTheme.primary, lineWidth: 2)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct ArtistArtworkView: View {
    let artist: String
    @State private var artworkURL: URL? = nil
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        .task {
            // Load artist artwork
            if artworkURL == nil {
                artworkURL = await SmartMetadataManager.shared.getArtistArtwork(artist: artist)
                isLoading = false
            }
        }
    }
    
    var initialsView: some View {
        Circle()
            .fill(SangeetTheme.surfaceElevated)
            .overlay(
                Text(artist.prefix(1).uppercased())
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(SangeetTheme.textMuted)
            )
    }
}
