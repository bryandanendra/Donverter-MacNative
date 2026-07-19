//
//  ImageConverterManager.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

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
            // Show notch overlay
            let startLabel = self.isPdfMode ? "Extracting PDF..." : "Converting..."
            NotchProgressController.shared.show(label: startLabel, progress: 0.0, filePath: nil)
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
            args = ["--mode", "pdf2img", "--format", format.lowercased(), "--quality", quality, "--files"]
            args.append(contentsOf: selectedFiles.map { $0.path })
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
        
        let stdoutBuffer = PipeLineBuffer()
        let stderrBuffer = PipeLineBuffer()

        let processLine: (String) -> Void = { [weak self] line in
            if let jsonData = line.data(using: .utf8),
               let update = try? JSONDecoder().decode(ProgressUpdate.self, from: jsonData) {
                DispatchQueue.main.async { self?.handleUpdate(update) }
            } else {
                print("Python Stdout: \(line)")
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                stdoutBuffer.flush(onLine: processLine)
                fileHandle.readabilityHandler = nil
                return
            }
            stdoutBuffer.append(data, onLine: processLine)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                stderrBuffer.flush { print("Python Stderr (Converter): \($0)") }
                fileHandle.readabilityHandler = nil
                return
            }
            stderrBuffer.append(data) { print("Python Stderr (Converter): \($0)") }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isConverting = false
                if let progress = self?.progress, progress < 1.0, self?.convertedFilePath == nil {
                    if let msg = self?.statusMessage, !msg.hasPrefix("Error") {
                        self?.statusMessage = "Conversion ended unexpectedly. See console."
                    }
                }
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
            if let pct = update.percent {
                let fraction = Double(pct) / 100.0
                self.progress = fraction
                let fileLabel = update.current_file.map { "Converting \($0)" } ?? "Converting..."
                NotchProgressController.shared.show(label: fileLabel, progress: fraction, filePath: nil)
            }
            if let file = update.current_file { self.statusMessage = "Converting: \(file)..." }
        case "status":
            self.statusMessage = update.message ?? "Processing..."
        case "success":
            self.progress = 1.0
            self.statusMessage = "\(update.message ?? "Conversion Complete!")"
            self.convertedFilePath = update.filepath
            self.isConverting = false
            self.selectedFiles = []
            NotchProgressController.shared.markDone(label: "Conversion Complete", filePath: update.filepath)
        case "error":
            self.statusMessage = "Error: \(update.message ?? "Unknown error")"
            self.isConverting = false
            NotchProgressController.shared.dismiss()
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
