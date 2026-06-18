import Foundation

/// Maps common app names to macOS bundle identifiers.
enum AppBundleResolver {
    private static let known: [String: String] = [
        "safari": "com.apple.Safari",
        "finder": "com.apple.finder",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "mail": "com.apple.mail",
        "notes": "com.apple.Notes",
        "terminal": "com.apple.Terminal",
        "xcode": "com.apple.dt.Xcode",
        "vscode": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "slack": "com.tinyspeck.slackmacgap",
        "spotify": "com.spotify.client",
        "music": "com.apple.Music",
        "photos": "com.apple.Photos",
        "calendar": "com.apple.iCal",
        "reminders": "com.apple.reminders",
        "messages": "com.apple.MobileSMS",
        "settings": "com.apple.systempreferences",
        "system settings": "com.apple.systempreferences",
        "preview": "com.apple.Preview",
        "activity monitor": "com.apple.ActivityMonitor",
    ]

    static func resolve(_ name: String) -> String? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = known[key] { return exact }
        for (alias, bundleId) in known where key.contains(alias) {
            return bundleId
        }
        return nil
    }
}
