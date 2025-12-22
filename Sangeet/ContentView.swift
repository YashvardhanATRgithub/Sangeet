import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            MainView()
        }
        .tint(Theme.accent)
    }
}
