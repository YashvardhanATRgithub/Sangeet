
import SwiftUI

struct SettingsView: View {
    @State private var rotation: Double = 0
    @State private var hoveredItemId: String?
    
    // Feature Toggles (bound to UserSettings/AudiophileSettings)
    @ObservedObject var audioSettings = AudiophileSettings.shared
    @ObservedObject var libraryManager = LibraryManager.shared
    @ObservedObject var metadataManager = SmartMetadataManager.shared
    
    // Popup States
    @State private var showLibraryParams = false
    @State private var showMetadataParams = false
    @State private var showEQParams = false
    @State private var showStatsParams = false
    @State private var showAboutParams = false
    @State private var showCrossfadeParams = false
    @State private var showThemeParams = false
    
    struct SettingsItem: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let description: String // New description field
        let icon: String // SF Symbol
        let angle: Double // Degrees placement around gear
        let type: ItemType
        
        enum ItemType {
            case toggle(Binding<Bool>)
            case action(() -> Void)
        }
        
        static func == (lhs: SettingsItem, rhs: SettingsItem) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    var body: some View {
        ZStack {
            SangeetTheme.background.ignoresSafeArea()
            
            // Central Gear
            ZStack {
                // Gear Icon
                Image(systemName: "gear")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 300, height: 300)
                    .foregroundStyle(SangeetTheme.primaryGradient.opacity(0.1))
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.5)) {
                            rotation = 45 // Small rotation on open
                        }
                    }
                
                // Center Label (Dynamic)
                VStack(spacing: 12) {
                    if let id = hoveredItemId, let item = items.first(where: { $0.id == id }) {
                        Text(item.name.uppercased())
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale).animation(.easeInOut(duration: 0.15)))
                            .id("Label_" + id) // Force transition
                        
                        Text(item.description)
                            .font(.caption)
                            .foregroundStyle(SangeetTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 220) // Widen to fit detailed text
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    } else {
                        Text("SETTINGS")
                            .font(.title2.bold())
                            .foregroundStyle(.white.opacity(0.5))
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            .id("Label_Static")
                    }
                }
                .offset(y: -5) // Shift up slightly
            }
            .offset(y: -50) // Shift gear assembly up away from dock
            
            // Re-implementing Item Placement using ZStack for better hit testing
            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2 - 50)
                let radius: CGFloat = 220
                
                ZStack {
                    ForEach(items) { item in
                        let angleRad = (item.angle - 90) * .pi / 180
                        // Calculate offset from center instead of absolute position
                        let offsetX = radius * cos(angleRad)
                        let offsetY = radius * sin(angleRad)
                        
                        SettingNode(item: item, isHovered: hoveredItemId == item.id)
                            .frame(width: 80, height: 80) // Explicit frame for hit testing
                            .offset(x: offsetX, y: offsetY)
                            .onHover { isHovering in
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                    if isHovering {
                                        hoveredItemId = item.id
                                    } else if hoveredItemId == item.id {
                                        hoveredItemId = nil
                                    }
                                }
                            }
                            .onTapGesture {
                                handleTap(item)
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                // Center the ZStack content
                .position(x: center.x, y: center.y)
            }
        }
        // Popups
        .sheet(isPresented: $showLibraryParams) { LibrarySettingsSheet() }
        .sheet(isPresented: $showMetadataParams) { MetadataSettingsSheet() }
        .sheet(isPresented: $showEQParams) { VisualEQSheet() }
        .sheet(isPresented: $showStatsParams) { StatsSheet() }
        .sheet(isPresented: $showAboutParams) { AboutSheet() }
        .sheet(isPresented: $showCrossfadeParams) { CrossfadeSheet() }
        .sheet(isPresented: $showThemeParams) { ThemeSheet() }
    }
    
    @Namespace private var namespace
    
    // Define Settings Configuration
    // 11 items evenly spaced: 360/11 ≈ 32.7° apart
    var items: [SettingsItem] {
        [
            // Top (Music Note) -> Library
            .init(name: "Library", description: "Manage your music sources. Add or remove folders to scan for local tracks.", icon: "music.note.list", angle: 0, type: .action({ showLibraryParams = true })),
            
            // Clockwise from top
            .init(name: "Metadata", description: "Automatically scan and fix missing tags and artwork for your library.", icon: "wand.and.stars", angle: 33, type: .action({ showMetadataParams = true })),
            
            .init(name: "Seamless", description: "Eliminate silence between tracks for a continuous, album-like experience.", icon: "arrow.triangle.2.circlepath", angle: 65, type: .toggle($audioSettings.seamlessPlayback)),
            
            .init(name: "Crossfade", description: "Smoothly overlap the end of one song with the start of the next.", icon: "waveform.path.ecg", angle: 98, type: .action({ showCrossfadeParams = true })),
            
            .init(name: "Exclusive", description: "Bypass the system mixer to take full control of your audio device.", icon: "lock.shield", angle: 131, type: .toggle($audioSettings.exclusiveAudioAccess)),
            
            .init(name: "Bit-Perfect", description: "Output audio at its native sample rate without resampling.", icon: "checkmark.seal", angle: 164, type: .toggle($audioSettings.bitPerfectOutput)),
            
            .init(name: "Hi-Res", description: "Prioritize the highest available quality and sample rate for playback.", icon: "waveform", angle: 196, type: .toggle($audioSettings.nativeSampleRate)),
            
            .init(name: "Stats", description: "View detailed statistics about your music library and listening habits.", icon: "chart.bar", angle: 229, type: .action({ showStatsParams = true })),
            
            .init(name: "About", description: "Information about Sangeet, its version, and the developer.", icon: "info.circle", angle: 262, type: .action({ showAboutParams = true })),
            
            .init(name: "Equalizer", description: "Customize the frequency response to match your taste or headphones.", icon: "slider.vertical.3", angle: 295, type: .action({ showEQParams = true })),
            
            .init(name: "Theme", description: "Change the app's accent color with a beautiful color spectrum.", icon: "paintpalette", angle: 327, type: .action({ showThemeParams = true }))
        ]
    }
    
    func handleTap(_ item: SettingsItem) {
        switch item.type {
        case .toggle(let binding):
            withAnimation(.easeInOut(duration: 0.2)) {
                binding.wrappedValue.toggle()
            }
        case .action(let action):
            action()
        }
    }
}

// Node Component
struct SettingNode: View {
    let item: SettingsView.SettingsItem
    let isHovered: Bool
    
    var isActive: Bool {
        if case .toggle(let binding) = item.type {
            return binding.wrappedValue
        }
        return false // Actions represent "opening" something, not a state
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? SangeetTheme.primary : SangeetTheme.surfaceElevated)
                .frame(width: 60, height: 60)
                .shadow(color: isActive ? SangeetTheme.primary.opacity(0.6) : .black.opacity(0.3), radius: isActive ? 16 : 10)
                .overlay(
                    Circle()
                        .stroke(isActive ? Color.white : Color.clear, lineWidth: 2)
                )
            
            Image(systemName: item.icon)
                .font(.title2)
                .foregroundStyle(isActive ? .white : SangeetTheme.textSecondary)
        }
        .scaleEffect(isHovered ? 1.35 : 1.0)
        // No more tooltip here
    }
}

// MARK: - Sheets for Complex Settings

struct LibrarySettingsSheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Library Folders").font(.headline)
            List {
                ForEach(libraryManager.folders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text(folder.path)
                        Spacer()
                        Button(action: { libraryManager.removeFolder(folder) }) {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                    }
                }
            }
            .frame(height: 200)
            
            Button("Add Folder") { libraryManager.addFolder() }
            Button("Done") { dismiss() }
        }
        .padding()
        .frame(width: 400)
    }
}

struct MetadataSettingsSheet: View {
    @ObservedObject var metadataManager = SmartMetadataManager.shared
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Metadata Management").font(.headline)
            Text("Scan library and auto-tag songs with iTunes metadata.")
                .multilineTextAlignment(.center)
            
            if metadataManager.isBulkFixing {
                ProgressView(value: Double(metadataManager.processedCount), total: Double(metadataManager.totalCount))
                Text("\(metadataManager.processedCount) / \(metadataManager.totalCount)")
            } else {
                Button("Start Auto-Tagging") {
                    Task { await metadataManager.fixAllMetadata(libraryManager: libraryManager) }
                }
            }
            Button("Done") { dismiss() }
        }
        .padding()
        .frame(width: 400)
    }
}

struct VisualEQSheet: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        EqualizerView()
    }
}

struct CrossfadeSheet: View {
    @ObservedObject var settings = AudiophileSettings.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Crossfade Settings").font(.headline)
            
            Toggle("Enable Crossfade", isOn: $settings.crossfadeEnabled)
                .toggleStyle(.switch)
                .tint(SangeetTheme.primary)
            
            if settings.crossfadeEnabled {
                VStack(spacing: 8) {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(Int(settings.crossfadeDuration))s")
                            .monospacedDigit()
                            .foregroundStyle(SangeetTheme.primary)
                    }
                    
                    Slider(value: $settings.crossfadeDuration, in: 1...12, step: 1)
                        .tint(SangeetTheme.primary)
                }
            }
            
            Button("Done") { dismiss() }
        }
        .padding(32)
        .frame(width: 400)
    }
}

struct StatsSheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Statistics").font(.headline)
            HStack(spacing: 20) {
                StatView(value: "\(libraryManager.tracks.count)", label: "Songs")
                StatView(value: "\(libraryManager.albums.count)", label: "Albums")
                StatView(value: "\(libraryManager.artists.count)", label: "Artists")
            }
            Button("Done") { dismiss() }
        }
        .padding()
        .frame(width: 400)
    }
}

struct StatView: View {
    let value: String, label: String
    var body: some View {
        VStack {
            Text(value).font(.title.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AboutSheet: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SangeetTheme.primaryGradient)
            Text("Sangeet 3.0").font(.title.bold())
            Text("Premium Music Player for macOS").font(.body)
            Button("Done") { dismiss() }
        }
        .padding()
        .frame(width: 300)
    }
}

struct ThemeSheet: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Text("App Theme")
                .font(.headline)
            
            HStack(alignment: .top, spacing: 32) {
                // Accent Color Section
                VStack(spacing: 16) {
                    Text("Accent Color")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    
                    AccentColorSlider()
                }
                
                Divider()
                    .frame(height: 300)
                
                // Background Color Section
                VStack(spacing: 16) {
                    Text("Background")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    
                    BackgroundColorPicker()
                }
            }
            
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(SangeetTheme.primary)
        }
        .padding(32)
        .frame(width: 450)
        .background(SangeetTheme.background)
    }
}

// MARK: - Accent Color Slider
struct AccentColorSlider: View {
    @ObservedObject var themeManager = ThemeManager.shared
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Spectrum Slider
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            stops: (0...10).map { i in
                                .init(color: Color(hue: Double(i) / 10.0, saturation: 0.7, brightness: 0.8), location: Double(i) / 10.0)
                            },
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 180)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                
                Circle()
                    .fill(themeManager.primary)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: themeManager.primary.opacity(0.6), radius: isDragging ? 10 : 6)
                    .offset(y: CGFloat(themeManager.hue) * 180 - 12)
            }
            .frame(width: 24, height: 180)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        themeManager.hue = min(1.0, max(0.0, value.location.y / 180))
                    }
                    .onEnded { _ in isDragging = false }
            )
            
            // Presets
            Text("Presets")
                .font(.caption2)
                .foregroundStyle(SangeetTheme.textMuted)
            
            LazyVGrid(columns: [GridItem(.fixed(22)), GridItem(.fixed(22)), GridItem(.fixed(22))], spacing: 6) {
                ForEach(ThemeManager.accentPresets, id: \.hue) { preset in
                    Circle()
                        .fill(Color(hue: preset.hue, saturation: 0.75, brightness: 0.75))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.white, lineWidth: abs(themeManager.hue - preset.hue) < 0.03 ? 2 : 0))
                        .onTapGesture { themeManager.hue = preset.hue }
                        .help(preset.name)
                }
            }
        }
    }
}

// MARK: - Background Color Picker
struct BackgroundColorPicker: View {
    @ObservedObject var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Brightness Slider
            VStack(spacing: 8) {
                Text("Brightness")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.black)
                        .font(.caption2)
                    
                    Slider(value: $themeManager.backgroundBrightness, in: 0...0.15)
                        .tint(SangeetTheme.primary)
                        .frame(width: 100)
                    
                    Image(systemName: "circle.fill")
                        .foregroundStyle(Color(white: 0.15))
                        .font(.caption2)
                }
            }
            
            // Preview
            RoundedRectangle(cornerRadius: 8)
                .fill(themeManager.background)
                .frame(width: 80, height: 50)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
            
            // Presets
            Text("Presets")
                .font(.caption2)
                .foregroundStyle(SangeetTheme.textMuted)
            
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30)), count: 4), spacing: 6) {
                ForEach(ThemeManager.backgroundPresets, id: \.name) { preset in
                    // Make preview colors more visible by increasing brightness
                    let previewColor = preset.hue < 0 
                        ? Color(white: max(0.08, preset.brightness + 0.05))
                        : Color(hue: preset.hue, saturation: 0.50, brightness: max(0.25, preset.brightness + 0.15))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(previewColor)
                        .frame(width: 28, height: 28)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    isCurrentPreset(preset) ? Color.white : Color.white.opacity(0.3),
                                    lineWidth: isCurrentPreset(preset) ? 2.5 : 1
                                )
                        )
                        .onTapGesture {
                            themeManager.backgroundBrightness = preset.brightness
                            themeManager.backgroundHue = preset.hue
                        }
                        .help(preset.name)
                }
            }
        }
    }
    
    private func isCurrentPreset(_ preset: (name: String, brightness: Double, hue: Double)) -> Bool {
        abs(themeManager.backgroundBrightness - preset.brightness) < 0.02 &&
        abs(themeManager.backgroundHue - preset.hue) < 0.03
    }
}
