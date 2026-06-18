import AppKit
import CoreGraphics
import Foundation

/// On-device ring buffer of the last ~10 seconds of cursor / app / element
/// activity. Summarized client-side into a short string for `ambient_summary`.
@MainActor
final class AmbientBuffer {
    static let shared = AmbientBuffer()

    struct Sample: Equatable {
        let timestamp: Date
        let appName: String?
        let bundleId: String?
        let windowTitle: String?
        let elementRole: String?
        let elementTitle: String?
    }

    private let windowSeconds: TimeInterval = 10
    private let timerInterval: TimeInterval = 0.5
    private let moveThrottle: TimeInterval = 0.35
    private let maxSamples = 40

    private var samples: [Sample] = []
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var lastSampleTime = Date.distantPast
    private var lastMouseLocation = CGPoint.zero

    private let extractor = AccessibilityExtractor()
    private let inspector = ForegroundAppInspector()

    private init() {}

    #if DEBUG
    func replaceSamplesForTesting(_ samples: [Sample]) {
        self.samples = samples
    }
    #endif

    func start() {
        guard timer == nil else { return }
        recordSample()
        timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordSample() }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            Task { @MainActor in self?.recordOnMouseMove() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        samples.removeAll()
    }

    /// Compact digest of recent activity for the backend prompt.
    func summarize() -> String? {
        prune()
        guard samples.count >= 2 else { return nil }

        var lines: [String] = []
        var lastKey: String?
        let now = Date.now

        for sample in samples.suffix(12) {
            let app = sample.appName ?? sample.bundleId ?? "unknown app"
            let window = sample.windowTitle.map { " · \($0)" } ?? ""
            let element = elementDigest(sample)
            let key = "\(app)\(window)\(element)"
            if key == lastKey { continue }
            lastKey = key

            let seconds = Int(now.timeIntervalSince(sample.timestamp))
            let ago = seconds <= 1 ? "just now" : "\(seconds)s ago"
            lines.append("\(app)\(window)\(element) (\(ago))")
        }

        let summary = lines.joined(separator: "; ")
        return summary.isEmpty ? nil : String(summary.prefix(1_800))
    }

    private func recordOnMouseMove() {
        let loc = NSEvent.mouseLocation
        let delta = hypot(loc.x - lastMouseLocation.x, loc.y - lastMouseLocation.y)
        guard delta >= 18 else { return }
        lastMouseLocation = loc
        guard Date.now.timeIntervalSince(lastSampleTime) >= moveThrottle else { return }
        recordSample(at: loc)
    }

    private func recordSample(at mouseLoc: CGPoint? = nil) {
        lastSampleTime = .now
        let cgPoint = Self.cgPoint(fromAppKit: mouseLoc ?? NSEvent.mouseLocation)
        let context = inspector.currentContext()
        let ax = extractor.snapshot(atScreenPoint: cgPoint)

        let sample = Sample(
            timestamp: .now,
            appName: context.appName,
            bundleId: context.bundleId,
            windowTitle: context.windowTitle,
            elementRole: ax?.role,
            elementTitle: ax?.title ?? ax?.value.map { String($0.prefix(40)) }
        )
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        prune()
    }

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-windowSeconds)
        samples.removeAll { $0.timestamp < cutoff }
    }

    private func elementDigest(_ sample: Sample) -> String {
        guard let role = sample.elementRole else { return "" }
        if let title = sample.elementTitle, !title.isEmpty {
            return " → \(role) \"\(title)\""
        }
        return " → \(role)"
    }

    private static func cgPoint(fromAppKit mouseLoc: CGPoint) -> CGPoint {
        if let event = CGEvent(source: nil) {
            return event.location
        }
        guard let screen = NSScreen.main else { return mouseLoc }
        return CGPoint(x: mouseLoc.x, y: screen.frame.height - mouseLoc.y)
    }
}
