import AppKit
import Combine
import SwiftUI

/// Owns the lifecycle of the floating panel:
/// - Creates a fresh `PanelWindow` per trigger so SwiftUI state resets
///   cleanly between asks (panels are cheap on macOS).
/// - Anchors the window near the click point, clamping to the screen.
/// - Auto-dismisses when the user clicks outside the panel.
@MainActor
final class PanelCoordinator {
    private let backendClient: BackendClient
    private let permissions: PermissionsManager
    private let haloOverlay: HaloOverlayWindow?
    private let onAddToDrawer: ((TriggerContext) -> Void)?
    private var window: PanelWindow?
    private var hostingView: NSHostingView<PanelView>?
    private var viewModel: PanelViewModel?
    private var clickOutsideGlobalMonitor: Any?
    private var clickOutsideLocalMonitor: Any?
    private var isPinned = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        backendClient: BackendClient,
        permissions: PermissionsManager,
        haloOverlay: HaloOverlayWindow? = nil,
        onAddToDrawer: ((TriggerContext) -> Void)? = nil
    ) {
        self.backendClient = backendClient
        self.permissions = permissions
        self.haloOverlay = haloOverlay
        self.onAddToDrawer = onAddToDrawer
    }

    func show(with context: TriggerContext) {
        dismiss()

        let viewModel = PanelViewModel(
            context: context,
            backendClient: backendClient,
            permissions: permissions
        )
        viewModel.onRequestStart = { [weak self] in
            self?.keepPanelActive()
        }
        viewModel.onAddToDrawer = { [weak self] context in
            self?.onAddToDrawer?(context)
            self?.dismiss()
        }
        viewModel.onHaloStateChange = { [weak self] state in
            self?.haloOverlay?.setState(state)
        }
        viewModel.onCompanionPin = { [weak self] in
            self?.pinCompanion()
        }
        self.viewModel = viewModel

        let hosting = NSHostingView(
            rootView: PanelView(
                viewModel: viewModel,
                onDismiss: { [weak self] in self?.dismiss() }
            )
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hostingView = hosting

        let panel = PanelWindow(contentView: hosting)
        let frame = idealFrame(near: context.clickPoint, containing: panel)
        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        window = panel

        // Grow the panel as content streams in; clamp so large result lists scroll inside.
        //
        // `@Published` fires inside `willSet` (during SwiftUI's update cycle), so we must
        // NOT resize synchronously here: forcing an `NSHostingView` layout
        // (`fittingSize` / `setFrame`) from within a publish re-enters SwiftUI mid-update
        // and triggers an AttributeGraph precondition crash. Throttling onto the main
        // queue both defers the work past the current update and coalesces the rapid
        // burst of token updates into a few resizes.
        viewModel.$phase
            .combineLatest(
                viewModel.$answer,
                viewModel.$statusMessage,
                viewModel.$entities
            )
            .throttle(for: .milliseconds(33), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _, _, _, _ in
                self?.refreshPanelSize()
            }
            .store(in: &cancellables)

        installClickOutsideDismiss(for: panel)
    }

    func dismiss() {
        // Kill any in-flight ask/continue (and tool loop) FIRST so the network
        // sequence can't keep streaming or fire actions against a torn-down
        // panel — otherwise a stale response races a freshly-opened panel.
        viewModel?.cancel()
        viewModel?.speechInput.stopListening()

        isPinned = false
        removeClickOutsideDismissMonitors()
        cancellables.removeAll()
        haloOverlay?.setState(.idle)
        window?.orderOut(nil)
        window = nil
        hostingView = nil
        viewModel = nil
    }

    /// Companion mode: panel stays open while user browses or works in other apps.
    private func pinCompanion() {
        isPinned = true
        removeClickOutsideDismissMonitors()
    }

    /// Re-focus the panel when the user sends a prompt.
    private func keepPanelActive() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Dismiss when the user clicks anywhere outside the panel.
    private func installClickOutsideDismiss(for panel: PanelWindow) {
        guard !isPinned else { return }
        removeClickOutsideDismissMonitors()

        // Clicks in other apps never reach Pointer; dismiss immediately.
        clickOutsideGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPinned else { return }
                self.dismiss()
            }
        }

        // Clicks inside Pointer but outside the panel (e.g. drawer).
        clickOutsideLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let window = self.window else { return event }
            if !self.isPinned, !window.frame.contains(NSEvent.mouseLocation) {
                self.dismiss()
            }
            return event
        }
    }

    private func removeClickOutsideDismissMonitors() {
        if let clickOutsideGlobalMonitor {
            NSEvent.removeMonitor(clickOutsideGlobalMonitor)
            self.clickOutsideGlobalMonitor = nil
        }
        if let clickOutsideLocalMonitor {
            NSEvent.removeMonitor(clickOutsideLocalMonitor)
            self.clickOutsideLocalMonitor = nil
        }
    }

    /// Resize the panel to fit streamed content. Grows upward so the
    /// anchor near the cursor stays stable.
    private func refreshPanelSize() {
        guard let window, let hostingView else { return }
        let width = max(window.frame.width, PanelLayout.width)
        var measureFrame = hostingView.frame
        measureFrame.size.width = width
        hostingView.frame = measureFrame
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let screenMax = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let maxHeight = min(PanelLayout.maxPanelHeight, screenMax * 0.65)
        let height = min(max(fitting.height + 8, 180), maxHeight)
        var frame = window.frame
        let delta = height - frame.height
        frame.size = NSSize(width: width, height: height)
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: false)
    }

    /// Places the panel near the click point, biased below + right of
    /// the cursor, then clamped to the containing screen so it never
    /// appears off-edge.
    private func idealFrame(near pointCG: CGPoint, containing window: NSWindow) -> NSRect {
        let panelSize = NSSize(width: PanelLayout.width, height: 200)
        // CGEvent gave us top-left coordinates; AppKit windows are bottom-left.
        let screen = NSScreen.screens.first { screen in
            let cg = screen.frame.flippedToCGScreen()
            return cg.contains(pointCG)
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: panelSize)
        }
        let cgScreenFrame = screen.frame.flippedToCGScreen()
        let cgInScreen = CGPoint(
            x: pointCG.x - cgScreenFrame.minX,
            y: pointCG.y - cgScreenFrame.minY
        )
        // Convert to AppKit screen coordinates.
        let appKitOrigin = CGPoint(
            x: screen.frame.minX + cgInScreen.x + 16,
            y: screen.frame.maxY - cgInScreen.y - panelSize.height - 16
        )
        var rect = NSRect(origin: appKitOrigin, size: panelSize)
        let visible = screen.visibleFrame
        if rect.maxX > visible.maxX { rect.origin.x = visible.maxX - rect.width - 12 }
        if rect.minX < visible.minX { rect.origin.x = visible.minX + 12 }
        if rect.minY < visible.minY { rect.origin.y = visible.minY + 12 }
        if rect.maxY > visible.maxY { rect.origin.y = visible.maxY - rect.height - 12 }
        _ = window
        return rect
    }
}

private extension NSRect {
    /// Returns this AppKit screen frame in CG (top-left) coordinates.
    /// AppKit's main-screen origin is bottom-left of the primary screen.
    func flippedToCGScreen() -> CGRect {
        guard let primary = NSScreen.screens.first else { return self }
        let primaryHeight = primary.frame.height
        return CGRect(
            x: minX,
            y: primaryHeight - maxY,
            width: width,
            height: height
        )
    }
}
