import SwiftUI
import AppKit

struct MainView: View {
    @State private var selection: SidebarSelection? = .home
    @State private var showQueue = false
    @State private var showCommandPalette = false
    @State private var showFullScreenPlayer = false
    @State private var nowPlayingBarHeight: CGFloat = NowPlayingBarDefaults.minHeight
    @State private var cachedToolbarVisibility: Bool?
    @State private var didApplyBaseWindowStyle = false
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selection: $selection)
                    .navigationTitle("")
            } detail: {
                NavigationStack {
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
                            .id(selection)
                            .transition(.opacity)
                        } else {
                            Text("Select an item")
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: selection)
                .padding(.top, !showFullScreenPlayer ? 38 : 0)
            }
            .inspector(isPresented: $showQueue) {
                 QueueView()
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                     NeonBrandingView()
                }
                
                ToolbarItem {
                    HStack(spacing: 12) {
                        Button(action: importMusic) {
                            Label("Import", systemImage: "arrow.down.doc")
                        }
                        .help("Import Music (Cmd+O)")
                        
                        Button(action: { showQueue.toggle() }) {
                            Image(systemName: "list.bullet")
                        }
                        .help("Queue")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(showFullScreenPlayer ? .hidden : .visible, for: .windowToolbar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !showFullScreenPlayer {
                    NowPlayingBar(showFullScreen: $showFullScreenPlayer)
                }
            }

            .modifier(CommandPaletteModifier(isPresented: $showCommandPalette))
            .background {
                // Invisible buttons to capture shortcuts if needed, mostly modifier works on Window
                Group {
                    Button("") { showCommandPalette.toggle() }
                        .keyboardShortcut("k", modifiers: .command)
                    Button("") { AppServices.shared.playback.togglePlayPause() }
                        .keyboardShortcut(.space, modifiers: [])
                }
                .opacity(0)
            }
            .background(Theme.background)
        }
        .environment(\.nowPlayingBarHeight, nowPlayingBarHeight)
        .onAppear {
            applyBaseWindowStyleIfNeeded()
        }
        .overlay {
            if showFullScreenPlayer {
                FullScreenPlayerView(isPresented: $showFullScreenPlayer, playback: AppServices.shared.playback)
                    .transition(.opacity)
                    .zIndex(10)
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .toggleQueue)) { _ in
            showQueue.toggle()
        }
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
    
    private func importMusic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task {
                let directories = AppServices.shared.libraryAccess.directoryURLs(from: urls)
                AppServices.shared.libraryAccess.addBookmarks(for: directories)
                try? await AppServices.shared.library.startScan(directories: urls)
                await AppServices.shared.search.buildIndex()
                NotificationCenter.default.post(name: .libraryDidUpdate, object: nil)
            }
        }
    }

    private func applyBaseWindowStyle(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.styleMask.insert(.fullSizeContentView)
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
