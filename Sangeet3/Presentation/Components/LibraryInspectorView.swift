
import SwiftUI

struct LibraryInspectorView: View {
    let track: Track?
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var libraryManager: LibraryManager
    @ObservedObject var metadataManager = SmartMetadataManager.shared
    
    var body: some View {
        Group {
            if let track = track {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Large Artwork
                            ArtworkView(track: track, size: 240, cornerRadius: 12)
                                .padding(.top, 40)
                                .overlay(
                                    metadataManager.isSearching ?
                                    ZStack {
                                        Color.black.opacity(0.6)
                                        ProgressView()
                                            .controlSize(.large)
                                            .tint(.white)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    : nil
                                )
                            
                            // Main Info
                            VStack(spacing: 8) {
                                Text(track.title)
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                
                                Text(track.artist)
                                    .font(.headline)
                                    .foregroundStyle(SangeetTheme.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text(track.album)
                                    .font(.subheadline)
                                    .foregroundStyle(SangeetTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.horizontal)
                            
                            // Action Buttons
                            HStack(spacing: 24) {
                                Button(action: { playbackManager.playQueue(tracks: [track]) }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "play.fill").font(.title3)
                                            .frame(width: 44, height: 44)
                                            .background(SangeetTheme.primary).foregroundStyle(.white).clipShape(Circle())
                                        Text("Play").font(.caption2).foregroundStyle(SangeetTheme.textSecondary)
                                    }
                                }.buttonStyle(.plain)
                                
                                Button(action: { libraryManager.toggleFavorite(track) }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: track.isFavorite ? "heart.fill" : "heart").font(.title3)
                                            .frame(width: 44, height: 44)
                                            .background(SangeetTheme.surfaceElevated).foregroundStyle(track.isFavorite ? SangeetTheme.primary : .white).clipShape(Circle())
                                        Text("Like").font(.caption2).foregroundStyle(SangeetTheme.textSecondary)
                                    }
                                }.buttonStyle(.plain)
                                
                                Button(action: { playbackManager.addToQueue(track) }) {
                                    VStack(spacing: 6) {
                                        Image(systemName: "text.badge.plus").font(.title3)
                                            .frame(width: 44, height: 44)
                                            .background(SangeetTheme.surfaceElevated).foregroundStyle(.white).clipShape(Circle())
                                        Text("Queue").font(.caption2).foregroundStyle(SangeetTheme.textSecondary)
                                    }
                                }.buttonStyle(.plain)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            // Metadata Grid
                            VStack(spacing: 16) {
                                MetadataRow(label: "Duration", value: track.formattedDuration)
                                MetadataRow(label: "Format", value: track.fileURL.pathExtension.uppercased())
                                
                                Button(action: {
                                    Task {
                                        await metadataManager.fixMetadata(for: track, libraryManager: libraryManager)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                        Text(metadataManager.isSearching ? "Searching..." : "Fix Metadata")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SangeetTheme.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(SangeetTheme.primary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                                .disabled(metadataManager.isSearching)
                            }
                            .padding(.horizontal)
                            
                            Spacer()
                        }
                        .padding(.bottom, 40)
                    }
                }
                .background(SangeetTheme.background.opacity(0.6)) // Panel background
                .background(.ultraThinMaterial)
            }
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).foregroundStyle(SangeetTheme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(.white).fontWeight(.medium)
        }
        .font(.subheadline)
    }
}
