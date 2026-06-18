import ApplicationServices
import AppKit
import Foundation

/// Dumps a compact accessibility tree for agent grounding.
enum AXTreeReader {
    struct Node: Encodable {
        var role: String?
        var title: String?
        var value: String?
        var frame: [String: Double]?
        var children: [Node]?
    }

    static func readFocusedTree(maxDepth: Int = 6) -> String? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
              let window = windowRef else { return nil }

        let root = walk(element: window as! AXUIElement, depth: 0, maxDepth: maxDepth)
        guard let data = try? JSONEncoder().encode(root),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return String(json.prefix(12_000))
    }

    private static func walk(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int
    ) -> Node {
        let role = stringAttribute(element, kAXRoleAttribute)
        let isSecure = role == "AXSecureTextField" || role == "AXPasswordField"
        var node = Node(
            role: role,
            title: stringAttribute(element, kAXTitleAttribute),
            value: isSecure
                ? "[redacted]"
                : stringAttribute(element, kAXValueAttribute).map { String($0.prefix(200)) },
            frame: frameDict(element),
            children: nil
        )
        if depth >= maxDepth { return node }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
              let children = childrenRef as? [AXUIElement],
              !children.isEmpty else {
            return node
        }
        node.children = children.prefix(40).map {
            walk(element: $0, depth: depth + 1, maxDepth: maxDepth)
        }
        return node
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func frameDict(_ element: AXUIElement) -> [String: Double]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &ref) == .success,
              let position = ref else { return nil }
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let size = sizeRef else { return nil }

        var point = CGPoint.zero
        var cgSize = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &cgSize)
        return [
            "x": Double(point.x),
            "y": Double(point.y),
            "w": Double(cgSize.width),
            "h": Double(cgSize.height),
        ]
    }
}
