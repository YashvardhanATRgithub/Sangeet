//
//  TopBarMetadataIndicator.swift
//  Sangeet
//
//  Created by SangeetDev on 10/01/26.
//

import SwiftUI

struct TopBarMetadataIndicator: View {
    @ObservedObject var metadataManager = SmartMetadataManager.shared
    @State private var isHovered = false
    
    var body: some View {
        if metadataManager.isBulkFixing {
            HStack(spacing: 8) {
                // Animated Icon
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                
                // Progress Text
                if isHovered {
                    Text("\(metadataManager.processedCount) / \(metadataManager.totalCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
                // Circular Progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    
                    Circle()
                        .trim(from: 0, to: Double(metadataManager.processedCount) / Double(max(1, metadataManager.totalCount)))
                        .stroke(SangeetTheme.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: metadataManager.processedCount)
                }
                .frame(width: 18, height: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .onHover { hovering in
                withAnimation(.snappy) {
                    isHovered = hovering
                }
            }
        }
    }
}
