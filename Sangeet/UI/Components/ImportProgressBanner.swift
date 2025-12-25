//
//  ImportProgressBanner.swift
//  Sangeet
//
//  Shows import progress when scanning music folders
//

import SwiftUI

struct ImportProgressBanner: View {
    @ObservedObject var db = DatabaseManager.shared
    @ObservedObject var theme = AppTheme.shared
    
    var body: some View {
        if db.isImporting {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // Spinning indicator
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    // Status text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(db.currentImportingFolder.isEmpty ? "Importing..." : "Importing '\(db.currentImportingFolder)'")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        
                        if !db.importStatusMessage.isEmpty {
                            Text(db.importStatusMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    
                    Spacer()
                    
                    // Progress percentage
                    Text("\(Int(db.importProgress * 100))%")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.2))
                        
                        Capsule()
                            .fill(theme.currentTheme.primaryColor)
                            .frame(width: geo.size.width * db.importProgress)
                            .animation(.spring(response: 0.3), value: db.importProgress)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.currentTheme.primaryColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: db.isImporting)
        }
    }
}
