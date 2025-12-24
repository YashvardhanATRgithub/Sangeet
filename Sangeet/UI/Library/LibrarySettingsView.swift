import SwiftUI

struct LibrarySettingsView: View {
    @EnvironmentObject var services: AppServices
    @State private var folders: [URL] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Library Folders")
                .font(.headline)
            
            List {
                ForEach(folders, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(Theme.accent)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        
                        Button {
                            removeFolder(url)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(height: 200)
            .listStyle(.plain)
            .overlay(folders.isEmpty ? Text("No folders added").foregroundStyle(.secondary) : nil)
            
            HStack {
                Button("Add Folder") {
                    importFolder()
                }
                Spacer()
                Button("Clear All") {
                    // Not implemented in DB manager yet efficiently, doing loop
                    let allFolders = services.database.getAllFolders()
                    Task {
                        for folder in allFolders {
                            try? await services.database.removeFolder(folder)
                        }
                        await MainActor.run { refresh() }
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            refresh()
        }
    }
    
    func refresh() {
        folders = services.database.getAllFolders().map { $0.url }
    }
    
    func removeFolder(_ url: URL) {
        Task {
            if let folder = services.database.getAllFolders().first(where: { $0.url == url }) {
                try? await services.database.removeFolder(folder)
            }
            await MainActor.run { refresh() }
        }
    }
    
    func importFolder() {
        // Delegate to DatabaseManager's addFolder which handles the NSOpenPanel
        services.database.addFolder()
        // We'll refresh on appear or via notification, but let's delay a bit to catch instant updates
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
           refresh()
        }
    }
}
