//
//  SongFeatures.swift
//  HiFidelity
//
//  Model for storing extracted audio features and embeddings for ML-based recommendations
//

import Foundation
import GRDB

// MARK: - Mood Enum

/// Musical mood classification
enum Mood: String, Codable, CaseIterable {
    case happy = "happy"
    case sad = "sad"
    case energetic = "energetic"
    case calm = "calm"
    case angry = "angry"
    case romantic = "romantic"
    case melancholic = "melancholic"
    case uplifting = "uplifting"
    case dark = "dark"
    case mysterious = "mysterious"
    case playful = "playful"
    case nostalgic = "nostalgic"
    case epic = "epic"
    case dreamy = "dreamy"
    case aggressive = "aggressive"
    case peaceful = "peaceful"
    case tense = "tense"
    case triumphant = "triumphant"
    
    var displayName: String {
        rawValue.capitalized
    }
    
    /// Derive mood from audio features
    static func fromFeatures(energy: Double?, valence: Double?, danceability: Double?, acousticness: Double?) -> Mood {
        let e = energy ?? 0.5
        let v = valence ?? 0.5
        let d = danceability ?? 0.5
        let a = acousticness ?? 0.5
        
        // High energy, high valence
        if e > 0.7 && v > 0.7 {
            return d > 0.6 ? .energetic : .uplifting
        }
        
        // High energy, low valence
        if e > 0.7 && v < 0.3 {
            return .aggressive
        }
        
        // Low energy, high valence
        if e < 0.3 && v > 0.7 {
            return a > 0.6 ? .peaceful : .calm
        }
        
        // Low energy, low valence
        if e < 0.3 && v < 0.3 {
            return .sad
        }
        
        // Medium energy, high valence
        if e > 0.4 && e < 0.7 && v > 0.6 {
            return d > 0.6 ? .playful : .happy
        }
        
        // Medium energy, low valence
        if e > 0.4 && e < 0.7 && v < 0.4 {
            return .melancholic
        }
        
        // High acousticness, medium valence
        if a > 0.7 && v > 0.4 && v < 0.6 {
            return .dreamy
        }
        
        // Default
        return .calm
    }
}

/// Audio features and embeddings for a track
struct SongFeatures: Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var trackId: Int64
    
    // MARK: - Audio Features (Extracted from audio analysis)
    
    /// Tempo in BPM (beats per minute)
    var tempo: Double?
    
    /// Energy level (0.0 to 1.0) - intensity and activity
    var energy: Double?
    
    /// Valence (0.0 to 1.0) - musical positiveness/happiness
    var valence: Double?
    
    /// Danceability (0.0 to 1.0) - how suitable for dancing
    var danceability: Double?
    
    /// Acousticness (0.0 to 1.0) - acoustic vs electronic
    var acousticness: Double?
    
    /// Instrumentalness (0.0 to 1.0) - likelihood of no vocals
    var instrumentalness: Double?
    
    /// Liveness (0.0 to 1.0) - presence of audience
    var liveness: Double?
    
    /// Speechiness (0.0 to 1.0) - presence of spoken words
    var speechiness: Double?
    
    /// Loudness in dB (typically -60 to 0)
    var loudness: Double?
    
    /// Key (0-11, representing C, C#, D, etc.)
    var key: Int?
    
    /// Mode (0 = minor, 1 = major)
    var mode: Int?
    
    /// Time signature (3, 4, 5, etc.)
    var timeSignature: Int?
    
    /// Musical mood classification
    var mood: Mood?
    
    // MARK: - Spectral Features
    
    /// Spectral centroid (brightness of sound)
    var spectralCentroid: Double?
    
    /// Spectral rolloff (frequency below which 85% of energy is contained)
    var spectralRolloff: Double?
    
    /// Zero crossing rate (noisiness/percussiveness)
    var zeroCrossingRate: Double?
    
    // MARK: - Embedding Vector
    
    /// High-dimensional feature embedding (stored as JSON array)
    /// This can be from a pre-trained audio model like:
    /// - OpenL3, VGGish, MFCC-based embeddings
    /// - Custom trained model
    var embedding: [Double]?
    
    /// Embedding model version/type used
    var embeddingModel: String?
    
    /// Dimensionality of the embedding
    var embeddingDimension: Int?
    
    // MARK: - Metadata
    
    /// When features were extracted
    var extractedAt: Date
    
    /// Version of feature extraction algorithm
    var extractorVersion: String?
    
    /// Confidence score of feature extraction (0.0 to 1.0)
    var confidence: Double?
    
    /// Whether features need re-extraction
    var needsUpdate: Bool
    
    // MARK: - Database Configuration
    
    static let databaseTableName = "song_features"
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let trackId = Column(CodingKeys.trackId)
        static let tempo = Column(CodingKeys.tempo)
        static let energy = Column(CodingKeys.energy)
        static let valence = Column(CodingKeys.valence)
        static let danceability = Column(CodingKeys.danceability)
        static let acousticness = Column(CodingKeys.acousticness)
        static let instrumentalness = Column(CodingKeys.instrumentalness)
        static let liveness = Column(CodingKeys.liveness)
        static let speechiness = Column(CodingKeys.speechiness)
        static let loudness = Column(CodingKeys.loudness)
        static let key = Column(CodingKeys.key)
        static let mode = Column(CodingKeys.mode)
        static let timeSignature = Column(CodingKeys.timeSignature)
        static let mood = Column(CodingKeys.mood)
        static let spectralCentroid = Column(CodingKeys.spectralCentroid)
        static let spectralRolloff = Column(CodingKeys.spectralRolloff)
        static let zeroCrossingRate = Column(CodingKeys.zeroCrossingRate)
        static let embedding = Column(CodingKeys.embedding)
        static let embeddingModel = Column(CodingKeys.embeddingModel)
        static let embeddingDimension = Column(CodingKeys.embeddingDimension)
        static let extractedAt = Column(CodingKeys.extractedAt)
        static let extractorVersion = Column(CodingKeys.extractorVersion)
        static let confidence = Column(CodingKeys.confidence)
        static let needsUpdate = Column(CodingKeys.needsUpdate)
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case trackId = "track_id"
        case tempo
        case energy
        case valence
        case danceability
        case acousticness
        case instrumentalness
        case liveness
        case speechiness
        case loudness
        case key
        case mode
        case timeSignature = "time_signature"
        case mood
        case spectralCentroid = "spectral_centroid"
        case spectralRolloff = "spectral_rolloff"
        case zeroCrossingRate = "zero_crossing_rate"
        case embedding
        case embeddingModel = "embedding_model"
        case embeddingDimension = "embedding_dimension"
        case extractedAt = "extracted_at"
        case extractorVersion = "extractor_version"
        case confidence
        case needsUpdate = "needs_update"
    }
    
    // MARK: - Initialization
    
    init(
        id: Int64? = nil,
        trackId: Int64,
        tempo: Double? = nil,
        energy: Double? = nil,
        valence: Double? = nil,
        danceability: Double? = nil,
        acousticness: Double? = nil,
        instrumentalness: Double? = nil,
        liveness: Double? = nil,
        speechiness: Double? = nil,
        loudness: Double? = nil,
        key: Int? = nil,
        mode: Int? = nil,
        timeSignature: Int? = nil,
        mood: Mood? = nil,
        spectralCentroid: Double? = nil,
        spectralRolloff: Double? = nil,
        zeroCrossingRate: Double? = nil,
        embedding: [Double]? = nil,
        embeddingModel: String? = nil,
        embeddingDimension: Int? = nil,
        extractedAt: Date = Date(),
        extractorVersion: String? = nil,
        confidence: Double? = nil,
        needsUpdate: Bool = false
    ) {
        self.id = id
        self.trackId = trackId
        self.tempo = tempo
        self.energy = energy
        self.valence = valence
        self.danceability = danceability
        self.acousticness = acousticness
        self.instrumentalness = instrumentalness
        self.liveness = liveness
        self.speechiness = speechiness
        self.loudness = loudness
        self.key = key
        self.mode = mode
        self.timeSignature = timeSignature
        self.mood = mood
        self.spectralCentroid = spectralCentroid
        self.spectralRolloff = spectralRolloff
        self.zeroCrossingRate = zeroCrossingRate
        self.embedding = embedding
        self.embeddingModel = embeddingModel
        self.embeddingDimension = embeddingDimension
        self.extractedAt = extractedAt
        self.extractorVersion = extractorVersion
        self.confidence = confidence
        self.needsUpdate = needsUpdate
    }
    
    // MARK: - PersistableRecord
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
    
    // MARK: - Associations
    
    static let track = belongsTo(Track.self)
    
    var track: QueryInterfaceRequest<Track> {
        request(for: SongFeatures.track)
    }
}

// MARK: - Helper Extensions

extension SongFeatures {
    /// Cosine similarity between two embeddings
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        
        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))
        
        guard magnitudeA > 0, magnitudeB > 0 else { return nil }
        
        return dotProduct / (magnitudeA * magnitudeB)
    }
    
    /// Euclidean distance between two embeddings
    static func euclideanDistance(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        
        let sumOfSquares = zip(a, b).map { pow($0 - $1, 2) }.reduce(0, +)
        return sqrt(sumOfSquares)
    }
    
    /// Calculate feature similarity score (0.0 to 1.0)
    func featureSimilarity(to other: SongFeatures) -> Double {
        var similarities: [Double] = []
        
        // Compare each feature if both exist
        if let t1 = self.tempo, let t2 = other.tempo {
            // Normalize tempo difference (max difference ~100 BPM)
            similarities.append(1.0 - min(abs(t1 - t2) / 100.0, 1.0))
        }
        
        if let e1 = self.energy, let e2 = other.energy {
            similarities.append(1.0 - abs(e1 - e2))
        }
        
        if let v1 = self.valence, let v2 = other.valence {
            similarities.append(1.0 - abs(v1 - v2))
        }
        
        if let d1 = self.danceability, let d2 = other.danceability {
            similarities.append(1.0 - abs(d1 - d2))
        }
        
        if let a1 = self.acousticness, let a2 = other.acousticness {
            similarities.append(1.0 - abs(a1 - a2))
        }
        
        // Return average similarity of available features
        guard !similarities.isEmpty else { return 0.0 }
        return similarities.reduce(0, +) / Double(similarities.count)
    }
    
    /// Automatically derive and set mood from audio features
    mutating func deriveMood() {
        mood = Mood.fromFeatures(
            energy: energy,
            valence: valence,
            danceability: danceability,
            acousticness: acousticness
        )
    }
    
    /// Get mood, deriving it if not set
    func getMood() -> Mood {
        if let existingMood = mood {
            return existingMood
        }
        return Mood.fromFeatures(
            energy: energy,
            valence: valence,
            danceability: danceability,
            acousticness: acousticness
        )
    }
}

// MARK: - Codable for Embedding Array

extension SongFeatures {
    enum EmbeddingCodingKeys: String, CodingKey {
        case embedding
    }
    
    // Custom encoding for embedding array as JSON
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(trackId, forKey: .trackId)
        try container.encodeIfPresent(tempo, forKey: .tempo)
        try container.encodeIfPresent(energy, forKey: .energy)
        try container.encodeIfPresent(valence, forKey: .valence)
        try container.encodeIfPresent(danceability, forKey: .danceability)
        try container.encodeIfPresent(acousticness, forKey: .acousticness)
        try container.encodeIfPresent(instrumentalness, forKey: .instrumentalness)
        try container.encodeIfPresent(liveness, forKey: .liveness)
        try container.encodeIfPresent(speechiness, forKey: .speechiness)
        try container.encodeIfPresent(loudness, forKey: .loudness)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(timeSignature, forKey: .timeSignature)
        try container.encodeIfPresent(mood, forKey: .mood)
        try container.encodeIfPresent(spectralCentroid, forKey: .spectralCentroid)
        try container.encodeIfPresent(spectralRolloff, forKey: .spectralRolloff)
        try container.encodeIfPresent(zeroCrossingRate, forKey: .zeroCrossingRate)
        
        // Encode embedding as JSON string
        if let embedding = embedding {
            let jsonData = try JSONEncoder().encode(embedding)
            let jsonString = String(data: jsonData, encoding: .utf8)
            try container.encodeIfPresent(jsonString, forKey: .embedding)
        }
        
        try container.encodeIfPresent(embeddingModel, forKey: .embeddingModel)
        try container.encodeIfPresent(embeddingDimension, forKey: .embeddingDimension)
        try container.encode(extractedAt, forKey: .extractedAt)
        try container.encodeIfPresent(extractorVersion, forKey: .extractorVersion)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(needsUpdate, forKey: .needsUpdate)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        trackId = try container.decode(Int64.self, forKey: .trackId)
        tempo = try container.decodeIfPresent(Double.self, forKey: .tempo)
        energy = try container.decodeIfPresent(Double.self, forKey: .energy)
        valence = try container.decodeIfPresent(Double.self, forKey: .valence)
        danceability = try container.decodeIfPresent(Double.self, forKey: .danceability)
        acousticness = try container.decodeIfPresent(Double.self, forKey: .acousticness)
        instrumentalness = try container.decodeIfPresent(Double.self, forKey: .instrumentalness)
        liveness = try container.decodeIfPresent(Double.self, forKey: .liveness)
        speechiness = try container.decodeIfPresent(Double.self, forKey: .speechiness)
        loudness = try container.decodeIfPresent(Double.self, forKey: .loudness)
        key = try container.decodeIfPresent(Int.self, forKey: .key)
        mode = try container.decodeIfPresent(Int.self, forKey: .mode)
        timeSignature = try container.decodeIfPresent(Int.self, forKey: .timeSignature)
        mood = try container.decodeIfPresent(Mood.self, forKey: .mood)
        spectralCentroid = try container.decodeIfPresent(Double.self, forKey: .spectralCentroid)
        spectralRolloff = try container.decodeIfPresent(Double.self, forKey: .spectralRolloff)
        zeroCrossingRate = try container.decodeIfPresent(Double.self, forKey: .zeroCrossingRate)
        
        // Decode embedding from JSON string
        if let jsonString = try container.decodeIfPresent(String.self, forKey: .embedding),
           let jsonData = jsonString.data(using: .utf8) {
            embedding = try? JSONDecoder().decode([Double].self, from: jsonData)
        } else {
            embedding = nil
        }
        
        embeddingModel = try container.decodeIfPresent(String.self, forKey: .embeddingModel)
        embeddingDimension = try container.decodeIfPresent(Int.self, forKey: .embeddingDimension)
        extractedAt = try container.decode(Date.self, forKey: .extractedAt)
        extractorVersion = try container.decodeIfPresent(String.self, forKey: .extractorVersion)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        needsUpdate = try container.decode(Bool.self, forKey: .needsUpdate)
    }
}

