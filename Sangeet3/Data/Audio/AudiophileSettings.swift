//
//  AudiophileSettings.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Central settings for audiophile audio features
//

import Foundation
import Combine

/// Manages all audiophile audio settings
@MainActor
final class AudiophileSettings: ObservableObject {
    
    static let shared = AudiophileSettings()
    
    // MARK: - Seamless Playback (Gapless)
    @Published var seamlessPlayback: Bool {
        didSet { UserDefaults.standard.set(seamlessPlayback, forKey: "seamlessPlayback") }
    }
    
    // MARK: - Track Crossfade
    @Published var crossfadeEnabled: Bool {
        didSet { UserDefaults.standard.set(crossfadeEnabled, forKey: "crossfadeEnabled") }
    }
    @Published var crossfadeDuration: Double {  // seconds
        didSet { UserDefaults.standard.set(crossfadeDuration, forKey: "crossfadeDuration") }
    }
    
    // MARK: - Exclusive Audio Access (Hog Mode)
    @Published var exclusiveAudioAccess: Bool {
        didSet {
            UserDefaults.standard.set(exclusiveAudioAccess, forKey: "exclusiveAudioAccess")
            NotificationCenter.default.post(name: .audioSettingsChanged, object: nil)
            print("[AudiophileSettings] Exclusive access toggled: \(exclusiveAudioAccess)")
        }
    }
    
    // MARK: - Native Sample Rate
    @Published var nativeSampleRate: Bool {
        didSet {
            UserDefaults.standard.set(nativeSampleRate, forKey: "nativeSampleRate")
            NotificationCenter.default.post(name: .audioSettingsChanged, object: nil)
        }
    }
    
    // MARK: - Bit-Perfect Output
    @Published var bitPerfectOutput: Bool {
        didSet {
            UserDefaults.standard.set(bitPerfectOutput, forKey: "bitPerfectOutput")
            NotificationCenter.default.post(name: .audioSettingsChanged, object: nil)
        }
    }
    
    // MARK: - Volume Normalization (ReplayGain)
    @Published var volumeNormalization: Bool {
        didSet { UserDefaults.standard.set(volumeNormalization, forKey: "volumeNormalization") }
    }
    
    // MARK: - Integer Output Mode
    @Published var integerOutputMode: Bool {
        didSet {
            UserDefaults.standard.set(integerOutputMode, forKey: "integerOutputMode")
            NotificationCenter.default.post(name: .audioSettingsChanged, object: nil)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load saved preferences with defaults
        let defaults = UserDefaults.standard
        
        _seamlessPlayback = Published(initialValue: defaults.bool(forKey: "seamlessPlayback"))
        _crossfadeEnabled = Published(initialValue: defaults.bool(forKey: "crossfadeEnabled"))
        
        let savedDuration = defaults.double(forKey: "crossfadeDuration")
        _crossfadeDuration = Published(initialValue: savedDuration > 0 ? savedDuration : 3.0)
        
        _exclusiveAudioAccess = Published(initialValue: defaults.bool(forKey: "exclusiveAudioAccess"))
        _nativeSampleRate = Published(initialValue: defaults.bool(forKey: "nativeSampleRate"))
        _bitPerfectOutput = Published(initialValue: defaults.bool(forKey: "bitPerfectOutput"))
        _volumeNormalization = Published(initialValue: defaults.bool(forKey: "volumeNormalization"))
        _integerOutputMode = Published(initialValue: defaults.bool(forKey: "integerOutputMode"))
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let audioSettingsChanged = Notification.Name("audioSettingsChanged")
    static let playlistUpdated = Notification.Name("playlistUpdated")
    static let createPlaylistRequested = Notification.Name("createPlaylistRequested")
}
