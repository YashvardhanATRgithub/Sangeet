import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var playback: PlaybackController
    @ObservedObject var theme = AppTheme.shared
    @ObservedObject var effects = AudioEffectsManager.shared
    @Binding var showFullScreen: Bool
    var onOpenLyrics: (() -> Void)?
    var onOpenEqualizer: (() -> Void)?
    @State private var isHoveringVolume: Bool = false
    
    init(playback: PlaybackController? = nil, showFullScreen: Binding<Bool>, onOpenLyrics: (() -> Void)? = nil, onOpenEqualizer: (() -> Void)? = nil) {
        self.playback = playback ?? AppServices.shared.playback
        self._showFullScreen = showFullScreen
        self.onOpenLyrics = onOpenLyrics
        self.onOpenEqualizer = onOpenEqualizer
    }
    
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
    
    // ...
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar (Full Width)
            // Progress Bar (Snake)
            CustomProgressBar(
                value: Binding(
                    get: { playback.currentTime },
                    set: { _ in }
                ),
                total: playback.duration,
                isPlaying: playback.state == .playing,
                onSeek: { time in
                    playback.seek(to: time)
                },
                onEditingChanged: { _ in }
            )
            .frame(height: 12)
            .padding(.top, -6) // Pull up to align closely with top edge
            
            HStack(spacing: 0) {
                // 1. Artwork & Info (Left)
                HStack(spacing: 16) {
                    Button(action: { showFullScreen = true }) {
                        TrackArtworkView(
                            track: playback.currentTrack,
                            size: 56, // Slightly smaller for minimized
                            cornerRadius: 8,
                            iconSize: 20,
                            showsGlow: false
                        )
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playback.currentTrack?.title ?? "Not Playing")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(playback.currentTrack?.artist ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let track = playback.currentTrack {
                        Button(action: { playback.toggleFavorite() }) {
                            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundStyle(track.isFavorite ? .red : .secondary)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .padding(.leading, 8)
                        .onReceive(NotificationCenter.default.publisher(for: .libraryDidUpdate)) { _ in
                            // Force view update when library changes (favorites)
                            // This works because the publisher fires, causing body re-eval
                            // Ideally PlaybackController should republish currentTrack, but this is a safe fallback
                        }
                    }
                }
                .frame(width: 480, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { showFullScreen = true }
                
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullScreen = true }
                
                // 2. Playback Controls (Center)
                HStack(spacing: 24) {
                    // Shuffle
                    Button(action: { playback.isShuffleEnabled.toggle() }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 14))
                            .foregroundStyle(playback.isShuffleEnabled ? theme.currentTheme.primaryColor : .secondary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(playback.isShuffleEnabled ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    
                    // Prev
                    Button(action: { playback.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20)) // Clean size
                            .foregroundStyle(theme.currentTheme.primaryColor)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(theme.currentTheme.primaryColor.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    
                    // Play/Pause (The Star)
                    Button(action: { playback.togglePlayPause() }) {
                        ZStack {
                            Circle()
                                .fill(theme.currentTheme.primaryColor)
                                .frame(width: 50, height: 50)
                                .shadow(color: theme.currentTheme.primaryColor.opacity(0.4), radius: 10, x: 0, y: 0)
                            
                            Image(systemName: playback.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.black)
                                .offset(x: playback.state == .playing ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(playback.state == .playing ? 1.0 : 0.95)
                    .hoverEffect()
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: playback.state)
                    
                    // Next
                    Button(action: { playback.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.currentTheme.primaryColor)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(theme.currentTheme.primaryColor.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    
                    // Loop
                    Button(action: {
                        switch playback.repeatMode {
                        case .off: playback.repeatMode = .all
                        case .all: playback.repeatMode = .one
                        case .one: playback.repeatMode = .off
                        }
                    }) {
                        Image(systemName: playback.repeatMode == .one ? "repeat.1" : "repeat")
                            .font(.system(size: 14))
                            .foregroundStyle(playback.repeatMode != .off ? theme.currentTheme.primaryColor : .secondary)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(playback.repeatMode != .off ? theme.currentTheme.primaryColor.opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                }
                
                Spacer()
                    .contentShape(Rectangle())
                    .onTapGesture { showFullScreen = true }
                
                // 3. Right Side (Time & Volume & Tools)
                HStack(spacing: 20) {
                    // Time
                    Text("\(formatTime(playback.currentTime)) / \(formatTime(playback.duration))")
                        .font(.custom("Inter", size: 12).monospacedDigit())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    // Volume
                    HStack(spacing: 12) {
                        Button(action: { playback.toggleMute() }) {
                            Image(systemName: volumeIconName)
                                .font(.system(size: 14))
                                .foregroundStyle(playback.isMuted ? .red.opacity(0.8) : .secondary)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        
                        GeometryReader { geo in
                            let w = geo.size.width
                            let h = geo.size.height
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.1))
                                    .frame(height: isHoveringVolume ? 8 : 4)
                                
                                Capsule()
                                    .fill(playback.isMuted ? .secondary : theme.currentTheme.primaryColor)
                                    .frame(width: w * CGFloat(playback.isMuted ? 0 : playback.volume), height: isHoveringVolume ? 8 : 4)
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
                        .frame(width: 80, height: 16)
                        .contentShape(Rectangle())
                        .onHover { isHoveringVolume = $0 }
                    }
                    
                    // Equalizer
                    Button(action: { onOpenEqualizer?() }) {
                        Image(systemName: "slider.vertical.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .tourTarget(id: "tour-equalizer-button")
                    
                    // Karaoke
                    Button(action: { 
                        effects.isKaraokeEnabled.toggle()
                        if effects.isKaraokeEnabled {
                            onOpenLyrics?() // Opens Full Screen with Lyrics
                        }
                    }) {
                        Image(systemName: effects.isKaraokeEnabled ? "music.mic" : "music.mic")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(effects.isKaraokeEnabled ? theme.currentTheme.primaryColor : .secondary)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .tourTarget(id: "tour-karaoke-button")
                    
                    // Lyrics
                    Button(action: { onOpenLyrics?() }) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .tourTarget(id: "tour-lyrics-button")

                    // Expand
                    Button(action: { showFullScreen = true }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect()
                    .tourTarget(id: "tour-fullscreen-button")
                }
                .frame(width: 480, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }

        .background(.ultraThinMaterial)
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: NowPlayingBarHeightPreferenceKey.self, value: geo.size.height)
            }
        )
        .overlay(Divider(), alignment: .top)
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
