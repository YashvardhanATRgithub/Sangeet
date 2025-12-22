import Foundation
import AVFoundation

protocol AudioDecoder {
    func canDecode(_ url: URL) -> Bool
    func decode(_ url: URL) async throws -> AVAudioPCMBuffer
}

class NativeAudioDecoder: AudioDecoder {
    func canDecode(_ url: URL) -> Bool {
        // Core formats supported by AVFoundation
        let ext = url.pathExtension.lowercased()
        // Added more common container formats
        return ["mp3", "m4a", "aac", "wav", "aiff", "caf", "m4b", "mp4", "flac"].contains(ext)
    }
    
    func decode(_ url: URL) async throws -> AVAudioPCMBuffer {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "Decoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }
        try file.read(into: buffer)
        return buffer
    }
}

// Placeholder for FFmpeg implementation
class FFmpegAudioDecoder: AudioDecoder {
    func canDecode(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["flac", "ogg", "opus", "wma", "ape"].contains(ext)
    }
    
    func decode(_ url: URL) async throws -> AVAudioPCMBuffer {
        // Fallback: try AVAudioFile decoding so common formats (including FLAC on modern macOS) still work without FFmpeg.
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "FFmpegDecoder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate audio buffer"
            ])
        }
        try file.read(into: buffer)
        return buffer
    }
}
