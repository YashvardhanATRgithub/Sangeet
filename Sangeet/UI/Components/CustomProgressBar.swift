import SwiftUI

// MARK: - Android-Style Squiggly Progress Bar (Lock Screen Snake)
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
    
    // Wave animation phase (only animates when playing)
    @State private var wavePhase: CGFloat = 0
    
    // Wave parameters (tuned for Android lock screen look)
    private let waveAmplitude: CGFloat = 3.0     // Height of the wave peaks
    private let waveFrequency: CGFloat = 0.08   // How many waves per point
    private let waveSpeed: CGFloat = 2.5         // Animation speed
    private let trackHeight: CGFloat = 4.0       // Base track height
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60, paused: !isPlaying && !isDragging)) { context in
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
            
            // Update wave phase continuously when playing
            let animatedPhase: CGFloat = isPlaying ? CGFloat(context.date.timeIntervalSinceReferenceDate) * waveSpeed : wavePhase
            
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let centerY = height / 2
                let progressX = width * CGFloat(progress)
                
                ZStack {
                    // 1. Background Track (straight line)
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: trackHeight)
                        .position(x: width / 2, y: centerY)
                    
                    // 2. Squiggly Progress Wave (the snake!)
                    Canvas { ctx, size in
                        guard progressX > 0 else { return }
                        
                        var path = Path()
                        let startX: CGFloat = 0
                        let endX = progressX
                        
                        // Start the path
                        path.move(to: CGPoint(x: startX, y: centerY))
                        
                        // Draw the wavy line
                        for x in stride(from: startX, through: endX, by: 1) {
                            // Sine wave that travels along the bar
                            let relativeX = x / width
                            let wave = sin((x * waveFrequency) + animatedPhase) * waveAmplitude
                            
                            // Dampen the wave near the edges for smooth entry/exit
                            let edgeDamping = min(x / 20, (endX - x) / 20, 1.0)
                            let dampedWave = wave * edgeDamping
                            
                            path.addLine(to: CGPoint(x: x, y: centerY + dampedWave))
                        }
                        
                        // Draw the wave stroke (no glow - clean look)
                        ctx.stroke(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [Theme.accent, Theme.accent.opacity(0.9)]),
                                startPoint: .zero,
                                endPoint: CGPoint(x: endX, y: 0)
                            ),
                            style: StrokeStyle(lineWidth: trackHeight, lineCap: .round, lineJoin: .round)
                        )
                    }
                    
                    // 3. Android-style Pill Thumb (vertical capsule - stays fixed at center, doesn't move with wave)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                        .frame(width: 8, height: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.001)).frame(width: 30, height: 30)) // Hit area
                        .scaleEffect(isDragging ? 1.2 : (isHovering ? 1.1 : 1.0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
                        .onHover { isHovering = $0 }
                        .position(
                            x: max(4, min(width - 4, progressX)),
                            y: centerY  // Fixed at center - doesn't move with wave
                        )
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

