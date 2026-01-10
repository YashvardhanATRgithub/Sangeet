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
    var queueContext: [Track]? = nil // Optional playback context
    
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
    
    /// Get file size as formatted string
    var fileSize: String {
        guard !track.isRemote else { return "Stream" }
        do {
            let resources = try track.fileURL.resourceValues(forKeys: [.fileSizeKey])
            if let size = resources.fileSize {
                return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            }
        } catch {}
        return "--"
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
                .frame(width: 60, alignment: .center)
            
            // File Size
            Text(fileSize)
                .font(.caption)
                .foregroundStyle(SangeetTheme.textSecondary)
                .frame(width: 70, alignment: .trailing)
            
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
        // Use reliable NSViewRepresentable to capture right clicks AND left clicks
        .overlay(
            RightClickableSwiftUIView(
                onRightClick: {
                    showNSContextMenu(for: track, isFavorite: isFavorite)
                },
                onLeftClick: {
                    // Logic:
                    // If queueContext is provided (e.g. Album/Playlist), play that list.
                    // If queueContext is NIL (Generic Library), trigger Smart Queue (Play via Context Switch).
                    
                    if let context = queueContext, let index = context.firstIndex(of: track) {
                        // Play Explicit Context (Album, Playlist, Artist)
                        playbackManager.playQueue(tracks: context, startIndex: index)
                    } else {
                        // Play Single Track -> Triggers Smart Queue logic in PlaybackManager
                        playbackManager.startRadio(from: track)
                    }
                    selectedTrack = track
                }
            )
        )
    }
    
    private func showNSContextMenu(for track: Track, isFavorite: Bool) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // 1. Unfavorite/Favorite - WITH ICONS to match user expectation/verify code run
        let favItem = NSMenuItem(
            title: isFavorite ? "Unfavorite" : "Favorite",
            action: #selector(PlaylistMenuHandler.toggleFavorite(_:)),
            keyEquivalent: ""
        )
        favItem.target = PlaylistMenuHandler.shared
        favItem.representedObject = track
        favItem.isEnabled = true
        // Set icon manually if possible, or leave text. The key is the LOGIC.
        menu.addItem(favItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 2. Add to Playlist
        let playlistSubmenu = NSMenu(title: "Add to Playlist")
        playlistSubmenu.autoenablesItems = false
        
        // Header
        let headerItem = NSMenuItem(title: "Choose Playlist:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        playlistSubmenu.addItem(headerItem)
        playlistSubmenu.addItem(NSMenuItem.separator())
        
        let lm = LibraryManager.shared
        let allPlaylists = lm.playlists
        // Force sync read for menu
        let membership = lm.getPlaylistIds(for: track)
        
        for playlist in allPlaylists {
            let isInPlaylist = membership.contains(playlist.id)
            let title = isInPlaylist ? "✓ Remove from \(playlist.name)" : playlist.name
            
            let item = NSMenuItem(title: title, action: #selector(PlaylistMenuHandler.handlePlaylistAction(_:)), keyEquivalent: "")
            item.target = PlaylistMenuHandler.shared
            item.representedObject = PlaylistMenuData(track: track, playlist: playlist, isInPlaylist: isInPlaylist)
            item.isEnabled = true
            playlistSubmenu.addItem(item)
        }
        
        // Ensure "Add to Playlist" exists even if playlists are empty
        if allPlaylists.isEmpty {
             let emptyItem = NSMenuItem(title: "(No user playlists)", action: nil, keyEquivalent: "")
             emptyItem.isEnabled = false
             playlistSubmenu.addItem(emptyItem)
        }

        playlistSubmenu.addItem(NSMenuItem.separator())
        
        let createItem = NSMenuItem(title: "Create New Playlist...", action: #selector(PlaylistMenuHandler.createNewPlaylist(_:)), keyEquivalent: "")
        createItem.target = PlaylistMenuHandler.shared
        createItem.representedObject = track
        createItem.isEnabled = true
        playlistSubmenu.addItem(createItem)
        
        let addToPlaylistItem = NSMenuItem(title: "Add to Playlist", action: nil, keyEquivalent: "")
        addToPlaylistItem.submenu = playlistSubmenu
        addToPlaylistItem.isEnabled = true
        menu.addItem(addToPlaylistItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 3. Add to Queue
        let queueItem = NSMenuItem(title: "Add to Queue", action: #selector(PlaylistMenuHandler.addToQueue(_:)), keyEquivalent: "")
        queueItem.target = PlaylistMenuHandler.shared
        queueItem.representedObject = track
        queueItem.isEnabled = true
        menu.addItem(queueItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // 4. Delete
        let deleteItem = NSMenuItem(title: "Delete Song", action: #selector(PlaylistMenuHandler.deleteTrack(_:)), keyEquivalent: "")
        deleteItem.target = PlaylistMenuHandler.shared
        deleteItem.representedObject = track
        deleteItem.isEnabled = true
        menu.addItem(deleteItem)
        
        // Show menu at mouse location
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Right Click Overlay
struct RightClickableSwiftUIView: NSViewRepresentable {
    let onRightClick: () -> Void
    let onLeftClick: (() -> Void)?
    
    init(onRightClick: @escaping () -> Void, onLeftClick: (() -> Void)? = nil) {
        self.onRightClick = onRightClick
        self.onLeftClick = onLeftClick
    }
    
    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        view.onLeftClick = onLeftClick
        return view
    }
    
    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
        nsView.onLeftClick = onLeftClick
    }
    
    class RightClickView: NSView {
        var onRightClick: (() -> Void)?
        var onLeftClick: (() -> Void)?
        
        override func mouseDown(with event: NSEvent) {
            // Trigger left click action if provided
            if let onLeftClick = onLeftClick {
                onLeftClick()
            } else {
                // If no action, try to pass through (though overlay usually blocks)
                super.mouseDown(with: event)
                self.nextResponder?.mouseDown(with: event)
            }
        }
        
        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}

// Wrapper class for menu data to ensure ObjC bridging safety
class PlaylistMenuData: NSObject {
    let track: Track
    let playlist: PlaylistRecord
    let isInPlaylist: Bool
    
    init(track: Track, playlist: PlaylistRecord, isInPlaylist: Bool) {
        self.track = track
        self.playlist = playlist
        self.isInPlaylist = isInPlaylist
    }
}

@objc class PlaylistMenuHandler: NSObject {
    static let shared = PlaylistMenuHandler()
    
    @objc func handlePlaylistAction(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? PlaylistMenuData else { return }
        if data.isInPlaylist {
            LibraryManager.shared.removeTrackFromPlaylist(data.track, playlist: data.playlist)
        } else {
            LibraryManager.shared.addTrackToPlaylist(data.track, playlist: data.playlist)
        }
    }
    
    @objc func createNewPlaylist(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        NotificationCenter.default.post(name: .createPlaylistRequested, object: track)
    }
    
    @objc func addToQueue(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        PlaybackManager.shared.addToQueue(track)
    }
    
    @objc func deleteTrack(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        LibraryManager.shared.deleteTrack(track)
    }
    
    @objc func toggleFavorite(_ sender: NSMenuItem) {
        guard let track = sender.representedObject as? Track else { return }
        LibraryManager.shared.toggleFavorite(track)
    }
}


