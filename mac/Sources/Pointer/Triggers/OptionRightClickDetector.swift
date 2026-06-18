import AppKit

/// Installs a `CGEventTap` that listens for `.rightMouseDown` events
/// with the Option modifier set, consumes them, and forwards the
/// click point to the panel coordinator.
///
/// Requires Input Monitoring permission. The first time `start()` is
/// called without it, macOS prompts the user.
final class OptionRightClickDetector {
    // `@Sendable` because the event-tap callback hops to the main queue
    // via `DispatchQueue.main.async`, which requires a sendable closure.
    private let onTrigger: @Sendable (CGPoint) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(onTrigger: @escaping @Sendable (CGPoint) -> Void) {
        self.onTrigger = onTrigger
    }

    deinit {
        // CGEventTap teardown is safe from any thread.
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
    }

    func start() {
        guard tap == nil else { return }

        let mask: CGEventMask = (1 << CGEventType.rightMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: optionRightClickCallback,
            userInfo: userInfo
        ) else {
            // Most likely Input Monitoring isn't granted yet. The
            // permissions manager surfaces this in onboarding.
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.tap = port
        self.runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
    }

    /// macOS disables an event tap if its callback ever runs too slowly
    /// (common under the Xcode debugger). The callback re-enables it on
    /// the disable event, but as a belt-and-suspenders the coordinator
    /// also polls this so a dead tap always comes back.
    func reEnableIfNeeded() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let hasOption = flags.contains(.maskAlternate)
        guard hasOption else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        DispatchQueue.main.async { [onTrigger] in
            onTrigger(location)
        }

        // Consume the event so the underlying app doesn't see this
        // right-click. The user will get the regular context menu by
        // right-clicking without Option.
        return nil
    }
}

private func optionRightClickCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // The OS may disable the tap if a callback runs too long; we
    // re-enable on the same dispatch.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let detector = Unmanaged<OptionRightClickDetector>
                .fromOpaque(userInfo).takeUnretainedValue()
            if let tap = detector.takeRawTap() {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .rightMouseDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let detector = Unmanaged<OptionRightClickDetector>
        .fromOpaque(userInfo).takeUnretainedValue()
    return detector.handle(event: event)
}

private extension OptionRightClickDetector {
    /// Exposes the underlying tap so the C callback can re-enable it
    /// without breaking encapsulation.
    func takeRawTap() -> CFMachPort? { tap }
}
