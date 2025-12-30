//
//  FloatingDock.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Premium floating dock with integrated Android-style squiggly progress bar
//

import SwiftUI

struct FloatingDock: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @Binding var showFullScreen: Bool
    @Binding var showQueue: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Main dock content (ZStack for perfect centering)
            ZStack {
                // Layer 1: Left and Right Content
                HStack(spacing: 16) {
                    // Album art & track info
                    Button(action: { showFullScreen = true }) {
                        HStack(spacing: 12) {
                            AlbumArtView(size: 48)
                            TrackInfoView()
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Volume & extras
                    VolumeAndExtrasView(showQueue: $showQueue)
                }
                
                // Layer 2: Center Controls
                PlaybackControlsView()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Integrated progress bar with labels
            VStack(spacing: 4) {
                SquigglyProgressBar()
                
                HStack {
                    Text(formatTime(playbackManager.currentTime))
                    Spacer()
                    Text(formatTime(playbackManager.duration))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(SangeetTheme.textMuted)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: 800)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Album Art
struct AlbumArtView: View {
    let size: CGFloat
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var body: some View {
        ZStack {
            // Use ArtworkView for actual album art
            ArtworkView(track: playbackManager.currentTrack, size: size, cornerRadius: 8)
            
            // Playing indicator overlay
            if playbackManager.isPlaying {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.3))
                    .frame(width: size, height: size)
                Image(systemName: "waveform")
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: true)
            }
        }
        .shadow(color: SangeetTheme.primary.opacity(playbackManager.isPlaying ? 0.3 : 0), radius: 12)
    }
}

// MARK: - Track Info (Now includes Heart)
struct TrackInfoView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playbackManager.currentTrack?.title ?? "Not Playing")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(playbackManager.currentTrack?.artist ?? "Select a song to play")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
            // Constrain width to avoid pushing center controls
            .frame(maxWidth: 160, alignment: .leading)
            
            if let track = playbackManager.currentTrack {
                HeartButton(track: track, size: 16, color: SangeetTheme.textSecondary)
            }
        }
    }
}

// MARK: - Playback Controls (Center only)
struct PlaybackControlsView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    
    var body: some View {
        HStack(spacing: 24) {
            ControlButton(icon: "backward.fill", size: .medium) {
                playbackManager.previous()
            }
            
            // Main play/pause button with glow
            Button(action: { playbackManager.togglePlayPause() }) {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(SangeetTheme.primary.opacity(0.4))
                        .frame(width: 48, height: 48)
                        .blur(radius: 12)
                        .opacity(playbackManager.isPlaying ? 1 : 0)
                    
                    // Main button
                    Circle()
                        .fill(SangeetTheme.primaryGradient)
                        .frame(width: 44, height: 44)
                        .shadow(color: SangeetTheme.glowShadow, radius: 16)
                    
                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .offset(x: playbackManager.isPlaying ? 0 : 2)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(playbackManager.isPlaying ? 1.0 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: playbackManager.isPlaying)
            
            ControlButton(icon: "forward.fill", size: .medium) {
                playbackManager.next(manualSkip: true)
            }
        }
    }
}

// MARK: - Volume and Extras
struct VolumeAndExtrasView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @Binding var showQueue: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Audio Output Picker
            CompactAudioOutputPicker()
            
            // Volume slider
            HStack(spacing: 8) {
                Image(systemName: volumeIcon)
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .frame(width: 16)
                    .onTapGesture {
                        playbackManager.toggleMute()
                    }
                
                GeometryReader { geo in
                    let width = geo.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(height: 4)
                        
                        Capsule()
                            .fill(SangeetTheme.primaryGradient)
                            .frame(width: width * CGFloat(playbackManager.volume), height: 4)
                    }
                    .frame(height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                playbackManager.setVolume(Float(min(max(0, v.location.x / width), 1)))
                            }
                    )
                }
                .frame(width: 60, height: 20)
            }
            
            // Shuffle
            ControlButton(
                icon: "shuffle",
                size: .small,
                isActive: playbackManager.shuffleEnabled
            ) {
                playbackManager.toggleShuffle()
            }
            
            // Repeat
            ControlButton(
                icon: repeatIcon,
                size: .small,
                isActive: playbackManager.repeatMode != .off
            ) {
                playbackManager.cycleRepeatMode()
            }
            
            // Queue
            Button(action: { showQueue.toggle() }) {
                Image(systemName: "list.bullet")
                    .font(.subheadline)
                    .foregroundStyle(showQueue ? SangeetTheme.primary : SangeetTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    var volumeIcon: String {
        if playbackManager.volume == 0 { return "speaker.slash.fill" }
        if playbackManager.volume < 0.33 { return "speaker.wave.1.fill" }
        if playbackManager.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
    
    var repeatIcon: String {
        switch playbackManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
}

// MARK: - Reusable Control Button
struct ControlButton: View {
    enum Size { case small, medium, large }
    
    let icon: String
    let size: Size
    var isActive: Bool = false
    let action: () -> Void
    
    @State private var isPressed = false
    
    var iconSize: Font {
        switch size {
        case .small: return .subheadline
        case .medium: return .title3
        case .large: return .title2
        }
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(iconSize)
                .foregroundStyle(isActive ? SangeetTheme.primary : .white.opacity(0.75))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.2), value: isPressed)
    }
}

// MARK: - Android-Style Squiggly Progress Bar
struct SquigglyProgressBar: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0.0
    @State private var isHovering: Bool = false
    
    // Wave parameters (tuned for Android lock screen look)
    private let waveAmplitude: CGFloat = 3.0
    private let waveFrequency: CGFloat = 0.08
    private let waveSpeed: CGFloat = 2.5
    private let trackHeight: CGFloat = 4.0
    
    // Direct progress from playback manager (DisplayLink provides 60fps updates)
    private var progress: Double {
        guard playbackManager.duration > 0 else { return 0 }
        if isDragging { return dragProgress }
        return playbackManager.currentTime / playbackManager.duration
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60, paused: !playbackManager.isPlaying && !isDragging)) { context in
            let animatedPhase = playbackManager.isPlaying ? CGFloat(context.date.timeIntervalSinceReferenceDate) * waveSpeed : 0
            
            GeometryReader { geometry in
                let width = geometry.size.width
                let centerY = geometry.size.height / 2
                let progressX = width * CGFloat(progress)
                
                ZStack {
                    // 1. Background Track
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: trackHeight)
                        .position(x: width / 2, y: centerY)
                    
                    // 2. Squiggly Progress Wave
                    if progress > 0 {
                        Canvas { ctx, size in
                            var path = Path()
                            let endX = progressX
                            
                            path.move(to: CGPoint(x: 0, y: centerY))
                            
                            for x in stride(from: 0, through: endX, by: 1) {
                                let wave = sin((x * waveFrequency) + animatedPhase) * waveAmplitude
                                let edgeDamping = min(x / 20, (endX - x) / 20, 1.0)
                                let dampedWave = wave * edgeDamping
                                path.addLine(to: CGPoint(x: x, y: centerY + dampedWave))
                            }
                            
                            ctx.stroke(
                                path,
                                with: .linearGradient(
                                    Gradient(colors: [SangeetTheme.secondary, SangeetTheme.accent]),
                                    startPoint: CGPoint(x: 0, y: centerY),
                                    endPoint: CGPoint(x: endX, y: centerY)
                                ),
                                style: StrokeStyle(lineWidth: trackHeight, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                    
                    // 3. Pill Thumb
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .frame(width: 8, height: 18)
                        .scaleEffect(isDragging ? 1.2 : (isHovering ? 1.1 : 1.0))
                        .position(x: max(4, min(width - 4, progressX)), y: centerY)
                        .animation(.spring(response: 0.2), value: isDragging)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            isDragging = true
                            dragProgress = min(max(0, v.location.x / width), 1)
                        }
                        .onEnded { v in
                            let p = min(max(0, v.location.x / width), 1)
                            isDragging = false
                            playbackManager.seek(to: p * playbackManager.duration)
                        }
                )
                .onHover { isHovering = $0 }
            }
        }
        .frame(height: 30)
    }
}
