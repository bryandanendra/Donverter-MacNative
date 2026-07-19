//
//  PipeLineBuffer.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Pipe Line Buffer
/// Menampung potongan data dari pipe dan hanya mengeluarkan baris yang sudah utuh.
/// readabilityHandler menerima chunk sembarang — satu baris JSON bisa terbelah di
/// dua callback, dan karakter UTF-8 multi-byte bisa terpotong di batas chunk.
/// Dengan buffering di level Data, dua-duanya aman.
final class PipeLineBuffer {
    private var buffer = Data()

    /// Tambahkan chunk baru, panggil `onLine` untuk setiap baris utuh (tanpa newline).
    /// \r juga dianggap pemisah baris — progress bar yt-dlp memakai \r tanpa \n,
    /// dan tanpa ini teksnya bisa menempel di depan baris JSON.
    func append(_ data: Data, onLine: (String) -> Void) {
        buffer.append(data)
        while let newlineIndex = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            emit(lineData, onLine: onLine)
        }
    }

    /// Keluarkan sisa data yang belum diakhiri newline (dipanggil saat EOF).
    func flush(onLine: (String) -> Void) {
        let remaining = buffer
        buffer = Data()
        emit(remaining, onLine: onLine)
    }

    private func emit(_ data: Data, onLine: (String) -> Void) {
        guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onLine(trimmed) }
    }
}
