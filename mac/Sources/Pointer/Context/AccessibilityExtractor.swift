import ApplicationServices
import AppKit

/// Reads a compact AX snapshot of the element under a screen point.
///
/// `AXUIElementCopyElementAtPosition` is synchronous and very fast
/// (microseconds), so we call it on whatever thread triggered us.
/// Field redaction for `AXSecureTextField` happens here so secrets
/// never enter our process memory beyond a single boolean.
struct AccessibilityExtractor {
    /// `point` is in CG (top-left origin) screen coordinates.
    func snapshot(atScreenPoint point: CGPoint) -> AXSnapshot? {
        guard AXIsProcessTrusted() else { return nil }

        let systemElement = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        let status = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(point.x),
            Float(point.y),
            &elementRef
        )
        guard status == .success, let element = elementRef else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute)
        let isSecure = role == "AXSecureTextField" || role == "AXPasswordField"

        var snapshot = AXSnapshot(
            role: role,
            subrole: stringAttribute(element, kAXSubroleAttribute),
            title: stringAttribute(element, kAXTitleAttribute),
            value: isSecure ? nil : stringAttribute(element, kAXValueAttribute),
            selectedText: isSecure ? nil : stringAttribute(element, kAXSelectedTextAttribute),
            parentRole: parentRole(of: element),
            redacted: isSecure
        )

        // Truncate to keep wire payloads sane.
        snapshot.value = snapshot.value.map { String($0.prefix(2_000)) }
        snapshot.selectedText = snapshot.selectedText.map { String($0.prefix(2_000)) }

        return snapshot
    }

    private func parentRole(of element: AXUIElement) -> String? {
        var parentRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentRef
        )
        guard status == .success, let parent = parentRef else { return nil }
        // swiftlint:disable:next force_cast
        let parentElement = parent as! AXUIElement
        return stringAttribute(parentElement, kAXRoleAttribute)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
        guard status == .success else { return nil }
        return ref as? String
    }
}
