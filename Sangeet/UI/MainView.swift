import SwiftUI
import AppKit

struct MainView: View {
    @State private var selection: SidebarSelection? = .home
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showQueue = false
    @State private var showCommandPalette = false
    @State private var showFullScreenPlayer = false
    @State private var nowPlayingBarHeight: CGFloat = NowPlayingBarDefaults.minHeight
    @State private var cachedToolbarVisibility: Bool?
    @State private var didApplyBaseWindowStyle = false
    @State private var showingLibrarySettings = false
    @State private var showingEqualizer = false
    @State private var showLyricsInFullScreen = false
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main Layout Container
            VStack(spacing: 0) {
                // Layer 1: Custom Top Bar
                if !showFullScreenPlayer {
                    topBar
                }
                
                // Layer 2: Main Content
                HStack(spacing: 0) {
                    // Left Sidebar (Manual)
                    if columnVisibility == .all {
                    SidebarView(selection: $selection)
                        .frame(width: 300)
                        .overlay(
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(width: 1),
                            alignment: .trailing
                        )
                        .transition(.move(edge: .leading))
                }

                NavigationStack(path: $navigationPath) {
                    ZStack {
                        if let selection = selection {
                            Group {
                                switch selection {
                                case .home:
                                    HomeView()
                                case .songs:
                                    LibrarySongsView()
                                case .albums:
                                    LibraryAlbumsView()
                                case .artists:
                                    LibraryArtistsView()
                                case .search:
                                    SearchView()
                                case .favorites:
                                    LibraryFavoritesView()
                                case .playlist(let id):
                                    PlaylistDetailView(playlistID: id)
                                        .id(id)
                                }
                            }
                            .transition(.opacity)
                        } else {
                            Text("Select an item")
                                .transition(.opacity)
                        }
                    }
                .navigationDestination(for: Artist.self) { artist in
                        ArtistDetailView(artist: artist)
                    }
                    .navigationDestination(for: Album.self) { album in
                        AlbumDetailView(album: album)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: selection)
            }
            .background(Theme.background)
            
            }
            
            // Layer 3: Player Bar (Always Mounted to preserve state)
            NowPlayingBar(
                showFullScreen: $showFullScreenPlayer,
                onOpenLyrics: {
                    showFullScreenPlayer = true
                    showLyricsInFullScreen = true
                },
                onOpenEqualizer: {
                    showingEqualizer = true
                }
            )
            .offset(y: showFullScreenPlayer ? 150 : 0) // Slide down
            .opacity(showFullScreenPlayer ? 0 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFullScreenPlayer)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .zIndex(9)
            
            // Layer 2.5: Queue Drawer
            if showQueue {
                QueueView()
                    .frame(width: 300)
                    .background(Theme.background)
                    .transition(.move(edge: .trailing))
                    .overlay(
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(width: 1),
                        alignment: .leading
                    )
                    .padding(.top, 68)
                    .padding(.bottom, nowPlayingBarHeight + 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .zIndex(25)
            }
            
            // Layer 4: Command Palette & Shortcuts
            Color.clear
                .modifier(CommandPaletteModifier(isPresented: $showCommandPalette))
                .background {
                    Group {
                         Button(action: { AppServices.shared.playback.togglePlayPause() }) { }
                            .keyboardShortcut(.space, modifiers: [])
                         Button(action: { showCommandPalette.toggle() }) { }
                            .keyboardShortcut("k", modifiers: .command)
                    }
                    .opacity(0)
                }
  
            // Layer 5: Settings Modal
            if showingLibrarySettings {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingLibrarySettings = false
                            }
                        }
                    
                    SettingsView()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .overlay(
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingLibrarySettings = false 
                                }
                            }) {
                                 Image(systemName: "xmark.circle.fill")
                                     .font(.system(size: 22))
                                     .foregroundStyle(.secondary)
                                     .background(Circle().fill(Theme.background).padding(2))
                            }
                            .buttonStyle(.plain)
                            .padding(12),
                            alignment: .topTrailing
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(100)
                .transition(.opacity)
            }
            
            // Layer 6: Equalizer Modal
            if showingEqualizer {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingEqualizer = false
                            }
                        }
                    
                    EqualizerView()
                        .frame(width: 750, height: 500)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                        .overlay(
                            Button(action: { 
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showingEqualizer = false 
                                }
                            }) {
                                 Image(systemName: "xmark.circle.fill")
                                     .font(.system(size: 22))
                                     .foregroundStyle(.secondary)
                                     .background(Circle().fill(Theme.background).padding(2))
                            }
                            .buttonStyle(.plain)
                            .padding(12),
                            alignment: .topTrailing
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(100)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.nowPlayingBarHeight, nowPlayingBarHeight)
        .onAppear {
            applyBaseWindowStyleIfNeeded()
        }
        .overlay {
            // Keep FullScreenPlayerView always mounted to preserve state/subscriptions
            FullScreenPlayerView(
                isPresented: $showFullScreenPlayer,
                playback: AppServices.shared.playback,
                showLyrics: $showLyricsInFullScreen
            )
                .offset(y: showFullScreenPlayer ? 0 : 1500) // Slide off-screen
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showFullScreenPlayer)
                .zIndex(10)
        }
        .onPreferenceChange(NowPlayingBarHeightPreferenceKey.self) { height in
            if height > 0 {
                nowPlayingBarHeight = max(height, NowPlayingBarDefaults.minHeight)
            }
        }
        .onChange(of: showFullScreenPlayer) { _, isPresented in
            updateWindowForFullScreenPlayer(isPresented)
        }
        .animation(.easeInOut(duration: 0.2), value: showFullScreenPlayer)
        .animation(.spring(response: 0.35, dampingFraction: 1), value: showQueue)
        .onReceive(NotificationCenter.default.publisher(for: .toggleQueue)) { _ in
            showQueue.toggle()
        }
        .onChange(of: selection) { _, _ in
            navigationPath = NavigationPath()
        }
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                NeonBrandingView()
                
                Button(action: {
                    withAnimation {
                        if columnVisibility == .detailOnly {
                            columnVisibility = .all
                        } else {
                            columnVisibility = .detailOnly
                        }
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 18))
                        .foregroundStyle(columnVisibility == .all ? Theme.accent : .secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(columnVisibility == .all ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
            .layoutPriority(1)
            .padding(.leading, 68) // Adjusted to be tighter (Standard Traffic Light width)
            
            Spacer()
            
            // Search Bar (Center)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                
                Text("What do you want to play?")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 200, maxWidth: 400) // Flexible width
            .frame(height: 36)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
            .onTapGesture {
                selection = .search
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                 Button(action: { showQueue.toggle() }) {
                     Image(systemName: "sidebar.right")
                        .font(.system(size: 18))
                        .foregroundStyle(showQueue ? Theme.accent : .secondary)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showQueue ? Theme.accent.opacity(0.15) : Color.clear)
                        )
                 }
                 .buttonStyle(.plain)
                 
                 Button(action: { showingLibrarySettings = true }) {
                     Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                 }
                 .buttonStyle(.plain)
            }
            .layoutPriority(1)
            .padding(.trailing, 68) // Match Left Padding (Symmetry)
        }
        .frame(height: 68)
        .background(Theme.background)
        .overlay(
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private func applyBaseWindowStyleIfNeeded() {
        guard !didApplyBaseWindowStyle else { return }
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        applyBaseWindowStyle(window)
        didApplyBaseWindowStyle = true
    }
    
    private func updateWindowForFullScreenPlayer(_ isPresented: Bool) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        
        if isPresented {
            if cachedToolbarVisibility == nil {
                cachedToolbarVisibility = window.toolbar?.isVisible
            }
            
            window.toolbar?.isVisible = false
            applyBaseWindowStyle(window)
        } else {
            applyBaseWindowStyle(window)
            if let cachedToolbarVisibility {
                window.toolbar?.isVisible = cachedToolbarVisibility
            }
            
            self.cachedToolbarVisibility = nil
        }
    }

    private func applyBaseWindowStyle(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.styleMask.insert(.fullSizeContentView)
        
        // Match HiFidelity style
        window.toolbar?.insertItem(withItemIdentifier: .init("separator"), at: 0)
        
        if let toolbar = window.toolbar {
            toolbar.displayMode = .iconOnly
            toolbar.isVisible = true // Ensure toolbar is visible for traffic lights to render correctly in unifiedCompact
        }
    }
}

enum SidebarSelection: Hashable {
    case home
    case songs
    case albums
    case artists
    case search
    case favorites
    case playlist(UUID)
}
