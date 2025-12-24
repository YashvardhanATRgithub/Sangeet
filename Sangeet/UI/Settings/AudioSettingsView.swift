//
//  AudioSettingsView.swift
//  Sangeet
//
// Ported from HiFidelity
//

import SwiftUI

struct AudioSettingsView: View {
    @ObservedObject var settings = AudioSettings.shared
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @ObservedObject var replayGainSettings = ReplayGainSettings.shared
    @ObservedObject var r128Scanner = R128LoudnessScanner.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Output Device
            settingsSection(title: "Output Device", icon: "speaker.wave.3") {
                deviceSettings
            }
            
            Divider()

            // Audio Effects
            settingsSection(title: "Audio Effects", icon: "waveform.badge.magnifyingglass") {
                effectsSettings
            }
            
            Divider()
            
            // ReplayGain
            settingsSection(title: "ReplayGain", icon: "waveform.path.ecg") {
                replayGainSettingsView
            }
            
            Divider()
            
            // Audio Quality
            settingsSection(title: "Audio Quality", icon: "waveform") {
                qualitySettings
            }
            
            Divider()
            
            // Reset Button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                    replayGainSettings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Settings Sections
    
    private var effectsSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Reverb Toggle
            settingRow(
                label: "Reverb",
                description: "Add spatial depth and ambience to audio"
            ) {
                Toggle("", isOn: Binding(
                    get: { effectsManager.isReverbEnabled },
                    set: { effectsManager.setReverbEnabled($0) }
                ))
                .toggleStyle(.switch)
            }
            
            // Reverb Mix
            if effectsManager.isReverbEnabled {
            settingRow(
                    label: "Reverb Mix",
                    description: "Amount of reverb effect to apply"
            ) {
                HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(effectsManager.reverbMix) },
                            set: { effectsManager.setReverbMix(Float($0)) }
                        ), in: -96...0, step: 1)
                        .frame(width: 150)
                    
                        Text("\(Int(effectsManager.reverbMix)) dB")
                            .frame(width: 60, alignment: .trailing)
                        .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }
    
    private var replayGainSettingsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ReplayGain Toggle
            settingRow(
                label: "Enable ReplayGain",
                description: "Automatically normalize volume across tracks"
            ) {
                Toggle("", isOn: $replayGainSettings.isEnabled)
                    .toggleStyle(.switch)
            }
            
            // Mode & Source Pickers
            if replayGainSettings.isEnabled {
                settingRow(
                    label: "Mode",
                    description: replayGainSettings.mode.description
                ) {
                    Picker("", selection: $replayGainSettings.mode) {
                        ForEach(ReplayGainMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .frame(width: 150)
                }
                
                settingRow(
                    label: "Source",
                    description: replayGainSettings.source.description
                ) {
                    Picker("", selection: $replayGainSettings.source) {
                        ForEach(LoudnessSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .frame(width: 220)
                }
                
                // R128 Loudness Analysis
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Loudness Analysis")
                                .font(.system(size: 13, weight: .medium))
                            Text("Scan your library to calculate EBU R128 loudness for accurate normalization")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if r128Scanner.isScanning {
                            Button("Cancel") {
                                r128Scanner.cancelScan()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Scan Library") {
                                r128Scanner.scanLibrary()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    // Progress indicator
                    if r128Scanner.isScanning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ProgressView(value: r128Scanner.progress)
                                    .frame(maxWidth: .infinity)
                                
                                Text("\(r128Scanner.scannedCount)/\(r128Scanner.totalCount)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                            
                            if let currentTrack = r128Scanner.currentTrack {
                                Text("Analyzing: \(currentTrack.title)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
    
    private var qualitySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Buffer Length
            settingRow(
                label: "Audio Buffer",
                description: "Larger buffer = more stable, but higher latency"
            ) {
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { Double(settings.bufferLength) },
                        set: { settings.bufferLength = Int($0) }
                    ), in: 100...2000, step: 100)
                    .frame(width: 150)
                    
                    Text("\(settings.bufferLength) ms")
                        .frame(width: 70, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var deviceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Synchronize Sample Rate
            settingRow(
                label: "Synchronize Sample Rate with Music Player (Hog mode)",
                description: "Enable exclusive audio access for bit-perfect playback"
            ) {
                Toggle("", isOn: $settings.synchronizeSampleRate)
                    .toggleStyle(.switch)
            }
            
            // Info text when enabled
            if settings.synchronizeSampleRate {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                    
                    Text("When enabled, the app takes exclusive control (hog mode) of your audio device and automatically switches the device sample rate to match each track (44.1kHz, 48kHz, 96kHz, etc.) preventing BASS from resampling for true bit-perfect playback.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                
                Text(title)
                    .font(.headline)
            }
            content()
        }
    }
    
    private func settingRow<Content: View>(
        label: String,
        description: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        SettingRow(label: label, description: description, control: content)
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    let description: String?
    let control: Content
    
    init(label: String, description: String? = nil, @ViewBuilder control: () -> Content) {
        self.label = label
        self.description = description
        self.control = control()
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control
        }
    }
}

struct SettingInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
        }
    }
}
