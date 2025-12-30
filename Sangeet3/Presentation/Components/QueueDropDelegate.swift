//
//  QueueDropDelegate.swift
//  Sangeet3
//
//  Created by Yashvardhan on 30/12/24.
//
//  Custom drop delegate for reordering queue items in LazyVStack
//

import SwiftUI
import UniformTypeIdentifiers

struct QueueDropDelegate: DropDelegate {
    let item: Track
    @Binding var current: Track?
    @Binding var changedView: Bool
    let action: (Track, Track) -> Void
    
    func dropEntered(info: DropInfo) {
        // Debounce visually if needed, or update immediately
        if let current = current, current != item {
            changedView.toggle()
            action(current, item)
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        self.current = nil
        return true
    }
}
