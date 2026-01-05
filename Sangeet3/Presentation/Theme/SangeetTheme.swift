//
//  SangeetTheme.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

enum SangeetTheme {
    // Dynamic background colors from ThemeManager
    static var background: Color { ThemeManager.shared.background }
    static var surface: Color { ThemeManager.shared.surface }
    static var surfaceElevated: Color { ThemeManager.shared.surfaceElevated }
    
    // Dynamic colors from ThemeManager
    static var primary: Color { ThemeManager.shared.primary }
    static var secondary: Color { ThemeManager.shared.secondary }
    static var accent: Color { ThemeManager.shared.accent }
    
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "B0B0B0")
    static let textMuted = Color(hex: "666666")
    
    static var primaryGradient: LinearGradient { ThemeManager.shared.primaryGradient }
    static var accentGradient: LinearGradient { ThemeManager.shared.accentGradient }
    static var glowShadow: Color { ThemeManager.shared.glowShadow }
    static let cardShadow = Color.black.opacity(0.3)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct GlassmorphicStyle: ViewModifier {
    var cornerRadius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.6))
            .background(SangeetTheme.surface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: SangeetTheme.cardShadow, radius: 20, x: 0, y: 10)
    }
}

extension View {
    func glassmorphic(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassmorphicStyle(cornerRadius: cornerRadius))
    }
}
