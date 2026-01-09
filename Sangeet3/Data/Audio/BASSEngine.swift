//
//  BASSEngine.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  BASS audio engine with audiophile features and DAC management
//

import Foundation
import Combine
import CoreAudio
import Bass

/// BASS audio engine with audiophile features
final class BASSEngine: ObservableObject {
    
    // MARK: - State
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    
    // MARK: - Volume
    @Published var volume: Float = 0.7 {
        didSet {
            applyVolume(volume)
            UserDefaults.standard.set(volume, forKey: "audioVolume")
        }
    }
    
    /// Apply volume directly to current stream
    func applyVolume(_ vol: Float) {
        let finalVol = vol * replayGainFactor
        guard currentStream != 0 else { return }
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), finalVol)
    }
    
    // MARK: - Audiophile Properties
    var replayGainFactor: Float = 1.0
    
    // MARK: - Dependencies
    private let dacManager = DACManager.shared
    
    // MARK: - Private
    private var currentStream: HSTREAM = 0
    private var nextStream: HSTREAM = 0
    private var dyingStream: HSTREAM = 0
    private var currentSync: HSYNC = 0  // Store sync handle to remove it later
    private var onTrackEnd: (() -> Void)?
    private var isInitialized = false
    
    // Global sync callback for slide cleanup
    private let slideSyncProc: @convention(c) (HSYNC, DWORD, DWORD, UnsafeMutableRawPointer?) -> Void = { handle, channel, data, user in
        var vol: Float = 0
        BASS_ChannelGetAttribute(channel, DWORD(BASS_ATTRIB_VOL), &vol)
        if vol <= 0.01 {
            BASS_StreamFree(channel)
        }
    }
    
    // MARK: - Singleton
    static let shared = BASSEngine()
    
    private init() {
        // Load saved volume
        let saved = UserDefaults.standard.float(forKey: "audioVolume")
        if saved > 0 {
            volume = saved
        }
        
        initializeBASSEngine()
        observeNotifications()
    }
    
    deinit {
        BASS_Free()
    }
    
    // MARK: - Engine Setup
    
    private func initializeBASSEngine() {
        // Always use a specific device number (never -1) matching the CoreAudio device
        let deviceNumber = findMatchingBASSDevice()
        let sampleRate = DWORD(dacManager.getCurrentDeviceSampleRate())
        
        // Pass 0 for flags
        let result = BASS_Init(deviceNumber, sampleRate, 0, nil, nil)
        
        if result == 0 {
            print("[BASSEngine] BASS initialization failed: \(BASS_ErrorGetCode())")
            isInitialized = false
            return
        }
        
        isInitialized = true
        print("[BASSEngine] BASS initialized on device \(deviceNumber) at \(sampleRate)Hz")
        
        BASS_SetConfig(DWORD(BASS_CONFIG_FLOATDSP), 1)
        
        // Network Buffering for smoother seeking
        // Set buffer to 15000ms (15 seconds) and read-ahead
        BASS_SetConfig(DWORD(BASS_CONFIG_NET_BUFFER), 15000)
        BASS_SetConfig(DWORD(BASS_CONFIG_NET_READTIMEOUT), 10000)
        BASS_SetConfig(DWORD(BASS_CONFIG_NET_PREBUF), 30) // Buffer 30% before starting
        print("[BASSEngine] Network buffer set to 15s")
    }
    
    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: .audioDeviceChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let device = notification.object as? AudioOutputDevice {
                self?.handleDeviceChange(to: device)
            }
        }
        
        // Settings changes (Hog Mode / Exclusive Access)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioSettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSettingsChange()
        }
        
        // Re-acquire device notification (from DACManager)
        NotificationCenter.default.addObserver(
            forName: .audioDeviceNeedsReacquisition,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDeviceReacquisition()
        }
    }
    
    private func handleSettingsChange() {
        let settings = getAudiophileSettings()
        
        // Handle Exclusive Access (Hog Mode)
        if settings.exclusiveAccess {
            if !dacManager.isInHogMode() {
                print("[BASSEngine] Enabling Exclusive Access (Hog Mode)")
                _ = dacManager.enableHogMode()
            }
        } else {
            if dacManager.isInHogMode() {
                print("[BASSEngine] Disabling Exclusive Access (Hog Mode)")
                dacManager.disableHogMode()
            }
        }
        
        // Check integer mode changes? (Requires stream recreation usually, handled on next track load)
    }
    
    private func handleDeviceReacquisition() {
        print("[BASSEngine] Re-acquiring device (Hog Mode triggered)")
        // Similar to handleDeviceChange, but just re-init on same device
        let deviceNumber = findMatchingBASSDevice()
        if deviceNumber != -1 {
            // Re-init logic if needed, or just move stream
            // Usually Hog Mode takes over the device, BASS might need a nudge
            BASS_SetDevice(DWORD(deviceNumber))
        }
    }
    
    /// Find the BASS device number that matches our CoreAudio device
    private func findMatchingBASSDevice() -> Int32 {
        guard let targetDeviceName = dacManager.getDeviceName() else {
            return -1
        }
        
        // Enumerate BASS devices
        var deviceInfo = BASS_DEVICEINFO()
        var deviceIndex: DWORD = 1 // Skip No Sound (0)
        
        while BASS_GetDeviceInfo(deviceIndex, &deviceInfo) != 0 {
            if let deviceName = deviceInfo.name {
                let bassDeviceName = String(cString: deviceName)
                
                // Check match
                let namesMatch = bassDeviceName == targetDeviceName ||
                                bassDeviceName.contains(targetDeviceName) ||
                                targetDeviceName.contains(bassDeviceName)
                
                if namesMatch && (deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED)) != 0 {
                    print("[BASSEngine] Found matching BASS device: \(deviceIndex) - \(bassDeviceName)")
                    return Int32(deviceIndex)
                }
            }
            deviceIndex += 1
        }
        
        // Fallback to default
        print("[BASSEngine] No matching BASS device found for '\(targetDeviceName)', using system default")
        return -1
    }
    
    private func findMatchingBASSDeviceForID(_ deviceID: AudioDeviceID) -> Int32 {
        guard let targetDeviceName = dacManager.getDeviceName() else { return -1 }
        
        // Logic identical to findMatchingBASSDevice but strictly for finding new device ID
        var deviceInfo = BASS_DEVICEINFO()
        var deviceIndex: DWORD = 1
        
        while BASS_GetDeviceInfo(deviceIndex, &deviceInfo) != 0 {
            if let deviceName = deviceInfo.name {
                let bassDeviceName = String(cString: deviceName)
                let namesMatch = bassDeviceName == targetDeviceName ||
                                bassDeviceName.contains(targetDeviceName) ||
                                targetDeviceName.contains(bassDeviceName)
                
                if namesMatch && (deviceInfo.flags & DWORD(BASS_DEVICE_ENABLED)) != 0 {
                    return Int32(deviceIndex)
                }
            }
            deviceIndex += 1
        }
        return -1
    }
    
    /// Handle audio device change - REPLICATING REFERENCE LOGIC
    private func handleDeviceChange(to device: AudioOutputDevice) {
        print("[BASSEngine] Handling device change to: \(device.name)")
        
        let newDeviceNumber = findMatchingBASSDevice() // Re-find based on current DACManager state
        guard newDeviceNumber != -1 else { return }
        
        let oldDeviceNumber = BASS_GetDevice()
        let wasPlaying = currentStream != 0 && isPlaying
        
        // Step 1: Initialize new device if needed
        var deviceInfo = BASS_DEVICEINFO()
        if BASS_GetDeviceInfo(DWORD(newDeviceNumber), &deviceInfo) != 0 {
            if deviceInfo.flags & DWORD(BASS_DEVICE_INIT) == 0 {
                let result = BASS_Init(newDeviceNumber, 44100, 0, nil, nil)
                if result == 0 {
                    print("[BASSEngine] Failed to init new device: \(BASS_ErrorGetCode())")
                    return
                }
            }
        }
        
        // Step 2: Move stream(s) to new device
        if currentStream != 0 {
            let result = BASS_ChannelSetDevice(currentStream, DWORD(newDeviceNumber))
            if result != 0 {
                print("[BASSEngine] Stream moved to new device")
                
                // Ensure output is started
                BASS_SetDevice(DWORD(newDeviceNumber))
                BASS_Start()
                
                if wasPlaying {
                    BASS_ChannelPlay(currentStream, 0)
                }
            } else {
                print("[BASSEngine] Stream move failed")
            }
        }
        
        // Step 3: Free old device
        if oldDeviceNumber != DWORD(newDeviceNumber) && oldDeviceNumber != DWORD(bitPattern: Int32.max) {
             // Must set context to old device to free it
             if BASS_SetDevice(oldDeviceNumber) != 0 {
                 BASS_Free()
                 print("[BASSEngine] Freed old device \(oldDeviceNumber)")
             }
        }
        
        // Restore new device context
        BASS_SetDevice(DWORD(newDeviceNumber))
        
        NotificationCenter.default.post(name: .audioDeviceChangeComplete, object: nil)
    }

    // MARK: - Initialization (Legacy method signature kept for compatibility)
    func initBASS() {
        // No-op if already initialized, logic is in init()
        if !isInitialized {
            initializeBASSEngine()
        }
    }
    
    // MARK: - Playback
    
    func load(url: URL, onEnd: @escaping () -> Void) throws {
        stop()
        self.onTrackEnd = onEnd
        
        // Create stream
        // Create stream
        if url.isFileURL {
            currentStream = BASS_StreamCreateFile(
                BOOL32(truncating: false),
                url.path,
                0,
                0,
                DWORD(BASS_STREAM_PRESCAN) | DWORD(BASS_SAMPLE_FLOAT)
            )
        } else {
            currentStream = BASS_StreamCreateURL(
                url.absoluteString,
                0,
                DWORD(BASS_STREAM_PRESCAN) | DWORD(BASS_SAMPLE_FLOAT),
                nil,
                nil
            )
        }
        
        if currentStream == 0 {
             throw NSError(domain: "BASSEngine", code: Int(BASS_ErrorGetCode()), userInfo: nil)
        }
        
        // Get duration
        let bytes = BASS_ChannelGetLength(currentStream, DWORD(BASS_POS_BYTE))
        duration = BASS_ChannelBytes2Seconds(currentStream, bytes)
        currentTime = 0
        
        // Apply volume
        let finalVol = volume * replayGainFactor
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), finalVol)
        
        // End sync
        currentSync = BASS_ChannelSetSync(currentStream, DWORD(BASS_SYNC_END), 0, { _, _, _, user in
            let engine = Unmanaged<BASSEngine>.fromOpaque(user!).takeUnretainedValue()
            engine.isPlaying = false
            engine.onTrackEnd?()
        }, Unmanaged.passUnretained(self).toOpaque())
        
        print("[BASSEngine] Loaded: \(url.lastPathComponent)")
        
        // Attach EQ if not bit-perfect
        let settings = getAudiophileSettings()
        if !settings.bitPerfect {
            Task { @MainActor in
                EQManager.shared.attachToStream(self.currentStream)
            }
        }
    }
    
    // MARK: - Stream Creation
    
    private func createStream(url: URL) -> HSTREAM {
        let settings = getAudiophileSettings()
        
        // Build flags
        var flags: DWORD = DWORD(BASS_STREAM_PRESCAN)
        
        // Float or integer mode
        if !settings.integerMode {
            flags |= DWORD(BASS_SAMPLE_FLOAT)
        }
        
        // Create stream
        let stream: HSTREAM
        
        if url.isFileURL {
            stream = BASS_StreamCreateFile(
                BOOL32(truncating: false),
                url.path,
                0,
                0,
                flags
            )
        } else {
            // Remote URL
            // Ensure flags don't include PRESCAN if it causes issues, but for now keep consistent
            // BASS_StreamCreateURL takes (url, offset, flags, proc, user)
            stream = BASS_StreamCreateURL(
                url.absoluteString,
                0,
                flags,
                nil,
                nil
            )
        }
        
        return stream
    }
    
    // MARK: - Legacy / Helpers
    
    private func getAudiophileSettings() -> (exclusiveAccess: Bool, nativeSampleRate: Bool, integerMode: Bool, bitPerfect: Bool) {
        let defaults = UserDefaults.standard
        return (
            exclusiveAccess: defaults.bool(forKey: "exclusiveAudioAccess"),
            nativeSampleRate: defaults.bool(forKey: "nativeSampleRate"),
            integerMode: defaults.bool(forKey: "integerOutputMode"),
            bitPerfect: defaults.bool(forKey: "bitPerfectOutput")
        )
    }
    
    // MARK: - Gapless Preloading
    
    func preloadNext(url: URL) {
        // Free any existing preloaded stream
        if nextStream != 0 {
            BASS_StreamFree(nextStream)
        }
        
        nextStream = createStream(url: url)
        if nextStream != 0 {
            print("[BASSEngine] Preloaded next: \(url.lastPathComponent)")
        }
    }
    
    func switchToPreloaded(onEnd: @escaping () -> Void) -> Bool {
        guard nextStream != 0 else { return false }
        
        // Stop current
        if currentStream != 0 {
            BASS_StreamFree(currentStream)
        }
        
        // Use preloaded
        currentStream = nextStream
        nextStream = 0
        
        self.onTrackEnd = onEnd
        
        // Setup new stream
        let bytes = BASS_ChannelGetLength(currentStream, DWORD(BASS_POS_BYTE))
        duration = BASS_ChannelBytes2Seconds(currentStream, bytes)
        currentTime = 0
        
        BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), volume * replayGainFactor)
        
        // End sync
        BASS_ChannelSetSync(
            currentStream,
            DWORD(BASS_SYNC_END),
            0,
            { _, _, _, user in
                let engine = Unmanaged<BASSEngine>.fromOpaque(user!).takeUnretainedValue()
                engine.isPlaying = false
                engine.onTrackEnd?()
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        
        // Attach EQ if not bit-perfect
        let settings = getAudiophileSettings()
        if !settings.bitPerfect {
            Task { @MainActor in
                EQManager.shared.attachToStream(self.currentStream)
            }
        }
        
        return true
    }
    
    // MARK: - TRUE Crossfade ("The Kill Switch" Strategy)
    
    /// TRUE crossfade: Load new track, efficiently managing old/dying streams to prevent overlap
    /// Implements "The Kill Switch" strategy for rapid skipping
    func crossfadeLoad(url: URL, duration: TimeInterval, onEnd: @escaping () -> Void) throws {
        print("[BASSEngine] Crossfade: Starting Kill Switch crossfade (\(duration)s)")
        
        let fadeDuration = DWORD(duration * 1000)
        
        // ---------------------------------------------------------
        // 1. CLEANUP PHASE (The Fix for Spamming)
        // ---------------------------------------------------------
        
        // If there is a song already fading out (dying), kill it instantly.
        if dyingStream != 0 {
            BASS_StreamFree(dyingStream)
            dyingStream = 0
        }
        
        // Check active stream (currentStream)
        if currentStream != 0 {
            var currentVol: Float = 0
            BASS_ChannelGetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), &currentVol)
            
            // SPAM LOGIC: If current song is barely audible (< 10%), kill it instantly
            if currentVol < 0.1 {
                BASS_StreamFree(currentStream)
                currentStream = 0
            } else {
                // Otherwise, this becomes the dying stream
                dyingStream = currentStream
                
                // CRITIAL FIX: Remove the "Track End" sync from the dying stream.
                // We don't want it to trigger onTrackEnd() when it finishes fading,
                // because we have already moved to the next song.
                if currentSync != 0 {
                    BASS_ChannelRemoveSync(dyingStream, currentSync)
                    currentSync = 0
                }
                
                // Slide volume to 0
                BASS_ChannelSlideAttribute(dyingStream, DWORD(BASS_ATTRIB_VOL), 0.0, fadeDuration)
                
                // Register sync to free stream when slide finishes
                BASS_ChannelSetSync(dyingStream, DWORD(BASS_SYNC_SLIDE), 0, slideSyncProc, nil)
            }
        }
        
        // ---------------------------------------------------------
        // 2. STARTUP PHASE
        // ---------------------------------------------------------
        
        // createStream already handles settings (float/integer)
        let newStream = createStream(url: url)
        
        if newStream == 0 {
             throw NSError(domain: "BASSEngine", code: Int(BASS_ErrorGetCode()), userInfo: nil)
        }
        
        currentStream = newStream
        self.onTrackEnd = onEnd
        
        // Get duration
        let bytes = BASS_ChannelGetLength(newStream, DWORD(BASS_POS_BYTE))
        self.duration = BASS_ChannelBytes2Seconds(newStream, bytes)
        currentTime = 0
        
        // Start Silent
        BASS_ChannelSetAttribute(newStream, DWORD(BASS_ATTRIB_VOL), 0.0)
        
        // Start Playing
        BASS_ChannelPlay(newStream, BOOL32(truncating: true)) // Restart=True
        
        // Slide Volume to Target
        let targetVolume = volume * replayGainFactor
        BASS_ChannelSlideAttribute(newStream, DWORD(BASS_ATTRIB_VOL), targetVolume, fadeDuration)
        
        // Setup end sync (Track End)
        currentSync = BASS_ChannelSetSync(newStream, DWORD(BASS_SYNC_END), 0, { _, _, _, user in
            let engine = Unmanaged<BASSEngine>.fromOpaque(user!).takeUnretainedValue()
            engine.isPlaying = false
            engine.onTrackEnd?()
        }, Unmanaged.passUnretained(self).toOpaque())
        
        // Attach EQ if not bit-perfect
        let settings = getAudiophileSettings()
        if !settings.bitPerfect {
            Task { @MainActor in
                EQManager.shared.attachToStream(newStream)
            }
        }
        
        isPlaying = true
        print("[BASSEngine] Crossfade: New stream started, fading in...")
    }
    

    
    // MARK: - ReplayGain
    
    func setReplayGain(db: Float?) {
        if let db = db {
            // Convert dB to linear: 10^(dB/20)
            replayGainFactor = pow(10, db / 20.0)
        } else {
            replayGainFactor = 1.0
        }
        
        // Apply immediately
        if currentStream != 0 {
            BASS_ChannelSetAttribute(currentStream, DWORD(BASS_ATTRIB_VOL), volume * replayGainFactor)
        }
    }
    
    // MARK: - Basic Controls
    
    func play() {
        guard currentStream != 0 else { return }
        
        if BASS_ChannelPlay(currentStream, BOOL32(truncating: false)) == 0 {
            print("[BASSEngine] Play failed: \(BASS_ErrorGetCode())")
        } else {
            isPlaying = true
        }
    }
    
    func pause() {
        guard currentStream != 0 else { return }
        BASS_ChannelPause(currentStream)
        isPlaying = false
    }
    
    func stop() {
        // No timer to invalidate anymore
        
        if currentStream != 0 {
            BASS_ChannelStop(currentStream)
            BASS_StreamFree(currentStream)
            currentStream = 0
        }
        if dyingStream != 0 {
            BASS_StreamFree(dyingStream)
            dyingStream = 0
        }
        if nextStream != 0 {
            BASS_StreamFree(nextStream)
            nextStream = 0
        }
        isPlaying = false
        currentTime = 0
        duration = 0
        replayGainFactor = 1.0
    }
    
    func seek(to time: TimeInterval) {
        guard currentStream != 0 else { return }
        
        let position = BASS_ChannelSeconds2Bytes(currentStream, time)
        BASS_ChannelSetPosition(currentStream, position, DWORD(BASS_POS_BYTE))
        currentTime = time
    }
    
    func updateCurrentTime() {
        guard currentStream != 0 else { return }
        
        let bytes = BASS_ChannelGetPosition(currentStream, DWORD(BASS_POS_BYTE))
        if bytes != QWORD(bitPattern: -1) {
            currentTime = BASS_ChannelBytes2Seconds(currentStream, bytes)
        }
    }
    
    // MARK: - Sample Rate Info
    
    func getSourceSampleRate() -> Double {
        guard currentStream != 0 else { return 0 }
        var freq: Float = 0
        BASS_ChannelGetAttribute(currentStream, DWORD(BASS_ATTRIB_FREQ), &freq)
        return Double(freq)
    }
    
    /// Get current active stream (for EQ attachment)
    func getCurrentStream() -> HSTREAM {
        return currentStream
    }
}

