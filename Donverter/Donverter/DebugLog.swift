//
//  DebugLog.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

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
        let enabled = UserDefaults.standard.object(forKey: "debugLogEnabled") as? Bool ?? true
        guard enabled else { return }
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
