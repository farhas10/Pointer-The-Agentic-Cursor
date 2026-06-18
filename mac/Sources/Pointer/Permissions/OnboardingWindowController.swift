import AppKit
import SwiftUI

/// A standalone window that walks the user through granting the three
/// required permissions. Reopened from the menu bar at any time.
@MainActor
final class OnboardingWindowController: NSWindowController {
    init(permissions: PermissionsManager) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pointer"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: OnboardingView(permissions: permissions)
        )
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct OnboardingView: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pointer")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Option + right-click anywhere on screen to ask about what's under your cursor.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                permissionRow(
                    title: "Accessibility",
                    description: "Read the UI element under your cursor.",
                    granted: permissions.state.accessibility,
                    grantAction: {
                        permissions.requestAccessibility()
                        permissions.openAccessibilitySettings()
                    }
                )
                permissionRow(
                    title: "Screen Recording",
                    description: "Capture a small region around the cursor for vision context.",
                    granted: permissions.state.screenRecording,
                    grantAction: {
                        permissions.requestScreenRecording()
                        permissions.openScreenRecordingSettings()
                    }
                )
                permissionRow(
                    title: "Input Monitoring",
                    description: "Detect Option+right-click anywhere on screen.",
                    granted: permissions.state.inputMonitoring,
                    grantAction: { permissions.requestInputMonitoring() }
                )
                microphoneSection
            }

            Spacer(minLength: 0)

            if permissions.screenRecordingNeedsRelaunch {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                    Text("Screen Recording was granted but macOS only applies it after a relaunch.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Quit & Relaunch") { permissions.relaunch() }
                Spacer()
                Button("Re-check now") { permissions.refresh() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button(permissions.isFullyGranted ? "All set" : "Continue") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!permissions.isFullyGranted)
            }

            if !permissions.isFullyGranted {
                Text("Status updates automatically as you grant permissions. Accessibility and Input Monitoring apply immediately; Screen Recording needs a relaunch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 520, height: 620, alignment: .topLeading)
        // Resume polling while onboarding is visible (it stops on its own
        // once fully granted). We intentionally don't stop on disappear —
        // AppDelegate keeps detection running app-wide until granted.
        .onAppear {
            permissions.startMonitoring()
            permissions.requestMicrophoneIfNeeded()
        }
    }

    @ViewBuilder
    private var microphoneSection: some View {
        if let issue = permissions.microphoneProvisioningIssue {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Microphone (voice input)")
                        .font(.system(size: 15, weight: .semibold))
                    Text(issue)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if permissions.microphoneAuthState == .denied {
            VStack(alignment: .leading, spacing: 8) {
                permissionRow(
                    title: "Microphone",
                    description: "Point-and-speak questions in the panel (tap mic twice).",
                    granted: false,
                    grantAction: { permissions.requestMicrophone() }
                )
                Text(permissions.microphoneDeniedHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Copy reset command") {
                    permissions.copyMicrophoneResetCommand()
                }
                .controlSize(.small)
            }
        } else {
            permissionRow(
                title: "Microphone",
                description: "Point-and-speak questions in the panel (tap mic twice).",
                granted: permissions.state.microphone,
                grantAction: { permissions.requestMicrophone() }
            )
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        granted: Bool,
        grantAction: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(granted ? .green : .secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "Granted" : "Grant…", action: grantAction)
                .disabled(granted)
        }
    }
}
