//
//  DonverterApp.swift
//  Donverter
//
//  Created by 1234 on 15/03/2026.
//

import SwiftUI

class AppCacheManager {
    static func clearAllCaches() {
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
        
        // Display Success Alert
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Cache Cleared Successfully"
            alert.informativeText = "All application caches, temporary files, and yt-dlp back-end caches have been cleaned up to free up space."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

@main
struct DonverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandMenu("Maintenance") {
                Button("Clear Cache") {
                    AppCacheManager.clearAllCaches()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
