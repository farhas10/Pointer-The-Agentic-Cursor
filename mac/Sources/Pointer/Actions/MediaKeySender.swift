import AppKit
import Carbon.HIToolbox

/// Posts system-defined media key events (play/pause/next/previous).
enum MediaKeySender {
    enum Action: String {
        case play
        case pause
        case play_pause
        case next
        case previous
    }

    static func send(_ action: Action) {
        let keyType: Int32
        switch action {
        case .play: keyType = NX_KEYTYPE_PLAY
        case .pause: keyType = NX_KEYTYPE_PLAY // toggle on macOS
        case .play_pause: keyType = NX_KEYTYPE_PLAY
        case .next: keyType = NX_KEYTYPE_NEXT
        case .previous: keyType = NX_KEYTYPE_PREVIOUS
        }
        postSystemDefinedKey(keyType)
    }

    private static func postSystemDefinedKey(_ keyType: Int32) {
        let ext1 = UInt32((keyType << 16) | (0xa << 8))
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(ext1)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(ext1),
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
