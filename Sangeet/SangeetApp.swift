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
    
    var body: some Scene {
        WindowGroup(" ") {
            ContentView()
                .environmentObject(services)
                .environmentObject(services.playlists)
        }
        // Standard window that supports native macOS full screen
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .windowResizability(.automatic)
        
        // Provide a dedicated full-screen command (mirrors green button behavior)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
    }
}
