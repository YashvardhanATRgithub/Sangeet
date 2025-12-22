import Foundation
import CoreData

@MainActor
class DatabaseService: DatabaseLayer {
    private let stack = CoreDataStack.shared
    private var context: NSManagedObjectContext { stack.container.viewContext }
    
    // MARK: - Save
    func saveTrack(_ track: Track) async throws {
        // Already on MainActor, direct access safe for viewContext
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.predicate = NSPredicate(format: "url == %@", track.url as CVarArg)
        
        let result = try? self.context.fetch(req)
        let cdTrack = result?.first ?? NSEntityDescription.insertNewObject(forEntityName: "CDTrack", into: self.context)
        
        // Preserve an existing ID so favorites/play counts stay attached across rescans
        let persistedID = (cdTrack.value(forKey: "id") as? UUID) ?? track.id
        let persistedFavorite = (cdTrack.value(forKey: "isFavorite") as? Bool) ?? track.isFavorite
        let persistedPlayCount = (cdTrack.value(forKey: "playCount") as? NSNumber)?.intValue ?? track.playCount
        let persistedDate = (cdTrack.value(forKey: "dateAdded") as? Date) ?? track.dateAdded
        
        cdTrack.setValue(persistedID, forKey: "id")
        cdTrack.setValue(track.url, forKey: "url")
        cdTrack.setValue(track.title, forKey: "title")
        cdTrack.setValue(track.artist, forKey: "artist")
        cdTrack.setValue(track.album, forKey: "album")
        cdTrack.setValue(track.albumArtist, forKey: "albumArtist")
        cdTrack.setValue(track.genre, forKey: "genre")
        cdTrack.setValue(track.duration, forKey: "duration")
        cdTrack.setValue(track.trackNumber, forKey: "trackNumber")
        cdTrack.setValue(track.discNumber, forKey: "discNumber")
        cdTrack.setValue(track.year, forKey: "year")
        cdTrack.setValue(persistedDate, forKey: "dateAdded")
        cdTrack.setValue(persistedPlayCount, forKey: "playCount")
        cdTrack.setValue(track.searchKeywords, forKey: "searchKeywords")
        cdTrack.setValue(persistedFavorite, forKey: "isFavorite")
        
        if self.context.hasChanges {
            try self.context.save()
        }
    }
    
    // MARK: - Fetch
    func fetchAllTracks() async throws -> [Track] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        let results = try self.context.fetch(req)
        return results.map { self.mapToTrack($0) }
    }
    
    func fetchRecentTracks(limit: Int = 10) async throws -> [Track] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]
        req.fetchLimit = limit
        
        let results = try self.context.fetch(req)
        return results.map { self.mapToTrack($0) }
    }
    
    func fetchFavorites() async throws -> [Track] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.predicate = NSPredicate(format: "isFavorite == YES")
        req.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        
        let results = try self.context.fetch(req)
        return results.map { self.mapToTrack($0) }
    }
    
    func fetchAlbums() async throws -> [Album] {
        // Simple distinct grouping implementation (optimization: use NSDictionary/grouping fetch later)
        let tracks = try await fetchAllTracks()
        let grouped = Dictionary(grouping: tracks, by: { $0.album })
        
        return grouped.map { (albumName, tracks) in
            Album(title: albumName,
                  artist: tracks.first?.artist ?? "Unknown",
                  artworkPath: nil,
                  releaseDate: nil,
                  tracks: tracks)
        }.sorted { $0.title < $1.title }
    }
    
    func fetchArtists() async throws -> [Artist] {
        let tracks = try await fetchAllTracks()
        let grouped = Dictionary(grouping: tracks, by: { $0.artist })
        
        return grouped.map { (name, tracks) in
            Artist(name: name,
                   genre: tracks.first?.genre ?? "Unknown",
                   albums: [], // Would need recursive grouping
                   tracks: tracks)
        }.sorted { $0.name < $1.name }
    }
    
    func searchTracks(query: String) async -> [Track] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.predicate = NSPredicate(format: "searchKeywords CONTAINS[cd] %@", query)
        req.fetchLimit = 100
        
        let results = try? self.context.fetch(req)
        return (results ?? []).map { self.mapToTrack($0) }
    }
    
    func updatePlayCount(for trackID: UUID) async {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.predicate = NSPredicate(format: "id == %@", trackID as CVarArg)
        
        guard let result = try? self.context.fetch(req).first else { return }
        let current = (result.value(forKey: "playCount") as? NSNumber)?.intValue ?? 0
        result.setValue(current + 1, forKey: "playCount")
        try? self.context.save()
    }
    
    func toggleFavorite(for trackID: UUID) async {
        let req = NSFetchRequest<NSManagedObject>(entityName: "CDTrack")
        req.predicate = NSPredicate(format: "id == %@", trackID as CVarArg)
        
        if let result = try? self.context.fetch(req).first {
            let current = result.value(forKey: "isFavorite") as? Bool ?? false
            result.setValue(!current, forKey: "isFavorite")
            try? self.context.save()
        }
    }
    
    // MARK: - Helper
    private func mapToTrack(_ obj: NSManagedObject) -> Track {
        var id = obj.value(forKey: "id") as? UUID
        if id == nil {
             print("WARNING: Track missing ID, generating temporary one. This will cause bugs.")
             id = UUID() 
        }
        let url = obj.value(forKey: "url") as? URL ?? URL(fileURLWithPath: "")
        
        return Track(
            id: id!,
            url: url,
            title: obj.value(forKey: "title") as? String ?? "Unknown",
            artist: obj.value(forKey: "artist") as? String ?? "Unknown",
            album: obj.value(forKey: "album") as? String ?? "Unknown",
            albumArtist: obj.value(forKey: "albumArtist") as? String ?? "",
            genre: obj.value(forKey: "genre") as? String ?? "",
            duration: obj.value(forKey: "duration") as? TimeInterval ?? 0,
            trackNumber: (obj.value(forKey: "trackNumber") as? NSNumber)?.intValue,
            discNumber: (obj.value(forKey: "discNumber") as? NSNumber)?.intValue,
            year: (obj.value(forKey: "year") as? NSNumber)?.intValue,
            dateAdded: obj.value(forKey: "dateAdded") as? Date ?? Date(),
            playCount: (obj.value(forKey: "playCount") as? NSNumber)?.intValue ?? 0,
            isFavorite: obj.value(forKey: "isFavorite") as? Bool ?? false
        )
    }
}
