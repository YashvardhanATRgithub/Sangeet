import Foundation
import Combine

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [StoredPlaylist] = []
    
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Sangeet", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storageURL = directory.appendingPathComponent("playlists.json")
        load()
    }
    
    func create(name: String, trackIDs: [UUID] = []) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let newPlaylist = StoredPlaylist(
            id: UUID(),
            name: trimmed,
            trackIDs: trackIDs,
            dateCreated: Date()
        )
        playlists.append(newPlaylist)
        persist()
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
        return newPlaylist.id
    }
    
    func delete(id: UUID) {
        playlists.removeAll { $0.id == id }
        persist()
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
    
    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = trimmed
        persist()
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
    
    func add(tracks: [UUID], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let existing = Set(playlists[index].trackIDs)
        let additions = tracks.filter { !existing.contains($0) }
        guard !additions.isEmpty else { return }
        playlists[index].trackIDs.append(contentsOf: additions)
        persist()
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
    
    func remove(tracks: [UUID], from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let removal = Set(tracks)
        playlists[index].trackIDs.removeAll { removal.contains($0) }
        persist()
        NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
    }
    
    func playlist(id: UUID) -> StoredPlaylist? {
        playlists.first { $0.id == id }
    }
    
    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let decoded = try? JSONDecoder().decode([StoredPlaylist].self, from: data) else { return }
        playlists = decoded
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}

struct StoredPlaylist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var trackIDs: [UUID]
    var dateCreated: Date
}
