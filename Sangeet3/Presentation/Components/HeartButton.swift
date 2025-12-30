//
//  HeartButton.swift
//  Sangeet3
//
//  Created for Sangeet
//

import SwiftUI

struct HeartButton: View {
    let track: Track
    var size: CGFloat = 20
    var color: Color = .white
    
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var isAnimating = false
    
    var isFavorite: Bool {
        libraryManager.tracks.first(where: { $0.id == track.id })?.isFavorite ?? track.isFavorite
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                libraryManager.toggleFavorite(track)
                isAnimating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isAnimating = false
            }
        }) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: size))
                .foregroundStyle(isFavorite ? .red : color)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
    }
}
