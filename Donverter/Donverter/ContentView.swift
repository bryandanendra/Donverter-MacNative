//
//  ContentView.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var appState = AppStateManager.shared
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var selectedTab = 0
    @State private var updateBannerDismissed = false

    var body: some View {
        ZStack {
            // macOS Native Desktop Blur Passthrough Layer
            VisualEffectView()
                .ignoresSafeArea()
            
            // Subtle theme tint over the blur to match the dark glassmorphism
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            // Extremely subtle inner tint to replicate glass material
            Color.white.opacity(0.03)
                .ignoresSafeArea()
                
            VStack(spacing: 0) {
                // Glassy Tab Bar
                HStack(spacing: 8) {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = 0 } }) {
                        Text("Downloader")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(selectedTab == 0 ? Color.white.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == 0 ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { selectedTab = 1 } }) {
                        Text("Converter")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(selectedTab == 1 ? Color.white.opacity(0.2) : Color.clear)
                            .foregroundColor(selectedTab == 1 ? .white : .white.opacity(0.6))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(6)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                .padding(.top, 32)
                .padding(.bottom, 16)

                // Update Available Banner
                if updater.updateAvailable && !updateBannerDismissed {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.accent)
                        Text("New version v\(updater.latestVersion ?? "") is available")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                        Button(action: { updater.openReleasesPage() }) {
                            Text("Download")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(AppTheme.accent.opacity(0.8))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) { updateBannerDismissed = true }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(5)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(AppTheme.accent.opacity(0.4), lineWidth: 1))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Content Switcher
                if selectedTab == 0 {
                    VideoDownloaderView().transition(.opacity)
                } else {
                    ImageConverterView().transition(.opacity)
                }
            }
            
            // Custom Cache Modal Overlay
            if appState.showClearCacheModal {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(99)
                
                ClearCacheModalView()
                    .transition(.scale(scale: 0.9, anchor: .center).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .frame(minWidth: 720, minHeight: 700)
        .preferredColorScheme(.dark)
        // Ensure Window is transparent to allow `VisualEffectView` to punch holes to Desktop
        .background(Color.clear)
        .onAppear {
            updater.checkForUpdates()
        }
    }
}
