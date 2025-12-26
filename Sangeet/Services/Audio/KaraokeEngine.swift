import Foundation
import Combine
import SwiftUI

// MARK: - Karaoke Engine State
enum KaraokeEngineState: Equatable, CustomStringConvertible {
    case notConfigured        // Initial state, no path set
    case validating           // Currently checking path
    case ready                // Environment confirmed working
    case missingSpleeter      // Python works, but spleeter module missing
    case invalidPython(String) // Python executable not found or error. Message contained.
    case processing(Double)   // Currently separating vocals (progress 0.0-1.0)
    case error(String)        // Runtime error
    
    var description: String {
        switch self {
        case .notConfigured: return "Not Configured"
        case .validating: return "Validating Environment..."
        case .ready: return "Ready"
        case .missingSpleeter: return "Spleeter Missing"
        case .invalidPython(let msg): return "Invalid Python: \(msg)"
        case .processing(let progress): return "Processing: \(Int(progress * 100))%"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Karaoke Engine
class KaraokeEngine: ObservableObject {
    static let shared = KaraokeEngine()
    
    // Published State for UI
    @Published var state: KaraokeEngineState = .notConfigured
    @Published var pythonPath: String
    
    // Persistence Keys
    private let kPythonPathKey = "KaraokeEngine_PythonPath"
    
    private init() {
        // Load persist path or default
        self.pythonPath = UserDefaults.standard.string(forKey: kPythonPathKey) ?? ""
        
        // If we have a path, validate it on launch (fail softly)
        if !pythonPath.isEmpty {
            Task {
                await validateEnvironment(path: pythonPath)
            }
        }
    }
    
    // MARK: - Environment Management
    
    /// Update and validate the python path. User initiated.
    @MainActor
    func setPythonPath(_ path: String) async {
        self.pythonPath = path
        UserDefaults.standard.set(path, forKey: kPythonPathKey)
        await validateEnvironment(path: path)
    }
    
    /// Checks if Python exists and if Spleeter is importable.
    @MainActor
    func validateEnvironment(path: String) async {
        guard !path.isEmpty else {
            self.state = .notConfigured
            return
        }
        
        self.state = .validating
        
        // 1. Basic File Check
        guard FileManager.default.fileExists(atPath: path) else {
            self.state = .invalidPython("File not found at path")
            return
        }
        
        // 1.5. Check Removed: System Python is now allowed since Sandbox is disabled.
        // if path == "/usr/bin/python3" || path == "/usr/bin/python" { ... }
        
        // 1.6. Resolve Symlinks (Crucial for Homebrew paths)
        // /opt/homebrew/bin/python3 is often a symlink to Cellar, which Process might fail to resolve if relative
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        
        // 1.7. Verify Resolved Path
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            self.state = .invalidPython("Resolved path does not exist:\nOriginal: \(path)\nResolved: \(resolvedPath)")
            return
        }
        
        // 2. Execution Check (Import Spleeter)
        // We run a simple "import spleeter" to verify library presence
        let result = await runProcess(
            executable: resolvedPath,
            args: ["-c", "import spleeter; print('OK')"]
        )
        
        
        switch result.exitCode {
        case 0:
            self.state = .ready
        default:
            Logger.error("Environment Validation Failed: \(result.stderr)")
            if result.stderr.contains("ModuleNotFoundError") {
                self.state = .missingSpleeter
            } else {
                 // Pass the actual error output with path context
                self.state = .invalidPython("Failed to execute at:\n\(resolvedPath)\n\nError: \(result.stderr)")
            }
        }
    }
    
    // MARK: - Processing
    
    /// Creates an instrumental version of the track
    func createInstrumental(for track: Track) async throws -> URL {
        guard case .ready = state else {
            throw NSError(domain: "KaraokeEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Environment not ready"])
        }
        
        // Ensure Output Directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let outputDir = appSupport.appendingPathComponent("Instrumentals")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        // Expected Output Path (Spleeter creates a folder named after the filename)
        // We need to be careful with Spleeter's output structure.
        // `spleeter separate -o output_dir input_file` -> creates `output_dir/filename/accompaniment.wav`
        
        let filename = track.url.deletingPathExtension().lastPathComponent
        let trackOutputDir = outputDir.appendingPathComponent(filename)
        let finalInstrumentalPath = trackOutputDir.appendingPathComponent("accompaniment.wav")
        
        // Check Cache
        if FileManager.default.fileExists(atPath: finalInstrumentalPath.path) {
            return finalInstrumentalPath
        }
        
        await MainActor.run { self.state = .processing(0.1) }
        
        // Run Spleeter
        // Command: spleeter separate -p spleeter:2stems -o <outputDir> <inputFile>
        // Note: runProcess now handles symlink resolution internally if needed, but we pass the raw path
        // to be resolved again if it was a symlink.
        
        // Run Spleeter
        // Note: runProcess now handles symlink resolution internally if needed, but we pass the raw path
        // to be resolved again if it was a symlink.
        // IMPORTANT: We set CWD to outputDir so spleeter can write 'pretrained_models' there if needed.
        
        // Start simulated progress
        let progressTask = Task {
            for i in 1...90 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s * 90 = 45s (Typical time)
                await MainActor.run { self.state = .processing(Double(i) / 100.0) }
            }
        }
        
        let result = await runProcess(
            executable: pythonPath,
            args: [
                "-m", "spleeter", "separate",
                "-p", "spleeter:2stems-16kHz",
                "-o", outputDir.path,
                track.url.path
            ],
            cwd: outputDir
        )
        
        progressTask.cancel()
        await MainActor.run { self.state = .processing(1.0) } // 100%
        try? await Task.sleep(nanoseconds: 500_000_000) // Show 100% briefly
        await MainActor.run { self.state = .ready }
        
        // Debug: Write logs to a file we can check
        let logFile = outputDir.appendingPathComponent("spleeter_log.txt")
        let totalOutput = "CMD: \(pythonPath) -m spleeter separate -p spleeter:2stems -o \(outputDir.path) \(track.url.path)\n\nSTDOUT:\n\(result.stdout)\n\nSTDERR:\n\(result.stderr)"
        try? totalOutput.write(to: logFile, atomically: true, encoding: String.Encoding.utf8)
        
        // Even if exit code is 0, we must find the file
        if result.exitCode == 0 {
             // Robust File Check Strategy:
            // 1. Check exact expected path
            if FileManager.default.fileExists(atPath: finalInstrumentalPath.path) {
                return finalInstrumentalPath
            }
             
            // 2. Check for Spleeter's "underscore" behavior (My Song.mp3 -> My_Song/accompaniment.wav)
            let safeFilename = filename.replacingOccurrences(of: " ", with: "_")
            let safePath = outputDir.appendingPathComponent(safeFilename).appendingPathComponent("accompaniment.wav")
            if FileManager.default.fileExists(atPath: safePath.path) {
                return safePath
            }
            
            // 3. Fallback: Scan for ANY recently modified "accompaniment.wav" in the output directory
            // This handles complex renaming cases we might miss.
            do {
                let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
                let files = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: resourceKeys)
                
                for file in files {
                   // Calculate modification time difference
                   if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      abs(date.timeIntervalSinceNow) < 120 { // Created in last 2 mins
                       
                       // Check if this folder has accompaniment.wav
                       let candidate = file.appendingPathComponent("accompaniment.wav")
                       if FileManager.default.fileExists(atPath: candidate.path) {
                           return candidate
                       }
                   }
                }
            } catch {
                Logger.error("Failed to scan output directory: \(error)")
            }
             
             // Failure Log
             let failLog = "\n\nFAILED TO FIND OUTPUT FILE. Looked for underscore variants and recent files."
             if let data = failLog.data(using: .utf8), let handle = try? FileHandle(forWritingTo: logFile) {
                 handle.seekToEndOfFile()
                 handle.write(data)
                 handle.closeFile()
             }
             
             throw NSError(domain: "KaraokeEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Spleeter output matching failed.\nDebug log: \(logFile.path)"])
        } else {
             // Failure
             throw NSError(domain: "KaraokeEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Spleeter Error (Code \(result.exitCode)).\nSee logs at: \(logFile.path)"])
        }
    }
    
    // MARK: - Internal Process Handler
    
    // MARK: - Internal Process Handler
    
    struct ProcessOutput {
        let exitCode: Int
        let stdout: String
        let stderr: String
    }
    
    private func runProcess(executable: String, args: [String], cwd: URL? = nil) async -> ProcessOutput {
        let process = Process()
        
        // Resolve symlinks one last time to be absolutely sure
        let resolvedURL = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
        process.executableURL = resolvedURL
        process.arguments = args
        if let cwd = cwd {
            process.currentDirectoryURL = cwd
        }
        
        // Debug Log
        print("Running Process: \(resolvedURL.path) with args: \(args) in cwd: \(cwd?.path ?? "nil")")
        
        // Setup Environment (Inherit from User + Fix PATH)
        var env = ProcessInfo.processInfo.environment
        // Append common paths to ensure we can find libs
        let userPath = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        env["PATH"] = userPath + ":" + (env["PATH"] ?? "")
        // Reset PYTHON variables that might confuse the embedded python if any
        env["PYTHONHOME"] = nil
        env["PYTHONPATH"] = nil
        // Force unbuffered output to help with piping
        env["PYTHONUNBUFFERED"] = "1"
        
        process.environment = env
        
        let pipeOut = Pipe()
        let pipeErr = Pipe()
        process.standardOutput = pipeOut
        process.standardError = pipeErr
        
        // Buffers to accumulate data
        var stdoutData = Data()
        var stderrData = Data()
        
        let group = DispatchGroup()
        
        // Read stdout continuously
        group.enter()
        pipeOut.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF
                pipeOut.fileHandleForReading.readabilityHandler = nil
                group.leave()
            } else {
                stdoutData.append(data)
            }
        }
        
        // Read stderr continuously
        group.enter()
        pipeErr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                // EOF
                pipeErr.fileHandleForReading.readabilityHandler = nil
                group.leave()
            } else {
                stderrData.append(data)
            }
        }
        
        return await withCheckedContinuation { continuation in
            do {
                try process.run()
                
                process.terminationHandler = { p in
                    // Wait for all reading to finish (streams to close)
                    // We dispatch to a background queue to wait on the group so we don't block the termination handler
                    DispatchQueue.global().async {
                        group.wait()
                        
                        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                        
                        continuation.resume(returning: ProcessOutput(exitCode: Int(p.terminationStatus), stdout: stdout, stderr: stderr))
                    }
                }
            } catch {
                // Ensure handlers are cleared on error
                pipeOut.fileHandleForReading.readabilityHandler = nil
                pipeErr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ProcessOutput(exitCode: -1, stdout: "", stderr: error.localizedDescription))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func findSpleeterOutput(for track: Track, filename: String) -> URL? {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let outputDir = appSupport.appendingPathComponent("Instrumentals")
        let originalFilename = track.url.deletingPathExtension().lastPathComponent
        
        // 1. Exact Input Filename Match in Folder
        // Structure: .../Instrumentals/MySong/accompaniment.wav
        var folderName = originalFilename
        var exactPath = outputDir.appendingPathComponent(folderName).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: exactPath.path) { return exactPath }
        
        // 2. Underscore Match (Spleeter behavior)
        // If file is "My Song", folder might be "My_Song"
        // Also check if the filename itself has spaces? Spleeter usually underscores the folder name.
        let safeFolderName = originalFilename.replacingOccurrences(of: " ", with: "_")
        let safePath = outputDir.appendingPathComponent(safeFolderName).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: safePath.path) { return safePath }
        
        return nil
    }
    
    func getInstrumentalPath(for track: Track) -> URL? {
        return findSpleeterOutput(for: track, filename: "accompaniment.wav")
    }
    
    func getVocalsPath(for track: Track) -> URL? {
        return findSpleeterOutput(for: track, filename: "vocals.wav")
    }
    
    func hasInstrumental(for track: Track) -> Bool {
        return getInstrumentalPath(for: track) != nil
    }
}
