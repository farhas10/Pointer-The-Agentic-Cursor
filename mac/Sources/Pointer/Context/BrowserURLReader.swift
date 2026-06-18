import AppKit
import Foundation

/// Reads the active tab URL from supported browsers via AppleScript.
enum BrowserURLReader {
    static func activeURL(for bundleId: String) -> String? {
        guard let script = script(for: bundleId) else { return nil }
        return runAppleScript(script)
    }

    private static func script(for bundleId: String) -> String? {
        switch bundleId {
        case "com.apple.Safari", "com.apple.Safari.WebApp":
            return """
            tell application "Safari"
              if (count of windows) = 0 then return ""
              return URL of current tab of front window
            end tell
            """
        case "company.thebrowser.Browser":
            return """
            tell application "Arc"
              if (count of windows) = 0 then return ""
              return URL of active tab of front window
            end tell
            """
        case "com.google.Chrome":
            return """
            tell application "Google Chrome"
              if (count of windows) = 0 then return ""
              return URL of active tab of front window
            end tell
            """
        case "org.mozilla.firefox":
            return """
            tell application "Firefox"
              if (count of windows) = 0 then return ""
              return URL of active tab of front window
            end tell
            """
        default:
            return nil
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let output = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let url = output.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url, !url.isEmpty, url.hasPrefix("http") else { return nil }
        return url
    }
}
