//
//  QueuePersistenceManager.swift
//  HiFidelity
//
//  Centralized queue persistence logic
//

import Foundation
import Combine

/// Manages automatic queue persistence with configurable auto-save intervals
@MainActor
final class QueuePersistenceManager: ObservableObject {
    static let shared = QueuePersistenceManager()
    
    // MARK: - Configuration
    
    /// Auto-save interval in seconds (default: 30 seconds)
    private let autoSaveInterval: TimeInterval = 30
    
    /// Minimum time between saves to prevent excessive writes
    private let minimumSaveInterval: TimeInterval = 5
    
    // MARK: - State
    
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var lastSaveDate: Date?
    @Published private(set) var lastError: Error?
    
    private var autoSaveTimer: Timer?
    private var hasUnsavedChanges: Bool = false
    private var lastSaveTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    private let database = DatabaseManager.shared
    private let playback: PlaybackController
    
    // MARK: - Initialization
    
    private init() {
        self.playback = PlaybackController.shared
        setupObservers()
    }
    
    // MARK: - Lifecycle Management
    
    /// Start automatic queue persistence
    /// Call this when app finishes launching
    func start() {
        Logger.info("Starting queue persistence manager")
        
        // Load persisted queue
        Task {
            await loadQueue()
        }
        
        // Start auto-save timer
        startAutoSaveTimer()
    }
    
    /// Stop automatic queue persistence
    /// Call this before app terminates
    func stop() async {
        Logger.info("Stopping queue persistence manager")
        
        // Stop timer
        stopAutoSaveTimer()
        
        // Save final state
        await saveQueue()
        
        Logger.info("Queue persistence manager stopped")
    }
    
    // MARK: - Queue Operations
    
    /// Load queue from database and restore playback state
    func loadQueue() async {
        do {
            Logger.info("Loading persisted queue from database")
            
            let result = try await database.loadQueue()
            
            guard !result.tracks.isEmpty else {
                Logger.info("No persisted queue found")
                return
            }
            
            // Restore to playback controller
            playback.queue = result.tracks
            playback.currentQueueIndex = result.currentIndex
            
            // Restore current track if valid
            if result.currentIndex >= 0 && result.currentIndex < result.tracks.count {
                let track = result.tracks[result.currentIndex]
                playback.currentTrack = track
                // Don't auto-play, just load the track
                Logger.info("Restored queue with \(result.tracks.count) tracks, current: \(track.title)")
            }
            
            lastSaveDate = Date()
            hasUnsavedChanges = false
            
        } catch {
            Logger.error("Failed to load queue: \(error)")
            lastError = error
        }
    }
    
    /// Save current queue to database
    func saveQueue() async {
        // Prevent saving too frequently
        if let lastSave = lastSaveTime,
           Date().timeIntervalSince(lastSave) < minimumSaveInterval {
            Logger.debug("Skipping save - too soon since last save")
            return
        }
        
        // Skip if no queue
        guard !playback.queue.isEmpty else {
            Logger.debug("Skipping save - queue is empty")
            return
        }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            Logger.debug("Saving queue to database")
            
            // Save queue and current index
            try await database.saveQueue(
                tracks: playback.queue,
                currentIndex: playback.currentQueueIndex
            )
            
            // Save current index to UserDefaults
            database.saveQueueCurrentIndex(playback.currentQueueIndex)
            
            lastSaveDate = Date()
            lastSaveTime = Date()
            hasUnsavedChanges = false
            
            Logger.debug("Queue saved successfully")
            
        } catch {
            Logger.error("Failed to save queue: \(error)")
            lastError = error
        }
    }
    
    /// Clear persisted queue from database
    func clearPersistedQueue() async {
        do {
            try await database.clearQueue()
            Logger.info("Cleared persisted queue")
        } catch {
            Logger.error("Failed to clear persisted queue: \(error)")
        }
    }
    
    // MARK: - Auto-Save Management
    
    private func setupObservers() {
        // Observe queue changes
        playback.$queue
            .dropFirst() // Skip initial value
            .sink { [weak self] _ in
                self?.markDirty()
            }
            .store(in: &cancellables)
        
        // Observe current queue index changes
        playback.$currentQueueIndex
            .dropFirst()
            .sink { [weak self] _ in
                self?.markDirty()
            }
            .store(in: &cancellables)
    }
    
    private func markDirty() {
        hasUnsavedChanges = true
    }
    
    private func startAutoSaveTimer() {
        stopAutoSaveTimer()
        
        autoSaveTimer = Timer.scheduledTimer(
            withTimeInterval: autoSaveInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                if self.hasUnsavedChanges {
                    await self.saveQueue()
                }
            }
        }
        
        // Ensure timer fires on common run loop modes
        RunLoop.current.add(autoSaveTimer!, forMode: .common)
        
        Logger.info("Auto-save timer started (interval: \(autoSaveInterval)s)")
    }
    
    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }
    
    // MARK: - Manual Save Trigger
    
    /// Manually trigger a queue save (respects minimum interval)
    func saveNow() async {
        await saveQueue()
    }
    
    // MARK: - Status
    
    /// Get current persistence status
    func getStatus() -> PersistenceStatus {
        PersistenceStatus(
            isActive: autoSaveTimer != nil,
            hasUnsavedChanges: hasUnsavedChanges,
            lastSaveDate: lastSaveDate,
            queueCount: playback.queue.count,
            currentIndex: playback.currentQueueIndex
        )
    }
}

// MARK: - Status Types

struct PersistenceStatus {
    let isActive: Bool
    let hasUnsavedChanges: Bool
    let lastSaveDate: Date?
    let queueCount: Int
    let currentIndex: Int
    
    var description: String {
        """
        Queue Persistence Status:
        - Active: \(isActive)
        - Unsaved Changes: \(hasUnsavedChanges)
        - Last Save: \(lastSaveDate?.formatted() ?? "Never")
        - Queue Count: \(queueCount)
        - Current Index: \(currentIndex)
        """
    }
}

