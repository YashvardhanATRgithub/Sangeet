import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @EnvironmentObject var playlists: PlaylistStore
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    
    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Home", systemImage: "house").tag(SidebarSelection.home)
                Label("Search", systemImage: "magnifyingglass").tag(SidebarSelection.search)
            }
            
            Section("Library") {
                Label("Songs", systemImage: "music.note").tag(SidebarSelection.songs)
                Label("Albums", systemImage: "square.stack").tag(SidebarSelection.albums)
                Label("Artists", systemImage: "music.mic").tag(SidebarSelection.artists)
            }
            
            Section {
                Label("Favorites", systemImage: "heart.fill").tag(SidebarSelection.favorites)
                ForEach(playlists.playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarSelection.playlist(playlist.id))
                }
            } header: {
                HStack {
                    Text("Playlists")
                        .font(.headline)
                    Spacer()
                    Button(action: { showingNewPlaylist = true }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Playlist")
                    .padding(.trailing, 4)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
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
}
