import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Standalone drawer window for drag-and-drop file context.
@MainActor
final class DrawerWindowController {
    private let store: DrawerStore
    private let backendClient: BackendClient
    private var window: NSWindow?
    private var viewModel: DrawerViewModel?
    private var hotkey: GlobalHotkey?

    init(store: DrawerStore, backendClient: BackendClient) {
        self.store = store
        self.backendClient = backendClient
        hotkey = GlobalHotkey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(cmdKey | shiftKey),
            hotKeyId: 2,
            handler: { [weak self] in self?.toggle() }
        )
        hotkey?.register()
    }

    func show() {
        if window == nil {
            let viewModel = DrawerViewModel(store: store, backendClient: backendClient)
            self.viewModel = viewModel

            let hosting = NSHostingView(rootView: DrawerView(viewModel: viewModel))
            hosting.autoresizingMask = [.width, .height]
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 640),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Pointer Drawer"
            win.titlebarAppearsTransparent = true
            win.isReleasedWhenClosed = false
            win.contentView = hosting
            win.center()
            window = win
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        viewModel?.selectAll()
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func addFromPanel(_ context: TriggerContext) {
        store.addFromPanel(context: context)
        show()
    }
}
