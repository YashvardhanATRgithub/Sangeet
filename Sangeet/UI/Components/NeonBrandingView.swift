import SwiftUI

struct NeonBrandingView: View {
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.circle.fill") // HiFi-like icon
                .font(.system(size: 24))
                .foregroundStyle(theme.currentTheme.primaryColor) // Dynamic Theme Color
            
            Text("Sangeet")
                .font(.system(size: 20, weight: .bold, design: .default))
                .foregroundStyle(theme.currentTheme.primaryColor) // Dynamic Theme Color
                .tracking(-0.5) // Tight tracking like a logotype
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sangeet App")
    }
}
