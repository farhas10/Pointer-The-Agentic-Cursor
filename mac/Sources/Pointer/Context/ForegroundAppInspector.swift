import AppKit
import ApplicationServices

/// Reads the bundle id, name, and frontmost window title of whatever
/// app is in front when the user triggers Pointer. Used to inform
/// chip selection and to give the model a tiny "where am I?" context.
struct ForegroundAppInspector {
    func currentContext() -> AppContext {
        let workspace = NSWorkspace.shared
        let app = workspace.frontmostApplication
        let bundleId = app?.bundleIdentifier
        let appName = app?.localizedName

        var context = AppContext(bundleId: bundleId, appName: appName)
        if let pid = app?.processIdentifier {
            context.windowTitle = focusedWindowTitle(forPid: pid)
            context.url = focusedUrl(forApp: app)
        }
        return context
    }

    private func focusedWindowTitle(forPid pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        )
        guard status == .success, let window = windowRef else { return nil }
        // swiftlint:disable:next force_cast
        let windowElement = window as! AXUIElement
        var titleRef: CFTypeRef?
        let titleStatus = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleStatus == .success else { return nil }
        return titleRef as? String
    }

    /// Best-effort URL extraction for known browsers. Phase 2 expands
    /// this list and uses the BrowserContextProvider protocol so each
    /// browser's quirks live in one file.
    private func focusedUrl(forApp app: NSRunningApplication?) -> String? {
        guard let bundleId = app?.bundleIdentifier else { return nil }
        return BrowserURLReader.activeURL(for: bundleId)
    }
}
