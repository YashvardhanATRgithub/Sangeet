//
//  ThemeManager.swift
//  Sangeet3
//
//  Dynamic theme color management
//

import SwiftUI
import Combine

/// Manages dynamic theme colors for the app
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    /// Hue value (0.0 - 1.0) for the primary/accent color
    @Published var hue: Double {
        didSet {
            UserDefaults.standard.set(hue, forKey: "themeHue")
            updateColors()
        }
    }
    
    /// Background brightness (0.0 = pure black, 0.15 = dark gray)
    @Published var backgroundBrightness: Double {
        didSet {
            UserDefaults.standard.set(backgroundBrightness, forKey: "themeBgBrightness")
            updateColors()
        }
    }
    
    /// Background hue (optional tint, -1 = neutral/no tint)
    @Published var backgroundHue: Double {
        didSet {
            UserDefaults.standard.set(backgroundHue, forKey: "themeBgHue")
            updateColors()
        }
    }
    
    /// Current colors
    @Published var primary: Color = Color(hex: "7B2CBF")
    @Published var secondary: Color = Color(hex: "9D4EDD")
    @Published var accent: Color = Color(hex: "E040FB")
    @Published var background: Color = Color(hex: "0D0D0D")
    @Published var surface: Color = Color(hex: "1A1A2E")
    @Published var surfaceElevated: Color = Color(hex: "242438")
    
    /// Accent color presets
    static let accentPresets: [(name: String, hue: Double)] = [
        ("Purple", 0.75),
        ("Blue", 0.58),
        ("Cyan", 0.50),
        ("Green", 0.38),
        ("Yellow", 0.14),
        ("Orange", 0.08),
        ("Red", 0.98),
        ("Pink", 0.90),
        ("Magenta", 0.83),
    ]
    
    /// Background presets (brightness, hue) - hue -1 means neutral
    static let backgroundPresets: [(name: String, brightness: Double, hue: Double)] = [
        // Neutral blacks/grays
        ("Pure Black", 0.0, -1),
        ("Dark Gray", 0.08, -1),
        ("Charcoal", 0.12, -1),
        // Colorful subtle backgrounds
        ("Midnight Blue", 0.10, 0.62),
        ("Deep Purple", 0.10, 0.75),
        ("Ocean Teal", 0.10, 0.50),
        ("Forest Green", 0.08, 0.38),
        ("Wine Red", 0.08, 0.95),
        ("Warm Brown", 0.10, 0.08),
        ("Slate Blue", 0.12, 0.58),
        ("Plum", 0.10, 0.83),
        ("Navy", 0.08, 0.65),
    ]
    
    private init() {
        // Load saved values or use defaults
        let savedHue = UserDefaults.standard.double(forKey: "themeHue")
        self.hue = savedHue > 0 ? savedHue : 0.75
        
        let savedBgBrightness = UserDefaults.standard.object(forKey: "themeBgBrightness") as? Double ?? 0.05
        self.backgroundBrightness = savedBgBrightness
        
        let savedBgHue = UserDefaults.standard.object(forKey: "themeBgHue") as? Double ?? -1
        self.backgroundHue = savedBgHue
        
        updateColors()
    }
    
    private func updateColors() {
        // Accent colors
        primary = Color(hue: hue, saturation: 0.75, brightness: 0.75)
        secondary = Color(hue: hue, saturation: 0.70, brightness: 0.85)
        accent = Color(hue: (hue + 0.05).truncatingRemainder(dividingBy: 1.0), saturation: 0.80, brightness: 0.95)
        
        // Background colors
        if backgroundHue < 0 {
            // Neutral (no tint)
            background = Color(white: backgroundBrightness)
            surface = Color(white: backgroundBrightness + 0.06)
            surfaceElevated = Color(white: backgroundBrightness + 0.10)
        } else {
            // Tinted background - increased saturation for more color
            background = Color(hue: backgroundHue, saturation: 0.35, brightness: backgroundBrightness + 0.08)
            surface = Color(hue: backgroundHue, saturation: 0.30, brightness: backgroundBrightness + 0.14)
            surfaceElevated = Color(hue: backgroundHue, saturation: 0.25, brightness: backgroundBrightness + 0.18)
        }
    }
    
    /// Primary gradient
    var primaryGradient: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// Accent gradient
    var accentGradient: LinearGradient {
        LinearGradient(colors: [secondary, accent], startPoint: .leading, endPoint: .trailing)
    }
    
    /// Glow shadow color
    var glowShadow: Color {
        primary.opacity(0.4)
    }
}
