//
//  GlassUI.swift
//  Donverter
//

import SwiftUI
import Foundation
import Combine
import UniformTypeIdentifiers

// MARK: - App Theme & Colors
struct AppTheme {
    static let accent = Color.accentColor
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // The magic enum for "Control Center" or "Sidebar" glass look that punches through to the desktop
        view.material = .hudWindow // or .popover / .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                // Optionally make the title bar clear too if needed
                window.titlebarAppearsTransparent = true
            }
        }
    }
}

// Custom Glass Card Modifier
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05)) // Extremely subtle inner tint
            .background(.ultraThinMaterial) // macOS native blur layer
            .cornerRadius(cornerRadius)
            .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 10)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Reusable UI Components
struct GlassSelectionBox: View {
    let title: String
    let iconSystemName: String?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = iconSystemName {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(isSelected || isHovering ? Color.white : Color.white.opacity(0.05))
            .background(.ultraThinMaterial)
            .foregroundColor(isSelected || isHovering ? AppTheme.accent : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected || isHovering ? Color.white : Color.white.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}

struct GlassResolutionChip: View {
    let label: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: isSelected || isHovering ? .bold : .medium))
                
                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected || isHovering ? AppTheme.accent.opacity(0.8) : Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected || isHovering ? Color.white : Color.white.opacity(0.05))
            .background(.ultraThinMaterial)
            .foregroundColor(isSelected || isHovering ? AppTheme.accent : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected || isHovering ? Color.white : Color.white.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
}
