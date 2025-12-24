//
//  AppearanceSettingsView.swift
//  Sangeet
//
//  Created for Sangeet
//

import SwiftUI

struct AppearanceSettingsView: View {
    @ObservedObject var theme = AppTheme.shared
    @AppStorage("accentOpacity") private var accentOpacity: Double = 1.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // Theme Selection
            themeSection
            
            Divider()
            
            // Advanced Options
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            
        }
    }
    
    // MARK: - Theme Section
    
    private var themeSection: some View {
        VStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Theme")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Choose your preferred color theme")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100), spacing: 16)
                ], spacing: 16) {
                    ForEach(ThemeOption.allCases) { themeOption in
                        ThemeCard(
                            theme: theme,
                            themeOption: themeOption,
                            opacity: accentOpacity
                        )
                    }
                }
            }
        
            
            
            // Accent opacity
            VStack(spacing: 8) {
                HStack {
                    Text("Accent Color Intensity")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(accentOpacity * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ModernSlider(value: $accentOpacity, range: 0.5...1.0, step: 0.1)
                    .accentColor(theme.currentTheme.primaryColor)
            }
        }
    }
    
    private func resetToDefaults() {
        accentOpacity = 1.0
        theme.setTheme(.blue)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    @ObservedObject var theme: AppTheme
    let themeOption: ThemeOption
    let opacity: Double
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                theme.setTheme(themeOption)
            }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: themeOption.gradientColors.map { $0.opacity(opacity) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    theme.currentTheme == themeOption ? themeOption.primaryColor : Color.clear,
                                    lineWidth: 3
                                )
                        )
                        .shadow(
                            color: isHovered ? themeOption.primaryColor.opacity(0.3) : Color.clear,
                            radius: 8
                        )
                    
                    if theme.currentTheme == themeOption {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
                
                Text(themeOption.name)
                    .font(.subheadline)
                    .fontWeight(theme.currentTheme == themeOption ? .semibold : .regular)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
