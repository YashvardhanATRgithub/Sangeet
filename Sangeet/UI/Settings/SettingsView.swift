import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .appearance
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance
        case library
        case audio
        case advanced
        case about
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .appearance: return "Appearance"
            case .library: return "Library"
            case .audio: return "Audio"
            case .advanced: return "Advanced"
            case .about: return "About"
            }
        }
        
        var icon: String {
            switch self {
            case .appearance: return "paintbrush.fill"
            case .library: return "music.note.list"
            case .audio: return "speaker.wave.3.fill"
            case .advanced: return "gearshape.2.fill"
            case .about: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                
                ForEach(SettingsTab.allCases) { tab in
                    SettingsSidebarButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
                
                Spacer()
            }
            .frame(width: 200)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Content
            VStack {
                switch selectedTab {
                case .appearance:
                    ScrollView {
                        AppearanceSettingsView()
                            .padding()
                    }
                case .library:
                    LibrarySettingsView()
                case .audio:
                    ScrollView {
                        AudioSettingsView()
                            .padding()
                    }
                case .advanced:
                    ScrollView {
                        AdvancedSettingsView()
                            .padding()
                    }
                case .about:
                    ScrollView {
                        AboutSettingsView()
                            .padding()
                    }
                }
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .frame(width: 750, height: 500)
    }
}

private struct SettingsSidebarButton: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Theme.accent.opacity(0.1) : (isHovered ? Color.secondary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
    }
}
