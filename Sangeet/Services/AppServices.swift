import Foundation
import Combine

@MainActor
class AppServices: ObservableObject {
    static let shared = AppServices()
    let objectWillChange = ObservableObjectPublisher()
    
    let database: DatabaseLayer
    let metadata: MetadataService
    let library: LibraryScanService
    let playback: RealPlaybackService
    let search: SearchService
    let libraryAccess: LibraryAccessStore
    let playlists: PlaylistStore
    
    private init() {
        // Initialize Core Services
        let dbService = DatabaseService()
        self.database = dbService
        
        let metaService = RealMetadataService()
        self.metadata = metaService
        
        let searchService = SearchService(database: dbService)
        self.search = searchService
        
        let accessStore = LibraryAccessStore.shared
        self.libraryAccess = accessStore
        let restored = accessStore.restoreAccess()
        let playlistStore = PlaylistStore()
        self.playlists = playlistStore
        
        let libraryService = RealLibraryScanService(database: dbService, metadataService: metaService, searchService: searchService)
        self.library = libraryService
        self.playback = RealPlaybackService()
        
        let watchedDirectories = accessStore.directoryURLs(from: restored)
        if !watchedDirectories.isEmpty {
            libraryService.startMonitoring(directories: watchedDirectories)
            Task {
                try? await libraryService.startScan(directories: watchedDirectories)
            }
        }
        
        // Start background tasks
        Task {
            await searchService.buildIndex()
        }
    }
}

extension Notification.Name {
    static let libraryDidUpdate = Notification.Name("libraryDidUpdate")
    static let toggleQueue = Notification.Name("toggleQueue")
}
