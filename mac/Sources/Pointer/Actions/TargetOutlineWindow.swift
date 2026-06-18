import AppKit

/// Highlights an on-screen target before automation runs (threat model: ≥ 250 ms).
@MainActor
enum TargetOutlineWindow {
    private static let outlineSize: CGFloat = 48
    private static var window: NSWindow?

    static func show(at cgPoint: CGPoint, duration: TimeInterval = 0.35) async {
        dismiss()
        let frame = outlineFrame(at: cgPoint)
        let view = OutlineView(frame: NSRect(origin: .zero, size: frame.size))
        let panel = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        window = panel
        panel.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        dismiss()
    }

    static func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    private static func outlineFrame(at cgPoint: CGPoint) -> NSRect {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.flippedToCGScreen().contains(cgPoint)
        }) ?? NSScreen.main else {
            return NSRect(x: cgPoint.x, y: cgPoint.y, width: outlineSize, height: outlineSize)
        }
        let cgFrame = screen.frame.flippedToCGScreen()
        let localX = cgPoint.x - cgFrame.minX
        let localY = cgPoint.y - cgFrame.minY
        let appKitY = screen.frame.maxY - localY
        return NSRect(
            x: screen.frame.minX + localX - outlineSize / 2,
            y: appKitY - outlineSize / 2,
            width: outlineSize,
            height: outlineSize
        )
    }
}

private final class OutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 4
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.lineWidth = 2.5
        NSColor.systemOrange.setStroke()
        path.stroke()
        NSColor.systemOrange.withAlphaComponent(0.15).setFill()
        path.fill()
    }
}

private extension NSRect {
    func flippedToCGScreen() -> CGRect {
        guard let primary = NSScreen.screens.first else { return self }
        let primaryHeight = primary.frame.height
        return CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
