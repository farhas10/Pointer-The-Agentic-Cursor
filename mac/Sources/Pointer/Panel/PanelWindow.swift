import AppKit
import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 420
    /// Max height for the scrollable results + answer region.
    static let maxScrollHeight: CGFloat = 320
    /// Max overall panel height (window clamp).
    static let maxPanelHeight: CGFloat = 520
}

/// The non-activating floating panel hosting `PanelView`.
///
/// A non-activating panel keeps focus in the underlying app, which is
/// essential for paste-into-focused-field actions in Phase 3+.
@MainActor
final class PanelWindow: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelLayout.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false   // shadow is drawn by the SwiftUI layer
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
