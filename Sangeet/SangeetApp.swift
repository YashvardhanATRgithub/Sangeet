//
//  SangeetApp.swift
//  Sangeet
//
//  Created by Yashvardhan . on 12/22/25.
//

import SwiftUI
import AppKit

@main
struct SangeetApp: App {
    @StateObject private var services = AppServices.shared
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var playlistStore = PlaylistStore()
    @StateObject private var appTheme = AppTheme.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(services)
                .environmentObject(libraryStore)
                .environmentObject(playlistStore)

        }
        // Standard window that supports native macOS full screen
        .windowStyle(.automatic)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.automatic)
        
        // Provide a dedicated full-screen command (mirrors green button behavior)
        .commands {
            CommandGroup(replacing: .newItem) { } // Remove New...
            
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
            
            CommandGroup(after: .toolbar) {
                Button("Play/Pause") {
                    AppServices.shared.playback.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("Seek Forward 5s") {
                    let s = AppServices.shared.playback
                    s.seek(to: s.currentTime + 5)
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                
                Button("Seek Backward 5s") {
                    let s = AppServices.shared.playback
                    s.seek(to: s.currentTime - 5)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }
        }
    }
}
