import SwiftUI

struct QueueView: View {
    @ObservedObject var playback: PlaybackController
    
    init() {
        self.playback = AppServices.shared.playback
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Pinned Header Section
            pinnedHeader
                .background(Theme.background)
            
            Divider()
                .opacity(0.5)
            
            // Scrollable Content
            if playback.userQueue.isEmpty && playback.contextQueue.isEmpty && playback.currentTrack == nil {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // User Queue
                        ForEach(Array(playback.userQueue.enumerated()), id: \.offset) { index, track in
                            QueueRow(track: track, index: index) {
                                playback.playFromUserQueue(at: index)
                            }
                        }
                        
                        // Context Queue
                        if !playback.contextQueue.isEmpty {
                            if !playback.userQueue.isEmpty {
                                HStack {
                                    Text("From Library")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                            }
                            
                            ForEach(Array(playback.contextQueue.enumerated()), id: \.offset) { index, track in
                                QueueRow(track: track, index: index + 1000) { // Offset ID for hover
                                    playback.playFromContextQueue(at: index)
                                }
                            }
                        }
                        
                        
                        Color.clear.frame(height: 20) // Bottom Padding
                    }
                    .padding(.vertical, 0)
                }
            }
        }
        .frame(minWidth: 300, maxWidth: 300, maxHeight: .infinity)
        .background(Theme.background)
        .overlay(
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1),
            alignment: .leading
        )
    }
    
    // MARK: - Components
    
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Bar: Title & Controls
            HStack {
                Text("Queue")
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                // Autoplay
                Button(action: { playback.isAutoplayEnabled.toggle() }) {
                    HStack(spacing: 6) {
                        Text("Autoplay")
                            .font(.system(size: 12))
                        Image(systemName: "infinity")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(playback.isAutoplayEnabled ? Theme.accent : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (playback.isAutoplayEnabled ? Theme.accent : Color.white).opacity(0.1)
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                // Clear
                Button(action: { playback.clearUpcomingTracks() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            // Now Playing Card
            if let current = playback.currentTrack {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Now Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                    
                    HStack(spacing: 12) {
                        TrackArtworkView(track: current, size: 48, cornerRadius: 6)
                            .overlay(
                                ZStack {
                                    Color.black.opacity(0.4)
                                    Image(systemName: "chart.bar.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.accent)
                                }
                                .cornerRadius(6)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(current.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .lineLimit(1)
                            Text(current.artist)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.03))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            
            // Next Up Label
            if !playback.userQueue.isEmpty || !playback.contextQueue.isEmpty {
                Text("Next Up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 4) {
             Spacer()
             Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.3))
                .padding(.bottom, 16)
             Text("Queue is empty")
                .font(.headline)
             Text("Play some music to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
             Spacer()
        }
    }
    
    struct QueueRow: View {
        let track: Track
        let index: Int
        let action: () -> Void
        @State private var isHovered = false
        
        var body: some View {
            HStack(spacing: 12) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(isHovered ? 0.5 : 0))
                    .frame(width: 16)
                
                TrackArtworkView(track: track, size: 40, cornerRadius: 6)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isHovered {
                    Button(action: { 
                        // Remove action (stubbed)
                    }) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(formatDuration(track.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 20) // Match header padding
            .padding(.vertical, 6)
            .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture {
                action() // Double tap logic or single? User interaction usually single in lists
            }
        }
        
        func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
