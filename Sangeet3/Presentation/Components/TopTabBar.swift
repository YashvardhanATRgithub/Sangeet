//
//  TopTabBar.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

struct TopTabBar: View {
    @Binding var selectedTab: AppState.Tab
    @Binding var showSearch: Bool
    @EnvironmentObject var appState: AppState // Access navigation path
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            // Branding
            HStack(spacing: 10) {
                Image("SangeetLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: SangeetTheme.primary.opacity(0.3), radius: 8)
                
                Text("Sangeet")
                    .font(.title2.bold())
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(.leading, 24)
            
            Spacer()
            
            // Premium Tab Bar
            HStack(spacing: 6) {
                ForEach(AppState.Tab.allCases, id: \.self) { tab in
                    TabButton(tab: tab, isSelected: selectedTab == tab, namespace: animation) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            appState.changeTab(to: tab)
                        }
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            
            Spacer()
            
            // Download Indicator
            TopBarDownloadIndicator()
                .padding(.trailing, 12)
            
            // Metadata Indicator
            TopBarMetadataIndicator()
                .padding(.trailing, 12)
            
            // Search Button
            Button(action: { withAnimation(.spring(response: 0.3)) { showSearch = true } }) {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .padding(.trailing, 24)
        }
        .frame(height: 64)
        .background(
            SangeetTheme.background.opacity(0.85)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [SangeetTheme.primary.opacity(0.3), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1),
            alignment: .bottom
        )
    }
}

// MARK: - Premium Tab Button
struct TabButton: View {
    let tab: AppState.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(tab.rawValue)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(isHovering ? 0.9 : 0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    Capsule()
                        .fill(SangeetTheme.primaryGradient)
                        .matchedGeometryEffect(id: "TAB_BG", in: namespace)
                        .shadow(color: SangeetTheme.primary.opacity(0.4), radius: 8, y: 2)
                } else if isHovering {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

struct TopBarDownloadIndicator: View {
    @ObservedObject var downloadManager = DownloadManager.shared
    @State private var isHovering = false
    
    var body: some View {
        if let task = activeTask {
            HStack(spacing: 8) {
                ZStack {
                    // Background Circle
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 3)
                        .frame(width: 28, height: 28)
                    
                    // Progress Circle
                    // Progress Circle / Status Icon
                    if case .downloading(let progress) = task.state {
                        ZStack {
                            Circle()
                                .trim(from: 0, to: CGFloat(progress))
                                .stroke(SangeetTheme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 28, height: 28)
                            
                            // Cancel Button overlay
                            if isHovering {
                                Button {
                                    downloadManager.cancelDownload(trackID: task.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if case .preparing = task.state {
                         ProgressView().scaleEffect(0.6)
                    } else if case .finished = task.state {
                        Button {
                             downloadManager.activeDownloads.removeValue(forKey: task.id)
                        } label: {
                             Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss")
                        
                    } else if case .failed = task.state {
                        Button {
                            downloadManager.retryDownload(trackID: task.id)
                        } label: {
                            Image(systemName: "arrow.clockwise") // Retry icon
                                .font(.caption2.bold())
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Retry")
                        
                    } else if case .cancelled = task.state {
                        Button {
                             downloadManager.activeDownloads.removeValue(forKey: task.id)
                        } label: {
                             Image(systemName: "xmark").font(.caption2.bold()).foregroundStyle(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Text details on hover
                if isHovering {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(task.track.title)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(statusText(for: task.state))
                            .font(.caption2)
                            .foregroundStyle(SangeetTheme.textSecondary)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .frame(maxWidth: 120, alignment: .leading)
                }
            }
            .padding(6)
            .background(isHovering ? SangeetTheme.surfaceElevated : Color.clear)
            .cornerRadius(20)
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.3), value: isHovering)
            .animation(.default, value: task.state)
            .onTapGesture {
                handleTaskTap(task)
            }
            .help(helpText(for: task.state))
            .onAppear {
                 // Auto-dismiss finished tasks if not dismissed by DownloadManager
                 if case .finished = task.state {
                      DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                           // This is handled by DownloadManager but UI can also hide it
                      }
                 }
            }
        }
    }
    
    private func handleTaskTap(_ task: DownloadManager.DownloadTask) {
        switch task.state {
        case .downloading, .preparing:
            downloadManager.cancelDownload(trackID: task.id)
        case .failed:
            downloadManager.retryDownload(trackID: task.id)
        case .finished, .cancelled:
            // Dismiss manually
            downloadManager.activeDownloads.removeValue(forKey: task.id)
        }
    }
    
    private func helpText(for state: DownloadManager.DownloadState) -> String {
        switch state {
        case .downloading, .preparing: return "Click to Cancel"
        case .failed: return "Click to Retry"
        case .finished: return "Click to Dismiss"
        case .cancelled: return "Click to Dismiss"
        }
    }
    
    private func statusText(for state: DownloadManager.DownloadState) -> String {
        switch state {
        case .preparing: return "Preparing..."
        case .downloading(let p): return "\(Int(p * 100))%"
        case .finished: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private var activeTask: DownloadManager.DownloadTask? {
        downloadManager.activeDownloads.values.first { task in
            if case .finished = task.state { return false }
            return true
        } ?? downloadManager.activeDownloads.values.first
    }
}

