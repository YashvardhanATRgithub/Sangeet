//
//  LyricsView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Synced lyrics display with auto-scrolling
//

import SwiftUI
import Combine

struct LyricsView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @StateObject private var viewModel = LyricsViewModel()
    
    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if !viewModel.lyrics.isEmpty {
                lyricsScrollView
            } else if let plain = viewModel.plainLyrics {
                plainLyricsView(plain)
            } else {
                noLyricsView
            }
        }
        .onChange(of: playbackManager.currentTrack?.id) { _, _ in
            viewModel.loadLyrics(for: playbackManager.currentTrack)
        }
        .onAppear {
            viewModel.loadLyrics(for: playbackManager.currentTrack)
        }
    }
    
    var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading lyrics...")
                .font(.caption)
                .foregroundStyle(SangeetTheme.textSecondary)
        }
    }
    
    func plainLyricsView(_ text: String) -> some View {
        ScrollView(showsIndicators: false) {
            Text(text)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(SangeetTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 60)
        }
    }

    var noLyricsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.quote")
                .font(.system(size: 40))
                .foregroundStyle(SangeetTheme.textMuted)
            
            Text("No lyrics available")
                .font(.headline)
                .foregroundStyle(SangeetTheme.textSecondary)
            
            if let track = playbackManager.currentTrack {
                Text("\(track.title) - \(track.artist)")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
    
    var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 16) {
                    Spacer(minLength: 100)
                    
                    ForEach(Array(viewModel.lyrics.enumerated()), id: \.element.id) { index, line in
                        LyricLine(
                            line: line,
                            isActive: viewModel.currentLineIndex == index,
                            isPast: index < viewModel.currentLineIndex,
                            currentTime: playbackManager.currentTime
                        )
                        .id(line.id)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard newIndex >= 0 && newIndex < viewModel.lyrics.count else { return }
                // Smoother scroll animation
                withAnimation(.easeInOut(duration: 0.6)) {
                    proxy.scrollTo(viewModel.lyrics[newIndex].id, anchor: .center)
                }
            }
            .onChange(of: playbackManager.currentTime) { _, time in
                viewModel.updateCurrentLine(for: time)
            }
        }
    }
}

struct LyricLine: View {
    let line: SyncedLine
    let isActive: Bool
    let isPast: Bool
    let currentTime: TimeInterval
    
    var body: some View {
        Group {
            if let words = line.words, !words.isEmpty, isActive {
                karaokeText(words: words)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6) // Increased line spacing
                    .frame(maxWidth: .infinity)
                    .scaleEffect(1.05)
                    .animation(.spring(response: 0.3), value: currentTime) // Slightly slower spring for smoothness
            } else {
                Text(line.text)
                    // Significantly bigger fonts
                    .font(.system(size: isActive ? 34 : 24, weight: isActive ? .bold : .medium))
                    .foregroundStyle(
                        isActive ? .white :
                        isPast ? SangeetTheme.textMuted :
                        SangeetTheme.textSecondary
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .scaleEffect(isActive ? 1.05 : 1.0)
                    .animation(.spring(response: 0.4), value: isActive)
            }
        }
    }
    
    private func karaokeText(words: [SyncedWord]) -> Text {
        var attributed = AttributedString()

        for word in words {
            let isSung = currentTime >= word.start
            var part = AttributedString(word.text)
            // Accent color for sung words, muted for upcoming ones
            part.foregroundColor = isSung ? SangeetTheme.primary : SangeetTheme.textMuted.opacity(0.6)
            part.font = .system(size: 34, weight: isSung ? .bold : .medium)
            attributed += part
        }

        return Text(attributed)
    }
}

// MARK: - ViewModel
@MainActor
class LyricsViewModel: ObservableObject {
    @Published var lyrics: [SyncedLine] = []
    @Published var plainLyrics: String?
    @Published var currentLineIndex: Int = -1
    @Published var isLoading = false

    private var loadedTrackId: UUID?

    func loadLyrics(for track: Track?) {
        guard let track = track else {
            lyrics = []
            plainLyrics = nil
            currentLineIndex = -1
            loadedTrackId = nil
            return
        }

        isLoading = true
        loadedTrackId = track.id

        Task {
            let result = await LyricsService.shared.fetchLyrics(for: track)

            // Ignore stale results if the track changed while loading
            guard self.loadedTrackId == track.id else { return }

            self.lyrics = result?.syncedLyrics ?? []
            self.plainLyrics = result?.plainLyrics
            self.currentLineIndex = -1
            self.isLoading = false
        }
    }
    
    func updateCurrentLine(for time: TimeInterval) {
        guard !lyrics.isEmpty else { return }
        
        // Find the line that should be active
        var newIndex = -1
        for (index, line) in lyrics.enumerated() {
            if line.time <= time {
                newIndex = index
            } else {
                break
            }
        }
        
        if newIndex != currentLineIndex {
            currentLineIndex = newIndex
        }
    }
}
