//
//  VideoDownloaderView.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Video Downloader UI
struct VideoDownloaderView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @ObservedObject private var logger = DebugLogger.shared
    
    @State private var url: String = ""
    @State private var selectedPlatform: String = "YouTube"
    @State private var selectedFormat: String = "MP4"
    @State private var selectedResolution: String = "Best"
    @State private var isHoveringDownload: Bool = false
    @State private var isHoveringCancel: Bool = false
    @State private var showDebugLog: Bool = false
    
    let platforms = [
        ("YouTube", "play.rectangle.fill"),
        ("TikTok", "music.note"),
        ("Instagram", "camera.metering.partial")
    ]
    let formats = [("MP4", "film"), ("MP3", "headphones")]
    
    let resolutions = [
        ("360", nil), ("480", nil), ("720", "HD"),
        ("1080", "FHD"), ("1440", "2K"), ("2160", "4K"),
        ("Best", "MAX")
    ]
    
    private func autoDetectPlatform(from urlString: String) {
        let lower = urlString.lowercased()
        if lower.contains("youtube.com") || lower.contains("youtu.be") {
            selectedPlatform = "YouTube"
        } else if lower.contains("tiktok.com") {
            selectedPlatform = "TikTok"
        } else if lower.contains("instagram.com") {
            selectedPlatform = "Instagram"
        }
    }
    
    private func checkClipboardAndAutoFill() {
        guard url.isEmpty else { return }
        if let clipString = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            let lower = clipString.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
                if lower.contains("youtube.com") || lower.contains("youtu.be") ||
                   lower.contains("tiktok.com") || lower.contains("instagram.com") {
                    withAnimation {
                        url = clipString
                        autoDetectPlatform(from: clipString)
                    }
                }
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                
                // NO MORE SEPARATE GLASS CARD HERE, IT IS IN THE PARENT CONTENTVIEW NOW
                
                // URL Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video URL")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        TextField("https://...", text: $url)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .disabled(manager.isDownloading)
                            .onChange(of: url) { newValue in
                                autoDetectPlatform(from: newValue)
                            }
                        
                        if !manager.isDownloading {
                            Button(action: {
                                if let clipString = NSPasteboard.general.string(forType: .string) {
                                    withAnimation {
                                        url = clipString.trimmingCharacters(in: .whitespacesAndNewlines)
                                        autoDetectPlatform(from: url)
                                    }
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.15))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Paste URL from clipboard")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                
                // Platform Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Platform")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        ForEach(platforms, id: \.0) { platform in
                            GlassSelectionBox(title: platform.0, iconSystemName: platform.1, isSelected: selectedPlatform == platform.0) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedPlatform = platform.0 }
                            }
                        }
                    }
                }
                
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Format")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        ForEach(formats, id: \.0) { format in
                            GlassSelectionBox(title: format.0, iconSystemName: format.1, isSelected: selectedFormat == format.0) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedFormat = format.0 }
                            }
                        }
                    }
                }
                
                // Resolution Selection
                if selectedFormat == "MP4" && selectedPlatform == "YouTube" {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Resolution")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.8))
                        
                        HStack(spacing: 8) {
                            ForEach(resolutions, id: \.0) { res in
                                GlassResolutionChip(label: res.0 == "Best" ? "Best" : "\(res.0)p", badge: res.1, isSelected: selectedResolution == res.0) {
                                    withAnimation(.easeOut(duration: 0.2)) { selectedResolution = res.0 }
                                }
                            }
                        }
                    }
                }
                
                // Download Action Button
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                    Button(action: {
                        manager.startDownload(url: url, platform: selectedPlatform, format: selectedFormat, resolution: selectedResolution)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.to.line.circle.fill")
                                .font(.system(size: 18))
                            Text(manager.isDownloading ? "Downloading..." : "Start Download")
                                .fontWeight(.bold)
                                .font(.system(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading
                            ? Color.white.opacity(0.1)
                            : (isHoveringDownload ? Color.white : AppTheme.accent.opacity(0.8))
                        )
                        .background(.ultraThinMaterial) // Liquid Glass on Button
                        .foregroundColor(
                            url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading
                            ? .white
                            : (isHoveringDownload ? AppTheme.accent : .white)
                        )
                        // Smooth modern border
                        .overlay(
                            Capsule()
                                .stroke(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading ? Color.white.opacity(0.1) : (isHoveringDownload ? Color.white : AppTheme.accent.opacity(0.6)), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isDownloading)
                    .scaleEffect(manager.isDownloading ? 0.98 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHoveringDownload = hovering
                        }
                    }

                    // Cancel Button — muncul hanya saat download berjalan
                    if manager.isDownloading {
                        Button(action: {
                            manager.cancelDownload()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 15))
                                Text("Cancel")
                                    .fontWeight(.bold)
                                    .font(.system(size: 15))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(isHoveringCancel ? Color.red : Color.red.opacity(0.65))
                            .background(.ultraThinMaterial)
                            .foregroundColor(.white)
                            .overlay(
                                Capsule()
                                    .stroke(isHoveringCancel ? Color.red : Color.red.opacity(0.5), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.2)) {
                                isHoveringCancel = hovering
                            }
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    } // HStack (Download + Cancel)
                    .animation(.easeOut(duration: 0.25), value: manager.isDownloading)

                    // Progress Section
                    if manager.isDownloading || manager.progress > 0 {
                        VStack(spacing: 8) {
                            ProgressView(value: manager.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            
                            HStack {
                                Text(manager.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(2)
                                Spacer()
                                if let path = manager.downloadedFilePath {
                                    Button(action: { manager.openFolder() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "folder.fill")
                                            Text("Show in Finder")
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
                            }
                        }
                        .padding(.top, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Debug Log Button (always visible after first use)
                    if !logger.logs.isEmpty {
                        Button(action: { showDebugLog = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 12))
                                Text("Debug Log")
                                    .font(.system(size: 13, weight: .medium))
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .opacity(manager.isDownloading ? 1 : 0)
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showDebugLog) {
                            DebugLogView()
                        }
                    }
                }
                .padding(.top, 14)
                
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .onAppear {
            checkClipboardAndAutoFill()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkClipboardAndAutoFill()
        }
    }
}
