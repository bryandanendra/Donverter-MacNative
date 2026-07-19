//
//  UpdateChecker.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Update Checker
/// Cek rilis terbaru di GitHub saat app dibuka. Ini penting karena yt-dlp yang
/// di-freeze di dalam app akan basi seiring situs (YouTube dll.) berubah —
/// satu-satunya jalan memperbaruinya adalah download rilis DMG baru.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String? = nil
    @Published var updateAvailable: Bool = false

    static let releasesPageURL = URL(string: "https://github.com/bryandanendra/Donverter-MacNative/releases/latest")!
    private static let apiURL = URL(string: "https://api.github.com/repos/bryandanendra/Donverter-MacNative/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    func checkForUpdates() {
        var request = URLRequest(url: Self.apiURL)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return } // offline / rate-limit → diam saja
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                self.latestVersion = latest
                self.updateAvailable = Self.isVersion(latest, newerThan: self.currentVersion)
                NSLog("UpdateChecker: current=%@ latest=%@ updateAvailable=%@",
                      self.currentVersion, latest, self.updateAvailable ? "YES" : "NO")
            }
        }.resume()
    }

    /// Bandingkan versi per komponen numerik: "2.1" > "2.0.3", dan "2.0" == "2.0.0".
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(Self.releasesPageURL)
    }
}
