//
//  SearchBar.swift
//  Sangeet
//
//  Ported from HiFidelity for robust search interaction
//

import SwiftUI

struct SearchBar: View {
    @Binding var text: String
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? .primary : .secondary)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.hierarchical)
            
            TextField("What do you want to play?", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                // Remove onCommit/onSubmit if not strictly needed, relying on onChange
                .onSubmit {
                    if !text.isEmpty {
                        isActive = true
                    }
                }
            
            if !text.isEmpty {
                Button {
                    text = ""
                    isActive = false
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
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
                        .strokeBorder(Color.primary.opacity(isFocused ? 0.1 : 0), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(isFocused ? 0.08 : 0.03), radius: isFocused ? 8 : 4, y: 2)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        .onChange(of: text) { _, newValue in
            if newValue.isEmpty {
                 // Don't auto-dismiss active search on clear unless explicit? 
                 // HiFi does: isActive = false
                 isActive = false
            } else if newValue.count >= 1 { // Sangeet Preference: 1 char enough? HiFi used 2
                isActive = true
            }
        }
        .onChange(of: isActive) { _, active in
            if !active {
                isFocused = false
            } else if text.count >= 1 {
                isFocused = true
            }
        }
        // If we want to verify tap focus
        .onTapGesture {
             isFocused = true
        }
    }
}
