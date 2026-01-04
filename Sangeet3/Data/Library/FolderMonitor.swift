//
//  FolderMonitor.swift
//  Sangeet3
//
//  Created by Sangeet AI on 31/12/24.
//

import Foundation

/// Monitors a directory for file changes using DispatchSource
class FolderMonitor {
    private let url: URL
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "com.sangeet.foldermonitor", attributes: .concurrent)
    
    var onDidChange: (() -> Void)?
    
    init(url: URL) {
        self.url = url
    }
    
    func start() {
        guard source == nil, fileDescriptor == -1 else { return }
        
        // Open the directory
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            print("[FolderMonitor] Failed to open: \(url.path)")
            return
        }
        
        // Create the source
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: queue
        )
        
        source?.setEventHandler { [weak self] in
            // Debounce or forward event
            self?.onDidChange?()
        }
        
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
            self.source = nil
        }
        
        source?.resume()
    }
    
    func stop() {
        source?.cancel()
    }
    
    deinit {
        stop()
    }
}
