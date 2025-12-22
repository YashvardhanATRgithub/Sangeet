import SwiftUI

enum Theme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.09, blue: 0.17),
            Color(red: 0.05, green: 0.08, blue: 0.15),
            Color(red: 0.03, green: 0.05, blue: 0.12)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let panel = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.2, blue: 0.27),
            Color(red: 0.11, green: 0.14, blue: 0.2)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let accent = Color(red: 0.36, green: 0.72, blue: 1.0)
    static let accentWarm = Color(red: 0.99, green: 0.43, blue: 0.6)
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
