//
//  ContentView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @ObservedObject var themeManager = ThemeManager.shared // Observe for instant color updates
    @State private var showFullScreenPlayer = false
    @State private var showQueueSidebar = false
    @State private var showGlobalSearch = false
    @State private var showingCreatePlaylistAlert = false
    @State private var newPlaylistName = ""
    @State private var trackToAddAfterCreation: Track?
    
    var body: some View {
        ZStack {
            // Use themeManager directly for instant updates
            themeManager.background.ignoresSafeArea()
            
            // Main Content Area
            VStack(spacing: 0) {
                TopTabBar(selectedTab: $appState.currentTab, showSearch: $showGlobalSearch)
                
                Group {
                    switch appState.currentTab {
                    case .home: HomeView()
                    case .library: LibraryView()
                    case .playlists: PlaylistsView()
                    case .online: OnlineView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Scan progress banner removed - User requested silence.

            }
            .overlay(alignment: .bottom) {
                FloatingDock(showFullScreen: $showFullScreenPlayer, showQueue: $showQueueSidebar)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            // Add a padding to the bottom of the content to allow scrolling behind the dock is handled in individual views
            
            // Queue Sidebar Overlay with click-outside-to-close
            // Placed in ZStack to float over content instead of shifting it
            if showQueueSidebar {
                // Dimmed background to click to close
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showQueueSidebar = false
                        }
                    }
                    .zIndex(45)
                
                HStack {
                    Spacer()
                    QueueSidebar(isVisible: $showQueueSidebar)
                        .transition(.move(edge: .trailing))
                }
                .zIndex(50)
            }
            
            // Full Screen Player
            if showFullScreenPlayer {
                FullScreenPlayerView(isPresented: $showFullScreenPlayer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(100)
            }
            

            
            // Global Search Overlay
            if showGlobalSearch {
                GlobalSearchOverlay(isVisible: $showGlobalSearch)
                    .transition(.opacity)
                    .zIndex(200)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showQueueSidebar)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showFullScreenPlayer)
        .animation(.easeOut(duration: 0.2), value: showGlobalSearch)
        .enableSwipeToBack {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                appState.navigateBack()
            }
        }
        // Playlist Creation Handler
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("createPlaylistRequested"))) { notification in
            if let track = notification.object as? Track {
                self.trackToAddAfterCreation = track
            } else {
                self.trackToAddAfterCreation = nil
            }
            self.showingCreatePlaylistAlert = true
        }
        .alert("Create New Playlist", isPresented: $showingCreatePlaylistAlert) {
            TextField("Playlist Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
                trackToAddAfterCreation = nil
            }
            Button("Create") {
                if !newPlaylistName.isEmpty {
                    libraryManager.createPlaylist(name: newPlaylistName)
                    
                    // If we wanted to add a track, do it now (need ID of newly created playlist?
                    // LibraryManager.createPlaylist is async and doesn't return ID easily here.
                    // But we can assume it's the latest or find it by name.
                    // For now, let's just wait a split second or notify User.
                    if let track = trackToAddAfterCreation {
                         // We need to wait for playlist to be created.
                         // Improve LibraryManager to return the created playlist or handle this.
                         // For now, simple implementation:
                         Task {
                             try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                             if let playlist = self.libraryManager.playlists.first(where: { $0.name == self.newPlaylistName }) {
                                 self.libraryManager.addTrackToPlaylist(track, playlist: playlist)
                             }
                             await MainActor.run {
                                 self.newPlaylistName = ""
                                 self.trackToAddAfterCreation = nil
                             }
                         }
                    } else {
                        newPlaylistName = ""
                    }
                }
            }
        }
    }
}
