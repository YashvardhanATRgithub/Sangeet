import SwiftUI

struct NowPlayingBar: View {
    @ObservedObject var playback: RealPlaybackService
    @Binding var showFullScreen: Bool
    
    init(playback: RealPlaybackService? = nil, showFullScreen: Binding<Bool>) {
        self.playback = playback ?? AppServices.shared.playback
        self._showFullScreen = showFullScreen
    }
    
    // ...
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress Bar (Full Width)
            GeometryReader { geo in
                let progress = playback.duration > 0 ? playback.currentTime / playback.duration : 0
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 4)
                    
                    if playback.duration > 0 {
                        let clamped = min(max(progress, 0), 1)
                        Rectangle()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.accentWarm], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * clamped, height: 4)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            guard playback.duration > 0 else { return }
                            let pct = max(0, min(1, value.location.x / geo.size.width))
                            playback.seek(to: playback.duration * pct)
                        }
                )
            }
            .frame(height: 4)
            
            HStack(spacing: 16) {
                // 1. Artwork & Info (Left)
                HStack {
                    Button(action: { showFullScreen = true }) {
                        TrackArtworkView(
                            track: playback.currentTrack,
                            size: 64,
                            cornerRadius: 10,
                            iconSize: 24,
                            showsGlow: false
                        )
                    }
                    .buttonStyle(.plain)
                    
                    VStack(alignment: .leading) {
                        Text(playback.currentTrack?.title ?? "Not Playing")
                            .font(.title3)
                            .lineLimit(1)
                        Text(playback.currentTrack?.artist ?? "")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    if let track = playback.currentTrack {
                        Button(action: { playback.toggleFavorite() }) {
                            Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                                .font(.title2)
                                .foregroundStyle(track.isFavorite ? .red : .gray)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)
                        
                        // Queue Button (Right of Heart)
                        Button(action: {
                            // Toggle Queue via Notification since State is in MainView
                            NotificationCenter.default.post(name: .toggleQueue, object: nil)
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
                .frame(width: 320, alignment: .leading)
                
                Spacer()
                
                // 2. Controls (Center)
                HStack(spacing: 24) {
                    Button(action: { playback.isShuffling.toggle() }) {
                        Image(systemName: "shuffle")
                            .foregroundStyle(playback.isShuffling ? .blue : .primary)
                    }
                    
                    Button(action: { playback.previous() }) {
                        Image(systemName: "backward.fill")
                    }
                    
                    Button(action: {
                        if playback.state == .playing {
                            playback.pause()
                        } else {
                            playback.resume()
                        }
                    }) {
                        Image(systemName: playback.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 54))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { playback.next() }) {
                        Image(systemName: "forward.fill")
                    }
                    
                    Button(action: {
                        switch playback.loopMode {
                        case .off: playback.loopMode = .all
                        case .all: playback.loopMode = .one
                        case .one: playback.loopMode = .off
                        }
                    }) {
                        Image(systemName: playback.loopMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(playback.loopMode != .off ? .blue : .primary)
                    }
                }

                .font(.system(size: 28))
                
                Spacer()
                
                // 3. Right Side (Time & Volume)
                HStack(spacing: 16) {
                    Text("\(formatTime(playback.currentTime)) / \(formatTime(playback.duration))")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    HStack(spacing: 8) {
                        Button(action: { playback.toggleMute() }) {
                            Image(systemName: playback.volume == 0 ? "speaker.slash.fill" : (playback.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"))
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Slider(
                            value: Binding(
                                get: { Double(playback.volume) },
                                set: { playback.volume = Float($0) }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)
                        .frame(width: 120)
                    }
                    
                    Button(action: { showFullScreen = true }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: 350, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
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
