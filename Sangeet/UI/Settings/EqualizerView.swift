import SwiftUI

struct EqualizerView: View {
    @ObservedObject var effectsManager = AudioEffectsManager.shared
    @State private var showSavePresetDialog = false
    @State private var newPresetName = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var presetToDelete: CustomEQPreset?
    
    // 10 bands
    private let frequencies = ["32 Hz", "64 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
    
    private var isCustomMode: Bool {
        effectsManager.currentPresetType == .userModified
    }
    
    private var displayPresetName: String {
        effectsManager.currentPresetName
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Control Bar
            controlBar
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            
            Divider()
            
            if effectsManager.isEqualizerEnabled {
                equalizerContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
            } else {
                disabledState
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Theme.background)
        .sheet(isPresented: $showSavePresetDialog) {
            savePresetDialog
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Preset Manager"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    // MARK: - Save Preset Dialog
    private var savePresetDialog: some View {
        VStack(spacing: 20) {
            Text("Save Custom Preset")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Enter a name for your custom equalizer preset")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            TextField("Preset Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    showSavePresetDialog = false
                    newPresetName = ""
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Save") {
                    if newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        alertMessage = "Please enter a valid preset name"
                        showAlert = true
                    } else if effectsManager.saveCustomPreset(name: newPresetName) {
                        showSavePresetDialog = false
                        newPresetName = ""
                        alertMessage = "Preset saved successfully!"
                        showAlert = true
                    } else {
                        alertMessage = "A preset with this name already exists"
                        showAlert = true
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(30)
        .frame(width: 400)
    }
    
    // MARK: - Control Bar
    private var controlBar: some View {
        HStack(spacing: 20) {
            // Power Switch
            HStack(spacing: 8) {
                Text("Power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                Toggle("", isOn: $effectsManager.isEqualizerEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: effectsManager.isEqualizerEnabled) { _, enabled in
                        effectsManager.setEqualizerEnabled(enabled)
                    }
            }
            
            // Actions
            HStack(spacing: 12) {
                if isCustomMode && effectsManager.isEqualizerEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 11))
                        Text("Custom")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Theme.accent.opacity(0.15))
                    )
                }
                
                Button(action: {
                    showSavePresetDialog = true
                    newPresetName = ""
                }) {
                    Label("Save Preset", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .disabled(!effectsManager.isEqualizerEnabled)
                
                if effectsManager.currentPresetType == .custom {
                    Button(action: {
                         if let preset = effectsManager.customPresets.first(where: { $0.name == effectsManager.currentPresetName }) {
                            // Simple delete processing
                            effectsManager.deleteCustomPreset(preset)
                            alertMessage = "Preset '\(preset.name)' deleted"
                            showAlert = true
                         }
                    }) {
                        Label("Delete Preset", systemImage: "trash")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(!effectsManager.isEqualizerEnabled)
                }
                
                Button(action: { effectsManager.resetEqualizer() }) {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
                .disabled(!effectsManager.isEqualizerEnabled)
            }
            
            Spacer()
            
            // Preset Selector
            HStack(spacing: 8) {
                Text("Preset")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                
                Menu {
                    ForEach(EQPreset.allCases) { preset in
                        Button(action: { applyEQPreset(preset) }) {
                            HStack {
                                Text(preset.name)
                                if effectsManager.currentPresetType == .builtin && effectsManager.currentPresetName == preset.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    
                    if !effectsManager.customPresets.isEmpty {
                        Divider()
                        Section(header: Text("My Presets")) {
                            ForEach(effectsManager.customPresets) { preset in
                                Button(action: { applyCustomPreset(preset) }) {
                                    HStack {
                                        Text(preset.name)
                                        if effectsManager.currentPresetType == .custom && effectsManager.currentPresetName == preset.name {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(displayPresetName)
                            .font(.system(size: 13))
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 180, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.separator, lineWidth: 0.5)
                    )
                }
                .disabled(!effectsManager.isEqualizerEnabled)
                .menuStyle(.borderlessButton)
            }
        }
    }
    
    // MARK: - Equalizer Content
    private var equalizerContent: some View {
        HStack(alignment: .center, spacing: 0) {
            // Preamp
            VStack(spacing: 0) {
                EQSlider(
                    value: $effectsManager.preampGain,
                    range: -12...12,
                    label: "Preamp",
                    isPreamp: true,
                    accentColor: Theme.accent
                )
                .frame(width: 60)
                
                Text("Master")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.top, 8)
            }
            .padding(.trailing, 32)
            
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
                .padding(.vertical, 20)
                .padding(.trailing, 32)
            
            // Bands
            HStack(alignment: .center, spacing: 16) {
                ForEach(0..<10) { index in
                    EQSlider(
                        value: Binding(
                            get: { Double(effectsManager.equalizerBands[index]) },
                            set: { effectsManager.setEqualizerBand(index, gain: Float($0)) }
                        ),
                        range: -12...12,
                        label: frequencies[index],
                        isPreamp: false,
                        accentColor: Theme.accent
                    )
                    .frame(width: 50)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var disabledState: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("Equalizer Disabled")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("Enable the equalizer to adjust frequency response")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func applyEQPreset(_ preset: EQPreset) {
        effectsManager.isEqualizerEnabled = true
        effectsManager.setEqualizerEnabled(true)
        effectsManager.applyBuiltinPreset(name: preset.name, bands: preset.bandValues)
    }
    
    private func applyCustomPreset(_ preset: CustomEQPreset) {
        effectsManager.isEqualizerEnabled = true
        effectsManager.setEqualizerEnabled(true)
        effectsManager.loadCustomPreset(preset)
    }
}

// MARK: - EQ Slider
struct EQSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    let isPreamp: Bool
    let accentColor: Color
    
    @State private var isHovering = false
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: isPreamp ? 12 : 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.bottom, 12)
            
            Text(formattedValue)
                .font(.system(size: isPreamp ? 14 : 12, weight: .semibold, design: .monospaced))
                .foregroundColor(value != 0 ? accentColor : .secondary)
                .frame(height: 20)
                .padding(.bottom, 8)
            
            GeometryReader { geometry in
                ZStack(alignment: .center) {
                    // Track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.separator.opacity(0.5))
                        .frame(width: isPreamp ? 6 : 5)
                    
                    let centerY = geometry.size.height / 2
                    let thumbY = valueToPosition(value, height: geometry.size.height)
                    let fillHeight = abs(thumbY - centerY)
                    let fillY = min(thumbY, centerY)
                    
                    if value != 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(
                                colors: value > 0 ? [accentColor.opacity(0.7), accentColor] : [accentColor, accentColor.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: isPreamp ? 6 : 5, height: fillHeight)
                            .position(x: geometry.size.width / 2, y: fillY + fillHeight / 2)
                    }
                    
                    // Zero line
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 20, height: 2)
                        .position(x: geometry.size.width / 2, y: centerY)
                    
                    // Thumb
                    Circle()
                        .fill(Theme.background)
                        .overlay(Circle().strokeBorder(value != 0 ? accentColor : Color.secondary, lineWidth: 2))
                        .shadow(color: Color.black.opacity(isDragging ? 0.3 : 0.2), radius: isDragging ? 4 : 2, y: 1)
                        .frame(width: 20, height: 20)
                        .scaleEffect(isDragging ? 1.1 : (isHovering ? 1.05 : 1.0))
                        .animation(.easeInOut(duration: 0.15), value: isDragging)
                        .position(x: geometry.size.width / 2, y: thumbY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    isDragging = true
                                    let val = positionToValue(gesture.location.y, height: geometry.size.height)
                                    value = val
                                }
                                .onEnded { _ in isDragging = false }
                        )
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 240)
            .onHover { isHovering = $0 }
        }
        .onTapGesture(count: 2) { value = 0 }
    }
    
    private var formattedValue: String {
        value == 0 ? "0 dB" : String(format: "%+.0f dB", value)
    }
    
    private func valueToPosition(_ value: Double, height: CGFloat) -> CGFloat {
        let normalized = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return height * (1.0 - normalized)
    }
    
    private func positionToValue(_ position: CGFloat, height: CGFloat) -> Double {
        let normalized = 1.0 - (position / height)
        let clamped = max(0.0, min(1.0, normalized))
        let raw = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        if abs(raw) < 0.5 { return 0.0 }
        // Snap to integer values for cleaner preset saves
        return round(raw)
    }
}

// MARK: - EQ Presets
enum EQPreset: String, CaseIterable, Identifiable {
    case flat = "Flat"
    case rock = "Rock"
    case pop = "Pop"
    case jazz = "Jazz"
    case classical = "Classical"
    case electronic = "Electronic"
    case bassBoost = "Bass Boost"
    case trebleBoost = "Treble Boost"
    case vocal = "Vocal"
    case acoustic = "Acoustic"
    case dance = "Dance"
    case latin = "Latin"
    case hiphop = "Hip-Hop"
    case metal = "Metal"
    case lounge = "Lounge"
    
    var id: String { rawValue }
    var name: String { rawValue }
    
    var bandValues: [Float] {
        switch self {
        case .flat: return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        case .rock: return [5, 3, -1, -2, 0, 2, 4, 5, 5, 4]
        case .pop: return [-2, -1, 0, 2, 4, 4, 2, 0, -1, -2]
        case .jazz: return [4, 3, 1, 2, -2, -2, 0, 2, 3, 4]
        case .classical: return [5, 4, 3, 2, -2, -2, 0, 2, 3, 4]
        case .electronic: return [5, 4, 0, -2, 2, 4, 5, 6, 6, 5]
        case .bassBoost: return [8, 7, 5, 3, 1, 0, 0, 0, 0, 0]
        case .trebleBoost: return [0, 0, 0, 0, 0, 1, 3, 5, 7, 8]
        case .vocal: return [-3, -2, 0, 3, 5, 5, 3, 0, -2, -3]
        case .acoustic: return [4, 4, 3, 1, 2, 2, 3, 4, 4, 3]
        case .dance: return [6, 5, 2, 0, 0, -2, 0, 2, 5, 6]
        case .latin: return [4, 3, 0, 0, -2, -2, -2, 0, 4, 5]
        case .hiphop: return [7, 6, 4, 2, 0, -1, 0, 1, 3, 4]
        case .metal: return [6, 5, 2, 0, -2, -1, 2, 4, 5, 6]
        case .lounge: return [-2, -1, 1, 3, 2, 1, 0, -1, 2, 3]
        }
    }
}
