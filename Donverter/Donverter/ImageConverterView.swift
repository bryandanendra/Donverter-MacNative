//
//  ImageConverterView.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Image Converter UI
struct ImageConverterView: View {
    @StateObject private var manager = ImageConverterManager()
    
    @State private var selectedFormat: String = "JPG"
    @State private var enableCompression: Bool = false
    @State private var isHovering: Bool = false
    @State private var isHoveringConvert: Bool = false
    
    let formats = ["JPG", "PNG", "PDF", "HEIF", "HIF", "WEBP", "SVG"]
    let pdfFormats = ["JPG", "PNG", "WEBP"]
    
    var activeFormats: [String] {
        manager.isPdfMode ? pdfFormats : formats
    }
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                
                // Content Area for files
                if manager.selectedFiles.isEmpty {
                    // Glassy Drag & Drop Area
                Button(action: {
                    manager.presentFilePicker()
                }) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(manager.selectedFiles.isEmpty ? Color.white.opacity(0.1) : Color.green.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: manager.selectedFiles.isEmpty ? "photo.stack" : "checkmark.seal.fill")
                                .font(.system(size: 32))
                                .foregroundColor(manager.selectedFiles.isEmpty ? .white : .green)
                        }
                        
                        Text(manager.selectedFiles.isEmpty ? "Drag & Drop Images or PDF" : "\(manager.selectedFiles.count) files ready for conversion")
                            .font(.system(size: 18, weight: .bold))
                        
                        Text(manager.statusMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(isHovering ? Color.white.opacity(0.15) : Color.black.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundColor(isHovering ? AppTheme.accent : Color.white.opacity(0.2))
                    )
                    .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(manager.isConverting)
                .onHover { hovering in
                    withAnimation { isHovering = hovering }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $isHovering) { providers in
                    var handled = false
                    var droppedURLs: [URL] = []
                    let group = DispatchGroup()
                    for provider in providers {
                        group.enter()
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                droppedURLs.append(url)
                                handled = true
                            }
                            group.leave()
                        }
                    }
                    group.notify(queue: .main) {
                        if manager.wouldCreateMixedSelection(newURLs: droppedURLs) {
                            manager.statusMessage = "⚠️ Cannot mix PDF and image files. Please select one type only."
                        } else {
                            for url in droppedURLs {
                                if !manager.selectedFiles.contains(url) {
                                    manager.selectedFiles.append(url)
                                }
                            }
                            manager.updatePdfMode()
                            if manager.isPdfMode {
                                manager.statusMessage = "PDF selected — pages will be extracted as images."
                            } else {
                                manager.statusMessage = "\(manager.selectedFiles.count) files selected for conversion."
                            }
                        }
                    }
                    return handled
                }
                } else {
                    // Selected Files UI
                    VStack(spacing: 20) {
                        HStack {
                            Text("Selected Files")
                                .font(.system(size: 16, weight: .bold))
                            
                            Text("\(manager.selectedFiles.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.1, green: 0.7, blue: 0.9))
                                .cornerRadius(12)
                                
                            Spacer()
                            
                            Button(action: {
                                withAnimation {
                                    manager.selectedFiles.removeAll()
                                    manager.isPdfMode = false
                                    selectedFormat = "JPG"
                                }
                            }) {
                                Text("Clear All")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.5), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        VStack(spacing: 0) {
                            ForEach(Array(manager.selectedFiles.enumerated()), id: \.offset) { index, file in
                                HStack(spacing: 12) {
                                    // Format Badge
                                    Text(file.pathExtension.uppercased())
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                                        .frame(width: 44, height: 44)
                                        .background(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.15))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(file.lastPathComponent)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        
                                        Text(getFileSize(url: file))
                                            .font(.system(size: 12))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        withAnimation {
                                            manager.selectedFiles.removeAll(where: { $0 == file })
                                            manager.updatePdfMode()
                                        }
                                    }) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color(red: 0.9, green: 0.3, blue: 0.3))
                                            .frame(width: 26, height: 26)
                                            .background(Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.15))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                
                                if index < manager.selectedFiles.count - 1 {
                                    Divider().background(Color.white.opacity(0.1))
                                }
                            }
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        
                        Button(action: {
                            manager.presentFilePicker()
                        }) {
                            Text("+ Add More Files")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.clear)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                        .foregroundColor(Color(red: 0.2, green: 0.6, blue: 1.0).opacity(0.5))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                            var handled = false
                            var droppedURLs: [URL] = []
                            let group = DispatchGroup()
                            for provider in providers {
                                group.enter()
                                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                        droppedURLs.append(url)
                                        handled = true
                                    }
                                    group.leave()
                                }
                            }
                            group.notify(queue: .main) {
                                if manager.wouldCreateMixedSelection(newURLs: droppedURLs) {
                                    manager.statusMessage = "⚠️ Cannot mix PDF and image files. Please select one type only."
                                } else {
                                    for url in droppedURLs {
                                        if !manager.selectedFiles.contains(url) {
                                            manager.selectedFiles.append(url)
                                        }
                                    }
                                    manager.updatePdfMode()
                                }
                            }
                            return handled
                        }
                    }
                }
                
                // Format Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text(manager.isPdfMode ? "Page Format" : "Output Format")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    HStack(spacing: 8) {
                        ForEach(activeFormats, id: \.self) { format in
                            GlassSelectionBox(title: format, iconSystemName: nil, isSelected: selectedFormat == format) {
                                withAnimation(.easeOut(duration: 0.2)) { selectedFormat = format }
                            }
                        }
                    }
                }
                
                // Mode-specific info banner
                if manager.isPdfMode {
                    // PDF mode info banner
                    HStack(spacing: 12) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PDF Page Extraction")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.3))
                            Text("Each page will be rendered as a high-quality image (300 DPI) into a folder")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.8, green: 0.4, blue: 0.1).opacity(0.15))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 1.0, green: 0.6, blue: 0.2).opacity(0.4), lineWidth: 1))
                } else if selectedFormat != "SVG" {
                    // Glassy Compression Toggle (hidden for SVG output since vtracer does vector tracing)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Compression")
                                .font(.system(size: 15, weight: .medium))
                            Text("Reduces file sizes while maintaining reasonable quality")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Toggle("", isOn: $enableCompression)
                            .toggleStyle(SwitchToggleStyle(tint: AppTheme.accent))
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .disabled(manager.isConverting)
                } else {
                    // SVG info banner
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vector Tracing Mode")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.7, green: 0.5, blue: 1.0))
                            Text("Converts raster pixels into scalable SVG vector paths")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(red: 0.4, green: 0.2, blue: 0.8).opacity(0.15))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4), lineWidth: 1))
                }
                
                Spacer().frame(height: 10)
                
                // Convert Action Button
                VStack(spacing: 12) {
                    Button(action: {
                        manager.startConversion(format: selectedFormat, enableCompression: enableCompression)
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: manager.isPdfMode ? "doc.viewfinder" : "sparkles")
                                .font(.system(size: 18))
                            Text(manager.isConverting
                                 ? (manager.isPdfMode ? "Extracting..." : "Converting...")
                                 : (manager.isPdfMode ? "Extract Pages" : (selectedFormat == "SVG" ? "Trace to SVG" : "Convert Images")))
                                .fontWeight(.bold)
                                .font(.system(size: 16))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            manager.selectedFiles.isEmpty || manager.isConverting
                            ? Color.white.opacity(0.1)
                            : (isHoveringConvert ? Color.white : AppTheme.accent.opacity(0.8))
                        )
                        .background(.ultraThinMaterial) // Liquid Glass on Button
                        .foregroundColor(
                            manager.selectedFiles.isEmpty || manager.isConverting
                            ? .white
                            : (isHoveringConvert ? AppTheme.accent : .white)
                        )
                        // Smooth modern border
                        .overlay(
                            Capsule()
                                .stroke(manager.selectedFiles.isEmpty || manager.isConverting ? Color.white.opacity(0.1) : (isHoveringConvert ? Color.white : AppTheme.accent.opacity(0.6)), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(manager.selectedFiles.isEmpty || manager.isConverting)
                    .scaleEffect(manager.isConverting ? 0.98 : 1.0)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.2)) {
                            isHoveringConvert = hovering
                        }
                    }
                    
                    // Progress Section
                    if manager.isConverting || manager.progress > 0 {
                        VStack(spacing: 8) {
                            ProgressView(value: manager.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: AppTheme.accent))
                                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                            
                            HStack {
                                Text(manager.statusMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                if let path = manager.convertedFilePath {
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
                }
                
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }
    
    private func getFileSize(url: URL) -> String {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            let fileSize = Double(resourceValues.fileSize ?? 0)
            if fileSize > 1_000_000 {
                return String(format: "%.2f MB", fileSize / 1_000_000)
            } else {
                return String(format: "%.2f KB", fileSize / 1_000)
            }
        } catch {
            return "Unknown"
        }
    }
}



#Preview {
    ContentView()
}
