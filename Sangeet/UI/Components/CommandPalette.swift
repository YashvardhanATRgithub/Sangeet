import SwiftUI

struct CommandPalette: View {
    @EnvironmentObject var services: AppServices
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var results: [Track] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                TextField("Type a command or search...", text: $query)
                    .font(.title2)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, newValue in
                        performSearch(newValue)
                    }
                    .onSubmit {
                        if let first = results.first {
                            play(first)
                        }
                    }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if results.isEmpty && !query.isEmpty {
                Text("No results found")
                    .padding()
                    .foregroundStyle(.secondary)
            } else {
                List(results) { track in
                    Button {
                        play(track)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(track.title).fontWeight(.medium)
                                Text(track.artist).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Play")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 520)
        .glassCard(cornerRadius: 16)
        .padding(.top, -160) // Visual offset center
    }
    
    func performSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            return
        }
        
        Task {
            // Using search service
            let ids = services.search.search(query: trimmed)
            // Fetch tracks (inefficient in bulk loop, better to have bulk fetch by IDs, but okay for prototype)
            // For now, search service is in-memory but returns IDs.
            // Ideally SearchService should return cached lightweight objects or we fetch from DB.
            var loaded: [Track] = []
                
            // Optimization: In real app, DB fetch by IDs
            let all = try? await services.database.fetchAllTracks()
            if let all = all {
                 loaded = all.filter { ids.contains($0.id) }
            }
            
            await MainActor.run {
                self.results = Array(loaded.prefix(10))
            }
        }
    }
    
    func play(_ track: Track) {
        services.playback.play(track)
        isPresented = false
    }
}

// Modifier to present nicely
struct CommandPaletteModifier: ViewModifier {
    @Binding var isPresented: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isPresented {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture { isPresented = false }
                
                CommandPalette(isPresented: $isPresented)
            }
        }
    }
}
