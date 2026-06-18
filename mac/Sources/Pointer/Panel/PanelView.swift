import SwiftUI

/// The chips-first SwiftUI panel. Layout intentionally compact and
/// playful (rounded blob shape via `RoundedRectangle` + custom shadow).
///
/// Visual style is a placeholder; `Phase 5 -> visual-style` task swaps
/// in the final accent color, blob asymmetry, and motion polish.
struct PanelView: View {
    @ObservedObject var viewModel: PanelViewModel
    let onDismiss: () -> Void

    @FocusState private var freeTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                contextStrip
                Spacer(minLength: 0)
                if viewModel.isCompanionPinned {
                    Button("Close") { onDismiss() }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                }
            }
            Divider().opacity(0.5)
            // Initial prompt only — once an answer is streaming/done, followUpRow
            // at the bottom takes over so we don't show two identical fields.
            if viewModel.showFreeText, !viewModel.showFollowUpInput {
                freeTextRow
                if viewModel.hasScreenshot {
                    screenshotToggle
                }
            } else if !viewModel.showFollowUpInput {
                chipsRow
                slashHint
            }
            if let banner = viewModel.toolConfirmation.banner {
                toolConfirmationBanner(banner)
            }
            // The streaming placeholder (in the scroll area) already echoes the
            // status message, so skip this row while it's visible — otherwise the
            // same "Sending to Gemini agent…" spinner shows up twice.
            if !showsStreamingPlaceholder {
                if !viewModel.statusMessage.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(viewModel.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if let queue = viewModel.actionQueue.statusLabel {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(queue)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let speechHint = viewModel.speechInput.statusHint, !speechHint.isEmpty {
                HStack(spacing: 6) {
                    if viewModel.speechInput.isListening || viewModel.speechInput.isTranscribing {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: viewModel.speechInput.isListening ? "mic.fill" : "waveform")
                        .imageScale(.small)
                        .foregroundStyle(viewModel.speechInput.isListening ? .red : .secondary)
                    Text(speechHint)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            viewModel.speechInput.errorMessage != nil ? .orange : .secondary
                        )
                        .lineLimit(2)
                }
            }
            if hasScrollableContent {
                Divider().opacity(0.5)
                scrollableContentArea
            }
            if hasScrollableContent {
                actionRow
            }
            if viewModel.showFollowUpInput {
                followUpRow
            }
            if case .errored(let message) = viewModel.phase, viewModel.answer.isEmpty {
                Divider().opacity(0.5)
                errorArea(message)
            }
            footerHint
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: PanelLayout.width, alignment: .topLeading)
        .background(panelBackground)
        .overlay(panelStrokeOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 10)
        .onExitCommand(perform: onDismiss)
        .onKeyPress(.return) {
            guard viewModel.toolConfirmation.banner != nil else { return .ignored }
            viewModel.confirmToolEarly()
            return .handled
        }
    }

    // MARK: - Sections

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "cursorarrow.click.2")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(viewModel.contextStrip)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Image(systemName: "line.3.horizontal")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)
                    .help("Drag to move")
            }
            if let selection = viewModel.selectionPreview {
                Text(selection)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(WindowDragHandle())
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(viewModel.chips.enumerated()), id: \.offset) { idx, chip in
                ChipButton(
                    title: chip.displayName,
                    isPrimary: idx == 0,
                    action: { viewModel.runChip(chip) }
                )
                .keyboardShortcut(idx == 0 ? .defaultAction : nil)
            }
        }
    }

    private var followUpRow: some View {
        HStack(spacing: 6) {
            TextField(
                voicePlaceholder(default: followUpPlaceholder),
                text: $viewModel.prompt
            )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($freeTextFocused)
                .onSubmit { viewModel.submitFollowUp() }
            voiceButton
            Button("Send") { viewModel.submitFollowUp() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.vertical, 2)
    }

    private var slashHint: some View {
        Button {
            viewModel.showFreeText = true
            DispatchQueue.main.async { freeTextFocused = true }
        } label: {
            Text("/ to type a custom prompt")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("/", modifiers: [])
    }

    private var freeTextRow: some View {
        HStack(spacing: 6) {
            TextField(
                voicePlaceholder(default: "Ask anything…"),
                text: $viewModel.prompt
            )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($freeTextFocused)
                .onSubmit { viewModel.submitFreeText() }
            voiceButton
            Button("Send") { viewModel.submitFreeText() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            Button {
                viewModel.showFreeText = false
                viewModel.prompt = ""
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .help("Back to chips")
        }
        .padding(.vertical, 4)
    }

    private var screenshotToggle: some View {
        Toggle(isOn: $viewModel.includeScreenshot) {
            Label("Include screenshot", systemImage: "photo.on.rectangle")
                .font(.system(size: 11))
        }
        .toggleStyle(.checkbox)
    }

    private var hasScrollableContent: Bool {
        !viewModel.entities.isEmpty
            || !viewModel.answer.isEmpty
            || viewModel.phase == .streaming
    }

    /// True while the scroll area shows the streaming spinner+status (no answer
    /// text yet). The top status row is suppressed in this state to avoid a
    /// duplicate "Sending to Gemini agent…" line.
    private var showsStreamingPlaceholder: Bool {
        viewModel.answer.isEmpty && viewModel.phase == .streaming
    }

    private var scrollableContentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.entities.isEmpty {
                    EntityCardsView(entities: viewModel.entities) { entity, action in
                        viewModel.runEntityAction(entity, action: action)
                    }
                }
                if !viewModel.answer.isEmpty || viewModel.phase == .streaming {
                    if viewModel.answer.isEmpty, viewModel.phase == .streaming {
                        streamingPlaceholder
                    } else {
                        FormattedAnswerView(
                            text: viewModel.answer,
                            citationLabels: viewModel.citationLabels
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
        .frame(maxHeight: PanelLayout.maxScrollHeight)
    }

    private var streamingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(viewModel.statusMessage.isEmpty ? "Thinking…" : viewModel.statusMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.answer, forType: .string)
            }
            .controlSize(.small)
            .disabled(viewModel.answer.isEmpty)

            if case .errored(let message) = viewModel.phase {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            if viewModel.phase == .streaming {
                Button("Stop") { viewModel.cancel() }
                    .controlSize(.small)
            }
        }
    }

    private func errorArea(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't reach the assistant")
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Is the backend running? Try: cd backend && npm run dev")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func toolConfirmationBanner(
        _ banner: ToolConfirmationCoordinator.BannerState
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: banner.tier == .destructive ? "exclamationmark.shield" : "hand.tap")
                .foregroundStyle(banner.tier == .destructive ? .orange : .accentColor)
                .imageScale(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.tier == .destructive ? "Confirm action" : "Running action")
                    .font(.system(size: 11, weight: .semibold))
                Text(banner.message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let countdown = banner.countdown {
                Text(String(format: "%.0fs", countdown.rounded(.up)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Run") { viewModel.confirmToolEarly() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                Button("Cancel") { viewModel.cancelToolConfirmation() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 2) {
            if viewModel.toolConfirmation.banner != nil {
                Text("↩ run now · Esc cancel · auto-runs in 5s")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else if viewModel.isCompanionPinned {
                Text("Companion mode · tap mic twice to speak · Esc or Close to dismiss")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Click outside or Esc to dismiss · / or tap mic twice to speak")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Voice

    private var followUpPlaceholder: String {
        viewModel.isCompanionPinned ? "Ask anything…" : "Ask a follow-up…"
    }

    private func voicePlaceholder(default text: String) -> String {
        if viewModel.speechInput.isListening { return "Recording…" }
        if viewModel.speechInput.isTranscribing { return "Transcribing…" }
        return text
    }

    private var voiceButton: some View {
        Button {
            viewModel.toggleVoiceInput()
        } label: {
            Image(systemName: viewModel.speechInput.isListening ? "mic.fill" : "mic")
                .imageScale(.small)
                .foregroundStyle(
                    viewModel.speechInput.isListening || viewModel.speechInput.isTranscribing
                        ? Color.red : Color.secondary
                )
                .disabled(viewModel.speechInput.isTranscribing)
        }
        .buttonStyle(.plain)
        .help("Tap to record, tap again to finish")
    }

    // MARK: - Decoration

    private var panelBackground: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            // A subtle warm tint so the panel feels playful rather than glassy-corporate.
            // Final accent applied in the visual-style polish phase.
            Color.accentColor.opacity(0.04)
        }
    }

    private var panelStrokeOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
    }
}

// MARK: - Chip button

private struct ChipButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isPrimary ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isPrimary ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isPrimary ? Color.accentColor : Color.gray.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Visual effect bridge

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
