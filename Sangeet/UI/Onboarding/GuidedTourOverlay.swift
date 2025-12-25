//
//  GuidedTourOverlay.swift
//  Sangeet
//
//  Interactive spotlight overlay for guided tour
//

import SwiftUI

struct GuidedTourOverlay: View {
    @ObservedObject var tour = GuidedTourManager.shared
    @ObservedObject var theme = AppTheme.shared
    let elementFrames: [String: CGRect]
    
    private var targetFrame: CGRect {
        guard let targetID = tour.currentStep.targetElementID,
              let frame = elementFrames[targetID] else {
            return .zero
        }
        return frame
    }
    
    var body: some View {
        if tour.isActive {
            GeometryReader { geometry in
                ZStack {
                    // Dimmed background with spotlight cutout
                    SpotlightMask(targetFrame: targetFrame, cornerRadius: 12)
                        .fill(Color.black.opacity(0.75))
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Clicking dark area advances tour
                            tour.nextStep()
                        }
                    
                    // Glowing border around target (if any)
                    if targetFrame != .zero {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [theme.currentTheme.primaryColor, theme.currentTheme.primaryColor.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: targetFrame.width + 16, height: targetFrame.height + 16)
                            .position(x: targetFrame.midX, y: targetFrame.midY)
                            .shadow(color: theme.currentTheme.primaryColor.opacity(0.6), radius: 15)
                            .allowsHitTesting(false)
                        
                        // Pulsing animation ring
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.currentTheme.primaryColor.opacity(0.3), lineWidth: 2)
                            .frame(width: targetFrame.width + 24, height: targetFrame.height + 24)
                            .position(x: targetFrame.midX, y: targetFrame.midY)
                            .modifier(PulseAnimation())
                            .allowsHitTesting(false)
                    }
                    
                    // Tooltip card
                    tooltipCard(in: geometry)
                }
            }
            .transition(.opacity)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tour.currentStep)
        }
    }
    
    private func tooltipCard(in geometry: GeometryProxy) -> some View {
        let position = calculateTooltipPosition(in: geometry)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Title
            Text(tour.currentStep.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            
            // Description
            Text(tour.currentStep.description)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<GuidedTourManager.TourStep.allCases.count, id: \.self) { index in
                    Circle()
                        .fill(index == tour.currentStep.rawValue ? theme.currentTheme.primaryColor : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 4)
            
            // Buttons
            HStack(spacing: 12) {
                Button(action: { tour.skipTour() }) {
                    Text("Skip")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Button(action: { tour.nextStep() }) {
                    Text(nextButtonText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(theme.currentTheme.primaryColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        )
        .position(position)
    }
    
    private func calculateTooltipPosition(in geometry: GeometryProxy) -> CGPoint {
        let screenCenter = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        
        // Center for welcome/complete steps
        if targetFrame == .zero {
            return screenCenter
        }
        
        let tooltipHeight: CGFloat = 180
        let tooltipWidth: CGFloat = 300
        let padding: CGFloat = 20
        
        switch tour.currentStep.tooltipPosition {
        case .above:
            // Position above the target
            let y = max(tooltipHeight/2 + padding, targetFrame.minY - tooltipHeight/2 - padding)
            return CGPoint(x: clamp(targetFrame.midX, min: tooltipWidth/2 + padding, max: geometry.size.width - tooltipWidth/2 - padding), y: y)
            
        case .below:
            // Position below the target
            let y = min(geometry.size.height - tooltipHeight/2 - padding, targetFrame.maxY + tooltipHeight/2 + padding)
            return CGPoint(x: clamp(targetFrame.midX, min: tooltipWidth/2 + padding, max: geometry.size.width - tooltipWidth/2 - padding), y: y)
            
        case .left:
            return CGPoint(x: targetFrame.minX - tooltipWidth/2 - padding, y: targetFrame.midY)
            
        case .right:
            return CGPoint(x: targetFrame.maxX + tooltipWidth/2 + padding, y: targetFrame.midY)
            
        case .center:
            return screenCenter
        }
    }
    
    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        return max(minVal, min(maxVal, value))
    }
    
    private var nextButtonText: String {
        switch tour.currentStep {
        case .welcome: return "Let's Go!"
        case .complete: return "Done"
        default: return "Next"
        }
    }
}

// MARK: - Spotlight Mask Shape
struct SpotlightMask: Shape {
    var targetFrame: CGRect
    var cornerRadius: CGFloat
    
    var animatableData: CGRect.AnimatableData {
        get { targetFrame.animatableData }
        set { targetFrame.animatableData = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        
        if targetFrame != .zero {
            // Create cutout with padding
            let cutoutRect = targetFrame.insetBy(dx: -8, dy: -8)
            let cutout = Path(roundedRect: cutoutRect, cornerRadius: cornerRadius)
            path = path.subtracting(cutout)
        }
        
        return path
    }
}

// MARK: - Pulse Animation Modifier
struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.15 : 1.0)
            .opacity(isPulsing ? 0 : 0.5)
            .animation(
                .easeInOut(duration: 1.2)
                .repeatForever(autoreverses: false),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - CGRect Animatable
extension CGRect: @retroactive Animatable {
    public var animatableData: AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData> {
        get {
            AnimatablePair(origin.animatableData, size.animatableData)
        }
        set {
            origin.animatableData = newValue.first
            size.animatableData = newValue.second
        }
    }
}

extension CGPoint: @retroactive Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}

extension CGSize: @retroactive Animatable {
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
}
