import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            Theme.background
            MainView()
            
            // Global Overlay for Karaoke Progress (Toast Style)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    KaraokeProgressBanner()
                        .frame(maxWidth: 320) // Limit width
                        .padding(.trailing, 20)
                        .padding(.bottom, 120) // Clear the NowPlayingBar (approx 80-100px)
                }
            }
        }
        .tint(Theme.accent)
    }
}
