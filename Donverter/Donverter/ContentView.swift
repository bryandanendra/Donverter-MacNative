import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - App Theme & Colors
struct AppTheme {
    static let accent = Color.accentColor
}

// MARK: - Debug Logger
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    @Published var logs: [LogEntry] = []
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let tag: String
        let message: String
        
        var formatted: String {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss.SSS"
            return "[\(df.string(from: timestamp))] [\(tag)] \(message)"
        }
    }
    
    func log(_ tag: String, _ message: String) {
        let entry = LogEntry(timestamp: Date(), tag: tag, message: message)
        DispatchQueue.main.async {
            self.logs.append(entry)
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }
    
    var allText: String {
        logs.map { $0.formatted }.joined(separator: "\n")
    }
}

// MARK: - Debug Log View
struct DebugLogView: View {
    @ObservedObject var logger = DebugLogger.shared
    @State private var copied = false
    @Environment(\.dismiss) var dismiss
    
    // Quick Fix state
    @State private var fixOutput: String = ""
    @State private var isRunningFix: Bool = false
    @State private var fixSuccess: Bool? = nil
    @State private var showFixPanel: Bool = true
    
    // MARK: Smart Error Detection
    struct KnownIssue {
        let id: String
        let label: String
        let description: String
        let icon: String
        let color: Color
        let command: String? // nil = informational only (no Run Fix button)
    }
    
    var detectedIssues: [KnownIssue] {
        let allText = logger.allText.lowercased()
        var issues: [KnownIssue] = []
        
        // 1. Backend bundle not found (app packaging issue)
        let hasBundleMissing = allText.contains("bundled downloader engine not found")
            || allText.contains("no module named 'yt_dlp'")
            || allText.contains("cli executable permission: ❌")
        
        // 2. Network / connection errors
        let hasNetworkError = allText.contains("network is unreachable")
            || allText.contains("connection refused")
            || allText.contains("nodename nor servname provided")
            || allText.contains("timed out")
            || allText.contains("urlopen error")
            || allText.contains("name resolution failed")
        
        // 3. Download interrupted mid-stream (partial download)
        let hasDownloadInterrupted = (allText.contains("got error:") && allText.contains("bytes read"))
            || allText.contains("incomplete read")
            || allText.contains("content too short")
        
        // 4. HTTP errors (rate limiting, forbidden, server errors)
        let hasHTTPError = allText.contains("http error 403")
            || allText.contains("http error 429")
            || allText.contains("http error 503")
        
        // 5. Video/content unavailable
        let hasContentError = allText.contains("this video is unavailable")
            || allText.contains("video is private")
            || allText.contains("sign in to confirm your age")
            || allText.contains("this video has been removed")
            || allText.contains("join this channel")
        
        // 6. yt-dlp extraction error (site changed, needs app update)
        let hasExtractionError = allText.contains("unable to extract")
            || allText.contains("unsupported url")
            || (allText.contains("extractor error") && !hasContentError)
        
        // 7. ffmpeg not working inside bundle
        let hasFfmpegError = allText.contains("ffmpeg")
            && (allText.contains("not found") || allText.contains("no such file"))
            && !allText.contains("ffmpeg_location") // exclude config logs
        
        // 8. Cannot find downloaded file
        let hasFileNotFound = allText.contains("cannot find downloaded file")
        
        if hasBundleMissing {
            issues.append(KnownIssue(
                id: "bundle_missing",
                label: "Engine Tidak Ditemukan",
                description: "Backend downloader tidak ditemukan di app. Reinstall Donverter untuk fix.",
                icon: "exclamationmark.triangle.fill",
                color: Color(red: 1.0, green: 0.3, blue: 0.3),
                command: nil
            ))
        }
        
        if hasNetworkError {
            issues.append(KnownIssue(
                id: "network_check",
                label: "Cek Koneksi",
                description: "Koneksi internet bermasalah. Klik untuk test koneksi.",
                icon: "wifi.exclamationmark",
                color: Color(red: 1.0, green: 0.4, blue: 0.4),
                command: "ping -c 3 google.com 2>&1 && echo '\n✅ Koneksi OK!' || echo '\n❌ Tidak bisa terhubung ke internet'"
            ))
        }
        
        if hasDownloadInterrupted && !hasNetworkError {
            issues.append(KnownIssue(
                id: "download_interrupted",
                label: "Download Terputus",
                description: "Download terhenti di tengah jalan. Bersihkan file sementara dan coba lagi.",
                icon: "arrow.clockwise.circle.fill",
                color: Color(red: 1.0, green: 0.75, blue: 0.2),
                command: "rm -f ~/Downloads/*.part ~/Downloads/*.ytdl 2>/dev/null; echo '✅ File sementara dibersihkan. Silakan coba download ulang.'"
            ))
        }
        
        if hasHTTPError {
            issues.append(KnownIssue(
                id: "http_error",
                label: "Server Menolak Akses",
                description: "Server membatasi request. Tunggu beberapa menit lalu coba lagi.",
                icon: "hand.raised.fill",
                color: Color(red: 1.0, green: 0.6, blue: 0.2),
                command: nil
            ))
        }
        
        if hasContentError {
            issues.append(KnownIssue(
                id: "content_error",
                label: "Video Tidak Tersedia",
                description: "Video mungkin sudah dihapus, private, atau dibatasi usia.",
                icon: "eye.slash.fill",
                color: Color(red: 0.7, green: 0.5, blue: 1.0),
                command: nil
            ))
        }
        
        if hasExtractionError && !hasBundleMissing {
            issues.append(KnownIssue(
                id: "extraction_error",
                label: "Update Donverter",
                description: "Engine yt-dlp perlu diperbarui. Download versi terbaru Donverter.",
                icon: "arrow.up.circle.fill",
                color: Color(red: 0.4, green: 0.6, blue: 1.0),
                command: nil
            ))
        }
        
        if hasFfmpegError && !hasBundleMissing {
            issues.append(KnownIssue(
                id: "ffmpeg_error",
                label: "ffmpeg Error",
                description: "ffmpeg tidak berjalan. Reinstall Donverter untuk fix.",
                icon: "film.circle.fill",
                color: Color(red: 0.4, green: 0.6, blue: 1.0),
                command: nil
            ))
        }
        
        if hasFileNotFound && !hasDownloadInterrupted && !hasNetworkError {
            issues.append(KnownIssue(
                id: "file_not_found",
                label: "File Tidak Ditemukan",
                description: "File hasil download tidak ditemukan. Cek folder Downloads.",
                icon: "doc.questionmark.fill",
                color: Color(red: 1.0, green: 0.75, blue: 0.2),
                command: "open ~/Downloads"
            ))
        }
        
        return issues
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                // Close Button (✕) — top-left
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.45))
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Close Debug Log")
                
                Image(systemName: "terminal.fill")
                    .foregroundColor(.green)
                Text("Debug Log")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Copy All button
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(logger.allText, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }) {
                    Label(copied ? "Copied!" : "Copy All", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(copied ? .green : .white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Clear button
                Button(action: {
                    logger.clear()
                    fixOutput = ""
                    fixSuccess = nil
                }) {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color.black.opacity(0.5))
            
            Divider().background(Color.white.opacity(0.1))
            
            // Log scroll area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if logger.logs.isEmpty {
                            Text("No logs yet. Start a download to see debug output.")
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(16)
                        } else {
                            ForEach(logger.logs) { entry in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(entry.tag)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(tagColor(entry.tag))
                                        .frame(width: 56, alignment: .leading)
                                    Text(entry.message)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.85))
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 3)
                                .id(entry.id)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logger.logs.count) { _ in
                    if let last = logger.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color.black.opacity(0.4))
            
            // Footer count
            HStack {
                Text("\(logger.logs.count) entries")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.5))
            
            // MARK: Quick Fix Panel
            if !detectedIssues.isEmpty && showFixPanel {
                Divider().background(Color.orange.opacity(0.3))
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                        Text("Quick Fix")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.4))
                        Text("— \(detectedIssues.count) issue\(detectedIssues.count > 1 ? "s" : "") detected")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Button(action: { withAnimation { showFixPanel = false } }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.4))
                                .padding(5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    ForEach(detectedIssues, id: \.id) { issue in
                        HStack(spacing: 12) {
                            Image(systemName: issue.icon)
                                .font(.system(size: 18))
                                .foregroundColor(issue.color)
                                .frame(width: 26)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Text(issue.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            
                            Spacer()
                            
                            if let command = issue.command {
                                // Actionable fix — show Run Fix button
                                Button(action: {
                                    runFix(command: command)
                                }) {
                                    HStack(spacing: 5) {
                                        if isRunningFix {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else {
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 10))
                                        }
                                        Text(isRunningFix ? "Running..." : "Run Fix")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isRunningFix ? Color.gray : issue.color)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isRunningFix)
                            } else {
                                // Informational only — show info badge
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 10))
                                    Text("Info")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(issue.color.opacity(0.25), lineWidth: 1)
                        )
                    }
                    
                    // Fix output terminal area
                    if !fixOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: fixSuccess == true ? "checkmark.circle.fill" : (fixSuccess == false ? "xmark.circle.fill" : "terminal"))
                                    .foregroundColor(fixSuccess == true ? .green : (fixSuccess == false ? .red : .yellow))
                                    .font(.system(size: 13))
                                Text("Fix Output")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.7))
                                Spacer()
                                Button(action: { fixOutput = ""; fixSuccess = nil }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(4)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            
                            ScrollView {
                                Text(fixOutput)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(fixSuccess == true ? Color(red: 0.4, green: 1.0, blue: 0.5) : (fixSuccess == false ? Color(red: 1.0, green: 0.5, blue: 0.4) : .white.opacity(0.8)))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 80)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(14)
                .background(Color(red: 0.14, green: 0.10, blue: 0.02).opacity(0.95))
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .preferredColorScheme(.dark)
    }
    
    // MARK: Run Fix Command
    private func runFix(command: String) {
        isRunningFix = true
        fixOutput = "⏳ Running: \(command)\n"
        fixSuccess = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = env
            
            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let outStr = String(data: outData, encoding: .utf8) ?? ""
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                let combined = (outStr + errStr).trimmingCharacters(in: .whitespacesAndNewlines)
                let exitCode = process.terminationStatus
                
                DispatchQueue.main.async {
                    fixOutput = combined.isEmpty
                        ? (exitCode == 0 ? "✅ Fix completed successfully!" : "⚠️ Process exited with code \(exitCode)")
                        : combined
                    fixSuccess = (exitCode == 0)
                    isRunningFix = false
                    DebugLogger.shared.log("FIX", exitCode == 0 ? "✅ Fix succeeded: \(command)" : "❌ Fix failed (exit \(exitCode)): \(command)")
                }
            } catch {
                DispatchQueue.main.async {
                    fixOutput = "❌ Error launching fix: \(error.localizedDescription)"
                    fixSuccess = false
                    isRunningFix = false
                }
            }
        }
    }
    
    func tagColor(_ tag: String) -> Color {
        switch tag {
        case "INFO": return Color(red: 0.3, green: 0.8, blue: 1.0)
        case "STDOUT": return Color(red: 0.4, green: 1.0, blue: 0.5)
        case "STDERR": return Color(red: 1.0, green: 0.5, blue: 0.3)
        case "ERROR": return Color(red: 1.0, green: 0.3, blue: 0.3)
        case "JSON": return Color(red: 1.0, green: 0.85, blue: 0.3)
        case "EXIT": return Color(red: 0.85, green: 0.5, blue: 1.0)
        case "FIX": return Color(red: 0.4, green: 1.0, blue: 0.5)
        default: return .white.opacity(0.6)
        }
    }
}

// Custom macOS Transparent Blur Effect (Control Center Style)
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The magic enum for "Control Center" or "Sidebar" glass look that punches through to the desktop
        view.material = .hudWindow // or .popover / .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                // Optionally make the title bar clear too if needed
                window.titlebarAppearsTransparent = true
            }
        }
    }
}

// Custom Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05)) // Extremely subtle inner tint
            .background(.ultraThinMaterial) // macOS native blur layer
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Download Manager
class DownloadManager: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var isDownloading: Bool = false
    @Published var downloadedFilePath: String? = nil
    
    struct ProgressUpdate: Codable {
        let type: String
        let message: String?
        let percent: String?
        let speed: String?
        let eta: String?
        let filepath: String?
        let filename: String?
    }
    
    func startDownload(url: String, platform: String, format: String, resolution: String) {
        let logger = DebugLogger.shared
        logger.clear()
        logger.log("INFO", "=== New Download Session ===")
        logger.log("INFO", "URL: \(url)")
        logger.log("INFO", "Platform: \(platform) | Format: \(format) | Resolution: \(resolution)")
        
        DispatchQueue.main.async {
            self.progress = 0.0
            self.statusMessage = "Starting download..."
            self.isDownloading = true
            self.downloadedFilePath = nil
        }
        
        guard let cliURL = Bundle.main.url(forResource: "downloader_cli", withExtension: nil) else {
            let msg = "Error: Bundled Downloader Engine not found in app bundle."
            logger.log("ERROR", msg)
            DispatchQueue.main.async {
                self.statusMessage = msg
                self.isDownloading = false
            }
            return
        }
        
        logger.log("INFO", "CLI path: \(cliURL.path)")
        
        // Check if CLI executable is actually executable
        let fm = FileManager.default
        let isExecutable = fm.isExecutableFile(atPath: cliURL.path)
        logger.log("INFO", "CLI executable permission: \(isExecutable ? "✅ YES" : "❌ NO — permission problem!")")
        
        let process = Process()
        process.executableURL = cliURL
        process.arguments = [
            "--url", url,
            "--platform", platform.lowercased(),
            "--format", format.lowercased(),
            "--resolution", resolution == "Best" ? "best" : resolution
        ]
        logger.log("INFO", "Args: \(process.arguments?.joined(separator: " ") ?? "-")")
        
        var env = ProcessInfo.processInfo.environment
        let brewPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(brewPath):\(existingPath)"
        } else {
            env["PATH"] = brewPath
        }
        process.environment = env
        logger.log("INFO", "PATH: \(env["PATH"] ?? "-")")
        
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            let lines = output.components(separatedBy: "\n")
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                logger.log("STDOUT", line)
                if let jsonData = line.data(using: .utf8),
                   let update = try? JSONDecoder().decode(ProgressUpdate.self, from: jsonData) {
                    logger.log("JSON", "type=\(update.type) msg=\(update.message ?? update.percent ?? "-")")
                    DispatchQueue.main.async { self?.handleUpdate(update) }
                } else {
                    // Line came in but couldn't be parsed as JSON
                    logger.log("JSON", "⚠️ Non-JSON stdout: \(line)")
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                let lines = output.components(separatedBy: "\n")
                for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    logger.log("STDERR", line)
                }
            }
        }
        
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            logger.log("EXIT", "Process exited with code: \(code) (\(code == 0 ? "success" : "failure"))")
            DispatchQueue.main.async {
                self?.isDownloading = false
                if let progress = self?.progress, progress < 1.0, self?.downloadedFilePath == nil {
                    // Hanya overwrite jika statusnya belum diganti menjadi pesan error oleh Swift
                    if let msg = self?.statusMessage, !msg.hasPrefix("Error") {
                        let failMsg = "Download ended unexpectedly (exit \(code)). Tap Debug Log."
                        self?.statusMessage = failMsg
                        logger.log("ERROR", failMsg)
                    }
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        
        do {
            try process.run()
            logger.log("INFO", "Process launched successfully (PID: \(process.processIdentifier))")
        } catch {
            let errMsg = "Error starting process: \(error.localizedDescription)"
            logger.log("ERROR", errMsg)
            DispatchQueue.main.async {
                self.statusMessage = errMsg
                self.isDownloading = false
            }
        }
    }
    
    private func handleUpdate(_ update: ProgressUpdate) {
        switch update.type {
        case "progress":
            if let percentStr = update.percent, let percentDouble = Double(percentStr) {
                self.progress = percentDouble / 100.0
            }
            let speed = update.speed ?? "-"
            self.statusMessage = "Downloading... (\(speed))"
        case "status":
            self.statusMessage = update.message ?? "Processing..."
        case "success":
            self.progress = 1.0
            self.statusMessage = update.message ?? "Download Complete!"
            self.downloadedFilePath = update.filepath
            self.isDownloading = false
        case "error":
            self.statusMessage = "Error: \(update.message ?? "Unknown error")"
            self.isDownloading = false
        default: break
        }
    }
    
    func openFolder() {
        guard let pathString = downloadedFilePath else { return }
        let url = URL(fileURLWithPath: pathString).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Image Converter Manager
class ImageConverterManager: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Format: PNG, JPG, JPEG, HEIC, HEIF, HIF, WEBP, SVG, PDF — Multiple files supported"
    @Published var isConverting: Bool = false
    @Published var convertedFilePath: String? = nil
    @Published var selectedFiles: [URL] = []
    @Published var isPdfMode: Bool = false
    
    /// Check if all selected files are PDFs and update mode accordingly
    func updatePdfMode() {
        if selectedFiles.isEmpty {
            isPdfMode = false
            return
        }
        let allPdf = selectedFiles.allSatisfy { $0.pathExtension.lowercased() == "pdf" }
        isPdfMode = allPdf
    }
    
    /// Returns true if adding the given URLs would create a mixed PDF+image selection
    func wouldCreateMixedSelection(newURLs: [URL]) -> Bool {
        let combined = selectedFiles + newURLs
        if combined.isEmpty { return false }
        let hasPdf = combined.contains { $0.pathExtension.lowercased() == "pdf" }
        let hasNonPdf = combined.contains { $0.pathExtension.lowercased() != "pdf" }
        return hasPdf && hasNonPdf
    }
    
    struct ProgressUpdate: Codable {
        let type: String
        let message: String?
        let percent: Int?
        let filepath: String?
        let current_file: String?
    }
    
    func startConversion(format: String, enableCompression: Bool) {
        if selectedFiles.isEmpty { return }
        
        DispatchQueue.main.async {
            self.progress = 0.0
            self.statusMessage = self.isPdfMode ? "Extracting PDF pages..." : "Starting conversion..."
            self.isConverting = true
            self.convertedFilePath = nil
        }
        
        guard let cliURL = Bundle.main.url(forResource: "image_converter_cli", withExtension: nil) else {
            DispatchQueue.main.async {
                self.statusMessage = "Error: Bundled Converter Engine not found."
                self.isConverting = false
            }
            return
        }
        
        let process = Process()
        process.executableURL = cliURL
        
        let quality = "100"
        var args: [String]
        if isPdfMode {
            args = ["--mode", "pdf2img", "--format", format.lowercased(), "--quality", quality, "--files", selectedFiles[0].path]
        } else {
            let q = enableCompression ? "50" : "100"
            args = ["--format", format.lowercased(), "--quality", q, "--files"]
            args.append(contentsOf: selectedFiles.map { $0.path })
        }
        process.arguments = args
        
        var env = ProcessInfo.processInfo.environment
        let brewPath = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let existingPath = env["PATH"] {
            env["PATH"] = "\(brewPath):\(existingPath)"
        } else {
            env["PATH"] = brewPath
        }
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return }
            
            let lines = output.components(separatedBy: "\n")
            for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                if let jsonData = line.data(using: .utf8),
                   let update = try? JSONDecoder().decode(ProgressUpdate.self, from: jsonData) {
                    DispatchQueue.main.async { self?.handleUpdate(update) }
                } else {
                    print("Python Stdout: \(line)")
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("Python Stderr (Converter): \(output)")
            }
        }
        
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isConverting = false
                if let progress = self?.progress, progress < 1.0, self?.convertedFilePath == nil {
                    if let msg = self?.statusMessage, !msg.hasPrefix("Error") {
                        self?.statusMessage = "Conversion ended unexpectedly. See console."
                    }
                }
                pipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
            }
        }
        
        do { try process.run() } catch {
            DispatchQueue.main.async {
                self.statusMessage = "Error: \(error.localizedDescription)"
                self.isConverting = false
            }
        }
    }
    
    private func handleUpdate(_ update: ProgressUpdate) {
        switch update.type {
        case "progress":
            if let pct = update.percent { self.progress = Double(pct) / 100.0 }
            if let file = update.current_file { self.statusMessage = "Converting: \(file)..." }
        case "status":
            self.statusMessage = update.message ?? "Processing..."
        case "success":
            self.progress = 1.0
            self.statusMessage = "\(update.message ?? "Conversion Complete!")"
            self.convertedFilePath = update.filepath
            self.isConverting = false
            self.selectedFiles = []
        case "error":
            self.statusMessage = "Error: \(update.message ?? "Unknown error")"
            self.isConverting = false
        default: break
        }
    }
    
    func openFolder() {
        guard let pathString = convertedFilePath else { return }
        let fileURL = URL(fileURLWithPath: pathString)
        
        // Check if path is a directory (PDF mode outputs a folder)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: pathString, isDirectory: &isDir), isDir.boolValue {
            NSWorkspace.shared.open(fileURL)
        } else {
            NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
        }
    }
    
    func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let svgType = UTType(filenameExtension: "svg") ?? .image
        panel.allowedContentTypes = [.image, .jpeg, .png, .pdf, .rawImage, svgType]
        
        if panel.runModal() == .OK {
            DispatchQueue.main.async {
                // Check for mixed selection
                if self.wouldCreateMixedSelection(newURLs: panel.urls) {
                    self.statusMessage = "⚠️ Cannot mix PDF and image files. Please select one type only."
                    return
                }
                
                for url in panel.urls {
                    if !self.selectedFiles.contains(url) {
                        self.selectedFiles.append(url)
                    }
                }
                self.updatePdfMode()
                
                if self.isPdfMode {
                    self.statusMessage = "PDF selected — pages will be extracted as images."
                } else {
                    self.statusMessage = "\(self.selectedFiles.count) files selected for conversion."
                }
            }
        }
    }
}


// MARK: - Reusable UI Components
struct GlassSelectionBox: View {
    let title: String
    let iconSystemName: String?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isSelected || isHovering ? Color.white : Color.white.opacity(0.05))
            .background(.ultraThinMaterial)
            .foregroundColor(isSelected || isHovering ? AppTheme.accent : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected || isHovering ? Color.white : Color.white.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct GlassResolutionChip: View {
    let label: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected || isHovering ? .bold : .medium))
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected || isHovering ? AppTheme.accent.opacity(0.8) : Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected || isHovering ? Color.white : Color.white.opacity(0.05))
            .background(.ultraThinMaterial)
            .foregroundColor(isSelected || isHovering ? AppTheme.accent : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected || isHovering ? Color.white : Color.white.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Views
struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            // macOS Native Desktop Blur Passthrough Layer
            VisualEffectView()
                .ignoresSafeArea()
            
            // Subtle theme tint over the blur to match the dark glassmorphism
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Extremely subtle inner tint to replicate glass material
            Color.white.opacity(0.03)
                .ignoresSafeArea()
                
            VStack(spacing: 0) {
                // Glassy Tab Bar
                HStack(spacing: 8) {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = 0 } }) {
                        Text("Downloader")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(selectedTab == 0 ? Color.white.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == 0 ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = 1 } }) {
                        Text("Converter")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(selectedTab == 1 ? Color.white.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == 1 ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(6)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.top, 32)
                .padding(.bottom, 16)
                
                // Content Switcher
                if selectedTab == 0 {
                    VideoDownloaderView().transition(.opacity)
                } else {
                    ImageConverterView().transition(.opacity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 700)
        .preferredColorScheme(.dark)
        // Ensure Window is transparent to allow `VisualEffectView` to punch holes to Desktop
        .background(Color.clear)
    }
}

// MARK: - Video Downloader UI
struct VideoDownloaderView: View {
    @StateObject private var manager = DownloadManager()
    @ObservedObject private var logger = DebugLogger.shared
    
    @State private var url: String = ""
    @State private var selectedPlatform: String = "YouTube"
    @State private var selectedFormat: String = "MP4"
    @State private var selectedResolution: String = "Best"
    @State private var isHoveringDownload: Bool = false
    @State private var showDebugLog: Bool = false
    
    let platforms = [
        ("YouTube", "play.rectangle.fill"),
        ("TikTok", "music.note"),
        ("Instagram", "camera.metering.partial")
    ]
    let formats = [("MP4", "film"), ("MP3", "headphones")]
    
    let resolutions = [
        ("360", nil), ("480", nil), ("720", "HD"),
        ("1080", "FHD"), ("1440", "2K"), ("2160", "4K"),
        ("Best", "MAX")
    ]
    
    private func autoDetectPlatform(from urlString: String) {
        let lower = urlString.lowercased()
        if lower.contains("youtube.com") || lower.contains("youtu.be") {
            selectedPlatform = "YouTube"
        } else if lower.contains("tiktok.com") {
            selectedPlatform = "TikTok"
        } else if lower.contains("instagram.com") {
            selectedPlatform = "Instagram"
        }
    }
    
    private func checkClipboardAndAutoFill() {
        guard url.isEmpty else { return }
        if let clipString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lower = clipString.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                if lower.contains("youtube.com") || lower.contains("youtu.be") ||
                   lower.contains("tiktok.com") || lower.contains("instagram.com") {
                    withAnimation {
                        url = clipString
                        autoDetectPlatform(from: clipString)
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                
                // NO MORE SEPARATE GLASS CARD HERE, IT IS IN THE PARENT CONTENTVIEW NOW
                
                // URL Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video URL")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        TextField("https://...", text: $url)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .disabled(manager.isDownloading)
                            .onChange(of: url) { newValue in
                                autoDetectPlatform(from: newValue)
                            }
                        
                        if !manager.isDownloading {
                            Button(action: {
                                if let clipString = NSPasteboard.general.string(forType: .string) {
                                    withAnimation {
                                        url = clipString.trimmingCharacters(in: .whitespacesAndNewlines)
                                        autoDetectPlatform(from: url)
                                    }
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Paste URL from clipboard")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                
                // Platform Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        ForEach(platforms, id: \.0) { platform in
                            GlassSelectionBox(title: platform.0, iconSystemName: platform.1, isSelected: selectedPlatform == platform.0) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedPlatform = platform.0 }
                            }
                        }
                    }
                }
                
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        ForEach(formats, id: \.0) { format in
                            GlassSelectionBox(title: format.0, iconSystemName: format.1, isSelected: selectedFormat == format.0) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedFormat = format.0 }
                            }
                        }
                    }
                }
                
                // Resolution Selection
                if selectedFormat == "MP4" && selectedPlatform == "YouTube" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resolution")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.8))
                        
                        HStack(spacing: 8) {
                            ForEach(resolutions, id: \.0) { res in
                                GlassResolutionChip(label: res.0 == "Best" ? "Best" : "\(res.0)p", badge: res.1, isSelected: selectedResolution == res.0) {
                                    withAnimation(.easeOut(duration: 0.2)) { selectedResolution = res.0 }
                                }
                            }
                        }
                    }
                }
                
                // Download Action Button
                VStack(spacing: 12) {
                    Button(action: {
                        manager.startDownload(url: url, platform: selectedPlatform, format: selectedFormat, resolution: selectedResolution)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.to.line.circle.fill")
                                .font(.system(size: 18))
                            Text(manager.isDownloading ? "Downloading..." : "Start Download")
                                .fontWeight(.bold)
                                .font(.system(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading
                            ? Color.white.opacity(0.1)
                            : (isHoveringDownload ? Color.white : AppTheme.accent.opacity(0.8))
                        )
                        .background(.ultraThinMaterial) // Liquid Glass on Button
                        .foregroundColor(
                            url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading
                            ? .white
                            : (isHoveringDownload ? AppTheme.accent : .white)
                        )
                        // Smooth modern border
                        .overlay(
                            Capsule()
                                .stroke(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading ? Color.white.opacity(0.1) : (isHoveringDownload ? Color.white : AppTheme.accent.opacity(0.6)), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading)
                    .scaleEffect(manager.isDownloading ? 0.98 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHoveringDownload = hovering
                        }
                    }
                    
                    // Progress Section
                    if manager.isDownloading || manager.progress > 0 {
                        VStack(spacing: 8) {
                            ProgressView(value: manager.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            
                            HStack {
                                Text(manager.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                                Spacer()
                                if let path = manager.downloadedFilePath {
                                    Button(action: { manager.openFolder() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                            Text("Show in Finder")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.top, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Debug Log Button (always visible after first use)
                    if !logger.logs.isEmpty {
                        Button(action: { showDebugLog = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12))
                                Text("Debug Log")
                                    .font(.system(size: 13, weight: .medium))
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .opacity(manager.isDownloading ? 1 : 0)
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showDebugLog) {
                            DebugLogView()
                        }
                    }
                }
                .padding(.top, 14)
                
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .onAppear {
            checkClipboardAndAutoFill()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboardAndAutoFill()
        }
    }
}

// MARK: - Image Converter UI
struct ImageConverterView: View {
    @StateObject private var manager = ImageConverterManager()
    
    @State private var selectedFormat: String = "JPG"
    @State private var enableCompression: Bool = false
    @State private var isHovering: Bool = false
    @State private var isHoveringConvert: Bool = false
    
    let formats = ["JPG", "PNG", "PDF", "HEIF", "HIF", "WEBP", "SVG"]
    let pdfFormats = ["JPG", "PNG", "WEBP"]
    
    var activeFormats: [String] {
        manager.isPdfMode ? pdfFormats : formats
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                
                // Content Area for files
                if manager.selectedFiles.isEmpty {
                    // Glassy Drag & Drop Area
                Button(action: {
                    manager.presentFilePicker()
                }) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(manager.selectedFiles.isEmpty ? Color.white.opacity(0.1) : Color.green.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: manager.selectedFiles.isEmpty ? "photo.stack" : "checkmark.seal.fill")
                                .font(.system(size: 32))
                                .foregroundColor(manager.selectedFiles.isEmpty ? .white : .green)
                        }
                        
                        Text(manager.selectedFiles.isEmpty ? "Drag & Drop Images or PDF" : "\(manager.selectedFiles.count) files ready for conversion")
                            .font(.system(size: 18, weight: .bold))
                        
                        Text(manager.statusMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(isHovering ? Color.white.opacity(0.15) : Color.black.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundColor(isHovering ? AppTheme.accent : Color.white.opacity(0.2))
                    )
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(manager.isConverting)
                .onHover { hovering in
                    withAnimation { isHovering = hovering }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isHovering) { providers in
                    var handled = false
                    var droppedURLs: [URL] = []
                    let group = DispatchGroup()
                    for provider in providers {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                droppedURLs.append(url)
                                handled = true
                            }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        if manager.wouldCreateMixedSelection(newURLs: droppedURLs) {
                            manager.statusMessage = "⚠️ Cannot mix PDF and image files. Please select one type only."
                        } else {
                            for url in droppedURLs {
                                if !manager.selectedFiles.contains(url) {
                                    manager.selectedFiles.append(url)
                                }
                            }
                            manager.updatePdfMode()
                            if manager.isPdfMode {
                                manager.statusMessage = "PDF selected — pages will be extracted as images."
                            } else {
                                manager.statusMessage = "\(manager.selectedFiles.count) files selected for conversion."
                            }
                        }
                    }
                    return handled
                }
                } else {
                    // Selected Files UI
                    VStack(spacing: 20) {
                        HStack {
                            Text("Selected Files")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text("\(manager.selectedFiles.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.1, green: 0.7, blue: 0.9))
                                .cornerRadius(12)
                                
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    manager.selectedFiles.removeAll()
                                    manager.isPdfMode = false
                                    selectedFormat = "JPG"
                                }
                            }) {
                                Text("Clear All")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.5), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        VStack(spacing: 0) {
                            ForEach(Array(manager.selectedFiles.enumerated()), id: \.offset) { index, file in
                                HStack(spacing: 12) {
                                    // Format Badge
                                    Text(file.pathExtension.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                                        .frame(width: 44, height: 44)
                                        .background(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.15))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(file.lastPathComponent)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Text(getFileSize(url: file))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        withAnimation {
                                            manager.selectedFiles.removeAll(where: { $0 == file })
                                            manager.updatePdfMode()
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                            .frame(width: 26, height: 26)
                                            .background(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.15))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                
                                if index < manager.selectedFiles.count - 1 {
                                    Divider().background(Color.white.opacity(0.1))
                                }
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        
                        Button(action: {
                            manager.presentFilePicker()
                        }) {
                            Text("+ Add More Files")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.5))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                            var handled = false
                            var droppedURLs: [URL] = []
                            let group = DispatchGroup()
                            for provider in providers {
                                group.enter()
                                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        droppedURLs.append(url)
                                        handled = true
                                    }
                                    group.leave()
                                }
                            }
                            group.notify(queue: .main) {
                                if manager.wouldCreateMixedSelection(newURLs: droppedURLs) {
                                    manager.statusMessage = "⚠️ Cannot mix PDF and image files. Please select one type only."
                                } else {
                                    for url in droppedURLs {
                                        if !manager.selectedFiles.contains(url) {
                                            manager.selectedFiles.append(url)
                                        }
                                    }
                                    manager.updatePdfMode()
                                }
                            }
                            return handled
                        }
                    }
                }
                
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(manager.isPdfMode ? "Page Format" : "Output Format")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        ForEach(activeFormats, id: \.self) { format in
                            GlassSelectionBox(title: format, iconSystemName: nil, isSelected: selectedFormat == format) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedFormat = format }
                            }
                        }
                    }
                }
                
                // Mode-specific info banner
                if manager.isPdfMode {
                    // PDF mode info banner
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PDF Page Extraction")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.3))
                            Text("Each page will be rendered as a high-quality image (300 DPI) into a folder")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.8, green: 0.4, blue: 0.1).opacity(0.15))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.4), lineWidth: 1))
                } else if selectedFormat != "SVG" {
                    // Glassy Compression Toggle (hidden for SVG output since vtracer does vector tracing)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Compression")
                                .font(.system(size: 15, weight: .medium))
                            Text("Reduces file sizes while maintaining reasonable quality")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Toggle("", isOn: $enableCompression)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .disabled(manager.isConverting)
                } else {
                    // SVG info banner
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vector Tracing Mode")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.7, green: 0.5, blue: 1.0))
                            Text("Converts raster pixels into scalable SVG vector paths")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.15))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4), lineWidth: 1))
                }
                
                Spacer().frame(height: 10)
                
                // Convert Action Button
                VStack(spacing: 12) {
                    Button(action: {
                        manager.startConversion(format: selectedFormat, enableCompression: enableCompression)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: manager.isPdfMode ? "doc.viewfinder" : "sparkles")
                                .font(.system(size: 18))
                            Text(manager.isConverting
                                 ? (manager.isPdfMode ? "Extracting..." : "Converting...")
                                 : (manager.isPdfMode ? "Extract Pages" : (selectedFormat == "SVG" ? "Trace to SVG" : "Convert Images")))
                                .fontWeight(.bold)
                                .font(.system(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            manager.selectedFiles.isEmpty || manager.isConverting
                            ? Color.white.opacity(0.1)
                            : (isHoveringConvert ? Color.white : AppTheme.accent.opacity(0.8))
                        )
                        .background(.ultraThinMaterial) // Liquid Glass on Button
                        .foregroundColor(
                            manager.selectedFiles.isEmpty || manager.isConverting
                            ? .white
                            : (isHoveringConvert ? AppTheme.accent : .white)
                        )
                        // Smooth modern border
                        .overlay(
                            Capsule()
                                .stroke(manager.selectedFiles.isEmpty || manager.isConverting ? Color.white.opacity(0.1) : (isHoveringConvert ? Color.white : AppTheme.accent.opacity(0.6)), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(manager.selectedFiles.isEmpty || manager.isConverting)
                    .scaleEffect(manager.isConverting ? 0.98 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHoveringConvert = hovering
                        }
                    }
                    
                    // Progress Section
                    if manager.isConverting || manager.progress > 0 {
                        VStack(spacing: 8) {
                            ProgressView(value: manager.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            
                            HStack {
                                Text(manager.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                if let path = manager.convertedFilePath {
                                    Button(action: { manager.openFolder() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                            Text("Show in Finder")
                                        }
                                        .font(.caption.bold())
                                        .foregroundColor(AppTheme.accent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .padding(.top, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
    
    private func getFileSize(url: URL) -> String {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Double(resourceValues.fileSize ?? 0)
            if fileSize > 1_000_000 {
                return String(format: "%.2f MB", fileSize / 1_000_000)
            } else {
                return String(format: "%.2f KB", fileSize / 1_000)
            }
        } catch {
            return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}
