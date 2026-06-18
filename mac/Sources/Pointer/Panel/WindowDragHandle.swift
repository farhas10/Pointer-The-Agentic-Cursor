import AppKit
import SwiftUI

/// Transparent overlay that lets the user drag a borderless panel by its
/// header. SwiftUI content in `NSHostingView` blocks
/// `isMovableByWindowBackground`, so we call `performDrag(with:)` here.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}
}

final class DragHandleView: NSView {
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
