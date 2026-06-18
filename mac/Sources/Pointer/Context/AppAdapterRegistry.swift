import Foundation

/// Loads per-app automation hints (shortcuts, menu paths, AX quirks) for the agent.
enum AppAdapterRegistry {
    struct Adapter: Decodable {
        var bundleIds: [String]
        var name: String
        var automationTier: String?
        var notes: String?
        var shortcuts: [String: String]?
        var menuPaths: [String: [String]]?

        enum CodingKeys: String, CodingKey {
            case bundleIds = "bundle_ids"
            case name
            case automationTier = "automation_tier"
            case notes
            case shortcuts
            case menuPaths = "menu_paths"
        }
    }

    private static let adapters: [Adapter] = loadAdapters()

    static func hint(for bundleId: String?) -> String? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        guard let adapter = adapters.first(where: { $0.bundleIds.contains(bundleId) }) else {
            return nil
        }
        var lines = ["App adapter (\(adapter.name)):"]
        if let notes = adapter.notes { lines.append(notes) }
        if let shortcuts = adapter.shortcuts, !shortcuts.isEmpty {
            let pairs = shortcuts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
            lines.append("Shortcuts: \(pairs)")
        }
        if let menus = adapter.menuPaths, !menus.isEmpty {
            let pairs = menus.map { "\($0.key): \($0.value.joined(separator: " > "))" }
                .sorted().joined(separator: "; ")
            lines.append("Menus: \(pairs)")
        }
        return lines.joined(separator: "\n")
    }

    private static func loadAdapters() -> [Adapter] {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("adapters", isDirectory: true) else {
            return bundledFallback()
        }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else {
            return bundledFallback()
        }
        var loaded: [Adapter] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let adapter = try? JSONDecoder().decode(Adapter.self, from: data) else {
                continue
            }
            loaded.append(adapter)
        }
        return loaded.isEmpty ? bundledFallback() : loaded
    }

    /// Minimal built-in hints when bundle resources are unavailable (e.g. swift test).
    private static func bundledFallback() -> [Adapter] {
        [
            Adapter(
                bundleIds: ["com.apple.Music"],
                name: "Apple Music",
                automationTier: "medium",
                notes: "Prefer media_control for playback. AX buttons: Play, Pause, Next, Previous.",
                shortcuts: ["play_pause": "media_play_pause"],
                menuPaths: nil
            ),
            Adapter(
                bundleIds: ["com.microsoft.Word"],
                name: "Microsoft Word",
                automationTier: "hard",
                notes: "AX tree is shallow. Prefer key_chord shortcuts over click_at.",
                shortcuts: ["bold": "cmd+b", "italic": "cmd+i", "save": "cmd+s", "undo": "cmd+z"],
                menuPaths: nil
            ),
        ]
    }
}
