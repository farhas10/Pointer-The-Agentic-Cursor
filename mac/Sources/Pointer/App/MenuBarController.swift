import AppKit
import Combine

/// Owns the `NSStatusItem` in the menu bar and its menu.
///
/// The icon shows a yellow dot when permissions aren't fully granted,
/// so the user always has a path back to the onboarding flow.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let permissions: PermissionsManager
    private let onShowOnboarding: () -> Void
    private let onOpenDrawer: () -> Void
    private let onQuit: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        permissions: PermissionsManager,
        onShowOnboarding: @escaping () -> Void,
        onOpenDrawer: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.permissions = permissions
        self.onShowOnboarding = onShowOnboarding
        self.onOpenDrawer = onOpenDrawer
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()
        refreshIcon()

        permissions.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshIcon() }
            .store(in: &cancellables)
    }

    private func configureMenu() {
        let menu = NSMenu()

        let setupItem = NSMenuItem(
            title: "Setup & permissions…",
            action: #selector(showOnboardingAction),
            keyEquivalent: ""
        )
        setupItem.target = self
        menu.addItem(setupItem)

        let drawerItem = NSMenuItem(
            title: "Open drawer…",
            action: #selector(openDrawerAction),
            keyEquivalent: "d"
        )
        drawerItem.keyEquivalentModifierMask = [.command, .shift]
        drawerItem.target = self
        menu.addItem(drawerItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(
            title: "About Pointer",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = permissions.isFullyGranted
            ? "cursorarrow.click.2"
            : "cursorarrow.and.square.on.square.dashed"
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Pointer"
        )?.withSymbolConfiguration(config)
        button.image = image
        button.imagePosition = .imageOnly
        button.toolTip = permissions.isFullyGranted
            ? "Pointer — Option+right-click anywhere"
            : "Pointer — setup needed"
    }

    @objc private func showOnboardingAction() { onShowOnboarding() }
    @objc private func openDrawerAction() { onOpenDrawer() }
    @objc private func quitAction() { onQuit() }
}
