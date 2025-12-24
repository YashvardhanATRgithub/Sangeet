import SwiftUI

struct HoverScaleEffect: ViewModifier {
    var scale: CGFloat = 1.2
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovering ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovering)
            .onHover { hover in
                isHovering = hover
            }
    }
}

extension View {
    func hoverEffect(scale: CGFloat = 1.2) -> some View {
        self.modifier(HoverScaleEffect(scale: scale))
    }
}
