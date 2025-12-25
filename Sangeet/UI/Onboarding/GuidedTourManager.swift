//
//  GuidedTourManager.swift
//  Sangeet
//
//  Interactive guided tour for first-time users with spotlight highlighting
//

import SwiftUI
import Combine

/// Manages the interactive guided tour with spotlight highlighting
class GuidedTourManager: ObservableObject {
    static let shared = GuidedTourManager()
    
    @Published var isActive: Bool = false
    @Published var currentStep: TourStep = .welcome
    
    private var hasCheckedTour = false
    
    private init() {
        // Tour will be started from MainView.onAppear
    }
    
    /// Marker file to track when tour was completed
    private var tourMarkerURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sangeetDir = appSupport.appendingPathComponent("Sangeet", isDirectory: true)
        return sangeetDir.appendingPathComponent(".tour_completed")
    }
    
    /// Get the app bundle's creation/modification date
    private var appInstallDate: Date? {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: bundlePath)
        // Use creation date, fallback to modification date
        return (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date)
    }
    
    /// Get the marker file's creation date
    private var markerDate: Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: tourMarkerURL.path)
        return attrs?[.creationDate] as? Date
    }
    
    /// Check if tour should be shown
    /// Returns true if: marker doesn't exist OR app is newer than marker (reinstall)
    private var shouldShowTour: Bool {
        // If marker doesn't exist, show tour
        guard FileManager.default.fileExists(atPath: tourMarkerURL.path) else {
            return true
        }
        
        // If app install date is newer than marker date, this is a reinstall - show tour
        if let appDate = appInstallDate, let marker = markerDate {
            return appDate > marker
        }
        
        return false
    }
    
    private func markTourCompleted() {
        let dir = tourMarkerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Delete old marker and create new one with current timestamp
        try? FileManager.default.removeItem(at: tourMarkerURL)
        FileManager.default.createFile(atPath: tourMarkerURL.path, contents: nil)
    }
    
    /// Called from MainView.onAppear to check and start tour if needed
    func checkAndStartTourIfNeeded() {
        guard !hasCheckedTour else { return }
        hasCheckedTour = true
        
        // Show tour if this is a fresh install or reinstall
        if shouldShowTour {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.startTour()
            }
        }
    }
    
    /// Tour steps - each highlights a specific UI element
    enum TourStep: Int, CaseIterable {
        case welcome
        case settingsButton
        case equalizerButton
        case karaokeButton
        case lyricsButton
        case fullscreenButton
        case complete
        
        var title: String {
            switch self {
            case .welcome: return "Welcome to Sangeet! 🎵"
            case .settingsButton: return "Add Your Music"
            case .equalizerButton: return "Professional Equalizer"
            case .karaokeButton: return "One-Click Karaoke"
            case .lyricsButton: return "Time-Synced Lyrics"
            case .fullscreenButton: return "Full Screen Mode"
            case .complete: return "You're All Set! 🎉"
            }
        }
        
        var description: String {
            switch self {
            case .welcome:
                return "Let's take a quick tour. Click Next or tap anywhere to continue."
            case .settingsButton:
                return "Click here to open Settings and add your music folders."
            case .equalizerButton:
                return "Fine-tune your audio with the 10-band EQ and 15+ presets."
            case .karaokeButton:
                return "Reduce vocals instantly for sing-along sessions!"
            case .lyricsButton:
                return "View time-synced lyrics that follow along with your music."
            case .fullscreenButton:
                return "Expand to full screen for an immersive experience."
            case .complete:
                return "Enjoy your music! Press ⌘K for the Command Palette."
            }
        }
        
        var targetElementID: String? {
            switch self {
            case .welcome, .complete: return nil
            case .settingsButton: return "tour-settings-button"
            case .equalizerButton: return "tour-equalizer-button"
            case .karaokeButton: return "tour-karaoke-button"
            case .lyricsButton: return "tour-lyrics-button"
            case .fullscreenButton: return "tour-fullscreen-button"
            }
        }
        
        var tooltipPosition: TooltipPosition {
            switch self {
            case .welcome, .complete: return .center
            case .settingsButton: return .below
            case .equalizerButton, .karaokeButton, .lyricsButton, .fullscreenButton: return .above
            }
        }
    }
    
    enum TooltipPosition {
        case above, below, left, right, center
    }
    
    func startTour() {
        currentStep = .welcome
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isActive = true
        }
    }
    
    func nextStep() {
        let allSteps = TourStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex + 1 < allSteps.count {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep = allSteps[currentIndex + 1]
            }
            
            if currentStep == .complete {
                // Auto-dismiss after showing complete message
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.completeTour()
                }
            }
        } else {
            completeTour()
        }
    }
    
    func skipTour() {
        completeTour()
    }
    
    func completeTour() {
        withAnimation(.easeOut(duration: 0.3)) {
            isActive = false
        }
        markTourCompleted()
    }
    
    /// Called when a tour target is clicked - advances if it matches current step
    func handleTargetClick(id: String) {
        if let targetID = currentStep.targetElementID, targetID == id {
            nextStep()
        }
    }
}

// MARK: - Tour Highlight Preference Key
struct TourHighlightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Tour Target Modifier
extension View {
    /// Marks this view as a tour target that advances the tour when clicked
    func tourTarget(id: String) -> some View {
        self
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: TourHighlightPreferenceKey.self,
                            value: [id: geo.frame(in: .global)]
                        )
                }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        GuidedTourManager.shared.handleTargetClick(id: id)
                    }
            )
    }
}
