import AppKit
import Carbon.HIToolbox

/// Thin wrapper around Carbon `RegisterEventHotKey`. Carbon is the
/// only supported way to register a system-wide hotkey on macOS;
/// AppKit's `globalMonitor` does not work for keys consumed by other
/// apps.
@MainActor
final class GlobalHotkey {
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let hotKeyId: UInt32
    private let handler: () -> Void

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyId: UInt32 = 1,
        handler: @escaping () -> Void
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.hotKeyId = hotKeyId
        self.handler = handler
    }

    func register() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userInfo -> OSStatus in
                guard let userInfo, let eventRef else { return noErr }
                let me = Unmanaged<GlobalHotkey>
                    .fromOpaque(userInfo).takeUnretainedValue()
                me.handler()
                _ = eventRef
                return noErr
            },
            1,
            &eventType,
            userInfo,
            &handlerRef
        )

        guard installStatus == noErr else { return }

        let registration = EventHotKeyID(signature: pointerSignature, id: hotKeyId)
        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            registration,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if registerStatus == noErr {
            hotKeyRef = ref
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

/// Four-char identifier for our hotkeys.
private let pointerSignature: OSType = {
    let chars: [Character] = ["P", "T", "R", "X"]
    var value: OSType = 0
    for char in chars {
        value = (value << 8) | OSType(char.asciiValue ?? 0)
    }
    return value
}()
