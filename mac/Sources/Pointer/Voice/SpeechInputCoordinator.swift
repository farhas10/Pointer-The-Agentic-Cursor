import AVFoundation
import Combine
import Foundation
import os

/// Point-and-speak: records on-device, transcribes via backend Gemini (no Speech.framework).
@MainActor
final class SpeechInputCoordinator: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var partialTranscript = ""
    @Published private(set) var errorMessage: String?

    private static let log = Logger(subsystem: "app.pointer.Pointer", category: "SpeechInput")

    private let backend: BackendClient
    private let permissions: PermissionsManager
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var transcribeTask: Task<Void, Never>?

    init(backend: BackendClient, permissions: PermissionsManager) {
        self.backend = backend
        self.permissions = permissions
    }

    var statusHint: String? {
        if isListening { return "Recording… tap mic again when done." }
        if isTranscribing { return "Transcribing…" }
        return errorMessage
    }

    func toggleListening(onFinal: @escaping @Sendable @MainActor (String) -> Void) {
        if isListening {
            stopRecordingAndTranscribe(onFinal: onFinal)
        } else if isTranscribing {
            errorMessage = "Still transcribing the last clip…"
        } else {
            startRecording()
        }
    }

    func stopListening() {
        transcribeTask?.cancel()
        transcribeTask = nil
        recorder?.stop()
        recorder = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        isListening = false
        isTranscribing = false
        partialTranscript = ""
    }

    private func startRecording() {
        errorMessage = nil
        partialTranscript = ""

        if let issue = permissions.microphoneProvisioningIssue {
            errorMessage = issue
            return
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            permissions.requestMicrophone()
            errorMessage = "Allow microphone in the system dialog, then tap mic again."
        case .denied:
            errorMessage = permissions.microphoneDeniedHelp
            permissions.openMicrophoneSettings()
        @unknown default:
            errorMessage = "Microphone permission unavailable."
        }
    }

    private func beginRecording() {
        stopListening()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pointer-speech-\(UUID().uuidString).wav")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]

        do {
            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.isMeteringEnabled = false
            guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
                errorMessage = "Could not start recording."
                stopListening()
                return
            }
            recorder = audioRecorder
            isListening = true
            partialTranscript = "Recording… tap mic again when done."
            Self.log.info("recording started")
        } catch {
            errorMessage = "Microphone error: \(error.localizedDescription)"
            Self.log.error("recorder failed: \(error.localizedDescription, privacy: .public)")
            stopListening()
        }
    }

    private func stopRecordingAndTranscribe(onFinal: @escaping @Sendable @MainActor (String) -> Void) {
        let duration = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        isListening = false
        isTranscribing = true
        partialTranscript = "Transcribing…"

        guard let url = recordingURL else {
            isTranscribing = false
            partialTranscript = ""
            return
        }

        if duration < 0.4 {
            errorMessage = "Recording too short. Hold the mic a moment longer."
            isTranscribing = false
            partialTranscript = ""
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
            return
        }

        transcribeTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let data = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)
                self.recordingURL = nil

                guard data.count > 1_000 else {
                    self.errorMessage = "No audio captured. Check your microphone input."
                    self.isTranscribing = false
                    self.partialTranscript = ""
                    self.transcribeTask = nil
                    return
                }

                Self.log.info("uploading audio bytes=\(data.count)")
                let response = try await self.backend.transcribeAudio(
                    audioData: data,
                    mimeType: "audio/wav"
                )
                let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                self.isTranscribing = false
                self.partialTranscript = ""
                self.transcribeTask = nil

                if text.isEmpty {
                    self.errorMessage = "Couldn't make out speech. Try again closer to the mic."
                    Self.log.error("transcribe returned empty text")
                } else {
                    Self.log.info("transcribe ok len=\(text.count)")
                    onFinal(text)
                }
            } catch is CancellationError {
                self.isTranscribing = false
                self.partialTranscript = ""
                self.transcribeTask = nil
            } catch {
                self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                Self.log.error("transcribe failed: \(error.localizedDescription, privacy: .public)")
                self.isTranscribing = false
                self.partialTranscript = ""
                self.transcribeTask = nil
            }
        }
    }
}
