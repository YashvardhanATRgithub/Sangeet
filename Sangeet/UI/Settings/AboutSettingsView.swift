//
//  AboutSettingsView.swift
//  Sangeet
//
//  Created for Sangeet
//

import SwiftUI

struct AboutSettingsView: View {
    @State private var libraryStats: LibraryStats?
    @State private var isCheckingForUpdates = false
    @State private var updateResult: UpdateResult?
    
    private enum UpdateResult {
        case upToDate
        case updateAvailable(version: String, url: URL)
        case error(String)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            appInfoSection

            if let stats = libraryStats, stats.totalFolders > 0 {
                libraryStatisticsSection
            }

            footerSection
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadLibraryStats()
        }
    }
    
    private func loadLibraryStats() async {
        do {
            libraryStats = try await DatabaseCache.shared.getLibraryStats()
        } catch {
            Logger.error("Failed to load library stats: \(error)")
        }
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(spacing: 16) {
            appIcon
            appDetails
        }
    }

    private var appIcon: some View {
        Group {
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Image(systemName: "music.note.house.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Theme.accent)
            }
        }
    }

    private var appDetails: some View {
        VStack(spacing: 12) {
            Text(About.appTitle)
                .font(.title)
                .fontWeight(.bold)

            Text("Version " + About.appVersion + " (Build " + About.appBuild + ")")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Check for Updates Button
            HStack(spacing: 12) {
                Button(action: checkForUpdates) {
                    HStack(spacing: 8) {
                        if isCheckingForUpdates {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text(isCheckingForUpdates ? "Checking..." : "Check for Updates")
                    }
                    .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .disabled(isCheckingForUpdates)
                
                // Update result indicator
                if let result = updateResult {
                    updateResultView(result)
                }
            }
        }
    }
    
    @ViewBuilder
    private func updateResultView(_ result: UpdateResult) -> some View {
        switch result {
        case .upToDate:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("You're up to date!")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .updateAvailable(let version, let url):
            Button(action: {
                NSWorkspace.shared.open(url)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("v\(version) available")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .underline()
        case .error(let message):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateResult = nil
        
        Task {
            do {
                let info = try await UpdateChecker.shared.checkForUpdates()
                await MainActor.run {
                    if info.isAvailable {
                        updateResult = .updateAvailable(version: info.latestVersion, url: info.releaseURL)
                    } else {
                        updateResult = .upToDate
                    }
                    isCheckingForUpdates = false
                }
            } catch {
                await MainActor.run {
                    updateResult = .error(error.localizedDescription)
                    isCheckingForUpdates = false
                }
            }
        }
    }

    // MARK: - Library Statistics Section

    private var libraryStatisticsSection: some View {
        VStack(spacing: 12) {
            Text("Library Statistics")
                .font(.headline)

            if let stats = libraryStats {
                statisticsRow(stats: stats)
            }
        }
    }

    private func statisticsRow(stats: LibraryStats) -> some View {
        HStack(spacing: 30) {
            statisticItem(
                value: "\(stats.totalFolders)",
                label: "Folders"
            )

            statisticItem(
                value: "\(stats.totalTracks)",
                label: "Tracks"
            )

            statisticItem(
                value: stats.formattedDuration,
                label: "Total Duration"
            )

            statisticItem(
                value: stats.formattedStorage,
                label: "Total Storage"
            )
        }
        .padding()
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(12)
    }

    private func statisticItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack(spacing: 20) {
            FooterLink(
                icon: "globe",
                title: "Website",
                url: URL(string: About.appWebsite)!,
                tooltip: "Visit project website"
            )
            
            FooterLink(
                icon: "questionmark.circle",
                title: "Help",
                url: URL(string: About.appWiki)!,
                tooltip: "Visit Help Wiki"
            )
            
            FooterLink(
                icon: "doc.text",
                title: "License",
                url: URL(string: "\(About.appWebsite)/blob/main/LICENSE"),
                tooltip: "View license"
            )
            
            FooterLink(
                icon: "folder",
                title: "App Data",
                action: {
                    let appDataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent(About.bundleIdentifier)
                    
                    if let url = appDataURL {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                    }
                },
                tooltip: "Show app data directory in Finder"
            )
        }
    }
    
    private struct FooterLink: View {
        let icon: String
        let title: String
        var url: URL?
        var action: (() -> Void)?
        let tooltip: String
        
        @State private var isHovered = false
        
        var body: some View {
            if let url = url {
                Link(destination: url) {
                    linkContent
                }
                .buttonStyle(.plain)
                .help(tooltip)
            } else if let action = action {
                Button(action: action) {
                    linkContent
                }
                .buttonStyle(.plain)
                .help(tooltip)
            }
        }
        
        private var linkContent: some View {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 12))
            }
            .foregroundColor(isHovered ? Theme.accent : .secondary)
            .underline(isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }

}
