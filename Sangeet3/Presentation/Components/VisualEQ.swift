//
//  VisualEQ.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Visual Equalizer with draggable frequency curve
//

import SwiftUI

/// Visual EQ with draggable bezier curve
struct VisualEQ: View {
    @StateObject private var eqManager = EQManager.shared
    @State private var draggedBand: Int? = nil
    
    private let frequencies = ["32", "64", "125", "250", "500", "1K", "4K", "16K"]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with toggle and preset
            header
            
            // Main EQ curve
            eqCurve
                .frame(height: 200)
            
            // Frequency labels
            frequencyLabels
            
            // Presets
            presetPicker
        }
        .padding(24)
        .background(SangeetTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Spacer()
            
            // Reset button
            Button(action: { eqManager.reset() }) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(SangeetTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Reset to flat")
            
            // Enable toggle
            Toggle("Enable EQ", isOn: $eqManager.isEnabled)
                .toggleStyle(.switch)
                .tint(SangeetTheme.primary)
        }
    }
    
    // MARK: - EQ Curve
    
    private var eqCurve: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let bandWidth = width / CGFloat(8)
            
            ZStack {
                // Background grid with dashed lines
                gridBackground(width: width, height: height)
                
                // Zero line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height / 2))
                    path.addLine(to: CGPoint(x: width, y: height / 2))
                }
                .stroke(SangeetTheme.textMuted.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                
                // Filled area under curve
                filledCurve(width: width, height: height, bandWidth: bandWidth)
                    .fill(
                        LinearGradient(
                            colors: [SangeetTheme.primary.opacity(0.4), SangeetTheme.primary.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(eqManager.isEnabled ? 1 : 0.3)
                
                // Curve line with glow
                curvePath(width: width, height: height, bandWidth: bandWidth)
                    .stroke(
                        eqManager.isEnabled ? SangeetTheme.primary : SangeetTheme.textMuted,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: eqManager.isEnabled ? SangeetTheme.primary.opacity(0.5) : .clear, radius: 8, x: 0, y: 0)
                
                // Control points
                ForEach(0..<8, id: \.self) { band in
                    controlPoint(band: band, width: width, height: height, bandWidth: bandWidth)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(value: value, width: width, height: height, bandWidth: bandWidth)
                    }
                    .onEnded { _ in
                        draggedBand = nil
                    }
            )
        }
    }
    
    // MARK: - Drawing Helpers
    
    private func gridBackground(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            // Horizontal lines at -6dB and +6dB
            let quarterHeight = height / 4
            
            for i in [1, 3] {
                let y = CGFloat(i) * quarterHeight
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
                context.stroke(path, with: .color(SangeetTheme.textMuted.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            
            // Vertical lines for each band
            let bandWidth = width / 8
            for i in 1..<8 {
                let x = CGFloat(i) * bandWidth
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
                context.stroke(path, with: .color(SangeetTheme.textMuted.opacity(0.1)), lineWidth: 1)
            }
        }
    }
    
    private func curvePath(width: CGFloat, height: CGFloat, bandWidth: CGFloat) -> Path {
        var path = Path()
        let points = controlPoints(width: width, height: height, bandWidth: bandWidth)
        
        guard points.count >= 2 else { return path }
        
        path.move(to: points[0])
        
        // Use Catmull-Rom or standard cubic bezier for smoothness
        for i in 1..<points.count {
            let previous = points[i - 1]
            let current = points[i]
            let midX = (previous.x + current.x) / 2
            
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        
        return path
    }
    
    private func filledCurve(width: CGFloat, height: CGFloat, bandWidth: CGFloat) -> Path {
        var path = curvePath(width: width, height: height, bandWidth: bandWidth)
        let points = controlPoints(width: width, height: height, bandWidth: bandWidth)
        
        guard let lastPoint = points.last, let firstPoint = points.first else { return path }
        
        path.addLine(to: CGPoint(x: lastPoint.x, y: height))
        path.addLine(to: CGPoint(x: firstPoint.x, y: height))
        path.closeSubpath()
        
        return path
    }
    
    private func controlPoints(width: CGFloat, height: CGFloat, bandWidth: CGFloat) -> [CGPoint] {
        (0..<8).map { band in
            let x = bandWidth * CGFloat(band) + bandWidth / 2
            let normalizedGain = CGFloat(eqManager.gains[band] + 12) / 24 // -12 to +12 -> 0 to 1
            let y = height * (1 - normalizedGain)
            return CGPoint(x: x, y: y)
        }
    }
    
    private func controlPoint(band: Int, width: CGFloat, height: CGFloat, bandWidth: CGFloat) -> some View {
        let point = controlPoints(width: width, height: height, bandWidth: bandWidth)[band]
        let isActive = draggedBand == band
        
        return ZStack {
            // Glow
            if isActive {
                Circle()
                    .fill(SangeetTheme.primary.opacity(0.3))
                    .frame(width: 24, height: 24)
            }
            
            // Knob
            Circle()
                .fill(eqManager.isEnabled ? SangeetTheme.primary : SangeetTheme.textMuted)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .position(point)
        .animation(.spring(response: 0.2), value: isActive)
    }
    
    // MARK: - Gesture Handling
    
    private func handleDrag(value: DragGesture.Value, width: CGFloat, height: CGFloat, bandWidth: CGFloat) {
        guard eqManager.isEnabled else { return }
        
        // Find closest band
        let x = value.location.x
        let band = Int((x / bandWidth).rounded())
        let clampedBand = max(0, min(7, band))
        
        draggedBand = clampedBand
        
        // Calculate gain from y position
        let y = value.location.y
        let normalizedY = 1 - (y / height) // Flip: top = +12, bottom = -12
        let gain = Float(normalizedY * 24 - 12)
        
        eqManager.setGain(band: clampedBand, gain: gain)
    }
    
    // MARK: - Frequency Labels
    
    private var frequencyLabels: some View {
        HStack {
            ForEach(0..<8, id: \.self) { i in
                Text(frequencies[i])
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(SangeetTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Preset Picker
    
    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Built-in presets
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(EQManager.presets.keys.sorted()), id: \.self) { preset in
                        presetButton(name: preset, isCustom: false)
                    }
                }
            }
            
            // Custom presets (if any)
            if !eqManager.customPresets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(eqManager.customPresets) { preset in
                            customPresetButton(preset: preset)
                        }
                    }
                }
            }
            
            // Save button (only show if current is Custom)
            if eqManager.currentPreset == "Custom" {
                savePresetButton
            }
        }
    }
    
    private func presetButton(name: String, isCustom: Bool) -> some View {
        Button(action: { eqManager.applyPreset(name) }) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(eqManager.currentPreset == name ? .white : SangeetTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    eqManager.currentPreset == name
                        ? SangeetTheme.primary
                        : SangeetTheme.surfaceElevated
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(eqManager.currentPreset == name ? .white.opacity(0.3) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func customPresetButton(preset: EQPresetRecord) -> some View {
        HStack(spacing: 4) {
            Button(action: { eqManager.applyCustomPreset(preset) }) {
                Text(preset.name)
                    .font(.subheadline)
                    .foregroundStyle(eqManager.currentPreset == preset.name ? .white : SangeetTheme.textSecondary)
            }
            .buttonStyle(.plain)
            
            Button(action: { eqManager.deleteCustomPreset(preset) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(eqManager.currentPreset == preset.name ? .white.opacity(0.7) : SangeetTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            eqManager.currentPreset == preset.name
                ? SangeetTheme.primary
                : SangeetTheme.surfaceElevated
        )
        .clipShape(Capsule())
    }
    
    @State private var showSaveAlert = false
    @State private var newPresetName = ""
    
    private var savePresetButton: some View {
        HStack {
            TextField("Preset name", text: $newPresetName)
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SangeetTheme.surfaceElevated)
                .clipShape(Capsule())
                .frame(maxWidth: 150)
            
            Button(action: saveCustomPreset) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Save")
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(SangeetTheme.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    
    private func saveCustomPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        
        eqManager.saveCurrentAsPreset(name: name)
        newPresetName = ""
    }
}

// MARK: - Preview

#Preview {
    VisualEQ()
        .frame(width: 500)
        .padding()
        .background(SangeetTheme.background)
}
