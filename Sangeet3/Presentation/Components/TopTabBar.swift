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

