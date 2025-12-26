import SwiftUI

struct KaraokeProgressBanner: View {
    @ObservedObject var engine = KaraokeEngine.shared
    
    @ObservedObject var theme = AppTheme.shared

    var body: some View {
        Group {
            if case .processing(let progress) = engine.state {
                HStack(spacing: 12) {
                    // Circular Progress
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.2), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear, value: progress)
                    }
                    .frame(width: 24, height: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Creating Karaoke...")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("Spleeter AI separating stems")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    
                    Spacer()
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundColor(.white)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.currentTheme.primaryColor.opacity(0.95)) // Theme match
                        .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) // Blur effect
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: engine.state)
    }
}
