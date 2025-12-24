import Foundation
import Combine

@MainActor
class LibraryStore: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var isLoading = false
    

    
    // Explicitly use singleton
    private var database: DatabaseManager { AppServices.shared.database }
    
    init() {
        // Load initially
        loadTracks()
        
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .libraryDidUpdate, object: nil)
    }
    
    @objc func refresh() {
        loadTracks()
    }
    
    func loadTracks() {
        Task {
            isLoading = true
            do {
                self.tracks = try await database.fetchAllTracks()
            } catch {
                print("LibraryStore Error: \(error)")
            }
            isLoading = false
        }
    }
}
