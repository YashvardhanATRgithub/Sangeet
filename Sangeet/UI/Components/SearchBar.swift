//
//  SearchBar.swift
//  Sangeet
//
//  Clean search bar implementation with proper focus handling
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? .primary : .secondary)
                .font(.system(size: 16, weight: .medium))
            
            TextField("Search songs, artists, albums...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
            
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minWidth: 300, maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .strokeBorder(Color.primary.opacity(isFocused ? 0.15 : 0), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(isFocused ? 0.1 : 0.03), radius: isFocused ? 10 : 4, y: 2)
        )
        .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}
