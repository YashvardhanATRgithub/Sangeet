import Foundation

/// Supported audio formats helper
enum AudioFormat {
    static let supportedMusicFormat = [
        "mp3", "m4a", "flac", "wav", "aiff", "aac", "dsf", "dff", "ogg", "opus", "ape", "wv"
    ]
    
    /// Check if a file extension is a supported audio format
    static func isSupported(_ extensionName: String) -> Bool {
        return supportedMusicFormat.contains(extensionName.lowercased())
    }
}
