import SwiftUI

struct LyricsView: View {
    let track: Track
    let currentTime: TimeInterval
    
    @State private var lines: [LyricLine] = []
    @State private var lyricsText: String?
    @State private var isLoading = false
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    if isLoading {
                         Text("Searching for lyrics...")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 100)
                        
                         ProgressView()
                            .scaleEffect(0.8)
                    } else if lines.isEmpty {
                        ContentUnavailableView(
                            "No Lyrics Found",
                            systemImage: "music.mic",
                            description: Text("We couldn't find time-synced lyrics for this song.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(lines) { line in
                            let isCurrent = isActive(line)
                            Text(line.text)
                                .font(isCurrent ? .system(size: 24, weight: .bold, design: .rounded) : .system(size: 18, weight: .medium, design: .rounded))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    isCurrent ?
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Theme.accent.opacity(0.1))
                                        .padding(.horizontal, -10)
                                    : nil
                                )
                                .animation(.spring(response: 0.3), value: currentTime)
                                .id(line.id)
                        }
                        
                        Color.clear.frame(height: 200) // Bottom padding
                    }
                }
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: currentTime) { _, time in
                if let activeLine = lines.last(where: { $0.timestamp <= time + 0.5 }) {
                    withAnimation(.spring) {
                        proxy.scrollTo(activeLine.id, anchor: .center)
                    }
                }
            }
        }
        .task(id: track.id) {
            await loadLyrics()
        }
    }
    
    private func loadLyrics() async {
        // 1. Check if track already has lyrics (from DB)
        if let existing = await AppServices.shared.database.getLyrics(for: track) {
            self.lyricsText = existing
            self.lines = LyricsService.shared.parse(existing)
            return
        }
        
        // 2. Fetch Online (Fallback if not found)
        isLoading = true
        defer { isLoading = false }
        
        if let onlineLyrics = await LyricsService.shared.searchOnline(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration
        ) {
            self.lyricsText = onlineLyrics
            self.lines = LyricsService.shared.parse(onlineLyrics)
            
            // Persist for future use
            if let id = track.trackId {
                await AppServices.shared.database.saveLyrics(for: id, lyrics: onlineLyrics)
            }
        } else {
            self.lyricsText = nil
            self.lines = []
        }
    }
    
    private func isActive(_ line: LyricLine) -> Bool {
        guard let index = lines.firstIndex(of: line) else { return false }
        
        let startTime = line.timestamp
        let endTime = (index + 1 < lines.count) ? lines[index + 1].timestamp : (startTime + 5.0)
        
        return currentTime >= startTime && currentTime < endTime
    }
    
    // Helper for scroll change
    private func activeLineId(at time: TimeInterval) -> UUID? {
        lines.last(where: { $0.timestamp <= time + 0.5 })?.id
    }

}
