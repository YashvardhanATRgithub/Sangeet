import SwiftUI

struct KaraokeContextMenu: View {
    let track: Track
    @ObservedObject var engine = KaraokeEngine.shared
    @Environment(\.openSettings) var openSettings // Custom environment key if we had one, or use Notification
    
    var body: some View {
        Group {
            Divider()
            
            // 1. Play Existing
            if engine.hasInstrumental(for: track) {
                Button {
                    if let url = engine.getInstrumentalPath(for: track) {
                        var instrumental = Track(url: url)
                        instrumental.title = "\(track.title) (Karaoke)"
                        instrumental.artist = track.artist
                        instrumental.album = track.album
                        instrumental.duration = track.duration
                        instrumental.artworkData = track.artworkData
                        PlaybackController.shared.play(track: instrumental)
                    }
                } label: {
                    Label("Play Karaoke Version", systemImage: "music.mic")
                }
            }
            // 2. Processing (Global state - ideally should be per track, but engine is singleton for now)
            else if case .processing = engine.state {
                 Button {} label: {
                     Label("Processing Karaoke...", systemImage: "hourglass")
                 }
                 .disabled(true)
            }
            // 3. Create New (If Ready)
            else if engine.state == .ready {
                Button {
                    Task {
                        do {
                            let url = try await engine.createInstrumental(for: track)
                            // Success: Already handled by UI state update if observing engine,
                            // or distinct notification. We don't auto-open finder anymore.
                            Logger.info("Karaoke created at: \(url.path)")
                        } catch {
                            Logger.error("Karaoke creation failed: \(error)")
                            // Ideally show an alert here, but for now log it
                        }
                    }
                } label: {
                    Label("Create Karaoke Version", systemImage: "wand.and.stars")
                }
            }
            // 4. Configure (If Not Ready)
            else {
                Button {
                    // Open Settings
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Label("Configure Karaoke...", systemImage: "gear")
                }
            }
        }
    }
}
