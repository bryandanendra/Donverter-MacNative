//
//  NotchIslandDemo.swift
//  Donverter
//
//  Simulasi Dynamic Island tanpa download/konversi sungguhan.
//  Jalankan dengan: DONVERTER_ISLAND_DEMO=1 ./Donverter.app/Contents/MacOS/Donverter
//  Berguna untuk mengetes desain island (termasuk skenario dua task berjalan
//  bersamaan) — setiap transisi dicatat ke NSLog untuk verifikasi.
//

import Foundation
import AppKit

@MainActor
enum NotchIslandDemo {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DONVERTER_ISLAND_DEMO"] == "1"
    }

    private static func logState(_ step: String) {
        let c = NotchProgressController.shared
        NSLog("IslandDemo[%@]: displayed=%@ state=%@ activeCount=%d",
              step,
              c.displayedKind?.rawValue ?? "nil",
              c.state.stateName,
              c.activeTaskCount)
    }

    static func run() {
        guard isEnabled else { return }
        let c = NotchProgressController.shared

        Task { @MainActor in
            NSLog("IslandDemo: start")

            // Fase 1 — download berjalan sendirian
            c.update(.download, label: "Downloading...", progress: 0.10, filePath: nil)
            logState("1-download-start")

            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // Fase 2 — konversi ikut berjalan; tampilan harus TETAP download (sticky)
            c.update(.convert, label: "Converting...", progress: 0.30, filePath: nil)
            logState("2-convert-joins")

            // Fase 3 — dua-duanya kirim progress bergantian; tampilan tetap download
            for i in 1...4 {
                try? await Task.sleep(nanoseconds: 700_000_000)
                c.update(.download, label: "Downloading...", progress: 0.10 + Double(i) * 0.20, filePath: nil)
                c.update(.convert, label: "Converting...", progress: 0.30 + Double(i) * 0.15, filePath: nil)
            }
            logState("3-both-progressing")

            // Fase 4 — download selesai; done card-nya tampil, konversi lanjut di belakang
            c.markDone(.download, label: "Download Complete", filePath: nil)
            logState("4-download-done")

            try? await Task.sleep(nanoseconds: 2_000_000_000)

            // Fase 5 — done card download ditutup; island pindah ke konversi yang masih jalan
            c.dismiss(.download)
            logState("5-download-dismissed")

            try? await Task.sleep(nanoseconds: 1_500_000_000)

            // Fase 6 — konversi selesai lalu ditutup; island menghilang
            c.markDone(.convert, label: "Conversion Complete", filePath: nil)
            logState("6-convert-done")

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            c.dismiss(.convert)
            logState("7-all-dismissed")

            NSLog("IslandDemo: finished")
        }
    }
}
