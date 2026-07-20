//
//  AppSettings.swift
//  Donverter
//
//  Setting level aplikasi (bukan Dynamic Island): folder output, dsb.
//

import Foundation
import AppKit

enum AppSettings {
    static let outputFolderKey = "outputFolderPath"

    /// Folder Downloads default milik user.
    static var defaultOutputFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    /// Folder output efektif: pilihan user kalau valid & writable, else Downloads.
    static var outputFolderURL: URL {
        let stored = UserDefaults.standard.string(forKey: outputFolderKey) ?? ""
        guard !stored.isEmpty else { return defaultOutputFolderURL }
        let url = URL(fileURLWithPath: (stored as NSString).expandingTildeInPath)
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue, fm.isWritableFile(atPath: url.path) {
            return url
        }
        return defaultOutputFolderURL
    }

    static var isUsingCustomOutputFolder: Bool {
        !(UserDefaults.standard.string(forKey: outputFolderKey) ?? "").isEmpty
    }

    /// Buka NSOpenPanel untuk memilih folder output; simpan pilihan user.
    @MainActor
    static func presentOutputFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = outputFolderURL
        panel.prompt = "Choose"
        panel.message = "Choose where downloaded and converted files are saved"
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: outputFolderKey)
        }
    }

    static func resetOutputFolder() {
        UserDefaults.standard.removeObject(forKey: outputFolderKey)
    }
}
