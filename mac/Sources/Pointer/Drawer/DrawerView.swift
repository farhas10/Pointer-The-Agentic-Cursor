import SwiftUI
import UniformTypeIdentifiers

struct DrawerView: View {
    @ObservedObject var viewModel: DrawerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dropZone
            if let error = viewModel.importError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            itemList
            Divider().opacity(0.4)
            chipsRow
            promptRow
            if !viewModel.statusMessage.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if !viewModel.answer.isEmpty || viewModel.phase == .streaming {
                answerArea
            } else if case .errored(let message) = viewModel.phase {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minWidth: 360, minHeight: 500)
        .background(VisualEffectBackground())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Drawer")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    viewModel.createDrawer()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New drawer")
                Button {
                    Task { await viewModel.pasteFromClipboard() }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")
            }
            if viewModel.store.drawers.count > 1 {
                Picker("Workspace", selection: viewModel.activeDrawerId) {
                    ForEach(viewModel.store.drawers) { drawer in
                        Text(drawer.name).tag(Optional(drawer.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            } else if let name = viewModel.store.activeDrawer?.name {
                Text(name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("Drop or paste files to give Gemini context")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(WindowDragHandle())
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(viewModel.isDropTargeted
                          ? Color.accentColor.opacity(0.08)
                          : Color.primary.opacity(0.03))
            )
            .frame(height: 72)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.down.doc")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                    Text("Drop PDFs, DOCX, images, URLs, or code")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(
                of: [UTType.fileURL],
                isTargeted: $viewModel.isDropTargeted
            ) { providers in
                viewModel.handleDrop(providers)
            }
    }

    private var itemList: some View {
        Group {
            if viewModel.activeItems.isEmpty {
                Text("No files yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(viewModel.activeItems) { item in
                                itemRow(item)
                                    .id(item.id)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .onChange(of: viewModel.highlightedItemId) { _, newId in
                        guard let newId else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func itemRow(_ item: DrawerItem) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { viewModel.selectedItemIds.contains(item.id) },
                set: { _ in viewModel.toggleSelection(item.id) }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: iconName(for: item.kind))
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(kindLabel(item))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .toggleStyle(.checkbox)

            Button {
                viewModel.removeItem(item.id)
            } label: {
                Image(systemName: "trash")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    viewModel.highlightedItemId == item.id
                        ? Color.accentColor.opacity(0.18)
                        : Color.primary.opacity(0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    viewModel.highlightedItemId == item.id
                        ? Color.accentColor.opacity(0.5)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(DrawerChipIntent.allCases.enumerated()), id: \.offset) { idx, chip in
                Button(chip.displayName) {
                    viewModel.runChip(chip)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular))
            }
        }
    }

    private var promptRow: some View {
        HStack(spacing: 6) {
            TextField("Ask about your files…", text: $viewModel.prompt)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit { viewModel.submitPrompt() }
            Button("Ask") { viewModel.submitPrompt() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var answerArea: some View {
        ScrollView {
            FormattedAnswerView(
                text: viewModel.answer,
                citationLabels: viewModel.citationLabels,
                onCitationTap: { itemId, chunkId in
                    viewModel.focusCitation(itemId: itemId, chunkId: chunkId)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: 260)
    }

    private var footer: some View {
        HStack {
            if !viewModel.activeItems.isEmpty {
                Button("Select all") { viewModel.selectAll() }
                    .controlSize(.small)
                    .font(.system(size: 10))
            }
            Spacer()
            Text("⌘⇧D to toggle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func iconName(for kind: DrawerItemKind) -> String {
        switch kind {
        case .file: return "doc"
        case .image: return "photo"
        case .text: return "text.alignleft"
        case .url: return "link"
        }
    }

    private func kindLabel(_ item: DrawerItem) -> String {
        if item.kind == .url, let url = item.sourceUrl {
            return url
        }
        let kb = max(1, Int(item.sizeBytes) / 1024)
        return "\(item.kind.rawValue) · \(kb) KB"
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
