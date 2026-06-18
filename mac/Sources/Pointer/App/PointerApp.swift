import SwiftUI

/// The app entry point.
///
/// We use `Settings { EmptyView() }` rather than `WindowGroup` because
/// Pointer is a menu-bar app: all real windows are owned imperatively
/// by `AppDelegate` (the panel, the drawer, the onboarding window).
@main
struct PointerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
