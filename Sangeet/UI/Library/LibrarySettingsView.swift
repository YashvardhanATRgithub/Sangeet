import SwiftUI

struct LibrarySettingsView: View {
    @EnvironmentObject var services: AppServices
    @State private var folders: [URL] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library Folders")
                    .font(.title2.bold())
                Text("Manage where Sangeet looks for your music.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top)
            
            List {
                ForEach(folders, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .font(.body.weight(.medium))
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button {
                            removeFolder(url)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary) // Subtle default
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                    .padding(.vertical, 8)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(Color.black.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .overlay(folders.isEmpty ? Text("No folders added").foregroundStyle(.secondary) : nil)
            .frame(height: 300) // Taller list
            .padding(.horizontal)
            
            HStack {
                Button(action: { importFolder() }) {
                    Label("Add Folder", systemImage: "plus.circle.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                
                Spacer()
                
                Button("Clear All") {
                    let allFolders = services.database.getAllFolders()
                    Task {
                        for folder in allFolders {
                            try? await services.database.removeFolder(folder)
                        }
                        await MainActor.run { refresh() }
                    }
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)
                .opacity(folders.isEmpty ? 0.5 : 1)
                .disabled(folders.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 550) // Signficantly wider
        .background(Theme.background)
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
