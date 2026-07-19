//
//  DownloadManager.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var progress: Double = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var isDownloading: Bool = false
    @Published var downloadedFilePath: String? = nil

    private var currentProcess: Process?
    private var wasCancelled: Bool = false
    
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
            self.wasCancelled = false
            // Show notch overlay
            NotchProgressController.shared.update(.download, label: "Downloading...", progress: 0.0, filePath: nil)
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

        let stdoutBuffer = PipeLineBuffer()
        let stderrBuffer = PipeLineBuffer()

        let processLine: (String) -> Void = { [weak self] line in
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

        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                // EOF — keluarkan sisa baris terakhir lalu berhenti membaca
                stdoutBuffer.flush(onLine: processLine)
                fileHandle.readabilityHandler = nil
                return
            }
            stdoutBuffer.append(data, onLine: processLine)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                stderrBuffer.flush { logger.log("STDERR", $0) }
                fileHandle.readabilityHandler = nil
                return
            }
            stderrBuffer.append(data) { logger.log("STDERR", $0) }
        }

        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            logger.log("EXIT", "Process exited with code: \(code) (\(code == 0 ? "success" : "failure"))")
            DispatchQueue.main.async {
                self?.currentProcess = nil
                self?.isDownloading = false
                if self?.wasCancelled == true {
                    self?.statusMessage = "Download cancelled."
                    self?.progress = 0.0
                    logger.log("INFO", "Download cancelled by user.")
                    NotchProgressController.shared.dismiss(.download)
                } else if let progress = self?.progress, progress < 1.0, self?.downloadedFilePath == nil {
                    // Hanya overwrite jika statusnya belum diganti menjadi pesan error oleh Swift
                    if let msg = self?.statusMessage, !msg.hasPrefix("Error") {
                        let failMsg = "Download ended unexpectedly (exit \(code)). Tap Debug Log."
                        self?.statusMessage = failMsg
                        logger.log("ERROR", failMsg)
                    }
                }
            }
        }

        do {
            try process.run()
            currentProcess = process
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

    /// Batalkan download yang sedang berjalan. Backend Python punya handler
    /// SIGTERM sehingga ffmpeg yang sedang berjalan ikut dimatikan dengan rapi.
    func cancelDownload() {
        guard let process = currentProcess, process.isRunning else { return }
        wasCancelled = true
        statusMessage = "Cancelling..."
        DebugLogger.shared.log("INFO", "Cancel requested — sending SIGTERM to PID \(process.processIdentifier)")
        process.terminate()
    }
    
    private func handleUpdate(_ update: ProgressUpdate) {
        switch update.type {
        case "progress":
            if let percentStr = update.percent, let percentDouble = Double(percentStr) {
                let pct = percentDouble / 100.0
                self.progress = pct
                NotchProgressController.shared.update(.download, label: "Downloading...", progress: pct, filePath: nil)
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
            NotchProgressController.shared.markDone(.download, label: "Download Complete", filePath: update.filepath)
        case "error":
            self.statusMessage = "Error: \(update.message ?? "Unknown error")"
            self.isDownloading = false
            NotchProgressController.shared.dismiss(.download)
        default: break
        }
    }
    
    func openFolder() {
        guard let pathString = downloadedFilePath else { return }
        let url = URL(fileURLWithPath: pathString).deletingLastPathComponent()
        NSWorkspace.shared.open(url)
    }
}
