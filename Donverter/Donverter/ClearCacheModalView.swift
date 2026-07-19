//
//  ClearCacheModalView.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - Custom Cache Maintenance Modal View
struct ClearCacheModalView: View {
    @ObservedObject var appState = AppStateManager.shared
    @State private var isCleared = false
    
    var body: some View {
        Group {
            if !isCleared {
                confirmContent
            } else {
                successContent
            }
        }
        .padding(32)
        .frame(width: 420)
        .background(
            ZStack {
                VisualEffectView()
                Color.black.opacity(0.45)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.6), radius: 30, x: 0, y: 15)
    }
    
    private var confirmContent: some View {
        VStack(spacing: 24) {
            // ICON
            iconHeader
            
            // TEXT BLOCK (TITLE + DESCRIPTION WITH TIGHTER SPACING)
            VStack(spacing: 8) {
                Text("Clear Application Cache?")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Are you sure you want to clear all cached data to free up space?")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
            }
            
            // CACHE CARD
            cacheSizeCard
            
            // BUTTONS
            confirmButtons
        }
    }
    
    private var iconHeader: some View {
        Group {
            if let appIcon = NSApplication.shared.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(16)
            }
        }
    }
    
    private var cacheSizeCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.45, green: 0.55, blue: 0.95))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Cache Size")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                
                Text(AppCacheManager.formatBytes(appState.currentCacheSize))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.7))
            }
            
            Spacer()
            
            Text("Will be freed")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0.3, green: 0.85, blue: 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.3, green: 0.85, blue: 0.7).opacity(0.12))
                .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
    
    private var confirmButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    appState.showClearCacheModal = false
                }
            }) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                AppCacheManager.performClearCache()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCleared = true
                }
            }) {
                Text("Clear Cache")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.05, green: 0.5, blue: 1.0),
                                Color(red: 0.0, green: 0.4, blue: 0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 8)
    }
    
    private var successContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.2, green: 0.8, blue: 0.4),
                                Color(red: 0.1, green: 0.6, blue: 0.3)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("Cache Cleared!")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text("Freed up \(AppCacheManager.formatBytes(appState.currentCacheSize)) of storage space successfully.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 16)
            
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    appState.showClearCacheModal = false
                    appState.currentCacheSize = 0
                }
            }) {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.05, green: 0.5, blue: 1.0),
                                Color(red: 0.0, green: 0.4, blue: 0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(20)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 16)
        }
    }
}
