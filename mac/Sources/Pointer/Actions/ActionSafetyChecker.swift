import AppKit
import ApplicationServices
import Foundation

/// Client-side safety checks before executing automation tools.
enum ActionSafetyChecker {
    enum BlockReason: Error, LocalizedError {
        case secureField
        case paymentSurface
        case blockedBundle(String)

        var errorDescription: String? {
            switch self {
            case .secureField: return "Blocked: target is a secure text field."
            case .paymentSurface: return "Blocked: target appears to be a payment surface."
            case .blockedBundle(let id): return "Blocked: automation not allowed in \(id)."
            }
        }
    }

    private static let blockedBundles: Set<String> = [
        "com.apple.Passwords",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
    ]

    private static let paymentHints = [
        "stripe", "payment", "card number", "cvv", "cvc", "checkout", "billing",
    ]

    static func validateClick(at cgPoint: CGPoint) throws {
        guard AXIsProcessTrusted() else { return }
        let system = AXUIElementCreateSystemWide()
        var elementRef: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            system,
            Float(cgPoint.x),
            Float(cgPoint.y),
            &elementRef
        ) == .success,
              let element = elementRef else { return }

        if isSecure(element) { throw BlockReason.secureField }
        if isPaymentSurface(element) { throw BlockReason.paymentSurface }

        if let bundleId = owningBundleId(element), blockedBundles.contains(bundleId) {
            throw BlockReason.blockedBundle(bundleId)
        }
    }

    static func elevatedTierForFocusApp(
        targetBundleId: String,
        foregroundBundleId: String?
    ) -> ToolConfirmationCoordinator.ToolTier {
        guard let foreground = foregroundBundleId, !foreground.isEmpty else {
            return .automation
        }
        return targetBundleId == foreground ? .automation : .destructive
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = axString(element, kAXRoleAttribute) ?? ""
        return role == "AXSecureTextField" || role == "AXPasswordField"
    }

    private static func isPaymentSurface(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let el = current else { break }
            let haystack = [
                axString(el, kAXRoleAttribute),
                axString(el, kAXTitleAttribute),
                axString(el, kAXDescriptionAttribute),
                axString(el, kAXValueAttribute),
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            if paymentHints.contains(where: { haystack.contains($0) }) {
                return true
            }
            current = parent(of: el)
        }
        return false
    }

    private static func owningBundleId(_ element: AXUIElement) -> String? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentRef
        ) == .success,
              let parent = parentRef else { return nil }
        return (parent as! AXUIElement)
    }

    private static func axString(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }
}
