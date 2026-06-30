//
//  NotchProgressView.swift
//  Donverter
//
//  SwiftUI Dynamic Island-style progress overlay
//  Fuses with the physical notch and supports two modes:
//   1. Compact (restW x closedH) - Circular progress & app icon
//   2. Hover-Expanded (expandW x closedH+expandH) - Detailed status & action card
//

import SwiftUI
import AppKit

// MARK: - NotchShape
// Top corners: tiny radius (blends into MacBook screen notch)
// Bottom corners: larger radius (curves bottom of the card)

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 18) {
        self.topCornerRadius    = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to:      CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        p.addQuadCurve(
            to:      CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        p.addQuadCurve(
            to:      CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        p.addQuadCurve(
            to:      CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Smooth ProgressBar

struct SmoothProgressBar: View {
    let progress: Double
    let foreground: Color
    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 3)
                Capsule().fill(foreground)
                    .frame(width: max(geo.size.width * animated, 0), height: 3)
            }
        }
        .frame(height: 3)
        .onChange(of: progress) { _, v in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { animated = v }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { animated = progress }
        }
    }
}

// MARK: - Circular Progress Ring (For Compact Mode)

struct CircularProgressView: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2.0)
            Circle()
                .trim(from: 0.0, to: CGFloat(progress))
                .stroke(color, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .rotationEffect(Angle(degrees: -90))
        }
        .frame(width: 14, height: 14)
    }
}

// MARK: - Pulsing Activity Dot

struct ActivityDot: View {
    @State private var pulsing = false
    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.18)).frame(width: 14, height: 14)
                .scaleEffect(pulsing ? 1.6 : 1.0).opacity(pulsing ? 0 : 0.6)
            Circle().fill(Color.white).frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) { pulsing = true }
        }
        .onDisappear { pulsing = false }
    }
}

struct NotchProgressView: View {
    @EnvironmentObject var controller: NotchProgressController
    @State private var isHovering = false
    @AppStorage("notchWidthExtension") private var widthExtension: Double = 90.0

    @AppStorage("dynamicIslandAlwaysExpanded") private var alwaysExpanded: Bool = false
    @AppStorage("dynamicIslandBGColor") private var bgColorHex: String = "#000000"

    // Geometry parameters (matches variables in NotchProgressWindow.swift)
    private var restW: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0 {
            let physicalWidth: CGFloat
            if let topLeft = screen.auxiliaryTopLeftArea?.width,
               let topRight = screen.auxiliaryTopRightArea?.width {
                physicalWidth = screen.frame.width - topLeft - topRight + 4
            } else {
                physicalWidth = 186 // Fallback physical notch width (MBP 14")
            }
            // Add custom width extension from menu settings
            return physicalWidth + CGFloat(widthExtension)
        }
        return 170 + CGFloat(widthExtension - 80) // Scale non-notch screen size proportionally
    }
    private let expandW: CGFloat  = 300   // width when hovered / expanded
    private let expandH: CGFloat  = 90    // expanded height below the notch bottom
    
    private var closedH: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
    }

    private var topR: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.safeAreaInsets.top > 0 ? 6 : 18
    }
    private var bottomR: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        return screen.safeAreaInsets.top > 0 ? 14 : 18
    }

    var body: some View {
        let visible = controller.state.isVisible
        let isExpanded = visible && (alwaysExpanded || isHovering)
        
        let totalW = isExpanded ? expandW : restW
        let totalH = isExpanded ? closedH + expandH : closedH

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background shape - Solid black to match the physical notch exactly
                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .fill(Color.black)
                    .opacity(visible ? 1.0 : 0.0)

                // Content router (Opacity-based routing for smooth matchedGeometryEffect rendering)
                if visible {
                    // Mode 1: Compact/closed resting view
                    compactView
                        .frame(width: restW, height: closedH)
                        .opacity(isExpanded ? 0.0 : 1.0)
                        .scaleEffect(isExpanded ? 0.92 : 1.0)
                        .allowsHitTesting(!isExpanded)
                    
                    // Mode 2: Hover-Expanded detailed card view
                    VStack(spacing: 0) {
                        Color.clear.frame(height: closedH)
                        contentView
                            .frame(width: expandW, height: expandH)
                    }
                    .opacity(isExpanded ? 1.0 : 0.0)
                    .scaleEffect(isExpanded ? 1.0 : 0.96)
                    .allowsHitTesting(isExpanded)
                }
            }
            .frame(width: totalW, height: totalH, alignment: .top)
            .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .contentShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .scaleEffect(isExpanded ? 1.02 : (isHovering && visible ? 1.012 : 1.0), anchor: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.76), value: isExpanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.76), value: visible)
            .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isHovering)
            .onHover   { isHovering = $0 }
            .onTapGesture { handleTap() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - Compact View (Resting Mode)

    @ViewBuilder
    private var compactView: some View {
        switch controller.state {
        case .active(let label, let progress, _):
            HStack(spacing: 8) {
                // Circular progress ring only
                CircularProgressView(progress: progress, color: .white)
                
                Spacer()
                
                // App Logo / Download Icon on the right
                Image("donverter-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5))
            }
            .padding(.horizontal, 12)
            .frame(height: closedH)

        case .done(_, _):
            HStack(spacing: 8) {
                // Checkmark green icon and label on the left
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(red: 0.28, green: 0.92, blue: 0.50))
                    Text("Done")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                
                Spacer()
                
                // App Logo / Download Icon on the right
                Image("donverter-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5))
            }
            .padding(.horizontal, 12)
            .frame(height: closedH)

        case .hidden:
            EmptyView()
        }
    }

    // MARK: - Expanded Content Router

    @ViewBuilder
    private var contentView: some View {
        switch controller.state {
        case .active(let label, let progress, _):
            activeCard(label: label, progress: progress)
        case .done(let label, let filePath):
            doneCard(label: label, filePath: filePath)
        case .hidden:
            EmptyView()
        }
    }

    // MARK: - Active Detailed Card

    private func activeCard(label: String, progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ActivityDot()
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            SmoothProgressBar(progress: progress, foreground: .white).frame(height: 3)

            Text("Processing — hover/click details")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Done Detailed Card

    private func doneCard(label: String, filePath: String?) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(red: 0.28, green: 0.92, blue: 0.50))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                if filePath != nil {
                    Text("Tap to reveal in Finder")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }

            Spacer()

            if filePath != nil {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Show")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(isHovering ? Color.white : Color.white.opacity(0.88)))
                .animation(.easeInOut(duration: 0.12), value: isHovering)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tap Action

    private func handleTap() {
        guard case .done(_, let filePath) = controller.state else { return }
        if let path = filePath {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run { controller.dismiss() }
        }
    }
}
