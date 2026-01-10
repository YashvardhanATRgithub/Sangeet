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
                .onAppear {
                    UpdateChecker.shared.checkForUpdates()
                }
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
                
                // Arrow key seeking is handled by custom event monitor in ContentView
                // to allow normal text editing in search fields
                
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
        case online = "Online"
        case settings = "Settings"
        
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .playlists: return "music.note.list"
            case .online: return "globe"
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
        case .online, .settings:
            break
        }
    }
}

enum LibraryPathItem: Hashable {
    case album(String) // Album name
    case artist(String) // Artist name
}

// MARK: - Update Checker (Inlined)
import AppKit
import UserNotifications

struct GitHubRelease: Codable {
    let tag_name: String
    let html_url: String
    let body: String
    let published_at: String
}

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""
    @Published var releaseNotes: String = ""
    @Published var releaseURL: URL?
    
    // Dynamically fetch current version
    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/YashvardhanATRgithub/Sangeet/releases/latest") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                let latestTag = release.tag_name.replacingOccurrences(of: "v", with: "")
                
                print("[UpdateChecker] Latest: \(latestTag), Current: \(self.currentVersion)")
                
                DispatchQueue.main.async {
                    if self.isVersion(latestTag, newThan: self.currentVersion) {
                        self.latestVersion = latestTag
                        self.releaseNotes = release.body
                        self.releaseURL = URL(string: release.html_url)
                        self.updateAvailable = true
                        
                        // Send Notification
                        self.sendUpdateNotification(version: latestTag)
                    }
                }
            } catch {
                print("Update Check Failed: \(error)")
            }
        }.resume()
    }
    
    // Simple semver compare
    private func isVersion(_ newVer: String, newThan oldVer: String) -> Bool {
        return newVer.compare(oldVer, options: .numeric) == .orderedDescending
    }
    
    private func sendUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "Sangeet v\(version) is now available. Click to download."
        content.sound = .default
        
        // Request permission implicitly by adding
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        
        let request = UNNotificationRequest(identifier: "UpdateAvailable", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
