import SwiftUI

struct ContentView: View {

    var body: some View {
        ZStack {
            Theme.background
            MainView()
            

        }
        .tint(Theme.accent)
    }
}
