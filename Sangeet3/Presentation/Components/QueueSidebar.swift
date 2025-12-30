//
//  QueueSidebar.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//
//  Premium queue sidebar with drag-to-reorder
//

import SwiftUI
import UniformTypeIdentifiers

struct QueueSidebar: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @Binding var isVisible: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Queue")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                
                Spacer()
                
                // Show count of remaining songs (Now Playing + Up Next)
                let remaining = max(0, playbackManager.queue.count - playbackManager.queueIndex)
                Text("\(remaining) songs")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                
                Button(action: { withAnimation { isVisible = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(SangeetTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(SangeetTheme.surface)
            
            Divider().background(Color.white.opacity(0.1))
            
            if playbackManager.queue.isEmpty {
                emptyState
            } else {
                queueList
            }
            
            // Quick Actions
            HStack(spacing: 12) {
                Button(action: { playbackManager.clearQueue() }) {
                    Label("Clear", systemImage: "trash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SangeetTheme.textSecondary)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Infinite Queue Toggle
                Button(action: { playbackManager.toggleInfiniteQueue() }) {
                    Image(systemName: "infinity")
                        .font(.body.weight(.medium))
                        .foregroundStyle(playbackManager.isInfiniteQueueEnabled ? SangeetTheme.primary : SangeetTheme.textSecondary)
                        .padding(6)
                        .background(playbackManager.isInfiniteQueueEnabled ? SangeetTheme.primary.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Infinite Autoplay")
                
                Button(action: { playbackManager.toggleShuffle() }) {
                    Image(systemName: "shuffle")
                        .font(.body.weight(.medium))
                        .foregroundStyle(playbackManager.shuffleEnabled ? SangeetTheme.primary : SangeetTheme.textSecondary)
                        .padding(6)
                        .background(playbackManager.shuffleEnabled ? SangeetTheme.primary.opacity(0.15) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(SangeetTheme.surface)
        }
        .frame(width: 320)
        .background(SangeetTheme.background.opacity(0.95))
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.4), radius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(SangeetTheme.textMuted)
            
            Text("Queue is empty")
                .font(.headline)
                .foregroundStyle(SangeetTheme.textSecondary)
            
            Text("Add songs from your library")
                .font(.caption)
                .foregroundStyle(SangeetTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Now Playing Section
                    if let current = playbackManager.currentTrack {
                        Section {
                            // QueueItem(track: current, index: playbackManager.queueIndex, isCurrentTrack: true)
                            //     .transition(.opacity)
                            //     .id("nowPlaying")
                            // Note: We use queueIndex identifier for Now Playing to avoid duplication logic issues,
                            // but since it's a single item, we just render it.
                            QueueItem(track: current, index: playbackManager.queueIndex, isCurrentTrack: true)
                                .id("nowPlaying")
                        } header: {
                            HStack {
                                Text("Now Playing")
                                    .font(.caption.bold())
                                    .foregroundStyle(SangeetTheme.primary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                    }
                    
                    // Up Next Section
                    if playbackManager.queueIndex < playbackManager.queue.count - 1 {
                        Section {
                            // Use enumerated offset as ID to handle duplicate songs (same UUID) correctly
                            ForEach(Array(playbackManager.queue.enumerated()), id: \.offset) { index, track in
                                if index > playbackManager.queueIndex {
                                    QueueItem(track: track, index: index, isCurrentTrack: false)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Up Next")
                                    .font(.caption.bold())
                                    .foregroundStyle(SangeetTheme.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: playbackManager.queueIndex) { _, newIndex in
                withAnimation {
                    proxy.scrollTo(playbackManager.queue[safe: newIndex]?.id)
                }
            }
        }
    }
}

struct QueueItem: View {
    let track: Track
    let index: Int
    let isCurrentTrack: Bool
    
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Artwork / Playing Indicator
            ZStack {
                ArtworkView(track: track, size: 48, cornerRadius: 8)
                
                if isCurrentTrack {
                    ZStack {
                        Color.black.opacity(0.6)
                        Image(systemName: playbackManager.isPlaying ? "waveform" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(SangeetTheme.primary)
                            .symbolEffect(.variableColor.iterative, isActive: playbackManager.isPlaying)
                    }
                } else if isHovering {
                    ZStack {
                        Color.black.opacity(0.6)
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrentTrack ? SangeetTheme.primary : .white)
                    .lineLimit(1)
                
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions (Reorder & Remove)
            if isHovering && !isCurrentTrack {
                HStack(spacing: 8) {
                    // Move Up
                    // Prevent moving "Up Next" items above the "Up Next" section (i.e., into Now Playing)
                    // Prevent moving History items if at top (0)
                    let isUpNext = index > playbackManager.queueIndex
                    let canMoveUp = isUpNext ? (index > playbackManager.queueIndex + 1) : (index > 0)
                    
                    if canMoveUp {
                        Button(action: { 
                            withAnimation {
                                playbackManager.moveItemUp(at: index) 
                            }
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                                .foregroundStyle(SangeetTheme.textMuted)
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Move Down
                    // Prevent moving History items below History section (i.e., into Now Playing)
                    // Prevent moving "Up Next" items if at bottom
                    let isHistory = index < playbackManager.queueIndex
                    let canMoveDown = isHistory ? (index < playbackManager.queueIndex - 1) : (index < playbackManager.queue.count - 1)
                    
                    if canMoveDown {
                        Button(action: { 
                            withAnimation {
                                playbackManager.moveItemDown(at: index) 
                            }
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(SangeetTheme.textMuted)
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Remove
                    Button(action: { playbackManager.removeFromQueue(at: index) }) {
                        Image(systemName: "xmark")
                            .font(.body)
                            .foregroundStyle(SangeetTheme.textMuted)
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(isCurrentTrack ? SangeetTheme.primary.opacity(0.15) : (isHovering ? SangeetTheme.surface : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if !isCurrentTrack {
                playbackManager.playQueue(tracks: playbackManager.queue, startIndex: index)
            } else {
                playbackManager.togglePlayPause()
            }
        }
    }
}
