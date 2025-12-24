import SwiftUI

struct FullScreenPlayerView: View {
    @Binding var isPresented: Bool
    @ObservedObject var playback: PlaybackController
    @ObservedObject var theme = AppTheme.shared
    @State private var showQueue = false
    @Binding var showLyrics: Bool
    @State private var isHoveringVolume: Bool = false
    @ObservedObject var effects = AudioEffectsManager.shared
    
    private var volumeIconName: String {
        if playback.isMuted || playback.volume == 0 {
            return "speaker.slash.fill"
        } else if playback.volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if playback.volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
    
    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()
            
            // Ambient Background
            Circle()
                .fill(Theme.accent.opacity(0.18))
                .blur(radius: 160)
                .offset(x: -220, y: -260)
            
            Circle()
                .fill(Theme.accentWarm.opacity(0.16))
                .blur(radius: 180)
                .offset(x: 260, y: 280)
            
            VStack(spacing: 0) {
                // Header (Dismiss)
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 10)
                
                // Main Content Area
                if showLyrics, let track = playback.currentTrack {
                    // Split View: Artwork (Left) | Lyrics (Right)
                    HStack(alignment: .top, spacing: 40) {
                        // Left: Artwork + Info
                        VStack(spacing: 20) {
                            TrackArtworkView(
                                track: track,
                                maxSize: 320,
                                cornerRadius: 20,
                                iconSize: 80
                            )
                            .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                            
                            VStack(spacing: 6) {
                                Text(track.title)
                                    .font(.system(size: 22, weight: .bold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                
                                Text(track.artist)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 320)
                        }
                        .frame(width: 360)
                        
                        // Right: Lyrics
                        LyricsView(track: track, currentTime: playback.currentTime)
                            .frame(maxWidth: 500, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(.ultraThinMaterial.opacity(0.5))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .padding(.horizontal, 40)
                    .frame(maxHeight: .infinity)
                } else {
                    // Standard View: Centered Artwork + Info
                    VStack(spacing: 24) {
                        Spacer()
                        
                        TrackArtworkView(
                            track: playback.currentTrack,
                            maxSize: 380,
                            cornerRadius: 24,
                            iconSize: 100
                        )
                        .shadow(color: .black.opacity(0.4), radius: 30, x: 0, y: 15)
                        
                        VStack(spacing: 8) {
                            Text(playback.currentTrack?.title ?? "Not Playing")
                                .font(.system(size: 32, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            
                            Text(playback.currentTrack?.artist ?? "")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                }
                
                // Controls Section (Fixed at bottom)
                VStack(spacing: 24) {
                    // Progress Bar
                    VStack(spacing: 8) {
                        CustomProgressBar(
                            value: Binding(
                                get: { playback.currentTime },
                                set: { _ in }
                            ),
                            total: playback.duration,
                            isPlaying: playback.isPlaying,
                            onSeek: { time in
                                playback.seek(to: time)
                            },
                            onEditingChanged: { _ in }
                        )
                        .frame(height: 24)
                        
                        HStack {
                            Text(formatDuration(playback.currentTime))
                            Spacer()
                            Text(formatDuration(playback.duration))
                        }
                        .font(.custom("Inter", size: 12).monospacedDigit()) // If font avail, else system
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                    }
                    .padding(.horizontal, 40)
                    
                    // Main Playback Controls
                    HStack(spacing: 60) {
                        Button(action: { playback.previous() }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(theme.currentTheme.primaryColor.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(scale: 1.1)
                        
                        Button(action: { playback.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(theme.currentTheme.primaryColor)
                                    .frame(width: 80, height: 80)
                                    .shadow(color: theme.currentTheme.primaryColor.opacity(0.4), radius: 20, x: 0, y: 0)
                                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                                
                                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32, weight: .black))
                                    .foregroundStyle(.white)
                                    // Slight offset for visual center of 'play' triangle
                                    .offset(x: playback.isPlaying ? 0 : 3)
                            }
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(playback.isPlaying ? 1.0 : 0.95)
                        .hoverEffect(scale: 1.1)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: playback.isPlaying)
                        
                        Button(action: { playback.next() }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(theme.currentTheme.primaryColor.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(scale: 1.1)
                    }
                    .padding(.top, 10)
                    
                    // Volume Slider (Sleek)
                    HStack(spacing: 16) {
                        Button(action: { playback.toggleMute() }) {
                            Image(systemName: volumeIconName)
                                .font(.body)
                                .foregroundStyle(playback.isMuted ? .red.opacity(0.8) : .white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                            
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.1))
                                    .frame(height: isHoveringVolume ? 10 : 5)
                                
                                Capsule()
                                    .fill(playback.isMuted ? .secondary : theme.currentTheme.primaryColor.opacity(0.9))
                                    .frame(width: w * CGFloat(playback.isMuted ? 0 : playback.volume), height: isHoveringVolume ? 10 : 5)
                            }
                            .frame(width: w, height: h, alignment: .center)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringVolume)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0).onChanged { v in
                                    let p = min(max(0, v.location.x / w), 1)
                                    playback.volume = Double(p)
                                    if playback.isMuted && p > 0 {
                                        playback.toggleMute() // Auto-unmute when adjusting volume
                                    }
                                }
                            )
                        }
                        .frame(height: 20)
                        .contentShape(Rectangle())
                        .onHover { isHoveringVolume = $0 }
                        .frame(maxWidth: 240)
                    }
                    
                    // Bottom Action Dock
                    HStack(spacing: 48) {
                        Button(action: { playback.toggleFavorite() }) {
                            Image(systemName: (playback.currentTrack?.isFavorite ?? false) ? "heart.fill" : "heart")
                                .font(.title3)
                                .symbolEffect(.bounce, value: playback.currentTrack?.isFavorite)
                                .foregroundStyle((playback.currentTrack?.isFavorite ?? false) ? .red : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()

                        Button(action: { withAnimation(.spring()) { showLyrics.toggle() } }) {
                            Image(systemName: showLyrics ? "quote.bubble.fill" : "quote.bubble")
                                .font(.title3)
                                .foregroundStyle(showLyrics ? Theme.accent : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()

                        Button(action: { 
                            effects.isKaraokeEnabled.toggle() 
                            if effects.isKaraokeEnabled {
                                withAnimation(.spring()) { showLyrics = true }
                            }
                        }) {
                            Image(systemName: effects.isKaraokeEnabled ? "music.mic" : "music.mic")
                                .font(.title3)
                                .foregroundStyle(effects.isKaraokeEnabled ? Theme.accent : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()

                        Button(action: { showQueue.toggle() }) {
                            Image(systemName: "list.bullet")
                                .font(.title3)
                                .foregroundStyle(showQueue ? Theme.accent : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .popover(isPresented: $showQueue, arrowEdge: .top) {
                            QueueView()
                                .frame(width: 320, height: 450)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 32)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    )
                    .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 10)
            }
        }
        .gesture(
            DragGesture().onEnded { value in
                if value.translation.height > 60 {
                    isPresented = false
                }
            }
        )
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
