
import SwiftUI

struct OnlineView: View {
    @StateObject private var viewModel = OnlineViewModel()
    @ObservedObject var networkMonitor = NetworkMonitor.shared
    @EnvironmentObject var libraryManager: LibraryManager // For trending data
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Search Bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SangeetTheme.textSecondary)
                    TextField("Search Tidal...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($isSearchFocused)
                    if !viewModel.searchText.isEmpty {
                        Button(action: { viewModel.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(SangeetTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(SangeetTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
            .frame(height: 80) // Fixed height to prevent layout shift
            .background(SangeetTheme.background)
            
            // Content
            ZStack {
                if viewModel.isSearching && !viewModel.searchText.isEmpty {
                    // Search Results
                    if viewModel.isLoading && viewModel.searchResults.isEmpty {
                        ProgressView().scaleEffect(1.5)
                    } else if viewModel.searchResults.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundStyle(SangeetTheme.textSecondary)
                            Text("No results found").foregroundStyle(SangeetTheme.textSecondary)
                        }
                    } else {
                        List {
                            ForEach(viewModel.searchResults) { track in
                                OnlineSongRow(track: track, onPlay: {
                                    viewModel.playTidalTrack(track)
                                }, onDownload: {
                                    viewModel.downloadTrack(track)
                                })
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    // Roaming / Trending
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            
                            // International
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Trending International")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(libraryManager.topSongs) { song in
                                            TrendingSongCard(song: song)
                                                .onTapGesture {
                                                    viewModel.playTrending(song)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                            
                            // India
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Trending India")
                                    .font(.title2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 16) {
                                        ForEach(libraryManager.trendingIndiaSongs) { song in
                                            TrendingSongCard(song: song)
                                                .onTapGesture {
                                                    viewModel.playTrending(song)
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                }
                            }
                            
                            // Legal Disclaimer
                            VStack(spacing: 8) {
                                Text("Disclaimer")
                                    .font(.caption.bold())
                                    .foregroundStyle(SangeetTheme.textSecondary)
                                    .padding(.top, 8)
                                
                                Text("This tool is provided for educational research purposes only. All content is sourced from the internet; the developer does not host or store any media. The developer assumes no liability for copyright infringement or misuse. Users are solely responsible for compliance with local laws and terms of service.")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .lineSpacing(4)
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 20)
                            
                            // Bottom Spacer for Floating Dock
                            Spacer()
                                .frame(height: 120)
                        }
                        .padding(.vertical, 24)
                    }
                }
                
                // Network / API Error Overlay
                if !networkMonitor.isConnected {
                    OfflineStateView(isAPIDown: false)
                        .transition(.opacity)
                        .zIndex(100)
                } else if !networkMonitor.apiReachable {
                    OfflineStateView(isAPIDown: true)
                        .transition(.opacity)
                        .zIndex(100)
                }
                
                // Loading Overlay
                if viewModel.isLoading {
                    Color.black.opacity(0.4)
                        .overlay(
                            VStack {
                                ProgressView()
                                Text("Loading...").font(.caption).padding(.top, 8)
                            }
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .cornerRadius(12)
                        )
                }
                
                // Error Toast (Simple)
                if let error = viewModel.errorMessage {
                    VStack {
                        HStack {
                            Spacer()
                            Text(error)
                                .foregroundStyle(.white)
                                .padding()
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .padding(.top, 60)
                                .padding(.trailing, 20)
                        }
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                             if viewModel.errorMessage == error { viewModel.errorMessage = nil }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = false
            }
        }
        .background(SangeetTheme.background)
        .onAppear {
            if libraryManager.topSongs.isEmpty {
                Task { await libraryManager.fetchTopSongs() }
            }
            if libraryManager.trendingIndiaSongs.isEmpty {
                 Task { await libraryManager.fetchTrendingIndia() }
            }
        }
    }
}

struct OnlineSongRow: View {
    let track: TidalTrack
    let onPlay: () -> Void
    let onDownload: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Artwork Placeholder
            AsyncImage(url: track.coverURL) { phase in
                switch phase {
                case .empty: Color.gray.opacity(0.3)
                case .success(let image): image.resizable()
                case .failure: Color.gray.opacity(0.3)
                @unknown default: Color.gray.opacity(0.3)
                }
            }
            .frame(width: 48, height: 48)
            .cornerRadius(6)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text("\(track.artistName) • \(track.albumName)")
                    .font(.caption)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Download button on hover
            if isHovering {
                TidalDownloadButton(track: track, size: 24, color: .white.opacity(0.8))
            }
            
            // Duration
            Text(formatDuration(track.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(SangeetTheme.textSecondary)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? SangeetTheme.surfaceElevated : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture { onPlay() }
        .onHover { isHovering = $0 }
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Network Utility (Inlined)
import Network
import Combine

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var isConnected: Bool = true
    @Published var apiReachable: Bool = true // Assume true initially
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isConnected = path.status == .satisfied
                
                if self.isConnected {
                    self.checkAPIHealth()
                } else {
                    self.apiReachable = false
                }
            }
        }
        monitor.start(queue: queue)
        checkAPIHealth()
    }
    
    func checkAPIHealth() {
        guard isConnected else {
             apiReachable = false
             return 
        }
        let healthURL = URL(string: "https://tidal-api.binimum.org/search/?s=test")!
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    self.apiReachable = true
                } else {
                    self.apiReachable = false 
                }
            }
        }.resume()
    }
}

// MARK: - Offline UI Component (Inlined)
struct OfflineStateView: View {
    var isAPIDown: Bool = false
    @State private var animate = false
    @State private var sparkOpacity = 0.0
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated Icon Container
            ZStack {
                // Glow buffer
                Circle()
                    .fill(isAPIDown ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .scaleEffect(animate ? 1.2 : 0.8)
                    .opacity(animate ? 0.0 : 0.5)
                    .animation(.easeOut(duration: 2).repeatForever(autoreverses: false), value: animate)
                
                // Broken Cable / Icon
                if isAPIDown {
                    // API Down: Server Rack with Warning
                    Image(systemName: "server.rack")
                        .font(.system(size: 60))
                        .foregroundStyle(.gray.opacity(0.5))
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.yellow)
                        .offset(x: 20, y: -25)
                        .scaleEffect(animate ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: animate)
                        
                } else {
                    // Internet Down: Broken Cable
                    ZStack {
                        // Cable Left
                        CablePath(isLeft: true)
                            .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 60, height: 40)
                            .offset(x: -35)
                        
                        // Cable Right
                        CablePath(isLeft: false)
                            .stroke(style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .foregroundStyle(.gray.opacity(0.3))
                            .frame(width: 60, height: 40)
                            .offset(x: 35)
                        
                        // Sparks
                        ForEach(0..<4) { i in
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 4, height: 4)
                                .offset(x: 0, y: CGFloat.random(in: -10...10))
                                .opacity(sparkOpacity)
                                .offset(x: animate ? 20 : -20, y: animate ? 15 : -15) // Random scatter logic simulated
                        }
                    }
                }
            }
            .onAppear {
                animate = true
                withAnimation(.easeInOut(duration: 0.1).repeatForever(autoreverses: true)) {
                    sparkOpacity = 1.0
                }
            }
            
            VStack(spacing: 8) {
                Text(isAPIDown ? "Server Unavailable" : "Connection Lost")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                Text(isAPIDown ? "The HiFi API server seems to be down.\nPlease check your local python server." : "It seems you are offline.\nCheck your internet connection.")
                    .font(.body)
                    .foregroundStyle(SangeetTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            if !isAPIDown {
                Button(action: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.network") {
                         NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Open Network Settings")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SangeetTheme.background.opacity(0.95)) 
    }
}

// Simple shape for broken cable
struct CablePath: Shape {
    var isLeft: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isLeft {
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addCurve(to: CGPoint(x: rect.width, y: rect.midY - 10), control1: CGPoint(x: rect.width/2, y: rect.midY), control2: CGPoint(x: rect.width/2, y: rect.midY - 10))
        } else {
            path.move(to: CGPoint(x: rect.width, y: rect.midY))
             path.addCurve(to: CGPoint(x: 0, y: rect.midY + 15), control1: CGPoint(x: rect.width/2, y: rect.midY), control2: CGPoint(x: rect.width/2, y: rect.midY + 15))
        }
        return path
    }
}
