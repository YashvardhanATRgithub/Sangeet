//
//  ProgressLine.swift
//  Sangeet3
//
//  Created by Yashvardhan on 29/12/24.
//

import SwiftUI

struct ProgressLine: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var progress: Double {
        guard playbackManager.duration > 0 else { return 0 }
        return isDragging ? dragProgress : playbackManager.currentTime / playbackManager.duration
    }
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progressX = width * progress
            
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 2)
                Rectangle().fill(SangeetTheme.accentGradient).frame(width: progressX, height: 3)
                RoundedRectangle(cornerRadius: 3).fill(.white).frame(width: 6, height: isDragging ? 18 : 14)
                    .shadow(color: SangeetTheme.glowShadow, radius: 6)
                    .position(x: max(3, min(width - 3, progressX)), y: geo.size.height / 2)
                    .animation(.spring(response: 0.2), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        isDragging = true
                        dragProgress = min(max(0, v.location.x / width), 1)
                    }
                    .onEnded { _ in
                        playbackManager.seek(to: dragProgress * playbackManager.duration)
                        isDragging = false
                    }
            )
        }
        .frame(height: 16)
        .padding(.horizontal, 24)
    }
}
