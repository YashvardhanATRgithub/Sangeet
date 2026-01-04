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
            HStack(spacing: 8) {

                
                Image("SangeetLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                Text("Sangeet")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            .padding(.leading, 20)
            
            Spacer()
            
            HStack(spacing: 4) {
                ForEach(AppState.Tab.allCases, id: \.self) { tab in
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { appState.changeTab(to: tab) } }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon).font(.subheadline)
                            Text(tab.rawValue).font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.6))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background { if selectedTab == tab { Capsule().fill(SangeetTheme.primaryGradient).matchedGeometryEffect(id: "TAB_BG", in: animation) } }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(SangeetTheme.surface.opacity(0.5))
            .clipShape(Capsule())
            
            Spacer()
            
            // Download Indicator
            TopBarDownloadIndicator()
                .padding(.trailing, 16)
            
            Button(action: { withAnimation(.spring(response: 0.3)) { showSearch = true } }) {
                Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .padding(.trailing, 20)
        }
        .frame(height: 56)
        .background(SangeetTheme.background.opacity(0.9))
        .overlay(Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1), alignment: .bottom)
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
                    if case .downloading(let progress) = task.state {
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(SangeetTheme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 28)
                    } else if case .preparing = task.state {
                         ProgressView().scaleEffect(0.6)
                    } else if case .finished = task.state {
                         Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(.green)
                    } else if case .failed = task.state {
                         Image(systemName: "exclamationmark").font(.caption2.bold()).foregroundStyle(.red)
                    }
                    
                    // Artwork overlay (optional - maybe too small, let's stick to progress ring)
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
        }
    }
    
    private func statusText(for state: DownloadManager.DownloadState) -> String {
        switch state {
        case .preparing: return "Preparing..."
        case .downloading(let p): return "\(Int(p * 100))%"
        case .finished: return "Done"
        case .failed: return "Failed"
        }
    }
    
    private var activeTask: DownloadManager.DownloadTask? {
        downloadManager.activeDownloads.values.first { task in
            if case .finished = task.state { return false }
            return true
        } ?? downloadManager.activeDownloads.values.first
    }
}

