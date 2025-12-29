import Foundation
import Combine

class KaraokeEngine: ObservableObject {
    static let shared = KaraokeEngine()
    @Published var state: Bool = false
}
