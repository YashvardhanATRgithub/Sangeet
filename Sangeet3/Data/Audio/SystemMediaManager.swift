//
//  SystemMediaManager.swift
//  Sangeet3
//
//  Created by Sangeet Team on 30/12/24.
//

import Foundation
import MediaPlayer
import AppKit

class SystemMediaManager {
    static let shared = SystemMediaManager()
    
    private let commandCenter = MPRemoteCommandCenter.shared()
    private let infoCenter = MPNowPlayingInfoCenter.default()
    
    // Callbacks for PlaybackManager to implement
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    
    private init() {
        setupRemoteCommands()
    }
    
    private func setupRemoteCommands() {
        // Play Command
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.onPlay?()
            return .success
        }
        
        // Pause Command
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.onPause?()
            return .success
        }
        
        // Toggle Play/Pause Command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            // Use current state to decide, or just let PlaybackManager toggle
            // For simplicity, we can't easily know state here without query, 
            // but usually Play/Pause separate commands are better if predictable.
            // Mac media key F8 usually sends Play or Pause depending on state, 
            // or Toggle if handled. Using separate handlers allows UI to drive it.
            // But F8 specifically triggers togglePlayPause usually.
            // We'll map it to onPlay/onPause if we knew state, but simpler to have an onToggle or just call onPlay/onPause based on internal tracking?
            // Actually, PlaybackManager should handle "Toggle".
            // Let's assume onPlay implies "Resume" and if playing "Pause".
            // Ideally we expose onToggle.
            return .commandFailed 
        }
        // Since we didn't define onToggle, we will rely on Play/Pause for now.
        // Actually, for F8 to work reliably, we need togglePlayPause.
        // Let's modify the class to support it properly or map it.
        // Re-implementing correctly below.
    }
    
    func setup(onPlay: @escaping () -> Void,
               onPause: @escaping () -> Void,
               onNext: @escaping () -> Void,
               onPrevious: @escaping () -> Void,
               onSeek: @escaping (Double) -> Void) {
        
        self.onPlay = onPlay
        self.onPause = onPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        
        // Register Targets
        
        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.playCommand.addTarget { _ in
            onPlay()
            return .success
        }
        
        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }
        
        // Toggle (F8)
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] event in
            // We need to know current state to toggle intelligently,
            // OR the closure handles the toggle.
            // Usually F8 triggers this.
            // We'll delegate to a toggle handler or infer from PlaybackManager if we had a ref.
            // For now, let's assume the caller will treat onPlay as "Toggle" if needed? 
            // No, that's ambiguous. let's add onToggle.
            self?.onTogglePlayback?()
            return .success
        }
        
        // Next (F9)
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.addTarget { _ in
            onNext()
            return .success
        }
        
        // Previous (F7)
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.addTarget { _ in
            onPrevious()
            return .success
        }
        
        // Seek (Scrub bar in Control Center)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.addTarget { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                onSeek(event.positionTime)
                return .success
            }
            return .commandFailed
        }
    }
    
    var onTogglePlayback: (() -> Void)?
    
    // Updates for Now Playing Info
    func updateNowPlaying(track: Track, image: NSImage?) {
        var nowPlayingInfo: [String: Any] = [:]
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = track.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = track.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = track.album
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = track.duration
        
        if let image = image {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in return image }
        }
        
        // Set update time for seek bar progression
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0 // Playing
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0 // Reset or update with specific time
        
        infoCenter.nowPlayingInfo = nowPlayingInfo
        
        // Update state to playing
        updatePlaybackState(isPlaying: true, elapsedTime: 0)
    }
    
    func updatePlaybackState(isPlaying: Bool, elapsedTime: Double) {
        guard var nowPlayingInfo = infoCenter.nowPlayingInfo else { return }
        
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsedTime
        
        infoCenter.nowPlayingInfo = nowPlayingInfo
        
        // Also update playback state on the info center directly if needed
        if #available(macOS 10.12.2, *) {
            infoCenter.playbackState = isPlaying ? .playing : .paused
        }
    }
    
    func clear() {
        infoCenter.nowPlayingInfo = nil
    }
}
