//
//  EQManager.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Parametric EQ using BASS standard DSP
//

import Foundation
import Combine
import Bass
import GRDB

/// Manages parametric EQ using BASS DX8 DSP (built-in, no plugin required)
@MainActor
final class EQManager: ObservableObject {
    
    static let shared = EQManager()
    
    // MARK: - EQ Bands (8 control points)
    
    /// Frequency centers for each band (logarithmically spaced)
    static let frequencies: [Float] = [32, 64, 125, 250, 500, 1000, 4000, 16000]
    
    /// Current gain for each band (-12 to +12 dB)
    @Published var gains: [Float] = Array(repeating: 0, count: 8)
    
    /// EQ enabled state
    @Published var isEnabled: Bool = false {
        didSet { updateEQState() }
    }
    
    /// Current preset name
    @Published var currentPreset: String = "Flat"
    
    // MARK: - BASS DSP Handles
    
    private var eqHandles: [HFX] = []
    private var currentStream: HSTREAM = 0
    
    // MARK: - Presets
    
    static let presets: [String: [Float]] = [
        "Flat": [0, 0, 0, 0, 0, 0, 0, 0],
        "Bass Boost": [6, 5, 4, 2, 0, 0, 0, 0],
        "Treble Boost": [0, 0, 0, 0, 2, 4, 5, 6],
        "Vocal": [-2, -1, 0, 3, 4, 3, 0, -1],
        "Rock": [4, 3, 0, -1, 0, 2, 4, 5],
        "Jazz": [3, 2, 0, 2, 0, 2, 4, 3],
        "Classical": [0, 0, 0, 0, 0, -2, -3, -4],
        "Electronic": [5, 4, 1, 0, -1, 2, 3, 5],
        "Acoustic": [-2, 0, 2, 3, 3, 2, 3, 2]
    ]
    
    /// Custom presets loaded from database
    @Published var customPresets: [EQPresetRecord] = []
    
    private init() {
        loadCustomPresets()
    }
    
    // MARK: - Custom Preset Management
    
    func loadCustomPresets() {
        do {
            customPresets = try DatabaseManager.shared.read { db in
                try EQPresetRecord.fetchAll(db: db)
            }
        } catch {
            print("[EQManager] Failed to load custom presets: \(error)")
        }
    }
    
    func saveCurrentAsPreset(name: String) {
        let record = EQPresetRecord(name: name, gains: gains)
        
        do {
            try DatabaseManager.shared.write { db in
                try record.insert(db)
            }
            customPresets.append(record)
            currentPreset = name
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
                reset()
            }
        } catch {
            print("[EQManager] Failed to delete preset: \(error)")
        }
    }
    
    func applyCustomPreset(_ preset: EQPresetRecord) {
        gains = preset.getGains()
        currentPreset = preset.name
        
        if isEnabled {
            updateAllBands()
        }
    }
    
    // MARK: - Attach to Stream
    
    func attachToStream(_ stream: HSTREAM) {
        // Remove existing EQ
        removeEQ()
        
        currentStream = stream
        
        if isEnabled {
            applyEQ()
        }
    }
    
    // MARK: - EQ Control
    
    func setGain(band: Int, gain: Float) {
        guard band >= 0 && band < 8 else { return }
        gains[band] = max(-12, min(12, gain))
        currentPreset = "Custom"
        
        if isEnabled && band < eqHandles.count {
            updateBandGain(band: band)
        }
    }
    
    func applyPreset(_ name: String) {
        guard let preset = Self.presets[name] else {
            // Try custom presets
            if let custom = customPresets.first(where: { $0.name == name }) {
                applyCustomPreset(custom)
            }
            return
        }
        gains = preset
        currentPreset = name
        
        if isEnabled {
            updateAllBands()
        }
    }
    
    func reset() {
        applyPreset("Flat")
    }
    
    // MARK: - Private Methods
    
    private func updateEQState() {
        if isEnabled {
            applyEQ()
        } else {
            removeEQ()
        }
    }
    
    private func applyEQ() {
        guard currentStream != 0 else { return }
        
        removeEQ()
        
        // Create DX8 parametric EQ for each band
        for i in 0..<8 {
            let handle = BASS_ChannelSetFX(currentStream, DWORD(BASS_FX_DX8_PARAMEQ), 0)
            if handle != 0 {
                eqHandles.append(handle)
                
                // Set band parameters using DX8 PARAMEQ structure
                var eq = BASS_DX8_PARAMEQ()
                eq.fCenter = Self.frequencies[i]
                eq.fBandwidth = 12  // Semitones (1 octave roughly)
                eq.fGain = gains[i]
                
                BASS_FXSetParameters(handle, &eq)
            }
        }
    }
    
    private func removeEQ() {
        for handle in eqHandles {
            BASS_ChannelRemoveFX(currentStream, handle)
        }
        eqHandles.removeAll()
    }
    
    private func updateBandGain(band: Int) {
        guard band < eqHandles.count else { return }
        
        var eq = BASS_DX8_PARAMEQ()
        eq.fCenter = Self.frequencies[band]
        eq.fBandwidth = 12  // Semitones
        eq.fGain = gains[band]
        
        BASS_FXSetParameters(eqHandles[band], &eq)
    }
    
    private func updateAllBands() {
        for i in 0..<8 {
            updateBandGain(band: i)
        }
    }
}
