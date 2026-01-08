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
    // Downloads removed
    var body: some View {
        EmptyView()
    }
}


