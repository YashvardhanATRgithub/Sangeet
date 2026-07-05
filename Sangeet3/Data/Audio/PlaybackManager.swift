//
//  PlaybackManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  High-performance local playback with audiophile features
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
    private var preShuffleOrder: [UUID]? // Queue order before shuffle was enabled

    // MARK: - Singleton
    static let shared = PlaybackManager()

    private init() {
        isInfiniteQueueEnabled = UserDefaults.standard.bool(forKey: "infiniteQueueEnabled")

        // Restore saved volume (0 is a valid saved value: muted)
        if UserDefaults.standard.object(forKey: "audioVolume") != nil {
            volume = UserDefaults.standard.float(forKey: "audioVolume")
        }
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
        // Ensure playback state is consistent if needed
        if isPlaying {
            player.play()
        }
    }

    func updateCurrentTrack(_ track: Track) {
        // Only update if IDs match to prevent race conditions
        guard currentTrack?.id == track.id else { return }

        currentTrack = track
        updateNowPlayingInfo(for: track)
    }

    private func updateNowPlayingInfo(for track: Track) {
        let image = track.artworkData.flatMap { NSImage(data: $0) }
        SystemMediaManager.shared.updateNowPlaying(track: track, image: image)
    }

    private func reloadCurrentTrack() {
        guard let track = currentTrack else { return }

        let wasPlaying = isPlaying
        let time = currentTime

        do {
            // Suppress 'handleTrackEnd' during reload to prevent skipping
            isReloading = true

            try player.load(url: track.fileURL) { [weak self] in
                self?.handleTrackEnd()
            }

            if time > 0 {
                player.seek(to: time)
            }

            if wasPlaying {
                player.play()
                isPlaying = true // Ensure UI state matches
            }

            // Allow BASS/CoreAudio to stabilize before accepting Track End events
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.isReloading = false
            }
        } catch {
            print("[PlaybackManager] Reload failed: \(error)")
            isReloading = false
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

    /// Starts a "Radio" session based on the seed track: plays it and fills
    /// the queue with similar songs from the local library.
    func startRadio(from track: Track) {
        queue = [track]
        queueIndex = 0
        preShuffleOrder = nil

        play(track)
        appendLocalRecommendations(seed: track, count: 15)
    }

    func play(_ track: Track) {
        guard !isTransitioning else { return }

        // Context Switch: If track is NOT in the current queue, start a new queue context.
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            queueIndex = index
        } else {
            queue = [track]
            queueIndex = 0
            preShuffleOrder = nil
            appendLocalRecommendations(seed: track, count: 15)
        }

        // Check if we should crossfade (a song is currently playing)
        let shouldCrossfade = crossfadeEnabled && isPlaying && currentTrack != nil

        // Update UI first (instant response)
        currentTrack = track
        isPlaying = true
        currentTime = 0
        duration = track.duration > 0 ? track.duration : 0

        startPositionTimer()

        // Apply ReplayGain if enabled
        applyReplayGain(for: track)

        updateNowPlayingInfo(for: track)

        // Load and play - use crossfade if enabled and already playing
        var crossfadeSucceeded = false

        if shouldCrossfade {
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

                syncDurationFromPlayer()

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

                player.play()
                syncDurationFromPlayer()

                if seamlessPlaybackEnabled {
                    preloadNextTrack()
                }
            } catch {
                isPlaying = false
                stopPositionTimer()
                print("[PlaybackManager] Error: \(error)")
            }
        }

        saveState()
    }

    /// The engine's decoded duration is authoritative; metadata durations can be stale.
    private func syncDurationFromPlayer() {
        if player.duration > 0 {
            duration = player.duration
        }
    }

    func playQueue(tracks: [Track], startIndex: Int = 0) {
        queue = tracks
        queueIndex = startIndex
        preShuffleOrder = nil
        if let track = tracks[safe: startIndex] {
            play(track)
        }
    }

    func togglePlayPause() {
        guard currentTrack != nil else { return }

        // If BASS has no stream loaded (e.g. state restored but file failed to load), retry full play
        if !isPlaying, let track = currentTrack, !player.hasActiveStream() {
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

    // MARK: - Track Transitions

    private var isReloading = false

    private func handleTrackEnd() {
        guard !isReloading else { return }

        if let track = currentTrack {
            Task { @MainActor in
                LibraryManager.shared.incrementPlayCount(track)
                RecommendationEngine.shared.recordInteraction(for: track, type: .playedFully)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.next()
        }
    }

    func next(manualSkip: Bool = false) {
        // Taste profile: record skips
        if manualSkip, let track = currentTrack {
            let time = currentTime
            if time < 10 {
                RecommendationEngine.shared.recordInteraction(for: track, type: .skippedImmediate)
            } else if time < 30 {
                RecommendationEngine.shared.recordInteraction(for: track, type: .skippedEarly)
            }
        }

        // Block all skips during crossfade transition
        guard !isTransitioning else { return }

        // Debounce: ignore rapid manual skips (0.5s minimum between skips)
        if manualSkip {
            let now = Date()
            guard now.timeIntervalSince(lastSkipTime) > 0.5 else { return }
            lastSkipTime = now
        }

        guard !queue.isEmpty else { return }

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

        // Top up the queue before advancing if infinite queue is running low
        if isInfiniteQueueEnabled && queueIndex >= queue.count - 2 {
            appendLocalRecommendations(seed: currentTrack ?? queue.last, count: 10)
        }

        queueIndex += 1

        if queueIndex >= queue.count {
            if repeatMode == .all {
                queueIndex = 0
            } else {
                // End of queue: stop, but rewind so Play restarts the last track
                queueIndex = queue.count - 1
                isPlaying = false
                player.pause()
                player.seek(to: 0)
                stopPositionTimer()
                currentTime = 0
                SystemMediaManager.shared.updatePlaybackState(isPlaying: false, elapsedTime: 0)
                saveState()
                return
            }
            if let nextTrack = queue[safe: queueIndex] {
                play(nextTrack)
            }
            return
        }

        if let nextTrack = queue[safe: queueIndex] {
            // Crossfade only on manual skip (when old track is still playing)
            if manualSkip && crossfadeEnabled && isPlaying {
                crossfadeToTrack(nextTrack)
            } else if seamlessPlaybackEnabled {
                gaplessToNextTrack(nextTrack)
            } else {
                play(nextTrack)
            }
        }
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

    // MARK: - Local Smart Queue

    /// Fills the queue with similar tracks from the local library
    /// (same artist/album first, then taste-profile ranked variety).
    private func appendLocalRecommendations(seed: Track?, count: Int) {
        guard let seed else { return }

        Task { @MainActor in
            let recommendations = LibraryManager.shared.getLocalRecommendations(
                for: seed,
                excluding: self.queue,
                limit: count
            )
            guard !recommendations.isEmpty else { return }

            self.queue.append(contentsOf: recommendations)

            if self.seamlessPlaybackEnabled {
                self.preloadNextTrack()
            }
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
        applyReplayGain(for: track)

        // Try to use preloaded stream
        if player.switchToPreloaded(onEnd: { [weak self] in self?.handleTrackEnd() }) {
            currentTrack = track
            currentTime = 0
            duration = player.duration
            isPlaying = true
            player.play()
            startPositionTimer()

            updateNowPlayingInfo(for: track)
            preloadNextTrack()
        } else {
            // Fallback to normal play
            play(track)
        }
    }

    // MARK: - Crossfade

    private func crossfadeToTrack(_ track: Track) {
        isTransitioning = true

        applyReplayGain(for: track)

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

            updateNowPlayingInfo(for: track)

            if seamlessPlaybackEnabled {
                preloadNextTrack()
            }
        } catch {
            isTransitioning = false
            print("[PlaybackManager] Crossfade error: \(error)")
            play(track)
        }
    }

    // MARK: - ReplayGain / Loudness Normalization

    private func applyReplayGain(for track: Track) {
        guard volumeNormalizationEnabled else {
            player.setReplayGain(db: nil)
            return
        }

        // Try ReplayGain tags first
        if let tagGain = MetadataExtractor.shared.extractReplayGain(from: track.fileURL) {
            player.setReplayGain(db: tagGain)
            return
        }

        // Fallback: Calculate loudness dynamically
        if let calculatedGain = LoudnessNormalizer.shared.getGainForTrack(url: track.fileURL) {
            player.setReplayGain(db: calculatedGain)
        } else {
            player.setReplayGain(db: nil)
        }
    }

    // MARK: - Basic Controls

    func seek(to time: TimeInterval) {
        let upperBound = duration > 0 ? duration : time
        let clamped = min(max(0, time), max(0, upperBound))
        currentTime = clamped
        player.seek(to: clamped)
        SystemMediaManager.shared.updatePlaybackState(isPlaying: isPlaying, elapsedTime: clamped)
    }

    func setVolume(_ vol: Float) {
        let clamped = min(max(0, vol), 1)
        volume = clamped
        player.volume = clamped
        player.applyVolume(clamped)
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

        // Start crossfade when remaining time <= crossfade duration
        if timeRemaining > 0 && timeRemaining <= crossfadeDuration {
            crossfadePending = true  // Prevent multiple triggers

            // Get next track
            var nextIndex = queueIndex + 1
            if nextIndex >= queue.count && repeatMode == .all {
                nextIndex = 0
            }

            if let nextTrack = queue[safe: nextIndex] {
                // Count the track that is about to fade out as played
                if let track = currentTrack {
                    Task { @MainActor in
                        LibraryManager.shared.incrementPlayCount(track)
                        RecommendationEngine.shared.recordInteraction(for: track, type: .playedFully)
                    }
                }

                isTransitioning = true
                queueIndex = nextIndex

                applyReplayGain(for: nextTrack)

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

                    updateNowPlayingInfo(for: nextTrack)

                    if seamlessPlaybackEnabled {
                        preloadNextTrack()
                    }

                    // Keep the infinite queue topped up across auto-crossfades
                    if isInfiniteQueueEnabled && queueIndex >= queue.count - 2 {
                        appendLocalRecommendations(seed: nextTrack, count: 10)
                    }
                } catch {
                    print("[PlaybackManager] Auto-crossfade error: \(error)")
                    // Revert state so the current track can finish naturally
                    queueIndex = max(0, queueIndex - 1)
                    isTransitioning = false

                    // Keep crossfadePending = true so the timer doesn't retry the
                    // failed crossfade every 0.1s; the track will finish via next().
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
        guard !queue.contains(where: { $0.id == track.id }) else { return }
        queue.append(track)

        if seamlessPlaybackEnabled && queue.count == queueIndex + 2 {
            preloadNextTrack()
        }
    }

    func addToQueue(_ tracks: [Track]) {
        let currentIDs = Set(queue.map { $0.id })
        let newTracks = tracks.filter { !currentIDs.contains($0.id) }

        guard !newTracks.isEmpty else { return }

        queue.append(contentsOf: newTracks)

        if seamlessPlaybackEnabled && queue.count > 1 {
            preloadNextTrack()
        }
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        // The currently playing item can't be removed; skip instead
        guard index != queueIndex else { return }

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
        // Keep the currently playing track so playback isn't interrupted
        if let current = currentTrack {
            queue = [current]
            queueIndex = 0
        } else {
            queue = []
            queueIndex = 0
        }
        preShuffleOrder = nil

        DatabaseManager.shared.writeAsync { db in
            try QueueStateRecord.clear(db: db)
        }
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()

        if shuffleEnabled {
            // Remember the order so it can be restored on un-shuffle
            preShuffleOrder = queue.map { $0.id }

            if let current = currentTrack, let idx = queue.firstIndex(where: { $0.id == current.id }) {
                var rest = queue
                rest.remove(at: idx)
                rest.shuffle()
                queue = [current] + rest
                queueIndex = 0
            } else {
                queue.shuffle()
                queueIndex = 0
            }
        } else if let originalOrder = preShuffleOrder {
            // Restore original order for tracks still in the queue,
            // appending anything added while shuffled.
            var lookup = [UUID: Track]()
            for track in queue { lookup[track.id] = track }

            var restored: [Track] = []
            for id in originalOrder {
                if let track = lookup.removeValue(forKey: id) {
                    restored.append(track)
                }
            }
            restored.append(contentsOf: queue.filter { lookup[$0.id] != nil })

            queue = restored
            if let current = currentTrack, let idx = queue.firstIndex(where: { $0.id == current.id }) {
                queueIndex = idx
            } else {
                queueIndex = min(queueIndex, max(0, queue.count - 1))
            }
            preShuffleOrder = nil
        }

        if seamlessPlaybackEnabled {
            preloadNextTrack()
        }
    }

    func toggleInfiniteQueue() {
        isInfiniteQueueEnabled.toggle()
        UserDefaults.standard.set(isInfiniteQueueEnabled, forKey: "infiniteQueueEnabled")

        if isInfiniteQueueEnabled && queueIndex >= queue.count - 2 {
            appendLocalRecommendations(seed: currentTrack ?? queue.last, count: 10)
        }
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)

        // Recalculate queueIndex using ID matching for reliability
        if let current = currentTrack, let newIndex = queue.firstIndex(where: { $0.id == current.id }) {
            queueIndex = newIndex
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
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.saveState()
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.saveState()
        }
    }

    func saveState() {
        let currentQueue = queue
        let currentIndex = queueIndex
        let time = currentTime

        guard !currentQueue.isEmpty else { return }

        let trackIds = currentQueue.map { $0.id }

        DatabaseManager.shared.writeAsync { db in
            try QueueStateRecord.save(
                trackIds: trackIds,
                currentIndex: currentIndex,
                currentTime: time,
                db: db
            )
        }
    }

    func restoreState() {
        Task {
            // Don't clobber a session that's already active (e.g. the app was
            // launched by opening an audio file from Finder).
            let alreadyActive = await MainActor.run {
                self.isPlaying || self.currentTrack != nil || !self.queue.isEmpty
            }
            guard !alreadyActive else { return }

            guard let record = try? DatabaseManager.shared.read({ db in
                try QueueStateRecord.load(db: db)
            }) else { return }

            let savedIds = record.getTrackIds()
            guard !savedIds.isEmpty else { return }

            // Remember which track was current *before* filtering out
            // tracks that no longer exist in the library.
            let savedCurrentId = savedIds[safe: record.currentIndex]

            let tracks = await MainActor.run {
                savedIds.compactMap { id -> Track? in
                    LibraryManager.shared.tracks.first(where: { $0.id == id })
                }
            }

            guard !tracks.isEmpty else { return }

            await MainActor.run {
                // Re-check: playback may have started while we were loading
                guard !self.isPlaying, self.currentTrack == nil, self.queue.isEmpty else { return }

                self.queue = tracks

                if let savedCurrentId, let idx = tracks.firstIndex(where: { $0.id == savedCurrentId }) {
                    self.queueIndex = idx
                } else {
                    self.queueIndex = min(max(0, record.currentIndex), tracks.count - 1)
                }

                guard let track = self.queue[safe: self.queueIndex] else { return }

                self.currentTrack = track
                self.currentTime = record.currentTime
                self.duration = track.duration

                // Load track into player but DO NOT PLAY
                do {
                    try self.player.load(url: track.fileURL) { [weak self] in
                        self?.handleTrackEnd()
                    }

                    if self.player.duration > 0 {
                        self.duration = self.player.duration
                    }

                    if record.currentTime > 0 {
                        self.player.seek(to: record.currentTime)
                    }

                    self.updateNowPlayingInfo(for: track)
                    SystemMediaManager.shared.updatePlaybackState(isPlaying: false, elapsedTime: record.currentTime)
                } catch {
                    print("[PlaybackManager] Restore load error: \(error)")
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
