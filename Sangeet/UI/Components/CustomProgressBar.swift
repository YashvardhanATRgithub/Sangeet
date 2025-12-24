import SwiftUI

struct CustomProgressBar: View {
    @Binding var value: TimeInterval
    var total: TimeInterval
    var isPlaying: Bool
    var onSeek: (TimeInterval) -> Void
    var onEditingChanged: (Bool) -> Void
    
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0
    
    // Interpolation Support
    @State private var lastUpdatedTime: Date = Date()
    @State private var baseValue: TimeInterval = 0
    @State private var isHovering: Bool = false
    
    var body: some View {
        TimelineView(.animation) { context in
            // Calculate interpolated time
            let currentDisplayTime: TimeInterval = {
                if isDragging { return dragProgress * total }
                if !isPlaying { return value }
                
                let elapsed = context.date.timeIntervalSince(lastUpdatedTime)
                // Prevent runaway interpolation (cap drift at 1.5s)
                if elapsed > 1.5 { return value } 
                return baseValue + elapsed
            }()
            
            let progress = total > 0 ? min(max(0, currentDisplayTime / total), 1.0) : 0
            
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let centerY = height / 2
                let filledWidth = max(0, min(width, width * CGFloat(progress)))
                
                ZStack(alignment: .leading) {
                    // 1. Background Track
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                    
                    // 2. Active Progress (Neon Beam)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: filledWidth, height: 4)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 6, x: 0, y: 0)
                    
                // Thumb (Standard Circle)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .frame(width: 14, height: 14) // Visual size
                    .background(Circle().fill(.white.opacity(0.001)).frame(width: 30, height: 30)) // Hit area
                    .scaleEffect(isDragging ? 1.3 : (isHovering ? 1.2 : 1.0))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
                    .onHover { isHovering = $0 }
                    .position(x: geometry.size.width * CGFloat(currentDisplayTime / total), y: geometry.size.height / 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                onEditingChanged(true)
                            }
                            let p = min(max(0, value.location.x / width), 1)
                            dragProgress = p
                        }
                        .onEnded { value in
                        let p = min(max(0, value.location.x / width), 1)
                        isDragging = false
                        onEditingChanged(false)
                        
                        let targetTime = p * total
                        // Optimistic update to prevent visual glitch/jump back
                        baseValue = targetTime
                        lastUpdatedTime = Date()
                        
                        onSeek(targetTime)
                    }
                )
            }
        }
        .frame(height: 24)
        .onChange(of: value) { newValue in
            // Backend update: Sync base
            baseValue = newValue
            lastUpdatedTime = Date()
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                // Resume interpolation from current value
                baseValue = value
                lastUpdatedTime = Date()
            }
        }
        .onAppear {
            baseValue = value
            lastUpdatedTime = Date()
        }
    }
}

