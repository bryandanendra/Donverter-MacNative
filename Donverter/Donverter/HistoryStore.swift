//
//  HistoryStore.swift
//  Donverter
//
//  Riwayat file hasil download & konversi, dipersist sebagai JSON di
//  ~/Library/Application Support/Donverter/history.json (maksimal 50 entri).
//

import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let filename: String
    let filepath: String
    let kind: String        // "download" | "convert"
    let date: Date
    let fileSize: Int64?
    /// URL sumber (video yang didownload). Optional supaya entri lama
    /// tanpa field ini tetap bisa di-decode.
    let sourceURL: String?

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filepath)
    }
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var entries: [HistoryEntry] = []

    static let maxEntries = 50
    private let storageURL: URL

    /// storageURL bisa dioverride untuk testing.
    init(storageURL: URL? = nil) {
        if let url = storageURL {
            self.storageURL = url
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Donverter", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            self.storageURL = appSupport.appendingPathComponent("history.json")
        }
        load()
    }

    func add(filename: String, filepath: String, kind: String, sourceURL: String? = nil) {
        var size: Int64? = nil
        if let attrs = try? FileManager.default.attributesOfItem(atPath: filepath),
           let s = attrs[.size] as? Int64 {
            size = s
        }
        let entry = HistoryEntry(
            id: UUID(), filename: filename, filepath: filepath,
            kind: kind, date: Date(), fileSize: size, sourceURL: sourceURL
        )
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > Self.maxEntries {
                self.entries = Array(self.entries.prefix(Self.maxEntries))
            }
            self.save()
        }
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = Array(decoded.prefix(Self.maxEntries))
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
