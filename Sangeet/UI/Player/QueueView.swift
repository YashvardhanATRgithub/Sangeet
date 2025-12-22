import SwiftUI

struct QueueView: View {
    @ObservedObject var playback: RealPlaybackService
    
    init() {
        self.playback = AppServices.shared.playback
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Up Next")
                .font(.headline)
                .padding()
            
            if playback.queue.isEmpty {
                Text("Queue is empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(playback.queue) { track in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .fontWeight(.medium)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatDuration(track.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            playback.play(track)
                        }
                    }
                    .onDelete { indexSet in
                        // Remove from playback queue
                        // Since array is value type in swift, likely need a method in service to mutate
                        indexSet.forEach { index in
                            playback.removeFromQueue(at: index)
                        }
                    }
                    .onMove { from, to in
                        // Setup reorder logic in service if needed
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .nowPlayingBarPadding()
        .frame(width: 250)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .leading)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
