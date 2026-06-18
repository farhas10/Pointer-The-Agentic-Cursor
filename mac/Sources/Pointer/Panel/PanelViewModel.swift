import Combine
import Foundation
import SwiftUI

/// Drives the panel's UI state. Owns the inflight ask task, accumulates
/// streamed tokens, and runs the Gemini agent tool loop on the Mac.
@MainActor
final class PanelViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case streaming
        case finished(reason: String)
        case errored(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var answer: String = ""
    @Published private(set) var citationLabels: [String: String] = [:]
    @Published private(set) var entities: [PanelEntity] = []
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var isCompanionPinned: Bool = false
    @Published var prompt: String = ""
    @Published var showFreeText: Bool = false
    @Published var includeScreenshot: Bool = true
    @Published var context: TriggerContext

    let toolConfirmation = ToolConfirmationCoordinator()
    let actionQueue = ActionQueueTracker()
    let speechInput: SpeechInputCoordinator
    let chips: [ChipIntent]
    let panelSessionId: String

    private let backendClient: BackendClient
    private let permissions: PermissionsManager
    private let actionExecutor: ActionExecutor
    private let agentPanic = AgentPanicCoordinator()
    private var networkTask: Task<Void, Never>?
    private var userCancelled = false
    private var askCount = 0
    private var cancellables = Set<AnyCancellable>()

    private static let companionTools: Set<String> = [
        "search_web", "search_places", "open_url",
        "key_chord", "media_control", "run_shortcut", "click_at",
        "type_text_at", "scroll_at", "wait_5_seconds", "key_combination",
        "paste_text", "type_text", "launch_app", "focus_app", "open_path",
    ]

    var onRequestStart: (() -> Void)?
    var onAddToDrawer: ((TriggerContext) -> Void)?
    var onHaloStateChange: ((HaloOverlayWindow.State) -> Void)?
    var onCompanionPin: (() -> Void)?

    init(
        context: TriggerContext,
        backendClient: BackendClient,
        permissions: PermissionsManager
    ) {
        self.context = context
        self.backendClient = backendClient
        self.permissions = permissions
        self.actionExecutor = ActionExecutor(backend: backendClient)
        self.speechInput = SpeechInputCoordinator(
            backend: backendClient,
            permissions: permissions
        )
        self.chips = ChipsEngine().chipSet(for: context)
        self.panelSessionId = UUID().uuidString
        toolConfirmation.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        actionQueue.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        speechInput.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        speechInput.$partialTranscript
            .sink { [weak self] text in
                guard let self, !text.isEmpty else { return }
                if self.speechInput.isListening || self.speechInput.isTranscribing {
                    self.prompt = text
                }
            }
            .store(in: &cancellables)
    }

    var contextStrip: String {
        let appPart = context.appContext.appName
            ?? context.appContext.bundleId
            ?? "macOS"
        var parts = [appPart]
        if let title = context.appContext.windowTitle, !title.isEmpty {
            parts.append("\"\(title)\"")
        }
        if let url = context.appContext.url, !url.isEmpty {
            let short = url.count > 48 ? String(url.prefix(45)) + "…" : url
            parts.append(short)
        }
        if isCompanionPinned {
            parts.append("· Companion")
        }
        return parts.joined(separator: " · ")
    }

    var hasScreenshot: Bool {
        Self.isValidImage(context.imagePngBase64)
    }

    var showFollowUpInput: Bool {
        switch phase {
        case .finished, .streaming:
            return !answer.isEmpty || phase == .streaming
        default:
            return isCompanionPinned
        }
    }

    var selectionPreview: String? {
        let snapshot = context.axSnapshot
        if let selected = snapshot?.selectedText, !selected.isEmpty {
            return previewify(selected)
        }
        if snapshot?.redacted == true { return "(secure content)" }
        if let value = snapshot?.value, !value.isEmpty {
            return previewify(value)
        }
        if let title = snapshot?.title, !title.isEmpty {
            return title
        }
        return nil
    }

    func runChip(_ chip: ChipIntent) {
        if chip == .addToDrawer {
            onAddToDrawer?(context)
            return
        }
        beginAsk(prompt: chip.displayName, chip: chip)
    }

    func submitFreeText() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        beginAsk(prompt: prompt.trimmingCharacters(in: .whitespaces), chip: nil)
    }

    func submitFollowUp() {
        submitFreeText()
    }

    func toggleVoiceInput() {
        speechInput.toggleListening { [weak self] transcript in
            guard let self else { return }
            self.prompt = transcript
            self.submitFreeText()
        }
    }

    func runEntityAction(_ entity: PanelEntity, action: PanelEntity.Action) {
        switch action {
        case .open:
            guard let url = entity.url else { return }
            runDirectTool(name: "open_url", input: ["url": url, "new_tab": true])
        case .reviews:
            beginAsk(prompt: "What do reviews say about \(entity.name)?", chip: nil)
        case .directions:
            let query = entity.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? entity.name
            let maps = "https://www.google.com/maps/search/?api=1&query=\(query)"
            runDirectTool(name: "open_url", input: ["url": maps, "new_tab": true])
        case .copy:
            NSPasteboard.general.clearContents()
            var text = entity.name
            if let subtitle = entity.subtitle { text += " — \(subtitle)" }
            if let url = entity.url { text += "\n\(url)" }
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    func cancel() {
        cancelAgentQueue(reason: "cancelled")
    }

    func cancelToolConfirmation() {
        cancelAgentQueue(reason: "cancelled")
    }

    private func cancelAgentQueue(reason: String) {
        userCancelled = true
        speechInput.stopListening()
        toolConfirmation.cancel()
        actionQueue.cancelAll()
        agentPanic.disarm()
        networkTask?.cancel()
        networkTask = nil
        statusMessage = reason == "cancelled" ? "Action queue cancelled (Esc)" : ""
        if case .streaming = phase {
            phase = .finished(reason: reason)
        }
        onHaloStateChange?(.idle)
    }

    func confirmToolEarly() {
        toolConfirmation.confirmEarly()
    }

    private struct PendingTool {
        let id: String
        let name: String
        let inputJson: String
        let sessionId: String
        let tier: String
    }

    private func beginAsk(prompt: String, chip: ChipIntent?) {
        self.prompt = ""
        userCancelled = false
        toolConfirmation.reset()
        actionQueue.beginSession()
        agentPanic.arm { [weak self] in
            self?.cancelAgentQueue(reason: "cancelled")
        }
        networkTask?.cancel()
        onRequestStart?()

        askCount += 1
        if askCount > 1 || isCompanionPinned {
            refreshLiveContext()
        }

        phase = .streaming
        answer = ""
        citationLabels = [:]
        statusMessage = "Sending to Gemini agent…"
        onHaloStateChange?(.thinking)

        let client = backendClient

        networkTask = Task.detached(priority: .userInitiated) {
            guard let request = await self.buildAskRequest(prompt: prompt, chip: chip) else {
                return
            }
            do {
                try await self.runAgentLoop(initialRequest: request, client: client)
            } catch is CancellationError {
                let cancelled = await MainActor.run { self.userCancelled }
                guard !cancelled else { return }
                await MainActor.run {
                    self.statusMessage = ""
                    self.phase = .errored(message: "Request was interrupted.")
                    self.onHaloStateChange?(.idle)
                }
            } catch {
                let cancelled = await MainActor.run { self.userCancelled }
                guard !cancelled else { return }
                await MainActor.run {
                    self.statusMessage = ""
                    self.phase = .errored(message: error.localizedDescription)
                    self.onHaloStateChange?(.idle)
                }
            }
        }
    }

    private func buildAskRequest(prompt: String, chip: ChipIntent?) async -> AskRequest? {
        let location = LocationProvider.shared.currentLocation()
        actionExecutor.userLocation = location

        let resolvedPrompt = EntityResolver.resolve(prompt: prompt, entities: entities)
        let isAutomation = AgentModeResolver.resolvesToAutomation(
            prompt: resolvedPrompt,
            chip: chip
        )
        actionExecutor.computerUseMode = isAutomation

        var imageB64: String?
        var imageMime: String?
        var screenWidth: Int?
        var screenHeight: Int?

        if isAutomation {
            if let capture = await ScreenCapturer().captureMainDisplay(
                longEdge: ScreenCaptureSettings.longEdge,
                format: .jpeg
            ) {
                imageB64 = capture.b64
                imageMime = capture.mime
                screenWidth = capture.width
                screenHeight = capture.height
                actionExecutor.screenSize = CGSize(
                    width: CGFloat(capture.width),
                    height: CGFloat(capture.height)
                )
            } else {
                statusMessage = ""
                phase = .errored(message:
                    "Screen capture failed. Grant Screen Recording permission in System Settings."
                )
                onHaloStateChange?(.idle)
                agentPanic.disarm()
                actionQueue.endSession()
                return nil
            }
        } else if Self.shouldAttachImage(
            for: chip,
            includeScreenshot: includeScreenshot,
            imageB64: context.imagePngBase64
        ) {
            if let region = await ScreenCapturer().capture(
                regionAround: context.clickPoint,
                size: ScreenCaptureSettings.longEdge,
                format: .jpeg
            ) {
                imageB64 = region
                imageMime = "image/jpeg"
            } else if Self.isValidImage(context.imagePngBase64) {
                imageB64 = context.imagePngBase64
                imageMime = "image/png"
            }
        }

        return AskRequest(
            prompt: resolvedPrompt,
            chipIntent: chip,
            axSnapshot: context.axSnapshot,
            imageB64: imageB64,
            imageMime: imageMime,
            appContext: context.appContext,
            ambientSummary: AmbientBuffer.shared.summarize(),
            location: location,
            adapterHint: AppAdapterRegistry.hint(for: context.appContext.bundleId),
            panelSessionId: panelSessionId,
            refreshContext: askCount > 1,
            entityContext: entities.map(EntityContextEntry.init),
            screenWidth: screenWidth,
            screenHeight: screenHeight
        )
    }

    private func runDirectTool(name: String, input: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let json = String(data: data, encoding: .utf8) else { return }
        Task {
            _ = try? await actionExecutor.execute(toolName: name, inputJson: json)
            await MainActor.run { self.pinCompanion() }
        }
    }

    private func ingestEntities(from text: String, toolName: String? = nil) {
        let kind: PanelEntity.Kind = {
            switch toolName {
            case "search_places": return .place
            case "search_web": return .link
            default: return .generic
            }
        }()
        let extracted = EntityExtractor.extract(from: text, kind: kind)
        guard !extracted.isEmpty else { return }
        entities = EntityStore.merge(existing: entities, new: extracted)
    }

    private func refreshLiveContext() {
        context.appContext = ForegroundAppInspector().currentContext()
    }

    private func runAgentLoop(
        initialRequest: AskRequest,
        client: BackendClient
    ) async throws {
        var request: AskRequest? = initialRequest
        var continueReq: AgentContinueRequest?
        var turns = 0
        var usedCompanionTools: [String] = []

        while turns < 10 {
            turns += 1
            var tokenCount = 0
            var pendingTools: [PendingTool] = []
            var finishReason = "stop"
            var sessionId: String?

            let handleEvent: @MainActor (SseEvent) -> Void = { event in
                guard !self.userCancelled else { return }
                switch event {
                case .token(let text):
                    tokenCount += 1
                    if tokenCount == 1 { self.statusMessage = "" }
                    self.answer.append(text)
                case .toolCall(let name, let inputJson, let id, let sid, let tier):
                    pendingTools.append(PendingTool(
                        id: id, name: name, inputJson: inputJson, sessionId: sid, tier: tier
                    ))
                    usedCompanionTools.append(name)
                case .citation(let itemId, _):
                    if self.citationLabels[itemId] == nil {
                        self.citationLabels[itemId] = "Source"
                    }
                case .error(let message):
                    self.statusMessage = ""
                    self.phase = .errored(message: message)
                    self.onHaloStateChange?(.idle)
                case .done(let reason, let sid, let mode):
                    finishReason = reason
                    sessionId = sid
                    self.actionExecutor.computerUseMode = mode == "automation"
                    self.statusMessage = ""
                }
            }

            if let req = request {
                try await client.streamAsk(req, onEvent: handleEvent)
            } else if let cont = continueReq {
                try await client.streamAgentContinue(cont, onEvent: handleEvent)
            }

            let cancelled = await MainActor.run { self.userCancelled }
            guard !cancelled else { return }

            if case .errored = await MainActor.run(body: { self.phase }) {
                return
            }

            if finishReason == "tool_use", !pendingTools.isEmpty,
               let sid = sessionId ?? pendingTools.first?.sessionId {
                actionQueue.enqueue(pendingTools.count)
                statusMessage = "Running action…"
                onHaloStateChange?(.acting)
                onRequestStart?()

                let confirmTools = pendingTools.map {
                    ToolConfirmationCoordinator.PendingTool(
                        id: $0.id,
                        name: $0.name,
                        inputJson: $0.inputJson,
                        tier: ToolConfirmationCoordinator.ToolTier(raw: $0.tier)
                    )
                }

                guard var results = await toolConfirmation.confirmAndExecute(
                    tools: confirmTools,
                    executor: actionExecutor,
                    foregroundBundleId: context.appContext.bundleId
                ) else {
                    cancelAgentQueue(reason: "cancelled")
                    return
                }

                let ranComputerUse = pendingTools.contains {
                    ComputerUseActions.isComputerUseTool($0.name)
                }
                if actionExecutor.computerUseMode,
                   ranComputerUse,
                   let capture = await ScreenCapturer().captureMainDisplay(
                       longEdge: ScreenCaptureSettings.longEdge,
                       format: .jpeg
                   ) {
                    actionExecutor.screenSize = CGSize(
                        width: CGFloat(capture.width),
                        height: CGFloat(capture.height)
                    )
                    results = results.map { result in
                        guard ComputerUseActions.isComputerUseTool(result.name) else {
                            return result
                        }
                        return AgentContinueRequest.ToolResult(
                            id: result.id,
                            name: result.name,
                            result: result.result,
                            screenshotB64: capture.b64,
                            screenshotMime: capture.mime,
                            screenWidth: capture.width,
                            screenHeight: capture.height
                        )
                    }
                }

                for (tool, result) in zip(pendingTools, results) {
                    if ["search_places", "search_web"].contains(tool.name),
                       case .string(let text) = result.result {
                        ingestEntities(from: text, toolName: tool.name)
                    }
                }

                actionQueue.markExecuted(pendingTools.count)
                statusMessage = ""

                request = nil
                continueReq = AgentContinueRequest(sessionId: sid, toolResults: results)
                onHaloStateChange?(.thinking)
                continue
            }

            agentPanic.disarm()
            actionQueue.endSession()

            if tokenCount == 0 && answer.isEmpty {
                phase = .errored(message:
                    "No response received. Confirm the backend is running."
                )
                onHaloStateChange?(.idle)
            } else {
                ingestEntities(from: answer)
                phase = .finished(reason: finishReason)
                if usedCompanionTools.contains(where: { Self.companionTools.contains($0) }) {
                    pinCompanion()
                }
                let hasActionChip = chips.contains {
                    $0 == .clickItForMe || $0 == .fillWithMyInfo
                }
                onHaloStateChange?(hasActionChip ? .suggestion : .idle)
            }
            return
        }

        agentPanic.disarm()
        actionQueue.endSession()
        phase = .errored(message: "Agent exceeded maximum turns.")
        onHaloStateChange?(.idle)
    }

    private func pinCompanion() {
        guard !isCompanionPinned else { return }
        isCompanionPinned = true
        onCompanionPin?()
    }

    private static func shouldAttachImage(
        for chip: ChipIntent?,
        includeScreenshot: Bool,
        imageB64: String?
    ) -> Bool {
        guard isValidImage(imageB64) else { return false }
        if let chip {
            switch chip {
            case .describe, .ocr, .explainChart, .findSimilar:
                return true
            default:
                return false
            }
        }
        return includeScreenshot
    }

    private static func isValidImage(_ b64: String?) -> Bool {
        ScreenCapturer.isValidImageBase64(b64)
    }

    private func previewify(_ s: String) -> String {
        let collapsed = s.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > 120
            ? String(collapsed.prefix(120)) + "…"
            : collapsed
    }
}
