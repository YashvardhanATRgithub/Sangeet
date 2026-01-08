//
//  Sangeet3App.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI
import Combine

@main
struct Sangeet3App: App {
    @StateObject private var appState = AppState()
    @StateObject private var playbackManager = PlaybackManager.shared
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some Scene {
        WindowGroup("Sangeet") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(playbackManager)
                .environmentObject(libraryManager)
                .environmentObject(themeManager)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        .commands {
            CommandGroup(replacing: .newItem) { }
            
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    playbackManager.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("Next Track") {
                    playbackManager.next(manualSkip: true)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                
                Button("Previous Track") {
                    playbackManager.previous()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                
                Divider()
                
                Button("Seek Forward 5s") {
                    playbackManager.seek(to: playbackManager.currentTime + 5)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Button("Seek Backward 5s") {
                    playbackManager.seek(to: playbackManager.currentTime - 5)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                
                Divider()
                
                Button("Increase Volume") {
                    playbackManager.setVolume(min(playbackManager.volume + 0.05, 1.0))
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                
                Button("Decrease Volume") {
                    playbackManager.setVolume(max(playbackManager.volume - 0.05, 0.0))
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
            }
        }
    }
}

// MARK: - App State
class AppState: ObservableObject {
    @Published var currentTab: Tab = .home
    @Published var homeNavigationPath: [PlaylistRecord] = []
    @Published var playlistNavigationPath: [PlaylistRecord] = []
    @Published var libraryNavigationPath: [LibraryPathItem] = []
    
    enum Tab: String, CaseIterable {
        case home = "Home"
        case library = "Library"
        case playlists = "Playlists"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .playlists: return "music.note.list"
            case .settings: return "gearshape.fill"
            }
        }
    }
    func changeTab(to tab: Tab) {
        // Reset all navigation paths when switching tabs
        homeNavigationPath.removeAll()
        playlistNavigationPath.removeAll()
        libraryNavigationPath.removeAll()
        currentTab = tab
    }
    
    func navigateBack() {
        switch currentTab {
        case .home:
            if !homeNavigationPath.isEmpty { homeNavigationPath.removeLast() }
        case .library:
            if !libraryNavigationPath.isEmpty { libraryNavigationPath.removeLast() }
        case .playlists:
            if !playlistNavigationPath.isEmpty { playlistNavigationPath.removeLast() }
        case .settings:
            break
        }
    }
}

enum LibraryPathItem: Hashable {
    case album(String) // Album name
    case artist(String) // Artist name
}
