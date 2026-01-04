//
//  EqualizerView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 31/12/24.
//
//  Modern 10-Band Equalizer with Frequency Curve Visualization
//

import SwiftUI

struct EqualizerView: View {
    @StateObject private var eqManager = EQManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var showSaveSheet = false
    @State private var newPresetName = ""
    @State private var deleteConfirmPreset: EQPresetRecord? = nil
    
    var body: some View {
        ZStack {
            // Background
            SangeetTheme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                header
                
                // MARK: - EQ Curve Visualization
                EQCurveView(gains: eqManager.gains, isEnabled: eqManager.isEnabled)
                    .frame(height: 100)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                
                // MARK: - Sliders Section
                slidersSection
                    .padding(.top, 12)
                
                Spacer(minLength: 8)
                
                // MARK: - Presets Section
                presetsSection
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 680, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showSaveSheet) {
            savePresetSheet
        }
        .alert("Delete Preset", isPresented: .constant(deleteConfirmPreset != nil)) {
            Button("Cancel", role: .cancel) { deleteConfirmPreset = nil }
            Button("Delete", role: .destructive) {
                if let preset = deleteConfirmPreset {
                    eqManager.deleteCustomPreset(preset)
                }
                deleteConfirmPreset = nil
            }
        } message: {
            Text("Are you sure you want to delete \"\(deleteConfirmPreset?.name ?? "")\"?")
        }
    }
    
    // MARK: - Header
    private var header: some View {
        HStack {
            // Title with glow when enabled
            HStack(spacing: 12) {
                Image(systemName: "slider.vertical.3")
                    .font(.title2)
                    .foregroundStyle(eqManager.isEnabled ? SangeetTheme.primaryGradient : LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                
                Text("Equalizer")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            // Save Custom EQ Button - Always Visible
            Button(action: { showSaveSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text("Save")
                        .font(.subheadline.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(SangeetTheme.primaryGradient)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Save current EQ as a custom preset")
            
            // Reset Button (when modified)
            if eqManager.isModified {
                Button(action: { eqManager.resetToPreset() }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Reset to preset")
            }
            
            // EQ Toggle
            Toggle("", isOn: $eqManager.isEnabled)
                .toggleStyle(.switch)
                .tint(SangeetTheme.primary)
                .labelsHidden()
                .scaleEffect(0.9)
            
            // Close Button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }
    
    // MARK: - Sliders Section
    private var slidersSection: some View {
        HStack(spacing: 0) {
            // Preamp Slider (separated)
            VStack(spacing: 8) {
                Text(String(format: "%+.0f", eqManager.preamp))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(eqManager.preamp == 0 ? .white.opacity(0.4) : SangeetTheme.accent)
                
                EQSliderControl(
                    value: $eqManager.preamp,
                    isEnabled: eqManager.isEnabled,
                    accentColor: SangeetTheme.accent
                )
                .frame(width: 44, height: 130)
                
                Text("PRE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.trailing, 16)
            
            // Divider
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1, height: 150)
            
            // 10 Band Sliders
            HStack(spacing: 6) {
                ForEach(0..<EQManager.bandCount, id: \.self) { index in
                    VStack(spacing: 8) {
                        // dB Value
                        Text(String(format: "%+.0f", eqManager.gains[index]))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(gainColor(for: eqManager.gains[index]))
                        
                        // Slider
                        EQSliderControl(
                            value: binding(for: index),
                            isEnabled: eqManager.isEnabled,
                            accentColor: SangeetTheme.primary
                        )
                        .frame(width: 44, height: 130)
                        
                        // Frequency Label
                        Text(EQManager.frequencyLabels[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Presets Section
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // My Presets Section (Custom)
            if !eqManager.customPresets.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(SangeetTheme.accent)
                        Text("MY PRESETS")
                            .font(.caption.bold())
                            .foregroundStyle(SangeetTheme.accent)
                    }
                    .padding(.horizontal, 24)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(eqManager.customPresets) { preset in
                                PresetChip(
                                    name: preset.name,
                                    gains: preset.getGains(),
                                    isSelected: eqManager.currentPreset == preset.name,
                                    isCustom: true,
                                    onTap: { eqManager.applyPreset(preset.name) },
                                    onDelete: { deleteConfirmPreset = preset }
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            
            // Built-in Presets Section
            VStack(alignment: .leading, spacing: 8) {
                Text("BUILT-IN PRESETS")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 24)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EQManager.presetOrder, id: \.self) { name in
                            PresetChip(
                                name: name,
                                gains: EQManager.presets[name] ?? [],
                                isSelected: eqManager.currentPreset == name,
                                isCustom: false,
                                onTap: { eqManager.applyPreset(name) },
                                onDelete: nil
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
    
    // MARK: - Save Preset Sheet
    private var savePresetSheet: some View {
        VStack(spacing: 20) {
            Text("Save Preset")
                .font(.headline)
            
            TextField("Preset Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit { saveNewPreset() }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    newPresetName = ""
                    showSaveSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") { saveNewPreset() }
                    .buttonStyle(.borderedProminent)
                    .tint(SangeetTheme.primary)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
    
    // MARK: - Helpers
    
    private func binding(for index: Int) -> Binding<Float> {
        Binding(
            get: { eqManager.gains[index] },
            set: { eqManager.setGain(band: index, gain: $0) }
        )
    }
    
    private func gainColor(for gain: Float) -> Color {
        if gain == 0 { return .white.opacity(0.4) }
        return gain > 0 ? SangeetTheme.primary : SangeetTheme.secondary
    }
    
    private func saveNewPreset() {
        guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        eqManager.saveCurrentAsPreset(name: newPresetName)
        newPresetName = ""
        showSaveSheet = false
    }
}

// MARK: - EQ Curve Visualization

struct EQCurveView: View {
    let gains: [Float]
    let isEnabled: Bool
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let centerY = height / 2
            
            ZStack {
                // Grid lines
                ForEach([-6, 0, 6], id: \.self) { db in
                    let y = centerY - CGFloat(db) / 12 * (height / 2 - 10)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(.white.opacity(db == 0 ? 0.2 : 0.08), lineWidth: 1)
                }
                
                // EQ Curve
                Path { path in
                    let points = curvePoints(width: width, height: height, centerY: centerY)
                    guard let first = points.first else { return }
                    path.move(to: first)
                    
                    // Smooth curve using Catmull-Rom spline
                    for i in 1..<points.count {
                        let p0 = points[max(0, i - 2)]
                        let p1 = points[max(0, i - 1)]
                        let p2 = points[i]
                        let p3 = points[min(points.count - 1, i + 1)]
                        
                        let cp1 = CGPoint(
                            x: p1.x + (p2.x - p0.x) / 6,
                            y: p1.y + (p2.y - p0.y) / 6
                        )
                        let cp2 = CGPoint(
                            x: p2.x - (p3.x - p1.x) / 6,
                            y: p2.y - (p3.y - p1.y) / 6
                        )
                        path.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                }
                .stroke(
                    isEnabled ? SangeetTheme.primaryGradient : LinearGradient(colors: [.white.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 2.5
                )
                
                // Filled area under curve
                Path { path in
                    let points = curvePoints(width: width, height: height, centerY: centerY)
                    guard let first = points.first else { return }
                    
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: first)
                    
                    for i in 1..<points.count {
                        let p0 = points[max(0, i - 2)]
                        let p1 = points[max(0, i - 1)]
                        let p2 = points[i]
                        let p3 = points[min(points.count - 1, i + 1)]
                        
                        let cp1 = CGPoint(
                            x: p1.x + (p2.x - p0.x) / 6,
                            y: p1.y + (p2.y - p0.y) / 6
                        )
                        let cp2 = CGPoint(
                            x: p2.x - (p3.x - p1.x) / 6,
                            y: p2.y - (p3.y - p1.y) / 6
                        )
                        path.addCurve(to: p2, control1: cp1, control2: cp2)
                    }
                    
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: isEnabled ? [SangeetTheme.primary.opacity(0.3), SangeetTheme.primary.opacity(0.05)] : [.white.opacity(0.1), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                // Band markers
                ForEach(0..<gains.count, id: \.self) { i in
                    let x = CGFloat(i) / CGFloat(gains.count - 1) * width
                    let y = centerY - CGFloat(gains[i]) / 12 * (height / 2 - 10)
                    
                    Circle()
                        .fill(isEnabled ? SangeetTheme.primary : .white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .position(x: x, y: y)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.3))
        )
    }
    
    private func curvePoints(width: CGFloat, height: CGFloat, centerY: CGFloat) -> [CGPoint] {
        gains.enumerated().map { i, gain in
            let x = CGFloat(i) / CGFloat(gains.count - 1) * width
            let y = centerY - CGFloat(gain) / 12 * (height / 2 - 10)
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - EQ Slider Control

struct EQSliderControl: View {
    @Binding var value: Float
    let isEnabled: Bool
    let accentColor: Color
    
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let width = geo.size.width
            let trackWidth: CGFloat = 6
            let thumbSize: CGFloat = 18
            
            let center = height / 2
            let normalized = CGFloat(value + 12) / 24.0
            let thumbY = height * (1 - normalized)
            
            ZStack {
                // Track Background
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: trackWidth)
                
                // Center Line
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 12, height: 2)
                    .position(x: width / 2, y: center)
                
                // Active Fill
                if isEnabled && value != 0 {
                    let fillHeight = abs(thumbY - center)
                    Capsule()
                        .fill(accentColor.opacity(0.8))
                        .frame(width: trackWidth, height: fillHeight)
                        .position(
                            x: width / 2,
                            y: value > 0 ? thumbY + fillHeight / 2 : center + fillHeight / 2
                        )
                }
                
                // Thumb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(white: 0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                    .scaleEffect(isDragging ? 1.15 : 1.0)
                    .position(x: width / 2, y: thumbY)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        isDragging = true
                        
                        let y = gesture.location.y
                        let percent = 1 - (y / height)
                        var newValue = Float(percent * 24 - 12)
                        
                        // Snap to zero near center
                        if abs(newValue) < 0.8 {
                            newValue = 0
                        }
                        
                        value = max(-12, min(12, newValue))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .animation(.easeOut(duration: 0.1), value: isDragging)
        }
    }
}

// MARK: - Preset Chip

struct PresetChip: View {
    let name: String
    let gains: [Float]
    let isSelected: Bool
    let isCustom: Bool
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Mini curve preview
                MiniCurvePreview(gains: normalizedGains, isSelected: isSelected)
                    .frame(width: 80, height: 40)
                
                // Name
                Text(name)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isCustom, let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
    
    private var normalizedGains: [Float] {
        // Ensure we have 10 values
        if gains.count == 10 { return gains }
        if gains.count == 8 {
            // Simple mapping
            return [gains[0], gains[0], gains[1], gains[2], gains[3], gains[4], (gains[4]+gains[5])/2, gains[5], gains[6], gains[7]]
        }
        return Array(repeating: 0, count: 10)
    }
}

// MARK: - Mini Curve Preview

struct MiniCurvePreview: View {
    let gains: [Float]
    let isSelected: Bool
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let centerY = height / 2
            
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? SangeetTheme.primary.opacity(0.2) : .white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? SangeetTheme.primary : .white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
                
                // Curve
                Path { path in
                    let points = gains.enumerated().map { i, gain in
                        let x = CGFloat(i) / CGFloat(gains.count - 1) * (width - 8) + 4
                        let y = centerY - CGFloat(gain) / 12 * (height / 2 - 4)
                        return CGPoint(x: x, y: y)
                    }
                    
                    guard let first = points.first else { return }
                    path.move(to: first)
                    
                    for i in 1..<points.count {
                        path.addLine(to: points[i])
                    }
                }
                .stroke(
                    isSelected ? SangeetTheme.primary : .white.opacity(0.4),
                    lineWidth: 1.5
                )
            }
        }
    }
}
