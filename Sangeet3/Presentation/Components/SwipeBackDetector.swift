
import SwiftUI

// MARK: - Swipe Back Detector

struct SwipeBackDetector: NSViewRepresentable {
    var onSwipeBack: () -> Void
    
    func makeNSView(context: Context) -> SwipeBackDetectorView {
        let view = SwipeBackDetectorView()
        view.onSwipeBack = onSwipeBack
        return view
    }
    
    func updateNSView(_ nsView: SwipeBackDetectorView, context: Context) {
        nsView.onSwipeBack = onSwipeBack
    }
}

class SwipeBackDetectorView: NSView {
    
    var onSwipeBack: (() -> Void)?
    private var lastGestureTime: Date = .distantPast
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
    
    private var monitor: Any?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        
        guard let window = self.window else { return }
        
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }
    }
    
    deinit {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    private func handleScroll(_ event: NSEvent) {
        // Debounce: 0.5s
        guard Date().timeIntervalSince(lastGestureTime) > 0.5 else { return }
        
        // Check for sufficient horizontal swipe
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) && abs(event.scrollingDeltaX) > 20 {
            // Swipe Right (Move fingers right) -> Back
            if event.scrollingDeltaX > 0 {
                onSwipeBack?()
                lastGestureTime = Date()
            }
        }
    }
}

extension View {
    func enableSwipeToBack(action: @escaping () -> Void) -> some View {
        self.background(SwipeBackDetector(onSwipeBack: action))
    }
}
