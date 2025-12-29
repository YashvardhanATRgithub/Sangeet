import Foundation
import Combine
import GRDB

@MainActor
class AppServices: ObservableObject {
    static let shared = AppServices()
    let objectWillChange = ObservableObjectPublisher()
    
    // Core Services (Sangeet Backend)
    let database: DatabaseManager
    let playback: PlaybackController
    let search: SearchService
    
    // Helpers
    let dac: DACManager
    let audioSettings: AudioSettings
    let effects: AudioEffectsManager
    
    // Legacy placeholders (to keep UI compiling for now, or we remove them?)
    // Best to remove and fix compile errors in UI.
    
    // Global Search State
    @Published var searchQuery: String = ""
    
    // Keep track of accessed folders to maintain scope
    private var activeFolderAccess: Set<URL> = []
    
    private init() {
        // Initialize Database
        self.database = DatabaseManager.shared
        
        // Initialize Audio & Playback
        self.dac = DACManager.shared
        self.audioSettings = AudioSettings.shared
        self.effects = AudioEffectsManager.shared
        self.playback = PlaybackController.shared
        
        // Initialize Search
        let searchService = SearchService(database: self.database)
        self.search = searchService
        
        Logger.info("AppServices initialized with Sangeet backend")
        
        // Restore access to music folders (Critical for Sandbox)
        Task {
            await restoreFolderAccess()
        }
        
        // Build search index
        Task {
            // Rebuilding FTS ensures all tracks are searchable even if migrated from old schema
            try? await database.rebuildFTS()
            await searchService.buildIndex()
        }
    }
    
    /// Restore access to all folders in the database using stored security bookmarks
    @MainActor
    private func restoreFolderAccess() async {
        Logger.info("Restoring file access permissions...")
        let folders = database.getAllFolders()
        var successCount = 0
        
        for folder in folders {
            guard let bookmarkData = folder.bookmarkData else {
                Logger.warning("Folder '\(folder.name)' has no bookmark data")
                continue
            }
            
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
                
                if url.startAccessingSecurityScopedResource() {
                    activeFolderAccess.insert(url)
                    successCount += 1
                    Logger.debug("Restored access to: \(folder.name)")
                } else {
                    Logger.error("Failed to start accessing: \(folder.name)")
                }
                
                if isStale {
                    Logger.warning("Bookmark for '\(folder.name)' is stale - should be refreshed")
                    // Ideally trigger a refresh here via FolderWatcher or similar
                }
            } catch {
                Logger.error("Failed to resolve bookmark for '\(folder.name)': \(error)")
            }
        }
        
        Logger.info("Restored access to \(successCount)/\(folders.count) folders")
    }
}

extension Notification.Name {
    static let libraryDidUpdate = Notification.Name("libraryDidUpdate") // Kept for UI compatibility
    static let toggleQueue = Notification.Name("toggleQueue")
}
