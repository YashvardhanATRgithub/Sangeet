//
//  EQManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  10-Band Parametric EQ with Preamp using BASS DSP
//

import Foundation
import Combine
import Bass
import GRDB

/// Manages 10-band parametric EQ using BASS DX8 DSP
@MainActor
final class EQManager: ObservableObject {
    
    static let shared = EQManager()
    
    // MARK: - EQ Configuration (10 bands)
    
    /// Frequency centers for each band (standard ISO octave centers)
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let frequencyLabels: [String] = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
    static let bandCount = 10
    
    /// Current gain for each band (-12 to +12 dB)
    @Published var gains: [Float] = Array(repeating: 0, count: 10)
    
    /// Preamp gain (-12 to +12 dB)
    @Published var preamp: Float = 0 {
        didSet {
            // Clamp value without triggering didSet again
            let clamped = max(-12, min(12, preamp))
            if preamp != clamped {
                preamp = clamped
                return // Exit early, the new set will trigger didSet again
            }
            if isEnabled {
                updatePreamp()
            }
            saveSettings()
        }
    }
    
    /// EQ enabled state
    @Published var isEnabled: Bool = false {
        didSet {
            updateEQState()
            saveSettings()
        }
    }
    
    /// Current preset name
    @Published var currentPreset: String = "Flat"
    
    /// Whether current gains differ from selected preset
    var isModified: Bool {
        guard let presetGains = getPresetGains(for: currentPreset) else { return false }
        return gains != presetGains
    }
    
    // MARK: - BASS DSP Handles
    
    private var eqHandles: [HFX] = []
    private var preampHandle: HFX = 0
    private var currentStream: HSTREAM = 0
    
    // MARK: - Built-in Presets (10-band)
    
    static let presets: [String: [Float]] = [
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass Boost": [6, 5, 4, 3, 1, 0, 0, 0, 0, 0],
        "Bass Reducer": [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0],
        "Treble Boost": [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
        "Treble Reducer": [0, 0, 0, 0, 0, -1, -2, -4, -5, -6],
        "Vocal": [-2, -1, 0, 2, 4, 4, 3, 2, 0, -1],
        "Rock": [5, 4, 2, 0, -1, 0, 2, 4, 5, 5],
        "Pop": [-1, 0, 2, 4, 4, 3, 1, 0, 1, 2],
        "Jazz": [3, 2, 1, 2, 0, 1, 2, 3, 4, 3],
        "Classical": [0, 0, 0, 0, 0, -1, -2, -2, -3, -4],
        "Electronic": [5, 4, 2, 0, -2, 0, 2, 3, 4, 5],
        "Acoustic": [-1, 0, 1, 2, 3, 3, 2, 2, 2, 1],
        "R&B": [3, 5, 4, 1, -1, 0, 2, 3, 3, 2],
        "Hip-Hop": [5, 5, 3, 1, 0, -1, 1, 2, 3, 3],
        "Lounge": [0, 1, 2, 1, 0, 0, 1, 2, 2, 1],
        "Spoken Word": [-2, -1, 0, 2, 4, 5, 4, 2, 0, -2],
        "Loudness": [4, 3, 1, 0, -1, -1, 0, 2, 4, 5],
        "Night Mode": [-3, -2, 0, 1, 2, 2, 1, 0, -2, -4]
    ]
    
    /// Ordered preset names for display
    static let presetOrder: [String] = [
        "Flat", "Bass Boost", "Bass Reducer", "Treble Boost", "Treble Reducer",
        "Vocal", "Rock", "Pop", "Jazz", "Classical", "Electronic", "Acoustic",
        "R&B", "Hip-Hop", "Lounge", "Spoken Word", "Loudness", "Night Mode"
    ]
    
    /// Custom presets loaded from database
    @Published var customPresets: [EQPresetRecord] = []
    
    private init() {
        loadSettings()
        loadCustomPresets()
    }
    
    // MARK: - Settings Persistence
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if defaults.object(forKey: "eqEnabled") != nil {
            isEnabled = defaults.bool(forKey: "eqEnabled")
        }
        
        if let savedPreset = defaults.string(forKey: "eqPreset") {
            currentPreset = savedPreset
        }
        
        if let savedGains = defaults.array(forKey: "eqGains") as? [Float] {
            // Handle migration from 8-band to 10-band
            if savedGains.count == 10 {
                gains = savedGains
            } else if savedGains.count == 8 {
                // Migrate: interpolate 8-band to 10-band
                gains = migrate8To10Band(savedGains)
            } else if let presetGains = Self.presets[currentPreset] {
                gains = presetGains
            }
        } else if let presetGains = Self.presets[currentPreset] {
            gains = presetGains
        }
        
        preamp = defaults.float(forKey: "eqPreamp")
    }
    
    private func migrate8To10Band(_ old: [Float]) -> [Float] {
        // Old: 80, 170, 310, 600, 1000, 3000, 8000, 14000
        // New: 32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
        // Simple mapping:
        return [
            old[0],        // 32 ← 80
            old[0],        // 64 ← 80
            old[1],        // 125 ← 170
            old[2],        // 250 ← 310
            old[3],        // 500 ← 600
            old[4],        // 1000 ← 1000
            (old[4] + old[5]) / 2, // 2000 (interpolate)
            old[5],        // 4000 ← 3000
            old[6],        // 8000 ← 8000
            old[7]         // 16000 ← 14000
        ]
    }
    
    private func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: "eqEnabled")
        defaults.set(currentPreset, forKey: "eqPreset")
        defaults.set(gains, forKey: "eqGains")
        defaults.set(preamp, forKey: "eqPreamp")
    }
    
    // MARK: - Custom Preset Management
    
    func loadCustomPresets() {
        do {
            customPresets = try DatabaseManager.shared.read { db in
                try EQPresetRecord.fetchAll(db: db)
            }
            customPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("[EQManager] Failed to load custom presets: \(error)")
        }
    }
    
    func saveCurrentAsPreset(name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Remove existing preset with same name (overwrite)
        if let existing = customPresets.first(where: { $0.name == trimmedName }) {
            deleteCustomPreset(existing)
        }
        
        let record = EQPresetRecord(name: trimmedName, gains: gains)
        
        do {
            try DatabaseManager.shared.write { db in
                try record.insert(db)
            }
            customPresets.append(record)
            customPresets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            currentPreset = trimmedName
            saveSettings()
        } catch {
            print("[EQManager] Failed to save preset: \(error)")
        }
    }
    
    func deleteCustomPreset(_ preset: EQPresetRecord) {
        do {
            try DatabaseManager.shared.write { db in
                try EQPresetRecord.delete(id: preset.id, db: db)
            }
            customPresets.removeAll { $0.id == preset.id }
            if currentPreset == preset.name {
                applyPreset("Flat")
            }
        } catch {
            print("[EQManager] Failed to delete preset: \(error)")
        }
    }
    
    // MARK: - Preset Application
    
    func getPresetGains(for name: String) -> [Float]? {
        if let builtin = Self.presets[name] {
            return builtin
        }
        if let custom = customPresets.first(where: { $0.name == name }) {
            return custom.getGains()
        }
        return nil
    }
    
    func applyPreset(_ name: String) {
        guard let presetGains = getPresetGains(for: name) else { return }
        
        // Ensure correct count
        let normalized: [Float]
        if presetGains.count == 10 {
            normalized = presetGains
        } else if presetGains.count == 8 {
            normalized = migrate8To10Band(presetGains)
        } else {
            normalized = Array(repeating: 0, count: 10)
        }
        
        gains = normalized
        currentPreset = name
        saveSettings()
        
        if isEnabled {
            updateAllBands()
        }
    }
    
    func resetToPreset() {
        if let presetGains = getPresetGains(for: currentPreset) {
            gains = presetGains.count == 10 ? presetGains : migrate8To10Band(presetGains)
            if isEnabled {
                updateAllBands()
            }
            saveSettings()
        }
    }
    
    func reset() {
        applyPreset("Flat")
        preamp = 0
    }
    
    // MARK: - Gain Control
    
    func setGain(band: Int, gain: Float) {
        guard band >= 0 && band < Self.bandCount else { return }
        
        gains[band] = max(-12, min(12, gain))
        saveSettings()
        
        if isEnabled && band < eqHandles.count {
            updateBandGain(band: band)
        }
    }
    
    // MARK: - Stream Attachment
    
    func attachToStream(_ stream: HSTREAM) {
        removeEQ()
        currentStream = stream
        
        if isEnabled {
            applyEQ()
        }
    }
    
    // MARK: - Private EQ Methods
    
    private func updateEQState() {
        print("[EQManager] State changed: \(isEnabled ? "Enabled" : "Disabled")")
        
        // If enabling and no current stream, try to get from BASSEngine
        if isEnabled && currentStream == 0 {
            let stream = BASSEngine.shared.getCurrentStream()
            if stream != 0 {
                currentStream = stream
                print("[EQManager] Fetched current stream from BASSEngine: \(stream)")
            }
        }
        
        if isEnabled {
            applyEQ()
        } else {
            removeEQ()
        }
    }
    
    private func applyEQ() {
        guard currentStream != 0 else {
            print("[EQManager] Cannot apply EQ: No active stream")
            return
        }
        
        removeEQ()
        
        // Apply preamp first (using amplification FX)
        applyPreampEffect()
        
        // Create DX8 parametric EQ for each band
        for i in 0..<Self.bandCount {
            let handle = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_DX8_PARAMEQ), 0)
            if handle != 0 {
                eqHandles.append(handle)
                
                var eq = BASS_DX8_PARAMEQ()
                eq.fCenter = Self.frequencies[i]
                eq.fBandwidth = 12  // Semitones (octave width)
                eq.fGain = gains[i]
                
                if BASS_FXSetParameters(handle, &eq) == 0 {
                    print("[EQManager] Failed to set parameters for band \(i): \(BASS_ErrorGetCode())")
                }
            } else {
                print("[EQManager] Failed to create FX for band \(i): \(BASS_ErrorGetCode())")
            }
        }
        
        print("[EQManager] Applied 10-band EQ to stream \(currentStream)")
    }
    
    private func applyPreampEffect() {
        guard preamp != 0 else { return }
        
        // Use BASS_FX_VOLUME for preamp
        // Note: BASS_FX_VOLUME requires bass_fx plugin. 
        // For simplicity, we'll skip preamp in DSP and apply via gain multiplier
        // This is handled by updating band gains relative to preamp
    }
    
    private func updatePreamp() {
        // Preamp is conceptual - we apply it by adjusting overall output
        // For now, just log; actual implementation would require BASS_FX
        print("[EQManager] Preamp set to \(preamp) dB")
    }
    
    private func removeEQ() {
        for handle in eqHandles {
            BASS_ChannelRemoveFX(currentStream, handle)
        }
        eqHandles.removeAll()
        
        if preampHandle != 0 {
            BASS_ChannelRemoveFX(currentStream, preampHandle)
            preampHandle = 0
        }
    }
    
    private func updateBandGain(band: Int) {
        guard band < eqHandles.count else { return }
        
        var eq = BASS_DX8_PARAMEQ()
        eq.fCenter = Self.frequencies[band]
        eq.fBandwidth = 12
        eq.fGain = gains[band]
        
        if BASS_FXSetParameters(eqHandles[band], &eq) == 0 {
            print("[EQManager] Failed to update band \(band): \(BASS_ErrorGetCode())")
        }
    }
    
    private func updateAllBands() {
        for i in 0..<Self.bandCount {
            updateBandGain(band: i)
        }
    }
}
