import ApplicationServices
import AppKit
import Foundation

/// Path-based accessibility element lookup and actions for the desktop agent.
enum AXElementResolver {
    struct Match: Encodable {
        var path: String
        var role: String?
        var title: String?
        var frame: [String: Double]?
        var actions: [String]?
        var enabled: Bool?
    }

    static func find(
        role: String? = nil,
        title: String? = nil,
        label: String? = nil,
        maxResults: Int = 5
    ) -> String? {
        guard AXIsProcessTrusted(),
              let window = focusedWindowElement() else { return nil }

        var results: [Match] = []
        search(
            element: window,
            path: "0",
            roleFilter: role,
            titleFilter: title ?? label,
            results: &results,
            maxResults: maxResults,
            depth: 0,
            maxDepth: 8
        )

        guard let data = try? JSONEncoder().encode(results),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    static func press(path: String, action: String = "AXPress") throws -> String {
        let element = try resolve(path: path)
        try validateWritable(element)
        let err = AXUIElementPerformAction(element, action as CFString)
        guard err == .success else {
            throw AXError.actionFailed("perform \(action) failed: \(err.rawValue)")
        }
        return "pressed"
    }

    static func setValue(path: String, value: String) throws -> String {
        let element = try resolve(path: path)
        try validateWritable(element)
        let err = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            value as CFTypeRef
        )
        guard err == .success else {
            throw AXError.actionFailed("set value failed: \(err.rawValue)")
        }
        return "value set"
    }

    static func focus(path: String) throws -> String {
        let element = try resolve(path: path)
        let err = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            true as CFTypeRef
        )
        guard err == .success else {
            throw AXError.actionFailed("focus failed: \(err.rawValue)")
        }
        return "focused"
    }

    static func invokeMenu(path: [String]) throws -> String {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else {
            throw AXError.unavailable("No foreground app.")
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXMenuBarAttribute as CFString,
            &menuBarRef
        ) == .success,
              let menuBar = menuBarRef else {
            throw AXError.unavailable("Menu bar not accessible.")
        }

        var current = menuBar as! AXUIElement
        for (idx, title) in path.enumerated() {
            guard let child = menuChild(matching: title, in: current) else {
                throw AXError.notFound("Menu item not found: \(title)")
            }
            if idx == path.count - 1 {
                let err = AXUIElementPerformAction(child, kAXPressAction as CFString)
                guard err == .success else {
                    throw AXError.actionFailed("menu press failed")
                }
                return "menu invoked"
            }
            // Open submenu
            let err = AXUIElementPerformAction(child, kAXPressAction as CFString)
            guard err == .success else {
                throw AXError.actionFailed("submenu open failed for \(title)")
            }
            current = child
        }
        throw AXError.invalidPath("Empty menu path")
    }

    // MARK: - Private

    enum AXError: Error, LocalizedError {
        case unavailable(String)
        case notFound(String)
        case invalidPath(String)
        case actionFailed(String)
        case secureField

        var errorDescription: String? {
            switch self {
            case .unavailable(let m): return m
            case .notFound(let m): return m
            case .invalidPath(let m): return m
            case .actionFailed(let m): return m
            case .secureField: return "Blocked: secure text field."
            }
        }
    }

    private static func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success,
              let window = windowRef else { return nil }
        return (window as! AXUIElement)
    }

    private static func resolve(path: String) throws -> AXUIElement {
        guard let window = focusedWindowElement() else {
            throw AXError.unavailable("Focused window not found.")
        }
        let indices = path.split(separator: "/").compactMap { Int($0) }
        guard let first = indices.first, first == 0 else {
            throw AXError.invalidPath("Path must start with window index 0.")
        }
        var current: AXUIElement = window
        for index in indices.dropFirst() {
            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXChildrenAttribute as CFString,
                &childrenRef
            ) == .success,
                  let children = childrenRef as? [AXUIElement],
                  index >= 0, index < children.count else {
                throw AXError.notFound("Child index \(index) out of range.")
            }
            current = children[index]
        }
        return current
    }

    private static func search(
        element: AXUIElement,
        path: String,
        roleFilter: String?,
        titleFilter: String?,
        results: inout [Match],
        maxResults: Int,
        depth: Int,
        maxDepth: Int
    ) {
        if results.count >= maxResults { return }

        let role = stringAttribute(element, kAXRoleAttribute)
        let title = stringAttribute(element, kAXTitleAttribute)
        let desc = stringAttribute(element, kAXDescriptionAttribute)
        let label = title ?? desc ?? stringAttribute(element, kAXValueAttribute)

        let roleMatch = roleFilter == nil || role == roleFilter
        let titleMatch = titleFilter == nil || [title, desc, label]
            .compactMap({ $0?.lowercased() })
            .contains(where: { $0.contains(titleFilter!.lowercased()) })

        if roleMatch && titleMatch && (roleFilter != nil || titleFilter != nil) {
            results.append(Match(
                path: path,
                role: role,
                title: label,
                frame: frameDict(element),
                actions: actionNames(element),
                enabled: isEnabled(element)
            ))
        }

        if depth >= maxDepth { return }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for (idx, child) in children.prefix(50).enumerated() {
            search(
                element: child,
                path: "\(path)/\(idx)",
                roleFilter: roleFilter,
                titleFilter: titleFilter,
                results: &results,
                maxResults: maxResults,
                depth: depth + 1,
                maxDepth: maxDepth
            )
        }
    }

    private static func menuChild(matching title: String, in parent: AXUIElement) -> AXUIElement? {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            parent,
            kAXChildrenAttribute as CFString,
            &childrenRef
        ) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        let needle = title.lowercased()
        for child in children {
            let t = stringAttribute(child, kAXTitleAttribute)?.lowercased()
            let d = stringAttribute(child, kAXDescriptionAttribute)?.lowercased()
            if t == needle || d == needle || t?.contains(needle) == true {
                return child
            }
        }
        return nil
    }

    private static func validateWritable(_ element: AXUIElement) throws {
        let role = stringAttribute(element, kAXRoleAttribute)
        if role == "AXSecureTextField" || role == "AXPasswordField" {
            throw AXError.secureField
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private static func isEnabled(_ element: AXUIElement) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &ref) == .success,
              let enabled = ref as? Bool else { return nil }
        return enabled
    }

    private static func actionNames(_ element: AXUIElement) -> [String]? {
        var namesArray: CFArray?
        guard AXUIElementCopyActionNames(element, &namesArray) == .success,
              let names = namesArray as? [String], !names.isEmpty else { return nil }
        return names
    }

    private static func frameDict(_ element: AXUIElement) -> [String: Double]? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return ["x": Double(point.x), "y": Double(point.y), "w": Double(size.width), "h": Double(size.height)]
    }
}
