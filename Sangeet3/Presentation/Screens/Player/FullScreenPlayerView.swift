//
//  FullScreenPlayerView.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Immersive full-screen player with lyrics
//

import SwiftUI

struct FullScreenPlayerView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var showLyrics = false
    
    var body: some View {
        ZStack {
            // Animated background
            SangeetTheme.background.ignoresSafeArea()
            Circle().fill(SangeetTheme.primary.opacity(0.15)).blur(radius: 180).offset(x: -200, y: -200)
            Circle().fill(SangeetTheme.accent.opacity(0.1)).blur(radius: 200).offset(x: 200, y: 200)
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "chevron.down")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Button(action: { showLyrics.toggle() }) {
                        Image(systemName: showLyrics ? "text.bubble.fill" : "text.bubble")
                            .font(.title3)
                            .foregroundStyle(showLyrics ? SangeetTheme.primary : .white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                
                Spacer()
                
                // Main content
                HStack(spacing: 40) {
                    // Album art side
                    VStack(spacing: 32) {
                        // Artwork with glow
                        ArtworkView(track: playbackManager.currentTrack, size: 300, cornerRadius: 24, showGlow: true)
                        
                        // Track info
                        VStack(spacing: 12) {
                            VStack(spacing: 8) {
                                Text(playbackManager.currentTrack?.title ?? "Not Playing")
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                
                                Text(playbackManager.currentTrack?.artist ?? "Unknown Artist")
                                    .font(.title3)
                                    .foregroundStyle(SangeetTheme.textSecondary)
                            }
                            
                            // Heart and Download buttons below metadata
                            if let track = playbackManager.currentTrack {
                                HStack(spacing: 16) {
                                    HeartButton(track: track, size: 24, color: .white.opacity(0.6))
                                    
                                    // Show download button for remote tracks
                                    if track.isRemote {
                                        DownloadButton(track: track, size: 24)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 300)
                    }
                    
                    // Lyrics panel
                    if showLyrics {
                        VStack {
                            LyricsView()
                        }
                        .frame(width: 350, height: 400)
                        .glassmorphic(cornerRadius: 24)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 60)
                
                Spacer()
                
                // Controls panel
                VStack(spacing: 24) {
                    // Progress bar - same squiggly style as FloatingDock
                    VStack(spacing: 8) {
                        SquigglyProgressBar()
                            .padding(.horizontal, 4)
                        
                        HStack {
                            Text(formatTime(playbackManager.currentTime))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(SangeetTheme.textSecondary)
                            Spacer()
                            Text(formatTime(playbackManager.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(SangeetTheme.textMuted)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Playback controls
                    HStack(spacing: 48) {
                        Button(action: { playbackManager.toggleShuffle() }) {
                            Image(systemName: "shuffle")
                                .font(.title3)
                                .foregroundStyle(playbackManager.shuffleEnabled ? SangeetTheme.primary : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.previous() }) {
                            Image(systemName: "backward.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.togglePlayPause() }) {
                            ZStack {
                                Circle()
                                    .fill(SangeetTheme.primaryGradient)
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                                    .offset(x: playbackManager.isPlaying ? 0 : 3)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.next(manualSkip: true) }) {
                            Image(systemName: "forward.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { playbackManager.cycleRepeatMode() }) {
                            Image(systemName: repeatIcon)
                                .font(.title3)
                                .foregroundStyle(playbackManager.repeatMode != .off ? SangeetTheme.primary : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(32)
                .glassmorphic(cornerRadius: 32)
                .padding(.horizontal, 80)
                .padding(.bottom, 40)
            }
        }
        .animation(.spring(response: 0.3), value: showLyrics)
        .gesture(DragGesture().onEnded { if $0.translation.height > 80 { isPresented = false } })
    }
    
    // progressBar function removed - now using SquigglyProgressBar component
    
    var repeatIcon: String {
        switch playbackManager.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
