//
//  HistoryView.swift
//  Donverter
//
//  Tab riwayat download & konversi di window utama.
//

import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var hoveredEntryID: UUID? = nil
    @State private var copiedEntryID: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header: jumlah entri + tombol Clear
            HStack {
                Text("\(store.entries.count) item\(store.entries.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if !store.entries.isEmpty {
                    Button(action: { store.clear() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear History")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)

            if store.entries.isEmpty {
                // Empty state
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 42))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No history yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                    Text("Downloaded and converted files will appear here.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.25))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(store.entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        let exists = entry.fileExists
        let isHovered = hoveredEntryID == entry.id

        HStack(spacing: 12) {
            // Ikon jenis task
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 36, height: 36)
                Image(systemName: entry.kind == "download" ? "arrow.down.circle.fill" : "photo.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(entry.kind == "download"
                                     ? Color(red: 0.35, green: 0.65, blue: 1.0)
                                     : Color(red: 0.55, green: 0.85, blue: 0.55))
            }
            .opacity(exists ? 1 : 0.35)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.filename)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(exists ? 0.9 : 0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(entry.date, format: .relative(presentation: .named))
                    if let size = entry.fileSize, exists {
                        Text("·")
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    if !exists {
                        Text("·")
                        Text("File moved or deleted")
                            .foregroundColor(.orange.opacity(0.55))
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            // Copy link sumber (selalu tampil untuk entri download yang punya URL)
            if let source = entry.sourceURL, !source.isEmpty {
                let isCopied = copiedEntryID == entry.id
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(source, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copiedEntryID = entry.id }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if copiedEntryID == entry.id {
                            withAnimation(.easeOut(duration: 0.2)) { copiedEntryID = nil }
                        }
                    }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "link")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isCopied ? .green : .white.opacity(isHovered ? 0.7 : 0.35))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help(isCopied ? "Copied!" : "Copy source link")
            }

            if exists && isHovered {
                Button(action: {
                    let url = URL(fileURLWithPath: entry.filepath)
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: entry.filepath, isDirectory: &isDir), isDir.boolValue {
                        NSWorkspace.shared.open(url)
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                        Text("Show")
                    }
                    .font(.caption.bold())
                    .foregroundColor(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if isHovered {
                Button(action: { store.remove(entry) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove from history")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(isHovered ? 0.07 : 0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering in
            hoveredEntryID = hovering ? entry.id : (hoveredEntryID == entry.id ? nil : hoveredEntryID)
        }
    }
}
