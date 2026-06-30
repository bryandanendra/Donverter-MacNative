//
//  NotchProgressWindow.swift
//  Donverter
//
//  Dynamic Island / Notch floating progress indicator
//  Window management using fixed-size transparent click-through panel
//

import AppKit
import SwiftUI
import Combine

// MARK: - State

enum NotchProgressState: Equatable {
    case hidden
    case active(label: String, progress: Double, filePath: String?)
    case done(label: String, filePath: String?)

    var isVisible: Bool {
        if case .hidden = self { return false }
        return true
    }

    var stateName: String {
        switch self {
        case .hidden:  return "hidden"
        case .active:  return "active"
        case .done:    return "done"
        }
    }
}

// MARK: - Controller

@MainActor
final class NotchProgressController: ObservableObject {
    static let shared = NotchProgressController()
    @Published private(set) var state: NotchProgressState = .hidden
    @Published var isAnimatingOut: Bool = false
    private var autoDismissTask: Task<Void, Never>?
    private init() {}

    func show(label: String, progress: Double, filePath: String?) {
        autoDismissTask?.cancel()
        isAnimatingOut = false
        state = .active(label: label, progress: min(max(progress, 0), 1), filePath: filePath)
    }

    func markDone(label: String, filePath: String?) {
        autoDismissTask?.cancel()
        state = .done(label: label, filePath: filePath)
        
        // Trigger generic haptic feedback on trackpad
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        
        let behavior = UserDefaults.standard.string(forKey: "dynamicIslandDismissBehavior") ?? "timer"
        if behavior == "timer" {
            let seconds = UserDefaults.standard.double(forKey: "dynamicIslandDismissSeconds")
            let activeSeconds = seconds > 0 ? seconds : 5.0
            autoDismissTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(activeSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.dismiss() }
            }
        }
    }

    func dismiss() {
        autoDismissTask?.cancel()
        isAnimatingOut = true
        
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await MainActor.run {
                self.state = .hidden
                self.isAnimatingOut = false
            }
        }
    }
}

// MARK: - NSPanel (based on Atoll's DynamicIslandWindow configuration)

final class NotchProgressPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel            = true
        isOpaque                   = false
        titleVisibility            = .hidden
        titlebarAppearsTransparent = true
        backgroundColor            = .clear
        isMovable                  = false
        hasShadow                  = false
        isReleasedWhenClosed       = false
        level                      = .mainMenu + 3
        collectionBehavior         = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        animationBehavior          = .none
    }
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }
}

// First-click-without-focus hosting view
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Screen helpers

private func notchScreen() -> NSScreen {
    NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
}

private func hasPhysicalNotch(_ screen: NSScreen) -> Bool {
    screen.safeAreaInsets.top > 0
}

// MARK: - Sizing constants

private let openNotchW: CGFloat  = 320
private let openNotchH: CGFloat  = 90
private let bottomPad: CGFloat   = 18

private func closedNotchHeight(for screen: NSScreen) -> CGFloat {
    hasPhysicalNotch(screen) ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
}

private func panelFrame(for screen: NSScreen) -> NSRect {
    let sf = screen.frame
    let cx = sf.midX
    let notchH = closedNotchHeight(for: screen)
    
    let w = openNotchW
    let h = notchH + openNotchH + bottomPad
    
    let y = sf.maxY - h
    let x = cx - w / 2
    return NSRect(x: x, y: y, width: w, height: h)
}

// MARK: - Window Manager

@MainActor
final class NotchProgressWindowManager {
    static let shared = NotchProgressWindowManager()
    private var panel: NotchProgressPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() { setup() }

    private func setup() {
        let screen = notchScreen()
        let frame  = panelFrame(for: screen)

        let p = NotchProgressPanel(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing:     .buffered,
            defer:       false
        )

        let rootView = NotchProgressView()
            .environmentObject(NotchProgressController.shared)

        let host = NotchHostingView(rootView: rootView)
        host.frame = NSRect(origin: .zero, size: frame.size)
        p.contentView = host
        p.ignoresMouseEvents = true // Start click-through
        p.orderFrontRegardless()
        panel = p

        // Update click-through when state or animation state changes
        Publishers.CombineLatest(
            NotchProgressController.shared.$state,
            NotchProgressController.shared.$isAnimatingOut
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.updateVisibilityAndClickThrough()
        }
        .store(in: &cancellables)

        // Update when preferences change
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateVisibilityAndClickThrough()
            }
            .store(in: &cancellables)

        // Reposition on screen parameter change
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.repositionIfNeeded()
            }
            .store(in: &cancellables)
            
        // Initial visibility check
        updateVisibilityAndClickThrough()
    }

    private func updateVisibilityAndClickThrough() {
        guard let p = panel else { return }
        let state = NotchProgressController.shared.state
        let enabled = UserDefaults.standard.object(forKey: "dynamicIslandEnabled") as? Bool ?? true
        let isAnimatingOut = NotchProgressController.shared.isAnimatingOut
        let shouldBeVisible = (state.isVisible || isAnimatingOut) && enabled
        
        p.ignoresMouseEvents = !shouldBeVisible
        p.alphaValue = shouldBeVisible ? 1.0 : 0.0
    }

    private func repositionIfNeeded() {
        guard let p = panel else { return }
        let screen = notchScreen()
        let frame  = panelFrame(for: screen)
        if p.frame != frame {
            p.setFrame(frame, display: true)
        }
    }
}
