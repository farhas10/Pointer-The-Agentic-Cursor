import AppKit
import CoreGraphics
import Foundation

/// Gemini Computer Use predefined actions (0–999 coordinate grid).
enum ComputerUseActions {
    static let toolNames: Set<String> = [
        "click_at",
        "type_text_at",
        "scroll_at",
        "wait_5_seconds",
        "key_combination",
        "hover_at",
        "drag_and_drop",
        "scroll_document",
        "go_forward",
        "go_back",
        "open_web_browser",
        "navigate",
        "search",
    ]

    static func isComputerUseTool(_ name: String) -> Bool {
        toolNames.contains(name)
    }

    /// Maps Computer Use grid coords to global top-left CG coordinates.
    static func denormalizedPoint(
        x: Int,
        y: Int,
        screenWidth: CGFloat,
        screenHeight: CGFloat
    ) -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: screenWidth, height: screenHeight)
        let localX = CGFloat(x) / 1000.0 * screenWidth
        let localY = CGFloat(y) / 1000.0 * screenHeight
        return CGPoint(x: frame.minX + localX, y: frame.minY + localY)
    }
}
