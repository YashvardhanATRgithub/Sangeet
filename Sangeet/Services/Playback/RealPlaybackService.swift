import Foundation
@preconcurrency import AVFoundation
import Combine
import MediaPlayer
import AppKit

@MainActor
class RealPlaybackService: NSObject, PlaybackService, ObservableObject {
    @Published var currentTrack: Track?
    @Published var state: PlaybackState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var loopMode: LoopMode = .off
    @Published var isShuffling: Bool = false
    @Published var volume: Float = 1.0 {
        didSet {
            let clamped = min(max(volume, 0), 1)
            if clamped != volume {
                volume = clamped
                return
            }
            engine.mainMixerNode.outputVolume = clamped
            saveState()
        }
    }
    
    // Previous volume for mute toggle
    private var previousVolume: Float = 0.5
    
    // Audio Engine & Dual Nodes for Crossfade
    private let engine = AVAudioEngine()
    private let playerNodeA = AVAudioPlayerNode()
    private let playerNodeB = AVAudioPlayerNode()
    
    // Which node is currently the "Main" active one
    private var useNodeA = true
    private var activeNode: AVAudioPlayerNode { useNodeA ? playerNodeA : playerNodeB }
    private var inactiveNode: AVAudioPlayerNode { useNodeA ? playerNodeB : playerNodeA }
    
    // Decoders
    private let nativeDecoder = NativeAudioDecoder()
    private let ffmpegDecoder = FFmpegAudioDecoder()
    
    // State
    private var audioFile: AVAudioFile?
    private var isSeeking = false
    private var isTransitioning = false // True during crossfade
    private var fadeTimers: [Timer] = [] // Track timers to cancel them
    
    // Settings
    private let crossfadeDuration: TimeInterval = 4.0 // Overlap duration
    private let fadeDuration: TimeInterval = 0.5 // Play/Pause fade
    
    // Queue
    @Published var queue: [Track] = []
    private var history: [Track] = []
    
    private var timer: Timer?
    private var timeOffset: TimeInterval = 0
    
    override init() {
        super.init()
        setupEngine()
        setupRemoteCommands()
        restoreState()
    }
    
    private func setupEngine() {
        // Attach both nodes
        if !engine.attachedNodes.contains(playerNodeA) { engine.attach(playerNodeA) }
        if !engine.attachedNodes.contains(playerNodeB) { engine.attach(playerNodeB) }
        
        // Connect both to mixer
        engine.connect(playerNodeA, to: engine.mainMixerNode, format: nil)
        engine.connect(playerNodeB, to: engine.mainMixerNode, format: nil)
        
        startEngineIfNeeded()
        engine.mainMixerNode.outputVolume = volume
        
        // Check alignment
        playerNodeA.volume = 1.0
        playerNodeB.volume = 1.0
    }
    
    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            engine.mainMixerNode.outputVolume = volume
        } catch {
            print("Failed to start engine: \(error)")
        }
    }
    
    // MARK: - Playback Control
    
    func play(_ track: Track) {
        transition(to: track)
    }
    
    func pause() {
        guard state == .playing else { return }
        // Smooth fade out then pause
        performFade(node: activeNode, from: 1.0, to: 0.0, duration: fadeDuration) { [weak self] in
            guard let self = self else { return }
            self.playerNodeA.pause()
            self.playerNodeB.pause()
            self.state = .paused
            self.stopTimer()
            self.saveState()
            self.updateNowPlayingInfo()
        }
    }
    
    func resume() {
        if state == .paused {
            if audioFile == nil, let track = currentTrack {
                // Cold resume
                transition(to: track, startTime: currentTime)
            } else {
                startEngineIfNeeded()
                let target = activeNode
                
                // Ensure correct volume state
                cancelFades()
                inactiveNode.pause() // Ensure other is stopped
                
                target.volume = 0
                target.play()
                state = .playing
                startTimer()
                target.play()
                state = .playing
                startTimer()
                updateNowPlayingInfo()
                performFade(node: target, from: 0.0, to: 1.0, duration: fadeDuration, completion: nil)
            }
        } else if let track = currentTrack {
            play(track)
        }
    }
    
    func togglePlayPause() {
        if state == .playing {
            pause()
        } else {
            resume()
        }
    }
    
    func stop() {
        playerNodeA.stop()
        playerNodeB.stop()
        engine.stop()
        state = .stopped
        currentTime = 0
        duration = 0
        audioFile = nil
        engine.reset()
        stopTimer()
        stopTimer()
        saveState()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    func toggleMute() {
        if volume > 0 {
            previousVolume = volume
            volume = 0
        } else {
            volume = previousVolume > 0 ? previousVolume : 0.5
        }
    }
    
    func toggleFavorite() {
        guard var track = currentTrack else { return }
        track.isFavorite.toggle()
        self.currentTrack = track
        
        Task {
             await AppServices.shared.database.toggleFavorite(for: track.id)
             await MainActor.run {
                 NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
             }
        }
    }
    
    // MARK: - Transitions & Loading
    
    private func transition(to track: Track, startTime: TimeInterval = 0) {
        let isAlreadyPlaying = (state == .playing)
        let targetNode = isAlreadyPlaying ? inactiveNode : activeNode
        let oldNode = isAlreadyPlaying ? activeNode : nil
        
        // Immediate swap so UI/timers see new state
        if isAlreadyPlaying {
            useNodeA.toggle()
            isTransitioning = true
        } else {
            isTransitioning = false
        }
        
        if let current = currentTrack, current.id != track.id {
            history.append(current)
        }
        
        currentTrack = track
        timeOffset = startTime
        state = .buffering
        saveState()
        
        let trackID = track.id
        startEngineIfNeeded()
        
        Task {
            guard self.currentTrack?.id == trackID else { return }
            
            do {
                if let (duration, file, buffer) = try await loadAudio(for: track) {
                    await MainActor.run {
                        guard self.currentTrack?.id == trackID else { return }
                        self.duration = duration
                        
                        targetNode.stop()
                        if let file = file {
                            self.audioFile = file
                            self.scheduleFile(file, on: targetNode, at: startTime > 0 ? startTime : 0)
                        } else if let buffer = buffer {
                            self.audioFile = nil
                            self.scheduleBuffer(buffer, on: targetNode)
                        }
                        
                        // Execute Crossfade
                        if isAlreadyPlaying, let old = oldNode {
                            // Target Fade In
                            targetNode.volume = 0
                            targetNode.play()
                            self.performFade(node: targetNode, from: 0, to: 1, duration: self.crossfadeDuration, completion: nil)
                            
                            // Old Fade Out
                            self.performFade(node: old, from: 1, to: 0, duration: self.crossfadeDuration) { [weak self] in
                                old.stop()
                                old.volume = 1
                                self?.isTransitioning = false
                            }
                        } else {
                             // Simple Start
                             targetNode.volume = 0
                             targetNode.play()
                             self.performFade(node: targetNode, from: 0, to: 1, duration: self.fadeDuration, completion: nil)
                        }
                        
                        self.state = .playing
                        self.startTimer()
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("Error: \(error)")
                self.state = .stopped
            }
        }
    }
    
    private func loadAudio(for track: Track) async throws -> (Double, AVAudioFile?, AVAudioPCMBuffer?)? {
         let fileURL = track.url
         let accessing = fileURL.startAccessingSecurityScopedResource()
         defer { if accessing { fileURL.stopAccessingSecurityScopedResource() }}
         
         if let file = try? AVAudioFile(forReading: fileURL) {
             let dur = file.length > 0 ? Double(file.length) / file.processingFormat.sampleRate : track.duration
             return (dur, file, nil)
         } else if ffmpegDecoder.canDecode(fileURL), let buffer = try? await ffmpegDecoder.decode(fileURL) {
             let dur = Double(buffer.frameLength) / buffer.format.sampleRate
             return (dur, nil, buffer)
         } else if let buffer = try? await nativeDecoder.decode(fileURL) {
             let dur = Double(buffer.frameLength) / buffer.format.sampleRate
             return (dur, nil, buffer)
         }
         return nil
    }

    private func scheduleFile(_ file: AVAudioFile, on node: AVAudioPlayerNode, at startTime: TimeInterval) {
        if startTime > 0 {
             let sampleRate = file.processingFormat.sampleRate
             let startFrame = AVAudioFramePosition(startTime * sampleRate)
             let frameCount = AVAudioFrameCount(file.length - startFrame)
             guard frameCount > 0 else { return }
             
             node.scheduleSegment(file, startingFrame: startFrame, frameCount: frameCount, at: nil) { [weak self] in
                 Task { @MainActor [weak self] in self?.handleTrackFinished(node: node) }
             }
             self.currentTime = startTime
             self.timeOffset = startTime
        } else {
            node.scheduleFile(file, at: nil) { [weak self] in
                Task { @MainActor [weak self] in self?.handleTrackFinished(node: node) }
            }
            self.timeOffset = 0
        }
    }
    
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, on node: AVAudioPlayerNode) {
        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in self?.handleTrackFinished(node: node) }
        }
    }
    
    // MARK: - Fading Logic
    private func performFade(node: AVAudioPlayerNode, from start: Float, to end: Float, duration: TimeInterval, completion: (() -> Void)?) {
        let steps = 20
        let interval = duration / Double(steps)
        let stepAmount = (end - start) / Float(steps)
        var currentStep = 0
        
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else { timer.invalidate(); return }
                currentStep += 1
                let newVol = start + (stepAmount * Float(currentStep))
                node.volume = min(max(newVol, 0), 1)
                
                if currentStep >= steps {
                    timer.invalidate()
                    if let index = self.fadeTimers.firstIndex(of: timer) {
                        self.fadeTimers.remove(at: index)
                    }
                    node.volume = end
                    completion?()
                }
            }
        }
        fadeTimers.append(timer)
    }
    
    private func cancelFades() {
        fadeTimers.forEach { $0.invalidate() }
        fadeTimers.removeAll()
    }

    // MARK: - Seek / Next / Prev
    
    func seek(to time: TimeInterval) {
        cancelFades()
        isTransitioning = false
        isSeeking = true
        
        let target = activeNode
        let other = inactiveNode
        
        // Stop both to ensure clean state
        target.stop()
        other.stop()
        
        // Reset volumes
        target.volume = 1.0
        other.volume = 1.0 // or 0, but 1 is safe for next use
        
        guard let file = audioFile else {
             isSeeking = false
             return
        }
        
        startEngineIfNeeded()
        scheduleFile(file, on: target, at: time)
        
        target.play()
        state = .playing
        startTimer()
        
        // Brief delay to prevent completion handler race conditions
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.isSeeking = false
            self?.updateNowPlayingInfo()
        }
    }
    
    func next() {
        if !queue.isEmpty {
            if isShuffling {
                let index = Int.random(in: 0..<queue.count)
                transition(to: queue.remove(at: index))
            } else {
                 transition(to: queue.removeFirst())
            }
        } else {
             if loopMode == .one, let current = currentTrack {
                 seek(to: 0)
             } else if loopMode == .all, let current = currentTrack {
                 startPlayback(current, recordHistory: false) // Fallback used
             } else {
                 stop()
             }
        }
    }
    
    func previous() {
        if currentTime > 3 {
            seek(to: 0)
        } else if let last = history.popLast() {
            transition(to: last)
        }
    }
    
    // Helper helper for loopMode
    private func startPlayback(_ track: Track, recordHistory: Bool) {
         // Re-use transition logic for consistency
         transition(to: track)
    }
    
    // MARK: - Queue
    func addToQueue(_ track: Track) { queue.append(track) }
    func removeFromQueue(at index: Int) { if index < queue.count { queue.remove(at: index) } }
    func startPlaylist(_ tracks: [Track]) {
        guard let first = tracks.first else { return }
        queue = Array(tracks.dropFirst())
        history.removeAll()
        play(first)
    }
    
    // MARK: - Timer & Events
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTimeFromNode()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func updateCurrentTimeFromNode() {
        guard state == .playing && !isSeeking else { return }
        
        let node = activeNode
        if let nodeTime = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: nodeTime) {
            let seconds = Double(playerTime.sampleTime) / playerTime.sampleRate
            let adjusted = timeOffset + seconds
            let clamped = duration > 0 ? min(adjusted, duration) : adjusted
            currentTime = clamped
            
            // Auto-Crossfade
            if duration > 0, currentTime >= (duration - crossfadeDuration), !queue.isEmpty, !isTransitioning {
               // Must prevent multiple triggers.
               // transition() sets isTransitioning=true IMMEDIATELY so guard works.
               next()
            }
        }
    }
    
    private func handleTrackFinished(node: AVAudioPlayerNode) {
        // Only trigger next if the FINISHED node is the ACTIVE node
        // If the old node (inactive) finishes, we don't care.
        guard node == activeNode else { return }
        guard state == .playing else { return }
        guard !isTransitioning else { return }
        guard !isSeeking else { return }
        
        next()
    }
    
    // MARK: - Persistence
    private func saveState() {
        if let track = currentTrack, let data = try? JSONEncoder().encode(track) {
            UserDefaults.standard.set(data, forKey: "lastPlayedTrack")
            UserDefaults.standard.set(currentTime, forKey: "lastPlayedTime")
        }
        UserDefaults.standard.set(volume, forKey: "lastVolume")
    }
    
    private func restoreState() {
        if let data = UserDefaults.standard.data(forKey: "lastPlayedTrack"),
           let track = try? JSONDecoder().decode(Track.self, from: data) {
            self.currentTrack = track
            self.duration = track.duration
            self.currentTime = UserDefaults.standard.double(forKey: "lastPlayedTime")
            self.state = .paused
        }
        if UserDefaults.standard.object(forKey: "lastVolume") != nil {
             self.volume = UserDefaults.standard.float(forKey: "lastVolume")
        }
    }
    
    // MARK: - Media Center Integration
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }
    
    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0
        ]
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        
        // Load Artwork Async
        Task {
            if let url = await AppServices.shared.metadata.loadArtwork(for: track),
               let image = NSImage(contentsOf: url) {
                let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in
                    return image
                }
                
                await MainActor.run {
                    var current = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    // Verify track hasn't changed
                    if let currentTitle = current[MPMediaItemPropertyTitle] as? String, currentTitle == track.title {
                        current[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = current
                    }
                }
            }
        }
    }
}
