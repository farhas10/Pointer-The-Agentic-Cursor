import AppKit
import ApplicationServices
import Foundation

/// Dispatches Gemini agent tool calls into real macOS actions.
@MainActor
final class ActionExecutor {
    private let backend: BackendClient
    var userLocation: UserLocation?
    /// When true, `click_at` uses 0–999 grid coords (Computer Use).
    var computerUseMode = false
    var screenSize = CGSize(width: 1440, height: 900)

    init(backend: BackendClient) {
        self.backend = backend
    }

    enum ActionError: Error, LocalizedError {
        case unknownTool(String)
        case invalidInput(String)
        case denied(String)

        var errorDescription: String? {
            switch self {
            case .unknownTool(let name): return "Unknown tool: \(name)"
            case .invalidInput(let msg): return msg
            case .denied(let msg): return msg
            }
        }
    }

    @discardableResult
    func execute(toolName: String, inputJson: String) async throws -> String {
        switch toolName {
        case "copy_to_clipboard":
            let text = try string(from: inputJson, key: "text")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return "copied"

        case "open_url":
            return try openURL(inputJson: inputJson)

        case "search_web":
            let query = try string(from: inputJson, key: "query")
            let result = try await backend.webSearch(query: query)
            return result.text

        case "search_places":
            let query = try string(from: inputJson, key: "query")
            let result = try await backend.placesSearch(
                query: query,
                location: userLocation
            )
            return result.text

        case "find_ax_element":
            let role = optionalString(from: inputJson, key: "role")
            let title = optionalString(from: inputJson, key: "title")
            let label = optionalString(from: inputJson, key: "label")
            guard role != nil || title != nil || label != nil else {
                throw ActionError.invalidInput("find_ax_element needs role, title, or label")
            }
            guard let json = AXElementResolver.find(role: role, title: title, label: label) else {
                throw ActionError.denied("No matching elements or AX unavailable.")
            }
            return json

        case "ax_press":
            let path = try string(from: inputJson, key: "path")
            let action = optionalString(from: inputJson, key: "action") ?? "AXPress"
            return try AXElementResolver.press(path: path, action: action)

        case "ax_set_value":
            let path = try string(from: inputJson, key: "path")
            let value = try string(from: inputJson, key: "value")
            return try AXElementResolver.setValue(path: path, value: value)

        case "ax_focus":
            let path = try string(from: inputJson, key: "path")
            return try AXElementResolver.focus(path: path)

        case "invoke_menu":
            let path = try stringArray(from: inputJson, key: "path")
            return try AXElementResolver.invokeMenu(path: path)

        case "media_control":
            let actionRaw = try string(from: inputJson, key: "action")
            guard let action = MediaKeySender.Action(rawValue: actionRaw) else {
                throw ActionError.invalidInput("unknown media action: \(actionRaw)")
            }
            MediaKeySender.send(action)
            return "media \(actionRaw)"

        case "run_shortcut":
            let name = try string(from: inputJson, key: "name")
            let input = optionalString(from: inputJson, key: "input")
            return try runShortcut(name: name, input: input)

        case "paste_text":
            let text = try string(from: inputJson, key: "text")
            if try setFocusedValue(text) {
                return "pasted via AX"
            }
            try pasteViaClipboard(text)
            return "pasted via Cmd+V"

        case "replace_selection":
            let text = try string(from: inputJson, key: "text")
            if try setFocusedValue(text) {
                return "replaced via AX"
            }
            try pasteViaClipboard(text)
            return "replaced via Cmd+V"

        case "click_at":
            let doubleClick = bool(from: inputJson, key: "double") ?? false
            let point: CGPoint
            if computerUseMode {
                let x = try intRequired(from: inputJson, key: "x")
                let y = try intRequired(from: inputJson, key: "y")
                point = ComputerUseActions.denormalizedPoint(
                    x: x,
                    y: y,
                    screenWidth: screenSize.width,
                    screenHeight: screenSize.height
                )
            } else {
                let x = try double(from: inputJson, key: "x")
                let y = try double(from: inputJson, key: "y")
                point = CGPoint(x: x, y: y)
            }
            try click(at: point, doubleClick: doubleClick)
            return "clicked"

        case "type_text_at":
            let x = try intRequired(from: inputJson, key: "x")
            let y = try intRequired(from: inputJson, key: "y")
            let text = try string(from: inputJson, key: "text")
            let pressEnter = bool(from: inputJson, key: "press_enter") ?? true
            let clearFirst = bool(from: inputJson, key: "clear_before_typing") ?? true
            let point = ComputerUseActions.denormalizedPoint(
                x: x,
                y: y,
                screenWidth: screenSize.width,
                screenHeight: screenSize.height
            )
            try click(at: point, doubleClick: false)
            if clearFirst {
                try synthesizeKeyChord(keyCode: 0x00, flags: .maskCommand)
                try synthesizeKeyChord(keyCode: 0x33, flags: [])
            }
            try typeUnicode(text)
            if pressEnter {
                try synthesizeKeyChord(keyCode: 0x24, flags: [])
            }
            return "typed at coordinate"

        case "scroll_at":
            let x = try intRequired(from: inputJson, key: "x")
            let y = try intRequired(from: inputJson, key: "y")
            let direction = try string(from: inputJson, key: "direction").lowercased()
            let magnitude = int(from: inputJson, key: "magnitude") ?? 800
            let point = ComputerUseActions.denormalizedPoint(
                x: x,
                y: y,
                screenWidth: screenSize.width,
                screenHeight: screenSize.height
            )
            try scroll(at: point, direction: direction, magnitude: magnitude)
            return "scrolled"

        case "wait_5_seconds":
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return "waited"

        case "key_combination":
            let keys = try string(from: inputJson, key: "keys")
            try synthesizeChord(keys)
            return "key combination sent"

        case "type_text":
            let text = try string(from: inputJson, key: "text")
            try typeUnicode(text)
            return "typed"

        case "key_chord":
            let chord = try string(from: inputJson, key: "chord")
            try synthesizeChord(chord)
            return "key chord sent"

        case "launch_app":
            return try launchApp(inputJson: inputJson)

        case "focus_app":
            let bundleId = try string(from: inputJson, key: "bundle_id")
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
                app.activate()
                return "focused \(bundleId)"
            }
            return try launchApp(name: nil, bundleId: bundleId)

        case "open_path":
            let path = try string(from: inputJson, key: "path")
            let expanded = (path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            guard FileManager.default.fileExists(atPath: expanded) else {
                throw ActionError.invalidInput("path does not exist: \(expanded)")
            }
            guard NSWorkspace.shared.open(url) else {
                throw ActionError.denied("could not open \(expanded)")
            }
            return "opened \(expanded)"

        case "list_directory":
            let path = try string(from: inputJson, key: "path")
            let maxEntries = int(from: inputJson, key: "max_entries") ?? 40
            return try listDirectory(path: path, maxEntries: maxEntries)

        case "run_applescript":
            let script = try string(from: inputJson, key: "script")
            return try runAppleScript(script)

        case "read_ax_tree":
            let depth = int(from: inputJson, key: "max_depth") ?? 6
            guard let tree = AXTreeReader.readFocusedTree(maxDepth: depth) else {
                throw ActionError.denied("Could not read accessibility tree.")
            }
            return tree

        default:
            throw ActionError.unknownTool(toolName)
        }
    }

    private func setFocusedValue(_ text: String) throws -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
              let focused = focusedRef else { return false }

        let element = focused as! AXUIElement
        let role = axString(element, kAXRoleAttribute)
        if role == "AXSecureTextField" || role == "AXPasswordField" {
            throw ActionError.denied("Cannot write to secure text field.")
        }
        let status = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        return status == .success
    }

    private func pasteViaClipboard(_ text: String) throws {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        try synthesizeKeyChord(keyCode: 0x09, flags: .maskCommand)
    }

    private func click(at cgPoint: CGPoint, doubleClick: Bool) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.denied("Could not create input event source.")
        }
        let quartz = quartzPoint(from: cgPoint)
        let downType: CGEventType = doubleClick ? .leftMouseDown : .leftMouseDown
        let upType: CGEventType = .leftMouseUp
        guard let down = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: quartz,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: quartz,
            mouseButton: .left
        ) else {
            throw ActionError.denied("Could not synthesize mouse event.")
        }
        if doubleClick { down.setIntegerValueField(.mouseEventClickState, value: 2) }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        if doubleClick {
            guard let down2 = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: quartz,
                mouseButton: .left
            ),
            let up2 = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: quartz,
                mouseButton: .left
            ) else { return }
            down2.setIntegerValueField(.mouseEventClickState, value: 2)
            down2.post(tap: .cghidEventTap)
            up2.post(tap: .cghidEventTap)
        }
    }

    private func scroll(at cgPoint: CGPoint, direction: String, magnitude: Int) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.denied("Could not create input event source.")
        }
        let quartz = quartzPoint(from: cgPoint)
        let wheelCount: UInt32 = 1
        var deltaY: Int32 = 0
        var deltaX: Int32 = 0
        let amount = Int32(max(1, min(magnitude, 999)))
        switch direction {
        case "up": deltaY = amount
        case "down": deltaY = -amount
        case "left": deltaX = amount
        case "right": deltaX = -amount
        default:
            throw ActionError.invalidInput("invalid scroll direction: \(direction)")
        }
        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: wheelCount,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            throw ActionError.denied("Could not synthesize scroll event.")
        }
        event.location = quartz
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private func typeUnicode(_ text: String) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.denied("Could not create input event source.")
        }
        let scalars = Array(text.utf16)
        guard !scalars.isEmpty else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw ActionError.denied("Could not synthesize typing event.")
        }
        down.keyboardSetUnicodeString(stringLength: scalars.count, unicodeString: scalars)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func synthesizeChord(_ chord: String) throws {
        let parts = chord.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last else {
            throw ActionError.invalidInput("invalid chord: \(chord)")
        }
        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default: break
            }
        }
        guard let keyCode = keyCode(for: keyPart) else {
            throw ActionError.invalidInput("unknown key in chord: \(chord)")
        }
        try synthesizeKeyChord(keyCode: keyCode, flags: flags)
    }

    private func synthesizeKeyChord(keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ActionError.denied("Could not create input event source.")
        }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw ActionError.denied("Could not synthesize key event.")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func launchApp(inputJson: String) throws -> String {
        let object = try jsonObject(from: inputJson)
        let name = object["name"] as? String
        let bundleId = object["bundle_id"] as? String
        return try launchApp(name: name, bundleId: bundleId)
    }

    private func launchApp(name: String?, bundleId: String?) throws -> String {
        let resolvedBundle = bundleId ?? name.flatMap(AppBundleResolver.resolve)
        if let resolvedBundle,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolvedBundle) {
            guard NSWorkspace.shared.open(appURL) else {
                throw ActionError.denied("could not launch \(resolvedBundle)")
            }
            return "launched \(resolvedBundle)"
        }
        if let name, !name.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", name]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ActionError.invalidInput("could not launch app: \(name)")
            }
            return "launched \(name)"
        }
        throw ActionError.invalidInput("launch_app requires name or bundle_id")
    }

    private func listDirectory(path: String, maxEntries: Int) throws -> String {
        let expanded = (path as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            throw ActionError.invalidInput("not a directory: \(expanded)")
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: expanded),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let entries: [[String: Any]] = urls.prefix(maxEntries).compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return [
                "name": url.lastPathComponent,
                "is_directory": values?.isDirectory ?? false,
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries),
              let json = String(data: data, encoding: .utf8) else {
            throw ActionError.denied("could not encode directory listing")
        }
        return json
    }

    private func jsonObject(from json: String) throws -> [String: Any] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ActionError.invalidInput("invalid json")
        }
        return object
    }

    private func runAppleScript(_ source: String) throws -> String {
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        guard let output = script?.executeAndReturnError(&error) else {
            let message = (error?["NSAppleScriptErrorMessage"] as? String) ?? "AppleScript failed"
            throw ActionError.denied(message)
        }
        return output.stringValue ?? "ok"
    }

    private func keyCode(for token: String) -> CGKeyCode? {
        if token.count == 1, let scalar = token.unicodeScalars.first {
            let table: [UnicodeScalar: CGKeyCode] = [
                "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
                "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
                "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
                "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
                "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10, "z": 0x06,
            ]
            return table[scalar]
        }
        switch token {
        case "return", "enter": return 0x24
        case "tab": return 0x30
        case "escape", "esc": return 0x35
        case "space": return 0x31
        case "delete", "backspace": return 0x33
        default: return nil
        }
    }

    private func quartzPoint(from cgPoint: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.flippedToCGScreen().contains(cgPoint)
        }) ?? NSScreen.main else { return cgPoint }
        let cgFrame = screen.frame.flippedToCGScreen()
        let localX = cgPoint.x - cgFrame.minX
        let localY = cgPoint.y - cgFrame.minY
        return CGPoint(
            x: screen.frame.minX + localX,
            y: screen.frame.maxY - localY
        )
    }

    private func axString(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else {
            return nil
        }
        return ref as? String
    }

    private func string(from json: String, key: String) throws -> String {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object[key] as? String
        else {
            throw ActionError.invalidInput("missing string \(key) in \(json)")
        }
        return value
    }

    private func double(from json: String, key: String) throws -> Double {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ActionError.invalidInput("invalid json")
        }
        if let value = object[key] as? Double { return value }
        if let value = object[key] as? Int { return Double(value) }
        throw ActionError.invalidInput("missing number \(key)")
    }

    private func bool(from json: String, key: String) -> Bool? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object[key] as? Bool
    }

    private func int(from json: String, key: String) -> Int? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let value = object[key] as? Int { return value }
        if let value = object[key] as? Double { return Int(value) }
        return nil
    }

    private func intRequired(from json: String, key: String) throws -> Int {
        guard let value = int(from: json, key: key) else {
            throw ActionError.invalidInput("missing integer \(key)")
        }
        return value
    }

    private func optionalString(from json: String, key: String) -> String? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object[key] as? String,
            !value.isEmpty
        else { return nil }
        return value
    }

    private func stringArray(from json: String, key: String) throws -> [String] {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = object[key] as? [String],
            !value.isEmpty
        else {
            throw ActionError.invalidInput("missing array \(key)")
        }
        return value
    }

    private func openURL(inputJson: String) throws -> String {
        let url = try string(from: inputJson, key: "url")
        guard let parsed = URL(string: url) else {
            throw ActionError.invalidInput("not a URL: \(url)")
        }
        let newTab = bool(from: inputJson, key: "new_tab") ?? false
        let browser = optionalString(from: inputJson, key: "browser") ?? "default"

        if newTab {
            let escaped = url.replacingOccurrences(of: "\"", with: "\\\"")
            let script: String
            switch browser.lowercased() {
            case "safari":
                script = """
                tell application "Safari"
                  tell front window
                    make new tab with properties {URL:"\(escaped)"}
                  end tell
                  activate
                end tell
                """
            case "arc":
                script = """
                tell application "Arc"
                  tell front window
                    make new tab with properties {URL:"\(escaped)"}
                  end tell
                  activate
                end tell
                """
            default:
                NSWorkspace.shared.open(parsed)
                return "opened"
            }
            return try runAppleScript(script)
        }

        NSWorkspace.shared.open(parsed)
        return "opened"
    }

    private func runShortcut(name: String, input: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        var args = ["run", name]
        if let input, !input.isEmpty {
            args.append(contentsOf: ["--input", input])
        }
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ActionError.denied("shortcut failed: \(output)")
        }
        return output.isEmpty ? "shortcut ran" : output
    }
}

private extension NSRect {
    func flippedToCGScreen() -> CGRect {
        guard let primary = NSScreen.screens.first else { return self }
        let primaryHeight = primary.frame.height
        return CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}
