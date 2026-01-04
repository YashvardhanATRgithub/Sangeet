
import Foundation

// MARK: - Models

struct TidalResponse<T: Codable>: Codable {
    let version: String?
    let data: T
}

struct TidalSearchData: Codable, Sendable {
    let items: [TidalTrack]
    let totalNumberOfItems: Int?
}

struct TidalTrack: Codable, Identifiable, Sendable {
    let id: Int
    let title: String
    let duration: Int
    let artist: TidalArtist?
    let artists: [TidalArtist]?
    let album: TidalAlbum
    
    // Helper to get primary artist name
    var artistName: String {
        if let name = artist?.name { return name }
        if let first = artists?.first { return first.name }
        return "Unknown Artist"
    }
    
    var albumName: String { album.title }
    
    var coverURL: URL? {
        guard let cover = album.cover else { return nil }
        // Format: xxxx-xxxx-xxxx-xxxx
        let path = cover.replacingOccurrences(of: "-", with: "/")
        return URL(string: "https://resources.tidal.com/images/\(path)/640x640.jpg")
    }
}

struct TidalArtist: Codable, Sendable {
    let id: Int
    let name: String
}

struct TidalAlbum: Codable, Sendable {
    let id: Int
    let title: String
    let cover: String?
}

struct TidalPlaybackInfo: Codable, Sendable {
    let url: String?
    let trackId: Int?
    let audioQuality: String?
    let manifestMimeType: String?
    let manifest: String?
}

enum TidalQuality: String, Sendable {
    case HI_RES = "HI_RES"
    case LOSSLESS = "LOSSLESS"
    case HIGH = "HIGH"
    case LOW = "LOW"
}

// MARK: - Service

actor TidalDLService {
    static let shared = TidalDLService()
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        // config.timeZone was invalid, removing it.
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Search
    
    func search(query: String) async throws -> [TidalTrack] {
        var components = URLComponents(string: "https://vogel.qqdl.site/search/")
        components?.queryItems = [URLQueryItem(name: "s", value: query)]
        
        guard let url = components?.url else { return [] }
        
        print("[TidalService] Searching: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("[TidalService] Search Status: \(httpResponse.statusCode)")
        }
        
        do {
            // Decode the wrapper first
            let wrapper = try JSONDecoder().decode(TidalResponse<TidalSearchData>.self, from: data)
            print("[TidalService] Found \(wrapper.data.items.count) tracks")
            return wrapper.data.items
        } catch {
            print("[TidalService] Search Parse Error: \(error)")
            // Provide a fallback debug print of raw JSON if parsing fails
            if let str = String(data: data, encoding: .utf8) {
                print("[TidalService] Raw Response: \(str.prefix(500))...")
            }
            return []
        }
    }
    
    // MARK: - Stream
    
    func getStreamURL(trackID: Int, quality: TidalQuality = .LOSSLESS) async throws -> URL? {
        // Based on main.py: /track/?id=...&quality=... returns Tidal playbackinfo inside 'data'
        let urlString = "https://vogel.qqdl.site/track/?id=\(trackID)&quality=\(quality.rawValue)"
        guard let url = URL(string: urlString) else { return nil }
        
        print("[TidalService] Fetching Stream: \(url.absoluteString)")
        
        let (data, response) = try await session.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("[TidalService] Stream Status: \(httpResponse.statusCode)")
        }
        
        // DEBUG: Print raw response to understand why decoding might fail or what we actually get
        if let str = String(data: data, encoding: .utf8) {
            print("[TidalService] Stream Response: \(str)")
        }
        
        do {
            // Try explicit wrapper decoding
            let wrapper = try JSONDecoder().decode(TidalResponse<TidalPlaybackInfo>.self, from: data)
            
            // 1. Check for direct URL
            if let streamUrl = wrapper.data.url {
                return URL(string: streamUrl)
            }
            
            // 2. Parsed Manifest Logic
            if let manifestBase64 = wrapper.data.manifest {
                // Decode Base64
                if let decodedData = Data(base64Encoded: manifestBase64),
                   let json = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any],
                   let urls = json["urls"] as? [String],
                   let firstUrl = urls.first {
                    
                    print("[TidalService] Extracted URL from Manifest: \(firstUrl)")
                    return URL(string: firstUrl)
                } 
                print("[TidalService] Failed to parse manifest JSON or find URLs.")
                return nil
            }
            
            return nil
            
        } catch {
            print("[TidalService] Stream Parse Error: \(error)")
            // Fallback: Try raw generic generic analysis in case it's not wrapped (unlikely based on search)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("[TidalService] Raw JSON keys: \(json.keys)")
                if let dataObj = json["data"] as? [String: Any] {
                    if let u = dataObj["url"] as? String { return URL(string: u) }
                }
            }
            return nil
        }
    }
}
