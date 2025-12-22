import CoreData

class CoreDataStack {
    static let shared = CoreDataStack()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        let model = CoreDataStack.makeModel()
        container = NSPersistentContainer(name: "Sangeet", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        if let description = container.persistentStoreDescriptions.first {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    // MARK: - Programmatic Model
    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        
        // CDTrack Entity
        let trackEntity = NSEntityDescription()
        trackEntity.name = "CDTrack"
        trackEntity.managedObjectClassName = "CDTrack" // We will map to NSManagedObject subset later if needed, or use generic
        
        // Attributes for Track
        let idAttr = NSAttributeDescription()
        idAttr.name = "id"
        idAttr.attributeType = .UUIDAttributeType
        idAttr.isOptional = false
        
        let urlAttr = NSAttributeDescription()
        urlAttr.name = "url"
        urlAttr.attributeType = .URIAttributeType
        urlAttr.isOptional = false
        
        let titleAttr = NSAttributeDescription()
        titleAttr.name = "title"
        titleAttr.attributeType = .stringAttributeType
        titleAttr.defaultValue = "Unknown Title"
        
        let artistAttr = NSAttributeDescription()
        artistAttr.name = "artist"
        artistAttr.attributeType = .stringAttributeType
        artistAttr.defaultValue = "Unknown Artist"
        
        let albumAttr = NSAttributeDescription()
        albumAttr.name = "album"
        albumAttr.attributeType = .stringAttributeType
        albumAttr.defaultValue = "Unknown Album"
        
        let albumArtistAttr = NSAttributeDescription()
        albumArtistAttr.name = "albumArtist"
        albumArtistAttr.attributeType = .stringAttributeType
        albumArtistAttr.defaultValue = ""
        
        let genreAttr = NSAttributeDescription()
        genreAttr.name = "genre"
        genreAttr.attributeType = .stringAttributeType
        genreAttr.defaultValue = ""
        
        let durationAttr = NSAttributeDescription()
        durationAttr.name = "duration"
        durationAttr.attributeType = .doubleAttributeType
        durationAttr.defaultValue = 0
        
        let trackNumberAttr = NSAttributeDescription()
        trackNumberAttr.name = "trackNumber"
        trackNumberAttr.attributeType = .integer64AttributeType
        trackNumberAttr.isOptional = true
        
        let discNumberAttr = NSAttributeDescription()
        discNumberAttr.name = "discNumber"
        discNumberAttr.attributeType = .integer64AttributeType
        discNumberAttr.isOptional = true
        
        let yearAttr = NSAttributeDescription()
        yearAttr.name = "year"
        yearAttr.attributeType = .integer64AttributeType
        yearAttr.isOptional = true
        
        let dateAddedAttr = NSAttributeDescription()
        dateAddedAttr.name = "dateAdded"
        dateAddedAttr.attributeType = .dateAttributeType
        dateAddedAttr.defaultValue = Date(timeIntervalSince1970: 0)
        
        let playCountAttr = NSAttributeDescription()
        playCountAttr.name = "playCount"
        playCountAttr.attributeType = .integer64AttributeType
        playCountAttr.defaultValue = 0
        
        let searchKeywordsAttr = NSAttributeDescription()
        searchKeywordsAttr.name = "searchKeywords"
        searchKeywordsAttr.attributeType = .stringAttributeType
        
        let isFavoriteAttr = NSAttributeDescription()
        isFavoriteAttr.name = "isFavorite"
        isFavoriteAttr.attributeType = .booleanAttributeType
        isFavoriteAttr.defaultValue = false
        
        // Add all attributes
        trackEntity.properties = [
            idAttr,
            urlAttr,
            titleAttr,
            artistAttr,
            albumAttr,
            albumArtistAttr,
            genreAttr,
            durationAttr,
            trackNumberAttr,
            discNumberAttr,
            yearAttr,
            dateAddedAttr,
            playCountAttr,
            searchKeywordsAttr,
            isFavoriteAttr
        ]
        
        model.entities = [trackEntity]
        return model
    }
}
