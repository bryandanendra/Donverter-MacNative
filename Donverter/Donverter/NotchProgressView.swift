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
    @State private var isButtonHovered = false
    @AppStorage("notchWidthExtension") private var widthExtension: Double = 90.0
    @AppStorage("dynamicIslandAlwaysExpanded") private var alwaysExpanded: Bool = false
    @AppStorage("dynamicIslandBGColor") private var bgColorHex: String = "#000000"

    // --- Animation state ---
    /// Glow overlay opacity (white on appear, green on done)
    @State private var glowOpacity: Double = 0
    @State private var glowColor: Color = .white
    /// Squeeze Y scale for expand animation
    @State private var squeezeScale: CGFloat = 1.0
    /// Manually controlled expand state
    @State private var isExpanded: Bool = false
    /// State to control the transition when collapsing back into the physical notch first
    @State private var isCollapsingToNotch: Bool = false
    /// Tracks previous visibility to detect appear/dismiss transitions
    @State private var wasVisible: Bool = false
    /// Tracks previous state to detect active→done transition
    @State private var prevStateName: String = "hidden"

    // Geometry parameters (matches variables in NotchProgressWindow.swift)
    private var physicalNotchW: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0 {
            if let topLeft = screen.auxiliaryTopLeftArea?.width,
               let topRight = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - topLeft - topRight + 4
            } else {
                return 186 // Fallback physical notch width (MBP 14")
            }
        }
        return 0 // Non-notch screens collapse to 0 width to disappear completely into top bezel
    }

    private var restW: CGFloat {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        if screen.safeAreaInsets.top > 0 {
            return physicalNotchW + CGFloat(widthExtension)
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
        let stateName = controller.state.stateName

        // Determine current dimensions based on the collapse-to-notch phase
        let totalW = isCollapsingToNotch ? physicalNotchW : (isExpanded ? expandW : restW)
        let totalH = isCollapsingToNotch ? closedH : (isExpanded ? closedH + expandH : closedH)
        
        // Hide content when collapsed or collapsing to the notch
        let contentOpacity = isCollapsingToNotch ? 0.0 : 1.0

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                // Background shape - Solid black to match the physical notch exactly
                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .fill(Color.black)
                    .opacity(visible ? 1.0 : 0.0)

                // ✨ Glow flash overlay (appear = white, done = green)
                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .fill(glowColor.opacity(0.35))
                    .blendMode(.screen)
                    .opacity(glowOpacity)
                    .allowsHitTesting(false)

                // Content router
                if visible {
                    // Mode 1: Compact/closed resting view
                    compactView
                        .frame(width: restW, height: closedH)
                        .opacity(isExpanded ? 0.0 : contentOpacity)
                        .scaleEffect(isExpanded ? 0.88 : 1.0)
                        .allowsHitTesting(!isExpanded)

                    // Mode 2: Hover-Expanded detailed card view
                    VStack(spacing: 0) {
                        Color.clear.frame(height: closedH)
                        contentView
                            .frame(width: expandW, height: expandH)
                    }
                    .opacity(isExpanded ? contentOpacity : 0.0)
                    .scaleEffect(isExpanded ? 1.0 : 0.95)
                    .allowsHitTesting(isExpanded)
                }
            }
            .frame(width: totalW, height: totalH, alignment: .top)
            .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .contentShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .scaleEffect(x: 1.0, y: squeezeScale, anchor: .top)
            // Expand scale
            .scaleEffect(isExpanded && !isCollapsingToNotch ? 1.02 : 1.0, anchor: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: totalW)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: totalH)
            .animation(.easeInOut(duration: 0.18), value: isCollapsingToNotch)
            .onHover { hovering in
                guard visible else { return }
                if hovering {
                    isCollapsingToNotch = false
                    isExpanded = true
                    
                    // Squeeze in Y before blooming
                    squeezeScale = 0.88
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                        squeezeScale = 1.05
                    }
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.72).delay(0.14)) {
                        squeezeScale = 1.0
                    }
                } else {
                    // ── COLLAPSE TO NOTCH FIRST ──
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isCollapsingToNotch = true
                    }
                    
                    // Once fully hidden inside physical notch boundaries (e.g. 350ms)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guard isCollapsingToNotch else { return }
                        
                        // Swap modes internally (while hidden)
                        isExpanded = false
                        
                        // Bloom back out as compact pill
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                            isCollapsingToNotch = false
                        }
                    }
                }
            }
            .onTapGesture { handleTap() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        // ── Watch visibility: trigger morph in/out ──────────────────────
        .onChange(of: visible) { _, nowVisible in
            if nowVisible && !wasVisible {
                isCollapsingToNotch = true
                glowColor = .white
                // Appear: bloom from notch out to compact size
                withAnimation(.spring(response: 0.44, dampingFraction: 0.65)) {
                    isCollapsingToNotch = false
                }
                // White glow flash
                glowOpacity = 0.9
                withAnimation(.easeOut(duration: 0.55).delay(0.05)) {
                    glowOpacity = 0
                }
            } else if !nowVisible && wasVisible {
                // Dismiss: collapse back to notch and fade out
                isExpanded = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.80)) {
                    isCollapsingToNotch = true
                }
            }
            wasVisible = nowVisible
        }
        // ── Watch state: green glow on done ────────────────────────────
        .onChange(of: stateName) { _, newState in
            if newState == "done" && prevStateName == "active" {
                glowColor = Color(red: 0.28, green: 0.92, blue: 0.50)
                glowOpacity = 0.90
                withAnimation(.easeOut(duration: 0.65).delay(0.05)) {
                    glowOpacity = 0
                }
            }
            prevStateName = newState
        }
        .onAppear {
            wasVisible = visible
            isExpanded = false
            isCollapsingToNotch = false
            prevStateName = controller.state.stateName
        }
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
            HStack(spacing: 6) {
                // Checkmark green icon and label on the left
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.28, green: 0.92, blue: 0.50))
                    .frame(width: 16, height: 16)
                
                Text("Done")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // App Logo / Download Icon on the right
                Image("donverter-icon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4.5))
            }
            .padding(.horizontal, 10)
            .frame(width: restW, height: closedH, alignment: .center)

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
                HStack(spacing: 6) {
                    Text("Show")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.0, green: 0.48, blue: 1.0)))
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 5)
                .background(Capsule().fill(isButtonHovered ? Color.white : Color.white.opacity(0.92)))
                .scaleEffect(isButtonHovered ? 1.04 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isButtonHovered)
                .onHover { isButtonHovered = $0 }
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
