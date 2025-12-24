import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @EnvironmentObject var playlists: PlaylistStore
    @ObservedObject var theme = AppTheme.shared
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                // Main Links
                Group {
                    sidebarItem(title: "Home", icon: "house.fill", selection: .home)
                }
                
                // Library
                VStack(spacing: 2) {
                    sectionHeader("Library")
                    sidebarItem(title: "Songs", icon: "music.note", selection: .songs)
                    sidebarItem(title: "Albums", icon: "square.stack.fill", selection: .albums)
                    sidebarItem(title: "Artists", icon: "music.mic", selection: .artists)
                }
                
                // Playlists
                VStack(spacing: 2) {
                    HStack {
                        sectionHeader("Playlists")
                        Spacer()
                        Button(action: { showingNewPlaylist = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 20)
                    }
                    
                    sidebarItem(title: "Favorites", icon: "heart.fill", selection: .favorites)
                    
                    ForEach(playlists.playlists) { playlist in
                        sidebarItem(title: playlist.name, icon: "music.note.list", selection: .playlist(playlist.id))
                            .contextMenu {
                                Button(role: .destructive) {
                                    if selection == .playlist(playlist.id) {
                                        selection = .songs
                                    }
                                    playlists.delete(id: playlist.id)
                                } label: {
                                    Label("Delete Playlist", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 90)
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.02))
        .alert("New Playlist", isPresented: $showingNewPlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                if let id = playlists.create(name: newPlaylistName) {
                    selection = .playlist(id)
                }
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
        } message: {
            Text("Give your playlist a name.")
        }
    }
    
    @ViewBuilder
    private func sidebarItem(title: String, icon: String, selection: SidebarSelection) -> some View {
        let isSelected = self.selection == selection
        
        Button(action: { self.selection = selection }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? theme.currentTheme.primaryColor : Color.secondary)
                
                Text(title)
                    .font(.system(size: 14, weight: .medium)) // HiFi: AppFonts.sidebarItem
                    .foregroundStyle(isSelected ? theme.currentTheme.primaryColor : Color.primary) // HiFi uses Primary Color for selected text too often
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.currentTheme.primaryColor.opacity(0.1) : Color.clear) // HiFi Selection Style
            )
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold)) // HiFi: Caption style for headers
                .foregroundStyle(Color.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12) // Aligned with items (12px padding inside item)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 6)
        .padding(.horizontal, 8) // Match item outer padding
    }
    

}
