import AppKit
import SwiftUI

// MARK: - Window Controller

final class CommandBarWindowController: NSWindowController {

    private var isVisible = false
    private var idleTimer: Timer?
    private var clickMonitor: Any?

    private static let collapsedHeight: CGFloat = 76
    private static let maxHeight:       CGFloat = 560
    private static let barWidth:        CGFloat = 680
    private static let idleTimeout:     TimeInterval = 8  // seconds before auto-dismiss

    convenience init() {
        let panel = CommandBarPanel.make()
        self.init(window: panel)

        NotificationCenter.default.addObserver(
            self, selector: #selector(resetIdleTimerObjc),
            name: .commandBarUserActivity, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(pauseIdleTimer),
            name: .commandBarContentVisible, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(resetIdleTimerObjc),
            name: .commandBarContentHidden, object: nil
        )

        let rootView = CommandBarView(
            onDismiss:      { [weak self] in self?.hide() },
            onHeightChange: { [weak self] h in self?.updateWindowHeight(h) }
        )
        panel.contentView = NSHostingView(rootView: rootView)
    }

    // MARK: Show / Hide / Toggle

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let window = window, !isVisible else { return }
        ContextCapture.shared.snapshot()
        repositionOnActiveScreen()
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        isVisible = true
        startIdleTimer()
        startClickMonitor()
    }

    func hide() {
        guard let window = window, isVisible else { return }
        stopIdleTimer()
        stopClickMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            window.animator().alphaValue = 0
        }) { [weak self] in
            window.orderOut(nil)
            self?.isVisible = false
        }
    }

    // MARK: Idle timer

    private func startIdleTimer() {
        stopIdleTimer()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func resetIdleTimer() {
        guard isVisible else { return }
        startIdleTimer()
    }

    @objc private func resetIdleTimerObjc() { resetIdleTimer() }
    @objc private func pauseIdleTimer() { stopIdleTimer() }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: Click-outside monitor

    private func startClickMonitor() {
        stopClickMonitor()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
    }

    private func stopClickMonitor() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
    }

    // MARK: Private

    private func updateWindowHeight(_ contentHeight: CGFloat) {
        guard let window = window else { return }
        let newH = max(Self.collapsedHeight, min(contentHeight, Self.maxHeight))
        guard abs(window.frame.size.height - newH) > 0.5 else { return }
        var frame = window.frame
        let delta = newH - frame.size.height
        frame.size.height = newH
        frame.origin.y   -= delta  // grow upward
        window.setFrame(frame, display: true, animate: false)
    }

    private func repositionOnActiveScreen() {
        guard let window = window else { return }
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let sf = screen.frame
        let w  = Self.barWidth
        let h  = Self.collapsedHeight
        let x  = sf.midX - w / 2
        let y  = sf.midY + 40  // slightly above centre
        window.setFrame(NSRect(x: x, y: y, width: w, height: h), display: false)
    }
}

// MARK: - Custom Panel

final class CommandBarPanel: NSPanel {

    static func make() -> CommandBarPanel {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let w: CGFloat = 680
        let h: CGFloat = 76
        let rect = NSRect(x: sf.midX - w / 2, y: sf.midY + 40, width: w, height: h)

        let panel = CommandBarPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    static let commandBarUserActivity  = Notification.Name("commandBarUserActivity")
    static let commandBarContentVisible = Notification.Name("commandBarContentVisible")
    static let commandBarContentHidden  = Notification.Name("commandBarContentHidden")
}
