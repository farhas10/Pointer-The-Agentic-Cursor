import AppKit
import ApplicationServices
import AVFoundation
import Combine
import IOKit.hid

/// Live state of the permissions Pointer needs.
///
/// Detection caveats on macOS (these drive the UX in onboarding):
/// - **Accessibility** (`AXIsProcessTrusted`) updates live once granted.
/// - **Input Monitoring** (`IOHIDCheckAccess`) updates live once granted.
/// - **Screen Recording** (`CGPreflightScreenCaptureAccess`) is cached for
///   the lifetime of the process. After the user grants it, this keeps
///   returning the stale value until the app is **relaunched**. There is
///   no API to force a re-read, so onboarding offers a "Quit & Relaunch".
///
/// `startMonitoring()` begins polling so the UI updates on its own without
/// the user clicking anything; `refresh()` does a single read.
@MainActor
final class PermissionsManager: ObservableObject {
    struct State: Equatable {
        var accessibility: Bool
        var screenRecording: Bool
        var inputMonitoring: Bool
        var microphone: Bool

        static let empty = State(
            accessibility: false,
            screenRecording: false,
            inputMonitoring: false,
            microphone: false
        )

        /// Core permissions required for Option+click. Microphone is separate (voice input).
        var isFullyGranted: Bool {
            accessibility && screenRecording && inputMonitoring
        }

        var isVoiceReady: Bool { microphone }
    }

    @Published private(set) var state: State = .empty

    /// True once Screen Recording has been requested in this process but is
    /// still reported as not granted — almost always means a relaunch is
    /// required for the cached preflight value to update.
    @Published private(set) var screenRecordingNeedsRelaunch = false

    private var requestedScreenRecording = false
    private var pollTimer: Timer?

    var isFullyGranted: Bool { state.isFullyGranted }

    /// macOS only registers microphone access for real `.app` bundles that
    /// ship `NSMicrophoneUsageDescription`. `swift run` / bare binaries never
    /// appear in System Settings → Microphone.
    static var isPackagedApp: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    static var hasMicrophonePlistKey: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        return value?.isEmpty == false
    }

    enum MicrophoneAuthState: Equatable {
        case granted
        case undetermined
        case denied
        case unavailable
    }

    var microphoneAuthState: MicrophoneAuthState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        case .undetermined: return .undetermined
        @unknown default: return .unavailable
        }
    }

    var microphoneProvisioningIssue: String? {
        if !Self.isPackagedApp {
            return "Run Pointer from Xcode: open mac/Pointer.xcodeproj and press ⌘R. SwiftPM builds (`swift run`) cannot request microphone access."
        }
        if !Self.hasMicrophonePlistKey {
            return "This build is missing NSMicrophoneUsageDescription. Rebuild from Pointer.xcodeproj."
        }
        return nil
    }

    /// Shown when mic is blocked but Pointer is missing from System Settings.
    var microphoneDeniedHelp: String {
        "Pointer isn’t listed yet. Quit Pointer, run "
            + "`tccutil reset Microphone app.pointer.Pointer` "
            + "in Terminal, reopen Pointer, then tap Grant next to Microphone."
    }

    static let microphoneBundleId = "app.pointer.Pointer"

    func refresh() {
        let new = State(
            accessibility: AXIsProcessTrusted(),
            screenRecording: hasScreenRecordingPermission(),
            inputMonitoring: hasInputMonitoringPermission(),
            microphone: hasMicrophonePermission()
        )
        if new != state {
            state = new
        }
        let needsRelaunch = requestedScreenRecording && !new.screenRecording
        if needsRelaunch != screenRecordingNeedsRelaunch {
            screenRecordingNeedsRelaunch = needsRelaunch
        }

        // Once everything is granted there's nothing left to poll for.
        if new.isFullyGranted {
            stopMonitoring()
        }
    }

    /// Begin polling permission state ~once a second so the UI reflects
    /// grants made in System Settings without any manual "Re-check".
    func startMonitoring() {
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Relaunches the app. Needed after granting Screen Recording (and
    /// occasionally Accessibility) because macOS caches those decisions
    /// for the process lifetime. Spawns a detached shell that waits for
    /// this instance to quit, then reopens the bundle.
    func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; open \"\(bundlePath)\""]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Prompts the user with the standard system AX dialog. After the
    /// user grants it in System Settings, the app must be relaunched
    /// for the trust state to update — we surface that in onboarding.
    func requestAccessibility() {
        // `kAXTrustedCheckOptionPrompt` is a global `CFString` constant
        // exposed as a `var` in the C header; we reach for its actual
        // CFString value rather than the imported pointer, which Swift 6
        // strict-concurrency flags as "shared mutable state."
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: NSDictionary = [key as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Triggers the system Screen Recording prompt. Once the user grants
    /// it, the cached preflight value won't update until relaunch, so we
    /// remember that we asked and surface a relaunch prompt.
    func requestScreenRecording() {
        requestedScreenRecording = true
        // `CGRequestScreenCaptureAccess` shows the system prompt the first
        // time; subsequently it's a no-op and the user must use Settings.
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    /// There is no public API to request Input Monitoring; tapping a
    /// CGEvent stream is what actually triggers the prompt. The
    /// trigger coordinator handles that the first time it tries to
    /// install its event tap.
    func requestInputMonitoring() {
        // Open System Settings to the relevant pane so the user
        // can grant manually if the implicit prompt didn't fire.
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )!
        NSWorkspace.shared.open(url)
    }

    /// Open the Accessibility pane.
    func openAccessibilitySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    /// Open the Screen Recording pane.
    func openScreenRecordingSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )!
        NSWorkspace.shared.open(url)
    }

    /// Shows the system microphone prompt (first time) so Pointer appears in
    /// System Settings → Privacy & Security → Microphone.
    func requestMicrophone() {
        if let issue = microphoneProvisioningIssue {
            NSLog("Pointer: microphone blocked — \(issue) bundle=\(Bundle.main.bundlePath)")
            return
        }

        NSLog(
            "Pointer: requesting microphone (plist key present=%@ bundle=%@)",
            Self.hasMicrophonePlistKey ? "yes" : "no",
            Bundle.main.bundlePath
        )

        // `AVAudioApplication` shows the standard macOS mic prompt.
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    NSLog("Pointer: microphone prompt result granted=%@", granted ? "yes" : "no")
                    self?.probeMicrophoneHardware()
                    self?.refresh()
                }
            }
        case .denied:
            probeMicrophoneHardware()
            openMicrophoneSettings()
        case .granted:
            probeMicrophoneHardware()
        @unknown default:
            openMicrophoneSettings()
        }

        // Also register with TCC via AVFoundation on older macOS paths.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    /// Prompt on first launch if the user has not been asked yet.
    func requestMicrophoneIfNeeded() {
        guard microphoneProvisioningIssue == nil else { return }
        guard microphoneAuthState == .undetermined else { return }
        requestMicrophone()
    }

    /// Copy the Terminal command that clears a stale denied mic entry.
    func copyMicrophoneResetCommand() {
        let command = "tccutil reset Microphone \(Self.microphoneBundleId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    /// Touching the input device registers the app with TCC so it appears in
    /// System Settings → Microphone (permission dialog alone is not always enough).
    private func probeMicrophoneHardware() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pointer-mic-probe-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            if recorder.prepareToRecord() {
                _ = recorder.record(forDuration: 0.15)
                recorder.stop()
            }
            try? FileManager.default.removeItem(at: url)
        } catch {
            NSLog("Pointer: microphone probe failed — \(error.localizedDescription)")
        }
    }

    func openMicrophoneSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )!
        NSWorkspace.shared.open(url)
    }

    // MARK: Private probes

    private func hasScreenRecordingPermission() -> Bool {
        // Does not show UI. NOTE: cached for the process lifetime — see
        // the type doc. A relaunch is required to observe a fresh grant.
        CGPreflightScreenCaptureAccess()
    }

    private func hasInputMonitoringPermission() -> Bool {
        // `IOHIDCheckAccess` is the canonical, side-effect-free probe for
        // Input Monitoring and reflects fresh grants without a relaunch.
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func hasMicrophonePermission() -> Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }
}
