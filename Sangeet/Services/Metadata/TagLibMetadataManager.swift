import Foundation
import AVFoundation

/// Swift wrapper for metadata extraction (AVFoundation implementation)
/// Replaces TagLib implementation to avoid C++ dependency issues
struct TagLibMetadataManager {
    
    /// Extract metadata from an audio file using AVFoundation
    static func extractMetadata(from url: URL) -> TrackMetadata {
        var metadata = TrackMetadata(url: url)
        let asset = AVAsset(url: url)
        
        // 1. Try Common Metadata first (high level abstraction)
        for item in asset.commonMetadata {
            extractItem(item, into: &metadata)
        }
        
        // 2. Fallback: Check all available formats if critical info is missing
        if metadata.title == nil || metadata.artist == nil || metadata.album == nil {
            for format in asset.availableMetadataFormats {
                let items = asset.metadata(forFormat: format)
                for item in items {
                    extractItem(item, into: &metadata)
                }
            }
        }
        
        // 3. Duration (Blocking usually, but necessary here)
        metadata.duration = CMTimeGetSeconds(asset.duration)
        
        // 4. File extension fallback for Title
        if metadata.title == nil || metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            metadata.title = url.deletingPathExtension().lastPathComponent
        }
        
        return metadata
    }
    
    private static func extractItem(_ item: AVMetadataItem, into metadata: inout TrackMetadata) {
        guard let value = item.value else { return }
        
        // Check Common Keys first
        if let commonKey = item.commonKey {
            switch commonKey {
            case .commonKeyTitle:
                if metadata.title == nil { metadata.title = value as? String }
            case .commonKeyArtist:
                if metadata.artist == nil { metadata.artist = value as? String }
            case .commonKeyAlbumName:
                if metadata.album == nil { metadata.album = value as? String }
            case .commonKeyArtwork:
                if metadata.artworkData == nil, let data = value as? Data {
                    metadata.artworkData = data
                }
            default: break
            }
            return
        }
        
        // Check standard identifier string keys (ID3/iTunes) if commonKey didn't match
        if let keyString = item.identifier?.rawValue {
            switch keyString {
            // ID3 v2.3/v2.4
            case "id3/TIT2": if metadata.title == nil { metadata.title = value as? String }
            case "id3/TPE1": if metadata.artist == nil { metadata.artist = value as? String }
            case "id3/TALB": if metadata.album == nil { metadata.album = value as? String }
            case "id3/APIC":
                if metadata.artworkData == nil, let data = value as? Data {
                   metadata.artworkData = data
                }
            
            // iTunes / m4a atoms
            case "©nam": if metadata.title == nil { metadata.title = value as? String }
            case "©ART": if metadata.artist == nil { metadata.artist = value as? String }
            case "©alb": if metadata.album == nil { metadata.album = value as? String }
            case "covr":
                if metadata.artworkData == nil, let data = value as? Data {
                    metadata.artworkData = data
                }
                
            default: break
            }
        }
    }
    
    /// Extract metadata asynchronously
    static func extractMetadata(from url: URL, completion: @escaping (TrackMetadata) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let metadata = extractMetadata(from: url)
            DispatchQueue.main.async {
                completion(metadata)
            }
        }
    }
    
    /// Apply metadata to a Track object
    static func applyMetadata(to track: inout Track, from metadata: TrackMetadata, at fileURL: URL) {
        track.title = metadata.title ?? fileURL.deletingPathExtension().lastPathComponent
        track.artist = metadata.artist ?? "Unknown Artist"
        track.album = metadata.album ?? "Unknown Album"
        track.duration = metadata.duration
        track.artworkData = metadata.artworkData
        track.isMetadataLoaded = true
    }
    
    private static func fourCCToString(_ fourCC: FourCharCode) -> String {
        // Check common audio formats first
        switch fourCC {
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatAC3: return "AC-3"
        case kAudioFormatMPEG4AAC_HE: return "HE-AAC"
        case kAudioFormatMPEG4AAC_HE_V2: return "HE-AACv2"
        default:
            // Convert FourCC bytes to string
            let bytes: [UInt8] = [
                UInt8((fourCC >> 24) & 0xFF),
                UInt8((fourCC >> 16) & 0xFF),
                UInt8((fourCC >> 8) & 0xFF),
                UInt8(fourCC & 0xFF)
            ]
            return String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespaces) ?? "Unknown"
        }
    }
}
