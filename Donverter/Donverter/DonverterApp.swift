//
//  DonverterApp.swift
//  Donverter
//
//  Created by 1234 on 15/03/2026.
//

import SwiftUI
import AppKit
import Combine

class AppCacheManager {
    static func calculateTotalCacheSize() -> Int64 {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser
        var totalSize: Int64 = 0
        
        // 1. Library/Caches/yt-dlp
        let macCacheURL = homeDir.appendingPathComponent("Library/Caches/yt-dlp")
        totalSize += getPathSize(atPath: macCacheURL.path)
        
        // 2. .cache/yt-dlp
        let xdgCacheURL = homeDir.appendingPathComponent(".cache/yt-dlp")
        totalSize += getPathSize(atPath: xdgCacheURL.path)
        
        // 3. macOS app caches
        if let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let bundleID = Bundle.main.bundleIdentifier {
            let appCacheURL = cacheURL.appendingPathComponent(bundleID)
            totalSize += getPathSize(atPath: appCacheURL.path)
        }
        
        // 4. NSTemporaryDirectory
        let tmpDir = NSTemporaryDirectory()
        if let contents = try? fm.contentsOfDirectory(atPath: tmpDir) {
            for file in contents {
                let path = (tmpDir as NSString).appendingPathComponent(file)
                totalSize += getPathSize(atPath: path)
            }
        }

        // 5. File download parsial yatim di ~/Downloads (sisa crash / download terputus)
        for url in findOrphanedPartialFiles() {
            totalSize += getPathSize(atPath: url.path)
        }

        return totalSize
    }

    /// Cari file parsial yatim (.part / .ytdl / .temp) di ~/Downloads.
    /// Hanya file yang tidak disentuh > 5 menit — supaya tidak mengganggu
    /// download yang sedang berjalan, baik milik app ini maupun aplikasi lain
    /// (Firefox juga memakai ekstensi .part untuk download aktifnya).
    static func findOrphanedPartialFiles() -> [URL] {
        let fm = FileManager.default
        let downloadsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let items = try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let partialSuffixes = [".part", ".ytdl", ".temp"]
        let cutoff = Date().addingTimeInterval(-5 * 60)

        return items.filter { url in
            let name = url.lastPathComponent
            guard partialSuffixes.contains(where: { name.hasSuffix($0) }) else { return false }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let mtime = values.contentModificationDate else { return false }
            return mtime < cutoff
        }
    }
    
    private static func getPathSize(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        
        if isDir.boolValue {
            let url = URL(fileURLWithPath: path)
            guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
                return 0
            }
            var totalSize: Int64 = 0
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
            return totalSize
        } else {
            if let attributes = try? fm.attributesOfItem(atPath: path),
               let fileSize = attributes[.size] as? Int64 {
                return fileSize
            }
        }
        return 0
    }
    
    static func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 KB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        let result = formatter.string(fromByteCount: bytes)
        if result == "Zero KB" {
            return "0 KB"
        }
        return result
    }

    static func performClearCache() {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser
        
        // Clear standard macOS Caches for yt-dlp
        let macCacheURL = homeDir.appendingPathComponent("Library/Caches/yt-dlp")
        try? fm.removeItem(at: macCacheURL)
        
        // Clear standard XDG cache for yt-dlp (jika ada)
        let xdgCacheURL = homeDir.appendingPathComponent(".cache/yt-dlp")
        try? fm.removeItem(at: xdgCacheURL)

        // Clear macOS app caches
        if let cacheURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let bundleID = Bundle.main.bundleIdentifier {
            let appCacheURL = cacheURL.appendingPathComponent(bundleID)
            try? fm.removeItem(at: appCacheURL)
        }
        
        // Clear NSTemporaryDirectory (files that we might have created, like temp h264 conversions)
        let tmpDir = NSTemporaryDirectory()
        if let contents = try? fm.contentsOfDirectory(atPath: tmpDir) {
            for file in contents {
                let path = (tmpDir as NSString).appendingPathComponent(file)
                try? fm.removeItem(atPath: path)
            }
        }

        // Clear file download parsial yatim di ~/Downloads
        for url in findOrphanedPartialFiles() {
            try? fm.removeItem(at: url)
        }
    }
}

class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    @Published var showClearCacheModal = false
    @Published var currentCacheSize: Int64 = 0
    
    func refreshCacheSize() {
        currentCacheSize = AppCacheManager.calculateTotalCacheSize()
    }
}

@main
struct DonverterApp: App {

    init() {
        // Boot the Dynamic Island-style notch progress overlay
        _ = NotchProgressWindowManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)
                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)
                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }
            CommandMenu("Maintenance") {
                Button("Clear Cache") {
                    AppStateManager.shared.refreshCacheSize()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        AppStateManager.shared.showClearCacheModal = true
                    }
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
        
        #if os(macOS)
        Settings {
            SettingsWindowView()
        }
        #endif
    }
}
