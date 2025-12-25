//
//  OnboardingView.swift
//  Sangeet
//
//  Welcome experience for first-time users
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @ObservedObject var theme = AppTheme.shared
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "music.note.house.fill",
            title: "Welcome to Sangeet",
            subtitle: "Your beautiful music player for macOS",
            features: [
                "Import your music folders and enjoy",
                "Beautiful glassmorphism design",
                "11 gorgeous theme colors"
            ]
        ),
        OnboardingPage(
            icon: "slider.vertical.3",
            title: "Professional Audio",
            subtitle: "Studio-grade sound control",
            features: [
                "10-band graphic equalizer",
                "15+ built-in EQ presets",
                "Save your own custom presets"
            ]
        ),
        OnboardingPage(
            icon: "music.mic",
            title: "One-Click Karaoke",
            subtitle: "Sing along to your favorites",
            features: [
                "Instantly reduce vocals",
                "View synced lyrics",
                "Full-screen immersive mode"
            ]
        ),
        OnboardingPage(
            icon: "keyboard",
            title: "Quick Tips",
            subtitle: "Keyboard shortcuts & gestures",
            features: [
                "⌘K → Command Palette",
                "Space → Play/Pause",
                "Double-click song → Play immediately"
            ]
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Spacer()
                Button(action: { completeOnboarding() }) {
                    Text("Skip")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }
            
            Spacer()
            
            // Page content
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
            .frame(height: 350)
            
            Spacer()
            
            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? theme.currentTheme.primaryColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }
            .padding(.bottom, 20)
            
            // Action button
            Button(action: {
                if currentPage < pages.count - 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        currentPage += 1
                    }
                } else {
                    completeOnboarding()
                }
            }) {
                Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 200, height: 44)
                    .background(theme.currentTheme.primaryColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .frame(width: 500, height: 550)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 60))
                .foregroundStyle(theme.currentTheme.primaryColor)
                .frame(height: 80)
            
            // Title & Subtitle
            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                
                Text(page.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.features, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.currentTheme.primaryColor)
                        Text(feature)
                            .font(.system(size: 14))
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let features: [String]
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
