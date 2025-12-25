//
//  EmptyStateView.swift
//  Sangeet
//
//  Reusable empty state component matching Favorites section style
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))
            
            Text(title)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "music.note",
        title: "No Music",
        message: "Import music folders to get started."
    )
    .background(Color.black)
}
