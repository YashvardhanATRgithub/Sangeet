import SwiftUI

enum Theme {
    // Sangeet uses a deeply dark neutral gray, standard macOS window background in dark mode.
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .windowBackgroundColor)
    
    static let separator = Color.white.opacity(0.1)
    
    // Sangeet uses specific yellow often, or blue. Sangeet accent is blue/cyan.
    static var accent: Color {
        AppTheme.shared.currentTheme.primaryColor
    }
    static let accentWarm = Color(red: 0.36, green: 0.72, blue: 1.0)
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
    }
    
    func pillButtonStyle() -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.panel)
            .clipShape(Capsule())
    }
}
