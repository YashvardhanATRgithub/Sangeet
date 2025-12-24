//
//  Folder.swift
//  HiFidelity
//
//  Created by Varun Rathod on 27/10/25.
//


import Foundation
import GRDB

struct Folder: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    let url: URL
    var name: String
    var trackCount: Int
    var dateAdded: Date
    var dateUpdated: Date
    var bookmarkData: Data?

    // MARK: - Initialization

    init(url: URL, id: Int64? = nil, bookmarkData: Data? = nil) {
        self.id = id
        self.url = url
        self.name = url.lastPathComponent
        self.trackCount = 0
        self.dateAdded = Date()
        self.dateUpdated = Date()
        self.bookmarkData = bookmarkData
    }

    // MARK: - DB Configuration

    static let databaseTableName = "folders"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let path = Column("path")
        static let name = Column(CodingKeys.name)
        static let trackCount = Column("track_count")
        static let dateAdded = Column("date_added")
        static let dateUpdated = Column("date_updated")
        static let bookmarkData = Column("bookmark_data")
    }

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case id, name, trackCount, dateAdded, dateUpdated
        case path // For database storage
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trackCount = try container.decode(Int.self, forKey: .trackCount)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        dateUpdated = try container.decode(Date.self, forKey: .dateUpdated)
        let path = try container.decode(String.self, forKey: .path)
        url = URL(fileURLWithPath: path)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(trackCount, forKey: .trackCount)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(dateUpdated, forKey: .dateUpdated)
        try container.encode(url.path, forKey: .path)
    }

    // MARK: - FetchableRecord

    init(row: Row) throws {
        id = row[Columns.id]
        name = row[Columns.name]
        trackCount = row[Columns.trackCount]
        dateAdded = row[Columns.dateAdded]
        dateUpdated = row[Columns.dateUpdated]
        bookmarkData = row[Columns.bookmarkData]

        let path: String = row[Columns.path]
        url = URL(fileURLWithPath: path)
    }

    // MARK: - PersistableRecord

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.path] = url.path
        container[Columns.name] = name
        container[Columns.trackCount] = trackCount
        container[Columns.dateAdded] = dateAdded
        container[Columns.dateUpdated] = dateUpdated
        container[Columns.bookmarkData] = bookmarkData
    }

    // Auto-incrementing id
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Associations

    static let tracks = hasMany(Track.self)

    var tracks: QueryInterfaceRequest<Track> {
        request(for: Folder.tracks)
    }

    // MARK: - Hashable & Identifiable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id ?? 0)
        hasher.combine(url)
    }

    static func == (lhs: Folder, rhs: Folder) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}
