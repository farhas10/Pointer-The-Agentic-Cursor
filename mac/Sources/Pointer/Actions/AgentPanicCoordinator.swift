import AppKit

/// Global panic key (Esc) that cancels the entire in-flight agent action queue.
@MainActor
final class AgentPanicCoordinator {
    private var monitor: Any?
    private var onPanic: (() -> Void)?

    func arm(onPanic: @escaping () -> Void) {
        disarm()
        self.onPanic = onPanic
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.onPanic?() }
        }
    }

    func disarm() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onPanic = nil
    }
}
