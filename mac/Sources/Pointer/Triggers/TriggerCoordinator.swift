import AppKit
import Carbon.HIToolbox

/// Owns the two ways the user opens the panel:
/// 1. **Primary** — Option+right-click anywhere on screen, via a
///    `CGEventTap` that consumes the event so the underlying app
///    doesn't also see the right-click.
/// 2. **Secondary** — `Cmd+Shift+Space` global hotkey via Carbon
///    `RegisterEventHotKey`.
///
/// Both paths funnel into a single `onTrigger(point:)` callback so the
/// rest of the app doesn't care how the panel was opened.
@MainActor
final class TriggerCoordinator {
    private let permissions: PermissionsManager
    private let onTrigger: (CGPoint) -> Void

    private var optionRightClick: OptionRightClickDetector?
    private var hotkey: GlobalHotkey?
    private var tapWatchdog: Timer?
    private var started = false

    init(permissions: PermissionsManager, onTrigger: @escaping (CGPoint) -> Void) {
        self.permissions = permissions
        self.onTrigger = onTrigger
    }

    func start() {
        guard !started else { return }
        started = true

        optionRightClick = OptionRightClickDetector(
            onTrigger: { [weak self] point in
                Task { @MainActor in self?.onTrigger(point) }
            }
        )
        optionRightClick?.start()

        hotkey = GlobalHotkey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey),
            handler: { [weak self] in
                guard let self else { return }
                let point = NSEvent.mouseLocation.flippedToCG()
                self.onTrigger(point)
            }
        )
        hotkey?.register()

        // Poll the tap and revive it if the system disabled it.
        tapWatchdog = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.optionRightClick?.reEnableIfNeeded() }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        tapWatchdog?.invalidate()
        tapWatchdog = nil
        optionRightClick?.stop()
        optionRightClick = nil
        hotkey?.unregister()
        hotkey = nil
    }
}

private extension NSPoint {
    /// `NSEvent.mouseLocation` is in AppKit screen coords (origin
    /// bottom-left). Most CG APIs we feed this into want top-left.
    func flippedToCG() -> CGPoint {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else {
            return CGPoint(x: x, y: y)
        }
        return CGPoint(x: x, y: primaryHeight - y)
    }
}
