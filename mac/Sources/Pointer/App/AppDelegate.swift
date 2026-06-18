import AppKit
import Combine

/// Owns the application's long-lived singletons:
/// - The menu bar item and its menu.
/// - The `PermissionsManager` (re-checks on activation).
/// - The `TriggerCoordinator` (Option+right-click + hotkey).
/// - The `PanelCoordinator` (opens / closes the floating panel).
///
/// Everything else is composed of small modules behind these
/// coordinators; see each module's README for its surface.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var permissions: PermissionsManager!
    private var triggers: TriggerCoordinator!
    private var panelCoordinator: PanelCoordinator!
    private var drawerController: DrawerWindowController!
    private var haloOverlay = HaloOverlayWindow()
    private let ambientBuffer = AmbientBuffer.shared
    private var onboarding: OnboardingWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        permissions = PermissionsManager()
        permissions.refresh()
        permissions.requestMicrophoneIfNeeded()
        // Prompt for location up front and warm up a GPS fix so the first
        // "nearby" query has coordinates to work with.
        LocationProvider.shared.start()
        // Poll continuously until everything is granted, so grants made in
        // System Settings are picked up within ~1s whether or not the
        // onboarding window is open. Stops itself once fully granted.
        if !permissions.isFullyGranted {
            permissions.startMonitoring()
        }

        // Use 127.0.0.1 — on macOS `localhost` can resolve to ::1 while
        // some dev servers only accept IPv4, which makes requests fail
        // silently from URLSession.
        let backendClient = BackendClient(
            baseURL: URL(string: "http://127.0.0.1:8787")!
        )
        Task {
            let ok = await backendClient.checkHealth()
            if !ok {
                NSLog("Pointer: backend not reachable at 127.0.0.1:8787 — run `cd backend && npm run dev`")
            }
        }

        drawerController = DrawerWindowController(
            store: DrawerStore.shared,
            backendClient: backendClient
        )
        panelCoordinator = PanelCoordinator(
            backendClient: backendClient,
            permissions: permissions,
            haloOverlay: haloOverlay,
            onAddToDrawer: { [weak self] context in
                self?.drawerController.addFromPanel(context)
            }
        )
        haloOverlay.start()

        triggers = TriggerCoordinator(
            permissions: permissions,
            onTrigger: { [weak self] clickPoint in
                self?.handleTrigger(at: clickPoint)
            }
        )

        menuBarController = MenuBarController(
            permissions: permissions,
            onShowOnboarding: { [weak self] in self?.showOnboarding() },
            onOpenDrawer: { [weak self] in self?.drawerController.show() },
            onQuit: { NSApp.terminate(nil) }
        )

        // Re-check permissions when the user toggles them in System Settings.
        NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.permissions.refresh() }
            .store(in: &cancellables)

        // If permissions aren't ready, walk the user through onboarding.
        if !permissions.isFullyGranted {
            showOnboarding()
        } else {
            triggers.start()
            ambientBuffer.start()
        }

        // Permission state changes drive the trigger coordinator on/off.
        permissions.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                if state.isFullyGranted {
                    self.triggers.start()
                    self.ambientBuffer.start()
                } else {
                    self.triggers.stop()
                    self.ambientBuffer.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func handleTrigger(at point: CGPoint) {
        let extractor = AccessibilityExtractor()
        let snapshot = extractor.snapshot(atScreenPoint: point)
        let appContext = ForegroundAppInspector().currentContext()

        Task { @MainActor in
            let image = await ScreenCapturer().capture(
                regionAround: point,
                size: 512
            )
            let context = TriggerContext(
                clickPoint: point,
                appContext: appContext,
                axSnapshot: snapshot,
                imagePngBase64: image
            )
            self.panelCoordinator.show(with: context)
        }
    }

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions)
        }
        onboarding?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
