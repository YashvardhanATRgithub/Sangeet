import SwiftUI
import AppKit

struct KaraokeSettingsView: View {
    @StateObject private var engine = KaraokeEngine.shared
    @State private var inputPath: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Vocal Separation")
                            .font(.headline)
                        Text("Build: 3.1 (Polish)")
                            .font(.caption2)
                            .padding(4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                    
                    Text("Sangeet uses the Spleeter library to separate vocals from instruments. This requires a working Python 3.9+ installation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if engine.state == .notConfigured {
                        Text("⚠️ Configuration Required")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                    
                    HStack {
                        TextField("Python Executable Path", text: $inputPath)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: inputPath) { _ in
                                isEditing = true
                            }
                        
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            panel.treatsFilePackagesAsDirectories = false
                            
                            if panel.runModal() == .OK, let url = panel.url {
                                inputPath = url.path
                                Task { await engine.setPythonPath(url.path) }
                            }
                        }
                        
                        Button("Validate") {
                            isEditing = false
                            Task {
                                await engine.setPythonPath(inputPath)
                            }
                        }
                        .disabled(inputPath.isEmpty)
                    }
                    
                    // Status Indicator
                    HStack {
                        StatusIcon(state: engine.state)
                        Text(engine.state.description)
                            .font(.callout)
                            .foregroundColor(KaraokeSettingsView.statusColor(for: engine.state))
                        
                        if engine.state == .validating {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                    }
                    .padding(.top, 4)
                    
                    if case .missingSpleeter = engine.state {
                        VStack(alignment: .leading) {
                            Text("Spleeter library not found.")
                                .fontWeight(.medium)
                            Text("Run this command in Terminal:")
                            // Suggest explicit pip install using the selected binary to avoid PATH mismatches
                            Text("\(inputPath) -m pip install spleeter")
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(4)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                    }
                    
                    if case .invalidPython(let errorMsg) = engine.state {
                         Text("Invalid Python Environment:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                         Text(errorMsg)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                
                Text("Output Location")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.top, 4)
                
                Button(action: {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let outputDir = appSupport.appendingPathComponent("Instrumentals")
                    try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir.path)
                }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Show Instrumentals Folder")
                    }
                }
                
                // Debug Log Button
                Button(action: {
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let logFile = appSupport.appendingPathComponent("Instrumentals/spleeter_log.txt")
                    if FileManager.default.fileExists(atPath: logFile.path) {
                        NSWorkspace.shared.open(logFile)
                    } else {
                        // Alert logic ideally, but sticking to simple for now
                        print("No log file found")
                    }
                }) {
                    Text("Open Last Debug Log")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } header: {
                Text("Configuration")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recommended Steps:")
                        .font(.caption)
                        .fontWeight(.bold)
                    
                    Group {
                        Text("1. Install Python 3.9+ (brew install python)")
                        Text("2. Install Spleeter (pip3 install spleeter)")
                        Text("3. Enter path (e.g. /usr/local/bin/python3)")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } header: {
               Text("Setup Guide")
            }
        }
        .onAppear {
            inputPath = engine.pythonPath
            if inputPath.isEmpty {
                // Smart Default: Check common Homebrew paths
                if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/python3") {
                    inputPath = "/opt/homebrew/bin/python3" // Apple Silicon
                } else if FileManager.default.fileExists(atPath: "/usr/local/bin/python3") {
                    inputPath = "/usr/local/bin/python3" // Intel
                } else {
                     inputPath = "/usr/bin/python3" // System Python is now a valid fallback
                }
            }
        }
    }
    
    static func statusColor(for state: KaraokeEngineState) -> Color {
        switch state {
        case .ready: return .green
        case .validating: return .blue
        case .notConfigured: return .secondary
        default: return .red
        }
    }
}

struct StatusIcon: View {
    let state: KaraokeEngineState
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundColor(KaraokeSettingsView.statusColor(for: state))
    }
    
    var iconName: String {
        switch state {
        case .ready: return "checkmark.circle.fill"
        case .validating: return "arrow.triangle.2.circlepath"
        case .notConfigured: return "circle"
        case .error, .missingSpleeter, .invalidPython: return "exclamationmark.triangle.fill"
        default: return "circle"
        }
    }
}
