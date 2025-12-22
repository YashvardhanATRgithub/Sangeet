import SwiftUI

struct FullScreenPlayerView: View {
    @Binding var isPresented: Bool
    @ObservedObject var playback: RealPlaybackService
    @State private var showQueue = false
    
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
            
            VStack(spacing: 32) {
                // Header (Dismiss)
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.down")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)
                
                Spacer()
                
                // Artwork
                TrackArtworkView(
                    track: playback.currentTrack,
                    maxSize: 520,
                    cornerRadius: 20,
                    iconSize: 120
                )
                .shadow(radius: 26)
                
                // Info
                VStack(spacing: 8) {
                    Text(playback.currentTrack?.title ?? "Not Playing")
                        .font(.system(size: 36, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    Text(playback.currentTrack?.artist ?? "")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                // Progress
                VStack(spacing: 10) {
                    let maxDuration = max(playback.duration, max(playback.currentTime, 1))
                    Slider(value: Binding(
                         get: { playback.currentTime },
                         set: { playback.seek(to: $0) }
                    ), in: 0...maxDuration)
                    .tint(Theme.accent)
                    .padding(.horizontal, 80)
                    
                    HStack {
                        Text(formatDuration(playback.currentTime))
                        Spacer()
                        Text(formatDuration(playback.duration))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 80)
                }
                
                // Controls
                HStack(spacing: 60) {
                    Button(action: { playback.previous() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 34, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { playback.togglePlayPause() }) {
                        Image(systemName: playback.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 92))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { playback.next() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 34, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                
                Spacer()
                
                // Bottom Actions
                HStack(spacing: 40) {
                     Button(action: { playback.toggleFavorite() }) {
                         Image(systemName: (playback.currentTrack?.isFavorite ?? false) ? "heart.fill" : "heart")
                             .font(.title2)
                             .foregroundStyle((playback.currentTrack?.isFavorite ?? false) ? .red : .secondary)
                     }
                     .buttonStyle(.plain)
                    
                    Button(action: { 
                        showQueue.toggle()
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .foregroundStyle(showQueue ? Theme.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showQueue, arrowEdge: .top) {
                        QueueView()
                            .frame(width: 300, height: 400)
                    }
                }
                .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
