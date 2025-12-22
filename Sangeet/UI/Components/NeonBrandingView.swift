import SwiftUI

struct NeonBrandingView: View {
    var body: some View {
        Text("Sangeet")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.accent, Theme.accentWarm],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Theme.accent.opacity(0.3), radius: 5, x: 0, y: 2)
            .accessibilityLabel("Sangeet")
    }
}
