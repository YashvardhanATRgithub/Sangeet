//
//  DownloadManager.swift
//  Sangeet3
//
//  Offline-only version (Online features removed)
//

import Foundation
import Combine

@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    // MARK: - State
    // No active downloads since online is removed
    @Published var lastError: String?
    
    override init() {
        super.init()
    }
}

