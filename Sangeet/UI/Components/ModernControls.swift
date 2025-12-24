import SwiftUI

struct ModernToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            Spacer()
            
            RoundedRectangle(cornerRadius: 16)
                .fill(configuration.isOn ? Theme.accent : Color.gray.opacity(0.3))
                .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
                .frame(width: 42, height: 24)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .padding(2)
                        .offset(x: configuration.isOn ? 9 : -9)
                        .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
                        .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

struct ModernSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.0
    var accentColor: Color = Theme.accent
    
    @State private var isHovering = false
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)
                
                // Fill Track
                Capsule()
                    .fill(accentColor)
                    .frame(width: max(0, CGFloat(normalizedValue) * geometry.size.width), height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .scaleEffect(isHovering || isDragging ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3), value: isHovering || isDragging)
                    .offset(x: max(0, CGFloat(normalizedValue) * geometry.size.width - 8))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = gesture.location.x / geometry.size.width
                        let clampedValue = min(max(0, Double(newValue)), 1)
                        let rawValue = range.lowerBound + (clampedValue * (range.upperBound - range.lowerBound))
                        
                        // Apply step if needed
                        if step > 0 {
                            value = round(rawValue / step) * step
                        } else {
                            value = rawValue
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
    
    private var normalizedValue: Double {
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// Extension to easily apply the style
extension ToggleStyle where Self == ModernToggleStyle {
    static var modern: ModernToggleStyle { .init() }
}
