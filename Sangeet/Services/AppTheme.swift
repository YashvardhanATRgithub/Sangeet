//
//  AppTheme.swift
//  Sangeet
//
//  Created for Sangeet
//

import SwiftUI
import Combine

/// Theme manager for the application
class AppTheme: ObservableObject {
    static let shared = AppTheme()
    
    @Published var currentTheme: ThemeOption = .blue
    
    private init() {
        // Load saved theme from UserDefaults
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = ThemeOption(rawValue: savedTheme) {
            currentTheme = theme
        }
    }
    
    func setTheme(_ theme: ThemeOption) {
        currentTheme = theme
        UserDefaults.standard.set(theme.rawValue, forKey: "selectedTheme")
        
        // Update the accent color globally
        if let window = NSApplication.shared.windows.first {
            window.appearance = theme.appearance
        }
    }
}

/// Available themes for the app
enum ThemeOption: String, CaseIterable, Identifiable {
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case mint = "mint"
    case teal = "teal"
    case cyan = "cyan"
    case indigo = "indigo"
    
    var id: String { rawValue }
    
    var name: String {
        rawValue.capitalized
    }
    
    var primaryColor: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return Color(hue: 0.15, saturation: 0.8, brightness: 0.9)
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .indigo: return .indigo
        }
    }
    
    var gradientColors: [Color] {
        [primaryColor, primaryColor.opacity(0.7)]
    }
    
    var appearance: NSAppearance? {
        return nil // Let system handle dark/light mode
    }
}
