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
            } else if viewModel.lyrics.isEmpty {
                noLyricsView
            } else {
                lyricsScrollView
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
                            isPast: index < viewModel.currentLineIndex
                        )
                        .id(line.id)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 24)
            }
            .onChange(of: viewModel.currentLineIndex) { _, newIndex in
                guard newIndex >= 0 && newIndex < viewModel.lyrics.count else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
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
    
    var body: some View {
        Text(line.text)
            .font(.system(size: isActive ? 24 : 18, weight: isActive ? .bold : .medium))
            .foregroundStyle(
                isActive ? .white :
                isPast ? SangeetTheme.textMuted :
                SangeetTheme.textSecondary
            )
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isActive)
    }
}

// MARK: - ViewModel
@MainActor
class LyricsViewModel: ObservableObject {
    @Published var lyrics: [SyncedLine] = []
    @Published var currentLineIndex: Int = -1
    @Published var isLoading = false
    
    func loadLyrics(for track: Track?) {
        guard let track = track else {
            lyrics = []
            currentLineIndex = -1
            return
        }
        
        isLoading = true
        
        Task {
            let result = await LyricsService.shared.fetchLyrics(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration
            )
            
            self.lyrics = result?.syncedLyrics ?? []
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
