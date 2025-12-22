import SwiftUI

enum NowPlayingBarDefaults {
    static let minHeight: CGFloat = 92
}

struct NowPlayingBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NowPlayingBarHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = NowPlayingBarDefaults.minHeight
}

extension EnvironmentValues {
    var nowPlayingBarHeight: CGFloat {
        get { self[NowPlayingBarHeightKey.self] }
        set { self[NowPlayingBarHeightKey.self] = newValue }
    }
}

struct NowPlayingBarPadding: ViewModifier {
    @Environment(\.nowPlayingBarHeight) private var nowPlayingBarHeight
    
    func body(content: Content) -> some View {
        content.padding(.bottom, nowPlayingBarHeight)
    }
}

extension View {
    func nowPlayingBarPadding() -> some View {
        modifier(NowPlayingBarPadding())
    }
}
