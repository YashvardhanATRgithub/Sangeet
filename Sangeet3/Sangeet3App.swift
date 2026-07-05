//
//  Sangeet3App.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI
import Combine
import AppKit

// MARK: - App Delegate (handles files opened from Finder / "Open With")
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        let audioURLs = urls.filter { LibraryManager.isSupportedAudioFile($0) }
        guard !audioURLs.isEmpty else { return }

        Task { @MainActor in
            await LibraryManager.shared.playExternalFiles(audioURLs)
        }
    }
}

@main
struct Sangeet3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var playbackManager = PlaybackManager.shared
    @StateObject private var libraryManager = LibraryManager.shared
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        // Single-window app: `Window` (unlike WindowGroup) never spawns extra
        // windows when files are opened from Finder.
        Window("Sangeet", id: "main") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(playbackManager)
                .environmentObject(libraryManager)
                .environmentObject(themeManager)
                .preferredColorScheme(.dark)
                .task {
                    // Best-effort update check; silently no-ops when offline
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
    @Published var isLyricsVisible: Bool = false // Persistent lyrics state

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

// MARK: - Update Checker
// Checks GitHub releases for a newer version. Fails silently when offline.
import UserNotifications

@MainActor
final class UpdateChecker: ObservableObject {

    static let shared = UpdateChecker()
    private init() {}

    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var releaseURL: URL?
    @Published var isChecking = false

    private static let releasesAPI = "https://api.github.com/repos/YashvardhanATRgithub/Sangeet/releases/latest"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private struct GitHubRelease: Codable {
        let tag_name: String
        let html_url: String
        let body: String?
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        Task { await performCheck() }
    }

    private func performCheck() async {
        isChecking = true
        defer { isChecking = false }

        guard let url = URL(string: Self.releasesAPI) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sangeet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latest = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name

            if latest.compare(currentVersion, options: .numeric) == .orderedDescending {
                latestVersion = latest
                releaseNotes = release.body ?? ""
                releaseURL = URL(string: release.html_url)
                updateAvailable = true
                print("[UpdateChecker] Update available: v\(latest) (current v\(currentVersion))")
                notifyOncePerVersion(latest)
            } else {
                updateAvailable = false
                print("[UpdateChecker] Up to date (current v\(currentVersion), latest v\(latest))")
            }
        } catch {
            // Offline or API unavailable - update checking is best-effort
            print("[UpdateChecker] Check skipped: \(error.localizedDescription)")
        }
    }

    func openReleasePage() {
        if let url = releaseURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Posts a user notification the first time a given version is seen,
    /// so users aren't re-notified on every launch.
    private func notifyOncePerVersion(_ version: String) {
        let key = "lastNotifiedUpdateVersion"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        UserDefaults.standard.set(version, forKey: key)

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Update Available"
            content.body = "Sangeet v\(version) is out. Click to download."
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "UpdateAvailable", content: content, trigger: nil))
        }
    }
}
