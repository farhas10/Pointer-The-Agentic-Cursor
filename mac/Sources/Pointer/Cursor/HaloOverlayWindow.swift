import AppKit

/// Ambient cursor halo — a small borderless window that follows the pointer
/// and reflects agent state (idle, thinking, suggestion, acting).
@MainActor
final class HaloOverlayWindow {
    enum State: Equatable {
        case idle
        case thinking
        case suggestion
        case acting
    }

    private static let haloSize: CGFloat = 14
    private static let suppressedBundleIds: Set<String> = [
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.apple.loginwindow",
    ]

    private(set) var state: State = .idle
    private var window: NSWindow?
    private var haloView: HaloView?
    private var mouseMonitor: Any?
    private var targetOrigin = CGPoint.zero
    private var currentOrigin = CGPoint.zero
    private var lastMoveTime = CFAbsoluteTimeGetCurrent()
    private var suppressed = false

    func start() {
        guard window == nil else { return }
        let view = HaloView(frame: NSRect(x: 0, y: 0, width: Self.haloSize, height: Self.haloSize))
        haloView = view

        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.haloSize, height: Self.haloSize)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        window = panel

        let loc = NSEvent.mouseLocation
        currentOrigin = haloScreenOrigin(for: loc)
        targetOrigin = currentOrigin
        panel.setFrameOrigin(currentOrigin)
        panel.orderFrontRegardless()

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.mouseDidMove() }
        }

        startAnimationTimer()
        refreshSuppression()
    }

    func stop() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        stopAnimationTimer()
        window?.orderOut(nil)
        window = nil
        haloView = nil
    }

    func setState(_ state: State) {
        guard self.state != state else { return }
        self.state = state
        haloView?.state = state
        window?.ignoresMouseEvents = true
        if state == .idle || suppressed {
            window?.orderOut(nil)
        } else if let window, !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    private func mouseDidMove() {
        targetOrigin = haloScreenOrigin(for: NSEvent.mouseLocation)
        lastMoveTime = CFAbsoluteTimeGetCurrent()
    }

    private func haloScreenOrigin(for mouseLoc: CGPoint) -> CGPoint {
        CGPoint(
            x: mouseLoc.x - Self.haloSize / 2,
            y: mouseLoc.y - Self.haloSize / 2
        )
    }

    private func refreshSuppression() {
        let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        suppressed = bundleId.map { Self.suppressedBundleIds.contains($0) } ?? false
        if suppressed || state == .idle {
            window?.orderOut(nil)
        }
    }

    private func tick() {
        refreshSuppression()
        guard !suppressed, state != .idle, let window else { return }

        let dt = min(0.05, CFAbsoluteTimeGetCurrent() - lastMoveTime)
        let factor = state == .acting ? 0.35 : 0.18
        let blend = 1 - pow(1 - factor, max(dt, 1.0 / 60.0) * 60)
        currentOrigin.x += (targetOrigin.x - currentOrigin.x) * blend
        currentOrigin.y += (targetOrigin.y - currentOrigin.y) * blend
        window.setFrameOrigin(currentOrigin)
        haloView?.needsDisplay = true
    }

    private var animationTimer: Timer?

    private func startAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Drawing

private final class HaloView: NSView {
    var state: HaloOverlayWindow.State = .idle {
        didSet { needsDisplay = true }
    }

    private var pulsePhase: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        pulsePhase += 0.08
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius = bounds.width * 0.32

        let (fill, glow): (NSColor, NSColor) = {
            switch state {
            case .idle:
                return (.clear, .clear)
            case .thinking:
                return (NSColor.controlAccentColor.withAlphaComponent(0.55), NSColor.controlAccentColor.withAlphaComponent(0.2))
            case .suggestion:
                return (NSColor.systemGreen.withAlphaComponent(0.7), NSColor.systemGreen.withAlphaComponent(0.25))
            case .acting:
                return (NSColor.systemOrange.withAlphaComponent(0.85), NSColor.systemOrange.withAlphaComponent(0.3))
            }
        }()

        guard state != .idle else { return }

        let pulse = 1 + 0.12 * sin(pulsePhase)
        let glowRadius = baseRadius * 2.2 * pulse

        let glowPath = NSBezierPath(ovalIn: CGRect(
            x: center.x - glowRadius,
            y: center.y - glowRadius,
            width: glowRadius * 2,
            height: glowRadius * 2
        ))
        glow.setFill()
        glowPath.fill()

        let coreRadius = baseRadius * pulse
        let corePath = NSBezierPath(ovalIn: CGRect(
            x: center.x - coreRadius,
            y: center.y - coreRadius,
            width: coreRadius * 2,
            height: coreRadius * 2
        ))
        fill.setFill()
        corePath.fill()
    }
}
