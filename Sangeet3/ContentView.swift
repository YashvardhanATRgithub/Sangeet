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
    @State private var showFullScreenPlayer = false
    @State private var showQueueSidebar = false
    @State private var showGlobalSearch = false
    
    var body: some View {
        ZStack {
            SangeetTheme.background.ignoresSafeArea()
            
            // Main Content Area
            VStack(spacing: 0) {
                TopTabBar(selectedTab: $appState.currentTab, showSearch: $showGlobalSearch)
                
                Group {
                    switch appState.currentTab {
                    case .home: HomeView()
                    case .library: LibraryView()
                    case .playlists: PlaylistsView()
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
            
            // Queue Sidebar Overlay
            // Placed in ZStack to float over content instead of shifting it
            if showQueueSidebar {
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
    }
}


// End of ContentView
