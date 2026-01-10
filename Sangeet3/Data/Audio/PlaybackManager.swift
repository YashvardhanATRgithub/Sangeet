//
//  PlaybackManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  High-performance playback with audiophile features
//

import Foundation
import Combine
import SwiftUI

/// Manages playback with audiophile features
final class PlaybackManager: ObservableObject {
    
    // MARK: - Published State
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.7
    
    // Queue
    @Published var queue: [Track] = []
    @Published var queueIndex: Int = 0
    @Published var shuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isInfiniteQueueEnabled = false
    
    enum RepeatMode { case off, all, one }
    
    // MARK: - Private
    private let player = BASSEngine.shared
    private var positionTimer: Timer?
    private var isTransitioning = false  // Prevents race conditions during crossfade
    private var lastSkipTime: Date = .distantPast  // Debounce protection
    private var crossfadePending = false  // Prevents multiple crossfade triggers
    
    // MARK: - Singleton
    static let shared = PlaybackManager()
    
    private init() {
        isInfiniteQueueEnabled = UserDefaults.standard.bool(forKey: "infiniteQueueEnabled")
        player.volume = volume
        
        // Listen for audio settings changes
        NotificationCenter.default.addObserver(
            forName: .audioSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChanged()
        }
        
        NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleDeviceChanged(notification)
        }
        
        setupSystemMedia()
        setupStatePersistence()
        
        // Try restoring state after a short delay (to allow LibraryManager to load)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.restoreState()
        }
    }
    
    private func setupSystemMedia() {
        SystemMediaManager.shared.setup(
            onPlay: { [weak self] in
                if !(self?.isPlaying ?? false) {
                    self?.togglePlayPause()
                }
            },
            onPause: { [weak self] in
                if self?.isPlaying ?? false {
                    self?.togglePlayPause()
                }
            },
            onNext: { [weak self] in
                self?.next(manualSkip: true)
            },
            onPrevious: { [weak self] in
                self?.previous()
            },
            onSeek: { [weak self] time in
                self?.seek(to: time)
            }
        )
        
        SystemMediaManager.shared.onTogglePlayback = { [weak self] in
            self?.togglePlayPause()
        }
    }
    
    private func handleSettingsChanged() {
        // If playing online content, IGNORE audiophile setting changes to prevent skipping/stopping.
        if let track = currentTrack, track.isRemote {
            print("[PlaybackManager] Audiophile settings ignored for Online Content to preserve playback stability.")
            return
        }

        // CoreAudio Stability Delay: Allow 500ms for device to settle (e.g. sample rate switch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // Reinitialize BASS with new settings
            self?.player.initBASS()
            
            // Reload current track if any
            self?.reloadCurrentTrack()
        }
    }
    
    private func handleDeviceChanged(_ notification: Notification) {
        // BASSEngine automatically handles the stream move upon device change notification
        print("[PlaybackManager] Audio device changed notification received")
        
        // Ensure playback state is consistent if needed
        if isPlaying {
            player.play()
        }
    }
    
    func updateCurrentTrack(_ track: Track) {
        // Only update if IDs match to prevent race conditions
        guard currentTrack?.id == track.id else { return }
        
        currentTrack = track
        
        // Update System Media Info
        let image = track.artworkData.flatMap { NSImage(data: $0) }
        SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
    }
    
    private func reloadCurrentTrack() {
        guard let track = currentTrack else { return }
        
        let wasPlaying = isPlaying
        let time = currentTime
        
        // Use a background task to handle potential URL resolution
        Task {
            var urlToLoad = track.fileURL
            
            // If it's a Tidal track, we MUST re-resolve the URL because:
            // 1. The original 'fileURL' is likely 'tidal://...' which BASS can't play directly.
            // 2. Even if we had the HTTP URL, it might have expired.
            if track.fileURL.absoluteString.hasPrefix("tidal://") {
                let idStr = track.fileURL.absoluteString.replacingOccurrences(of: "tidal://", with: "")
                if let id = Int(idStr), let streamURL = try? await TidalDLService.shared.getStreamURL(trackID: id, quality: .HIGH) {
                    urlToLoad = streamURL
                    print("[PlaybackManager] Resolved new stream URL for reload")
                } else {
                    print("[PlaybackManager] Failed to resolve stream URL for reload")
                    return // Abort if we can't get a stream
                }
            }
            
            await MainActor.run {
                do {
                    // Suppress 'handleTrackEnd' during reload to prevent skipping
                    self.isReloading = true
                    
                    try player.load(url: urlToLoad) { [weak self] in
                        self?.handleTrackEnd()
                    }
                    
                    if time > 0 {
                        // Small buffer for network streams
                        player.seek(to: time)
                    }
                    
                    if wasPlaying {
                        player.play()
                        self.isPlaying = true // Ensure UI state matches
                    }
                    
                    print("[PlaybackManager] Track reloaded successfully at \(time)s")
                    
                    // Allow 1.5 seconds for BASS/CoreAudio to stabilize before accepting Track End events
                    // This prevents FLAC Syncword errors or initial glitches from skipping the song
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.isReloading = false
                    }
                    
                } catch {
                    print("[PlaybackManager] Reload failed: \(error)")
                    self.isReloading = false
                }
            }
        }
    }
    
    // MARK: - Audiophile Settings Access
    
    private var seamlessPlaybackEnabled: Bool {
        UserDefaults.standard.bool(forKey: "seamlessPlayback")
    }
    
    private var crossfadeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "crossfadeEnabled")
    }
    
    private var crossfadeDuration: TimeInterval {
        let duration = UserDefaults.standard.double(forKey: "crossfadeDuration")
        return duration > 0 ? duration : 3.0
    }
    
    private var volumeNormalizationEnabled: Bool {
        UserDefaults.standard.bool(forKey: "volumeNormalization")
    }
    
    // MARK: - Playback Controls
    
    /// Starts a "Radio" session based on the seed track.
    /// Resets the queue to just this track and immediately generates similar songs.
    func startRadio(from track: Track) {
        // 1. Reset Queue
        self.queue = [track]
        self.queueIndex = 0
        
        // 2. Play (Force Context Switch Logic is handled, but we want to be explicit about Smart Queue)
        play(track)
        
        // 3. Force Smart Queue (Radio Mode)
        // play(track) will see it in queue and NOT trigger smart queue if infinite is off.
        // So we explicitly trigger it here.
        Task {
            await updateSmartQueue(for: track, force: true)
        }
    }
    
    func play(_ track: Track) {
        guard !isTransitioning else { return }
        
        // Context Switch: If track is NOT in the current queue, start a new queue context.
        var isContextSwitch = false
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            self.queueIndex = index
        } else {
            // New Context (e.g. Played from Search)
            self.queue = [track]
            self.queueIndex = 0
            isContextSwitch = true
            print("[PlaybackManager] Context Switch: Reset queue for '\(track.title)'")
        }
        
        // Dynamic Smart Queue (Instant Update)
        // If it's a context switch (new session), we ALWAYS want similar songs if online.
        if isContextSwitch || isInfiniteQueueEnabled {
            Task { await updateSmartQueue(for: track, force: isContextSwitch) }
        } else {
            // Even if infinite queue is off, we should pre-cache existing songs
            preCacheUpcomingTracks()
        }
        
        // Handle Remote Tidal Tracks (Smart Queue)
        if track.isRemote && track.fileURL.absoluteString.hasPrefix("tidal://") {
             handleRemoteTidalPlayback(track)
             return
        }
        
        // ... Normal Playback Logic ...
        
        // Check if we should crossfade (a song is currently playing)
        let shouldCrossfade = crossfadeEnabled && isPlaying && currentTrack != nil
        
        // Update UI first (instant response)
        currentTrack = track
        isPlaying = true
        currentTime = 0
        duration = track.duration > 0 ? track.duration : 0
        
        startPositionTimer()
        
        // Apply ReplayGain if enabled
        if volumeNormalizationEnabled {
            applyReplayGain(for: track)
        } else {
            player.setReplayGain(db: nil)
        }
        
        // Sync device sample rate if enabled
        syncSampleRateForTrack(track)
        
        // Update System Media Info
        let image = track.artworkData.flatMap { NSImage(data: $0) }
        SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
        
        // Load and play - use crossfade if enabled and already playing
        var crossfadeSucceeded = false
        
        if shouldCrossfade {
            // Use crossfade for smooth transition
            isTransitioning = true
            do {
                try player.crossfadeLoad(
                    url: track.fileURL,
                    duration: crossfadeDuration,
                    onEnd: { [weak self] in
                        self?.handleTrackEnd()
                    }
                )
                isTransitioning = false
                crossfadeSucceeded = true
                
                if duration == 0 {
                    duration = player.duration
                }
                
                // Preload next track for gapless
                if seamlessPlaybackEnabled {
                    preloadNextTrack()
                }
                
            } catch {
                isTransitioning = false
                crossfadeSucceeded = false
                print("[PlaybackManager] Crossfade play error: \(error), falling back to normal play")
            }
        }
        
        // Normal load (no crossfade requested, or crossfade failed)
        if !crossfadeSucceeded {
            do {
                try player.load(url: track.fileURL) { [weak self] in
                    self?.handleTrackEnd()
                }
                
                // Bit-Perfect mode: bypass EQ
                let bitPerfect = UserDefaults.standard.bool(forKey: "bitPerfectOutput")
                if !bitPerfect {
                    // Attach EQ only if not in bit-perfect mode
                    Task { @MainActor in
                        EQManager.shared.attachToStream(0)  // EQ attachment happens in BASSEngine
                    }
                }
                
                player.play()
                
                if duration == 0 {
                    duration = player.duration
                }
                
                // Preload next track for gapless
                if seamlessPlaybackEnabled {
                    preloadNextTrack()
                }
                
            } catch {
                isPlaying = false
                print("[PlaybackManager] Error: \(error)")
            }
        }
        
        saveState()
    }
    
    func playQueue(tracks: [Track], startIndex: Int = 0) {
        queue = tracks
        queueIndex = startIndex
        if let track = tracks[safe: startIndex] {
            play(track)
        }
    }
    
    func togglePlayPause() {
        // If trying to play but BASS has no stream loaded (e.g., restored remote track), trigger full play
        if !isPlaying, let track = currentTrack, track.isRemote, !player.hasActiveStream() {
            print("[PlaybackManager] Restored remote track - triggering full play flow")
            play(track)
            return
        }
        
        isPlaying.toggle()
        
        if isPlaying {
            player.play()
            startPositionTimer()
        } else {
            player.pause()
            stopPositionTimer()
        }
        
        SystemMediaManager.shared.updatePlaybackState(isPlaying: isPlaying, elapsedTime: currentTime)
        if !isPlaying { saveState() }
    }
    
    // MARK: - Remote Playback
    
    private func handleRemoteTidalPlayback(_ track: Track) {
        let tidalIDString = track.fileURL.absoluteString.replacingOccurrences(of: "tidal://", with: "")
        guard let tidalID = Int(tidalIDString) else {
            print("[PlaybackManager] Invalid Tidal ID: \(tidalIDString)")
            return
        }
        
        print("[PlaybackManager] resolving remote Tidal track: \(tidalID)")
        
        // Update UI immediately
        currentTrack = track
        isPlaying = true
        currentTime = 0
        duration = 0 // Will update when stream loads
        
        // Stop current if playing
        player.pause()
        stopPositionTimer()
        
        Task {
            // 1. Check local cache first
            if let cachedURL = await StreamCache.shared.getCachedFileURL(for: tidalID) {
                await MainActor.run {
                    do {
                        try self.player.load(url: cachedURL) { [weak self] in
                            self?.handleTrackEnd()
                        }
                        let image = track.artworkData.flatMap { NSImage(data: $0) }
                        SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
                        
                        self.player.play()
                        self.startPositionTimer()
                        
                        if self.duration == 0 {
                            self.duration = self.player.duration
                        }
                        print("[PlaybackManager] Loaded from CACHE: \(track.title)")
                    } catch {
                        print("[PlaybackManager] Cache Load Error: \(error)")
                        self.isPlaying = false
                    }
                }
                return
            }
            
            // 2. Resolve stream URL from Tidal API
            do {
                if let streamURL = try await TidalDLService.shared.getStreamURL(trackID: tidalID, quality: .HIGH) {
                    await MainActor.run {
                        do {
                            try self.player.load(url: streamURL) { [weak self] in
                                self?.handleTrackEnd()
                            }
                            let image = track.artworkData.flatMap { NSImage(data: $0) }
                            SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
                            
                            self.player.play()
                            self.startPositionTimer()
                            
                            if self.duration == 0 {
                                self.duration = self.player.duration
                            }
                            
                            // 3. Cache stream in background for offline resume
                            Task {
                                await StreamCache.shared.cacheStreamInBackground(from: streamURL, trackID: tidalID)
                            }
                            
                        } catch {
                            print("[PlaybackManager] BASS Load Error (Stream): \(error)")
                            self.isPlaying = false
                        }
                    }
                } else {
                    print("[PlaybackManager] Failed to get stream URL for \(tidalID)")
                    await MainActor.run { self.isPlaying = false }
                }
            } catch {
                print("[PlaybackManager] Tidal Stream Resolve Error: \(error)")
                await MainActor.run { self.isPlaying = false }
            }
        }
    }
    
    // MARK: - Track Transitions
    
    private var isReloading = false

    private func handleTrackEnd() {
        guard !isReloading else {
            print("[PlaybackManager] Track End ignored (Reloading)")
            return
        }

        if let track = currentTrack {
            Task { @MainActor in
                LibraryManager.shared.incrementPlayCount(track)
                // ML: Record Full Play
                RecommendationEngine.shared.recordInteraction(for: track, type: .playedFully)
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.next()
        }
    }
    
    func next(manualSkip: Bool = false) {
        // ML Skip Logic
        if manualSkip, let track = currentTrack {
             let time = self.currentTime
             // If manual skip (and not just finished), check duration
             // Only if current time is small (meaning user HIT next)
             // But be careful: if song finished naturally, manualSkip is false.
             // If user hits NEXT, manualSkip is true.
             
             if time < 10 {
                 RecommendationEngine.shared.recordInteraction(for: track, type: .skippedImmediate)
             } else if time < 30 {
                 RecommendationEngine.shared.recordInteraction(for: track, type: .skippedEarly)
             }
        }

        // Block all skips during crossfade transition
        guard !isTransitioning else {
            print("[PlaybackManager] Skip blocked (transitioning)")
            return
        }
        
        // Debounce: ignore rapid manual skips (1 second minimum between skips)
        if manualSkip {
            let now = Date()
            guard now.timeIntervalSince(lastSkipTime) > 0.5 else { 
                print("[PlaybackManager] Skip ignored (debounce)")
                return
            }
            lastSkipTime = now
        }
        
        guard !queue.isEmpty, !isTransitioning else { return }
        
        // Safety: Ensure queueIndex matches currentTrack to prevent drift
        if let current = currentTrack, let realIndex = queue.firstIndex(where: { $0.id == current.id }) {
            queueIndex = realIndex
        }
        
        if repeatMode == .one && !manualSkip {
            seek(to: 0)
            isPlaying = true
            player.play()
            startPositionTimer()
            return
        }
        
        queueIndex += 1
        
        if queueIndex >= queue.count && isInfiniteQueueEnabled {
             // If somehow empty, try to fill
             Task { await updateSmartQueue(for: currentTrack ?? queue.last) }
        }
        
        if queueIndex >= queue.count {
             if repeatMode == .all {
                 queueIndex = 0
             } else {
                 queueIndex = queue.count - 1
                 isPlaying = false
                 player.pause() // Explicitly stop the engine
                 stopPositionTimer()
                 
                 // Reset UI state
                 DispatchQueue.main.async {
                     self.currentTime = 0
                     self.positionTimer?.invalidate()
                     self.positionTimer = nil
                 }
                 
                 print("[PlaybackManager] End of queue reached - Playback Stopped")
                 return
             }
             if let nextTrack = queue[safe: queueIndex] {
                 play(nextTrack)
             }
             return
        }
        
        if let nextTrack = queue[safe: queueIndex] {
            print("[PlaybackManager] Next track: \(nextTrack.title) (Index: \(queueIndex))")
            
            // Crossfade only on manual skip (when old track is still playing)
            if manualSkip && crossfadeEnabled {
                crossfadeToTrack(nextTrack)
            } else if seamlessPlaybackEnabled {
                gaplessToNextTrack(nextTrack)
            } else {
                play(nextTrack)
            }
            
            // Dynamic Queue Update
            if isInfiniteQueueEnabled {
                Task { await updateSmartQueue(for: nextTrack) }
            }
        }
    }
    
    // MARK: - Dynamic Smart Queue
    
    private var smartQueueTask: Task<Void, Never>?
    
    private func updateSmartQueue(for track: Track?, force: Bool = false) async {
        guard let seed = track else { return }
        
        // Cancel previous update to avoid race conditions
        smartQueueTask?.cancel()
        
        smartQueueTask = Task {
            // 1. Check if we actually need to update
            // If we have plenty of songs (e.g. > 10), don't aggressively churn.
            let shouldUpdate: Bool = await MainActor.run {
                let remaining = self.queue.count - (self.queueIndex + 1)
                return remaining < 5 // Only update if running low
            }
            
            // If Forced (Context Switch) OR Low on songs (Infinite Queue), proceed.
            // Otherwise stop.
            if !force && (!shouldUpdate || !isInfiniteQueueEnabled) { return }
            
            // 2. Fetch New Recommendations FIRST
            print("[PlaybackManager] Smart Queue: Fetching recommendations for '\(seed.title)'...")
            
            // Capture current queue for exclusion
            let currentQueueSnapshot = await MainActor.run { return self.queue }
            
            async let fastRecsTask = LibraryManager.shared.getFastRecommendations(for: seed, exclude: currentQueueSnapshot)
            async let deepRecsTask = LibraryManager.shared.getDeepRecommendations(for: seed, exclude: currentQueueSnapshot)
            
            let (fastRecs, deepRecs) = await (fastRecsTask, deepRecsTask)
            
            if Task.isCancelled { return }
            
            await MainActor.run {
                // Now we have data. We can safely update.
                
                // 3. Robust Duplicate Filtering
                // We must filter out tracks that are already in the queue, even if IDs differ (e.g. Album vs Single)
                // We use a simplified sanitization here to match what LibraryManager does.
                
                func fastSanitize(_ s: String) -> String {
                    return s.lowercased()
                        .replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .filter { $0.isLetter || $0.isNumber }
                }
                
                let existingSignatures = Set(self.queue.map { fastSanitize($0.title + $0.artist) })
                
                let uniqueTracks = (fastRecs + deepRecs).filter { track in
                    // 1. Check ID
                    if self.queue.contains(where: { $0.id == track.id }) { return false }
                    
                    // 2. Check Title+Artist Signature
                    let sig = fastSanitize(track.title + track.artist)
                    if existingSignatures.contains(sig) { return false }
                    
                    return true
                }
                
                // 3. Remove duplicates within the new batch itself
                var finalTracks: [Track] = []
                var seenSigs: Set<String> = []
                
                for track in uniqueTracks {
                    let sig = fastSanitize(track.title + track.artist)
                    if !seenSigs.contains(sig) {
                        seenSigs.insert(sig)
                        finalTracks.append(track)
                    }
                }
                
                // OFFLINE FALLBACK: If no recommendations, use local library shuffle
                if finalTracks.isEmpty {
                    print("[PlaybackManager] Smart Queue: No online recommendations. Falling back to local library shuffle.")
                    
                    // Get local tracks only (non-remote), excluding current queue
                    let localTracks = LibraryManager.shared.tracks.filter { !$0.isRemote }
                    let existingIds = Set(self.queue.map { $0.id })
                    
                    var candidates = localTracks.filter { !existingIds.contains($0.id) }
                    
                    // Shuffle and take up to 10
                    candidates.shuffle()
                    finalTracks = Array(candidates.prefix(10))
                    
                    if finalTracks.isEmpty {
                        print("[PlaybackManager] Smart Queue: No local tracks available for fallback.")
                        return
                    }
                    
                    print("[PlaybackManager] Smart Queue: Using \(finalTracks.count) local tracks as fallback.")
                }
                
                guard !finalTracks.isEmpty else {
                    print("[PlaybackManager] Smart Queue: No new unique tracks found (Filtered \(fastRecs.count + deepRecs.count)).") 
                    return
                }
                
                // Safe Update Strategy:
                // Since user complained about empty queue, let's be conservative: JUST APPEND.
                
                self.queue.append(contentsOf: finalTracks)
                print("[PlaybackManager] Smart Queue: Appended \(finalTracks.count) new tracks.")
                
                // 4. Pre-Cache Upcoming
                self.preCacheUpcomingTracks()
            }
        }
        await smartQueueTask?.value
    }
    
    func previous() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        
        guard !queue.isEmpty else { return }
        
        queueIndex -= 1
        if queueIndex < 0 {
            queueIndex = repeatMode == .all ? queue.count - 1 : 0
        }
        
        if let track = queue[safe: queueIndex] {
            play(track)
        }
    }
    
    // MARK: - Gapless Playback
    
    private func preloadNextTrack() {
        let nextIndex = queueIndex + 1
        guard nextIndex < queue.count || repeatMode == .all else { return }
        
        let idx = nextIndex >= queue.count ? 0 : nextIndex
        if let nextTrack = queue[safe: idx] {
            player.preloadNext(url: nextTrack.fileURL)
        }
    }
    
    private func gaplessToNextTrack(_ track: Track) {
        // Apply ReplayGain for next track
        if volumeNormalizationEnabled {
            applyReplayGain(for: track)
        }
        
        // Try to use preloaded stream
        if player.switchToPreloaded(onEnd: { [weak self] in self?.handleTrackEnd() }) {
            currentTrack = track
            currentTime = 0
            duration = player.duration
            player.play()
            
            // Update System Info
            let image = track.artworkData.flatMap { NSImage(data: $0) }
            SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
            
            // Preload the next one
            preloadNextTrack()
        } else {
            // Fallback to normal play
            play(track)
        }
    }
    
    // MARK: - Crossfade
    
    private func crossfadeToTrack(_ track: Track) {
        isTransitioning = true
        
        // Apply ReplayGain for new track
        if volumeNormalizationEnabled {
            applyReplayGain(for: track)
        }
        
        // Use TRUE concurrent crossfade - both songs play simultaneously
        do {
            try player.crossfadeLoad(
                url: track.fileURL,
                duration: crossfadeDuration,
                onEnd: { [weak self] in
                    self?.handleTrackEnd()
                }
            )
            
            currentTrack = track
            currentTime = 0
            duration = player.duration
            isTransitioning = false
            
            // Update System Info
            let image = track.artworkData.flatMap { NSImage(data: $0) }
            SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
            
            // Preload next if gapless also enabled
            if seamlessPlaybackEnabled {
                preloadNextTrack()
            }
            
        } catch {
            isTransitioning = false
            print("[PlaybackManager] Crossfade error: \(error)")
            // Fallback to normal play
            play(track)
        }
    }
    
    // MARK: - ReplayGain / Loudness Normalization
    
    private func applyReplayGain(for track: Track) {
        guard volumeNormalizationEnabled else {
            print("[PlaybackManager] Normalization: disabled")
            player.setReplayGain(db: nil)
            return
        }
        
        // Try ReplayGain tags first
        if let tagGain = MetadataExtractor.shared.extractReplayGain(from: track.fileURL) {
            player.setReplayGain(db: tagGain)
            print("[PlaybackManager] Normalization: ReplayGain tag = \(tagGain) dB")
            return
        }
        
        // Fallback: Calculate loudness dynamically
        if let calculatedGain = LoudnessNormalizer.shared.getGainForTrack(url: track.fileURL) {
            player.setReplayGain(db: calculatedGain)
            print("[PlaybackManager] Normalization: Calculated gain = \(calculatedGain) dB")
        } else {
            print("[PlaybackManager] Normalization: Unable to calculate, using default")
            player.setReplayGain(db: nil)
        }
    }
    
    // MARK: - Sample Rate Sync
    
    private func syncSampleRateForTrack(_ track: Track) {
        let settings = UserDefaults.standard
        guard settings.bool(forKey: "nativeSampleRate") else {
            print("[PlaybackManager] SampleRate: sync disabled")
            return
        }
        
        let sourceRate = MetadataExtractor.shared.getSourceSampleRate(from: track.fileURL)
        print("[PlaybackManager] SampleRate: source=\(sourceRate)Hz")
        
        if sourceRate > 0 {
            // player.syncSampleRate(sourceRate: sourceRate)
            // TODO: Implement sample rate sync in BASSEngine/DACManager
        }
    }
    
    // MARK: - Basic Controls
    
    func seek(to time: TimeInterval) {
        currentTime = time
        player.seek(to: time)
        SystemMediaManager.shared.updatePlaybackState(isPlaying: isPlaying, elapsedTime: time)
    }
    
    func setVolume(_ vol: Float) {
        volume = vol
        
        // Direct application to BASS stream
        player.volume = vol
        player.applyVolume(vol)
    }
    
    private var previousVolume: Float = 0.7
    
    func toggleMute() {
        if volume > 0 {
            previousVolume = volume
            setVolume(0)
        } else {
            setVolume(previousVolume > 0 ? previousVolume : 0.3)
        }
    }
    
    // MARK: - Position Timer
    
    private func startPositionTimer() {
        stopPositionTimer()
        crossfadePending = false  // Reset crossfade flag
        
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.player.updateCurrentTime()
            self.currentTime = self.player.currentTime
            
            // Check for crossfade trigger at track end
            self.checkCrossfadeTrigger()
        }
        
        RunLoop.main.add(positionTimer!, forMode: .common)
    }
    
    /// Trigger crossfade when approaching track end
    private func checkCrossfadeTrigger() {
        guard crossfadeEnabled,
              !crossfadePending,
              !isTransitioning,
              duration > 0,
              repeatMode != .one,  // Crossfade must NOT trigger in Repeat One mode
              queueIndex < queue.count - 1 || repeatMode == .all else { return }
        
        let timeRemaining = duration - currentTime
        let crossfadeStart = crossfadeDuration
        
        // Start crossfade when remaining time <= crossfade duration
        if timeRemaining > 0 && timeRemaining <= crossfadeStart {
            crossfadePending = true  // Prevent multiple triggers
            
            print("[PlaybackManager] Auto-crossfade triggered (\(timeRemaining)s remaining)")
            
            // Get next track
            var nextIndex = queueIndex + 1
            if nextIndex >= queue.count && repeatMode == .all {
                nextIndex = 0
            }
            
            if let nextTrack = queue[safe: nextIndex] {
                // Increment play count for the track that is about to fade out
                if let track = currentTrack {
                    Task { @MainActor in
                        LibraryManager.shared.incrementPlayCount(track)
                    }
                }
                
                isTransitioning = true
                queueIndex = nextIndex
                
                if volumeNormalizationEnabled {
                    applyReplayGain(for: nextTrack)
                }
                
                do {
                    try player.crossfadeLoad(
                        url: nextTrack.fileURL,
                        duration: crossfadeDuration,
                        onEnd: { [weak self] in
                            self?.handleTrackEnd()
                        }
                    )
                    
                    currentTrack = nextTrack
                    currentTime = 0
                    duration = player.duration
                    isTransitioning = false
                    crossfadePending = false
                    
                    // Update System Info
                    let image = nextTrack.artworkData.flatMap { NSImage(data: $0) }
                    SystemMediaManager.shared.updateNowPlaying(track: nextTrack, image: image)
                    
                    if seamlessPlaybackEnabled {
                        preloadNextTrack()
                    }
                    
                    // CRITICAL FIX: Trigger Smart Queue Update during Auto-Crossfade
                    // (Previously this was only called in next(), causing queue starvation)
                    if isInfiniteQueueEnabled {
                        Task { await updateSmartQueue(for: nextTrack) }
                    }
                    
                } catch {
                    print("[PlaybackManager] Auto-crossfade error: \(error)")
                    // Fallback Safety:
                    // Revert state so the current track can finish naturally (waiting for handleTrackEnd)
                    queueIndex -= 1
                    if queueIndex < 0 { queueIndex = 0 } // Safety
                    
                    isTransitioning = false
                    
                    // Do NOT reset crossfadePending to false. Keep it true to prevent
                    // the timer from retrying this failed crossfade every 0.1s.
                    // We will just let the track finish and hit 'next()' normally.
                    crossfadePending = true
                }
            }
        }
    }
    
    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }
    
    // MARK: - Queue Management
    
    func addToQueue(_ track: Track) {
        // Prevent duplicates
        guard !queue.contains(where: { $0.id == track.id }) else {
            print("[PlaybackManager] Track '\(track.title)' already in queue, skipping.")
            return
        }
        queue.append(track)
        
        // If queue was empty and we added one, refresh engine state?
        // Usually `play(track)` is called directly if playing from scratch.
        // This is mostly for "Play Next" / "Add to Queue".
        if seamlessPlaybackEnabled && queue.count == 2 {
            preloadNextTrack()
        }
    }
    
    func addToQueue(_ tracks: [Track]) {
        // Filter out tracks already in queue
        let currentIDs = Set(queue.map { $0.id })
        let newTracks = tracks.filter { !currentIDs.contains($0.id) }
        
        guard !newTracks.isEmpty else {
            print("[PlaybackManager] All tracks already in queue, skipping.")
            return
        }
        
        queue.append(contentsOf: newTracks)
        print("[PlaybackManager] Added \(newTracks.count) unique tracks to queue.")
        
        if seamlessPlaybackEnabled && queue.count > 1 {
            preloadNextTrack()
        }
    }
    
    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        queue.remove(at: index)
        if index < queueIndex {
            queueIndex -= 1
        }
        
        // Refresh preload in case we removed the next track
        if seamlessPlaybackEnabled {
            preloadNextTrack()
        }
    }
    
    func clearQueue() {
        queue.removeAll()
        queueIndex = 0
    }
    
    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled {
            if let current = currentTrack, let idx = queue.firstIndex(of: current) {
                var rest = queue
                rest.remove(at: idx)
                rest.shuffle()
                queue = [current] + rest
                queueIndex = 0
            }
        }
    }
    
    func toggleInfiniteQueue() {
        isInfiniteQueueEnabled.toggle()
        UserDefaults.standard.set(isInfiniteQueueEnabled, forKey: "infiniteQueueEnabled")
    }
    
    private func autoplaySimilarSongs() {
        // Simple implementation: Pick 5 random songs from library that are not in the current queue (or recently played)
        // Ideally this would use genre/artist matching
        Task { @MainActor in
            let library = LibraryManager.shared.tracks
            guard !library.isEmpty else { return }
            
            // Exclude current queue to ensure variety
            let currentIDs = Set(queue.map { $0.id })
            let candidates = library.filter { !currentIDs.contains($0.id) }
            
            let pool = candidates.isEmpty ? library : candidates
            let selection = Array(pool.shuffled().prefix(5))
            
            guard !selection.isEmpty else { return }
            
            self.addToQueue(selection)
            print("[PlaybackManager] Infinite Queue: Added \(selection.count) songs")
            
            // Preload the first of the new songs immediately if needed
            if seamlessPlaybackEnabled {
                preloadNextTrack()
            }
        }
    }
    
    func moveQueueItems(from source: IndexSet, to destination: Int) {
        // Adjust destination if needed
        let adjustedDest = destination
        
        // Logic to keep queueIndex pointing to correct song if moved
        // Complex if the current song itself moves.
        // Simplification: Just move logic first.
        
        queue.move(fromOffsets: source, toOffset: adjustedDest)
        
        // Recalculate queueIndex using ID matching for reliability
        if let current = currentTrack, let newIndex = queue.firstIndex(where: { $0.id == current.id }) {
            queueIndex = newIndex
            print("[PlaybackManager] Queue reordered. New index for '\(current.title)': \(queueIndex)")
        } else {
            print("[PlaybackManager] Queue reordered but current track not found in queue!")
        }
        
        // Refresh preload/gapless logic since order changed
        if seamlessPlaybackEnabled {
            preloadNextTrack()
        }
    }
    
    func moveItemUp(at index: Int) {
        guard index > 0, index < queue.count else { return }
        moveQueueItems(from: IndexSet(integer: index), to: index - 1)
    }
    
    func moveItemDown(at index: Int) {
        guard index >= 0, index < queue.count - 1 else { return }
        moveQueueItems(from: IndexSet(integer: index), to: index + 2)
    }
    
    func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
    
    // MARK: - State Persistence
    
    private func setupStatePersistence() {
        // Save on app background/terminate
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.saveState()
        }
        
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.saveState()
        }
    }
    
    func saveState() {
        let currentQueue = self.queue
        let currentIndex = self.queueIndex
        let currentTime = self.currentTime
        
        // Don't save empty states
        guard !currentQueue.isEmpty else { return }
        
        let trackIds = currentQueue.map { $0.id }
        
        // Collect remote tracks that need metadata saved for restoration
        let remoteTracks = currentQueue.filter { $0.isRemote }
        
        DatabaseManager.shared.writeAsync { db in
            try? QueueStateRecord.save(
                trackIds: trackIds,
                currentIndex: currentIndex,
                currentTime: currentTime,
                remoteTracks: remoteTracks,
                db: db
            )
        }
        
        print("[PlaybackManager] State saved: index=\(currentIndex), time=\(currentTime), remoteTracks=\(remoteTracks.count)")
    }
    
    func restoreState() {
        Task {
            // Read record
            guard let record = try? DatabaseManager.shared.read({ db in
                try QueueStateRecord.load(db: db)
            }) else { return }
            
            // Restore queue
            let savedIds = record.getTrackIds()
            guard !savedIds.isEmpty else { return }
            
            // Get saved remote track metadata
            let remoteTrackLookup: [UUID: Track] = {
                var lookup = [UUID: Track]()
                for track in record.getRemoteTracks() {
                    lookup[track.id] = track
                }
                return lookup
            }()
            
            // Map IDs to real track objects from LibraryManager OR from saved remote metadata
            let tracks = await MainActor.run {
                savedIds.compactMap { id -> Track? in
                    // First, try local library
                    if let localTrack = LibraryManager.shared.tracks.first(where: { $0.id == id }) {
                        return localTrack
                    }
                    // Otherwise, check saved remote metadata
                    if let remoteTrack = remoteTrackLookup[id] {
                        return remoteTrack
                    }
                    return nil
                }
            }
            
            guard !tracks.isEmpty else {
                print("[PlaybackManager] Restore failed: no tracks could be resolved from saved IDs.")
                return
            }
            
            await MainActor.run {
                self.queue = tracks
                // Clamp index safely
                self.queueIndex = min(max(0, record.currentIndex), tracks.count - 1)
                
                if let track = self.queue[safe: self.queueIndex] {
                    self.currentTrack = track
                    self.currentTime = record.currentTime
                    self.duration = track.duration
                    
                    // For remote tracks, we can't load immediately without resolving the URL.
                    // We'll load the track state (UI shows it), but actual playback requires
                    // user to press play, which will trigger URL resolution.
                    if track.isRemote {
                        // Just update UI state, don't try to load the tidal:// URL into BASS
                        let image = track.artworkData.flatMap { NSImage(data: $0) }
                        SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
                        SystemMediaManager.shared.updatePlaybackState(isPlaying: false, elapsedTime: record.currentTime)
                        print("[PlaybackManager] State restored (Remote): \(track.title) at \(record.currentTime)s - Press Play to stream")
                    } else {
                        // Load local track into player but DO NOT PLAY
                        do {
                            try self.player.load(url: track.fileURL) { [weak self] in
                                self?.handleTrackEnd()
                            }
                            
                            // Seek to saved time
                            if record.currentTime > 0 {
                                self.player.seek(to: record.currentTime)
                            }
                            
                            // Update system info
                            let image = track.artworkData.flatMap { NSImage(data: $0) }
                            SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
                            SystemMediaManager.shared.updatePlaybackState(isPlaying: false, elapsedTime: record.currentTime)
                            
                            print("[PlaybackManager] State restored (Local): \(track.title) at \(record.currentTime)s")
                        } catch {
                            print("[PlaybackManager] Restore load error: \(error)")
                        }
                    }
                }
            }
        }
    }
    // MARK: - Pre-Caching
    
    private func preCacheUpcomingTracks() {
        guard !queue.isEmpty else { return }
        
        let start = queueIndex + 1
        let end = min(start + 3, queue.count)
        guard start < end else { return }
        
        let candidates = queue[start..<end]
        
        Task {
            for (offset, track) in candidates.enumerated() {
                // If it's a Tidal track that hasn't been resolved yet
                if track.isRemote && track.fileURL.scheme == "tidal" {
                    if let id = Int(track.fileURL.host ?? "") {
                        // Resolve silently
                        if let streamURL = try? await TidalDLService.shared.getStreamURL(trackID: id) {
                            // Update the track in the queue with the resolved URL
                            let index = start + offset
                            if index < self.queue.count { // Safety check
                                await MainActor.run {
                                    var updatedTrack = self.queue[index]
                                    updatedTrack.fileURL = streamURL
                                    self.queue[index] = updatedTrack
                                    print("[PlaybackManager] Pre-cached (URL Resolved): \(updatedTrack.title)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Array Extension
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
