import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DrawerViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case streaming
        case finished
        case errored(message: String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var answer: String = ""
    @Published private(set) var statusMessage: String = ""
    @Published var prompt: String = ""
    @Published var selectedItemIds: Set<UUID> = []
    @Published var isDropTargeted: Bool = false
    @Published var importError: String?
    @Published var highlightedItemId: UUID?
    @Published var highlightedChunkId: UUID?

    let store: DrawerStore
    var activeDrawerId: Binding<UUID?> {
        Binding(
            get: { self.store.activeDrawerId },
            set: { if let id = $0 { self.store.setActiveDrawer(id) } }
        )
    }
    private let backendClient: BackendClient
    private var networkTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(store: DrawerStore, backendClient: BackendClient) {
        self.store = store
        self.backendClient = backendClient
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var activeItems: [DrawerItem] {
        store.activeItems
    }

    var citationLabels: [String: String] {
        Dictionary(uniqueKeysWithValues: store.activeItems.map {
            ($0.id.uuidString, $0.label)
        })
    }

    func toggleSelection(_ id: UUID) {
        if selectedItemIds.contains(id) {
            selectedItemIds.remove(id)
        } else {
            selectedItemIds.insert(id)
        }
    }

    func selectAll() {
        selectedItemIds = Set(activeItems.map(\.id))
    }

    func runChip(_ chip: DrawerChipIntent) {
        submit(prompt: chip.displayName, chip: chip)
    }

    func submitPrompt() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submit(prompt: trimmed, chip: nil)
    }

    func createDrawer() {
        let count = store.drawers.count + 1
        store.createDrawer(named: "Drawer \(count)")
    }

    func pasteFromClipboard() async {
        do {
            try await store.pasteFromClipboard()
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    func focusCitation(itemId: String, chunkId: String?) {
        guard let id = UUID(uuidString: itemId) else { return }
        highlightedItemId = id
        highlightedChunkId = chunkId.flatMap(UUID.init(uuidString:))
        selectedItemIds.insert(id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self.highlightedItemId == id {
                self.highlightedItemId = nil
                self.highlightedChunkId = nil
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        Task {
            for provider in fileProviders {
                do {
                    let url = try await Self.loadFileURL(from: provider)
                    try await store.importFile(url: url)
                    importError = nil
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
        return true
    }

    func removeItem(_ id: UUID) {
        store.removeItem(id)
        selectedItemIds.remove(id)
    }

    private func submit(prompt: String, chip: DrawerChipIntent?) {
        guard let request = store.buildQueryRequest(
            prompt: prompt,
            chip: chip,
            selectedItemIds: selectedItemIds
        ) else {
            phase = .errored(message: "Add files to the drawer and select at least one.")
            return
        }

        networkTask?.cancel()
        phase = .streaming
        answer = ""
        statusMessage = "Querying Gemini…"
        let client = backendClient

        networkTask = Task.detached(priority: .userInitiated) {
            var tokenCount = 0
            do {
                try await client.streamDrawerQuery(request) { @MainActor event in
                    switch event {
                    case .token(let text):
                        tokenCount += 1
                        if tokenCount == 1 { self.statusMessage = "" }
                        self.answer.append(text)
                    case .citation:
                        break
                    case .toolCall(let name, _, _, _, _):
                        if name == "search_web" {
                            self.statusMessage = "Searching the web…"
                        }
                    case .error(let message):
                        self.statusMessage = ""
                        self.phase = .errored(message: message)
                    case .done(_, _, _):
                        self.statusMessage = ""
                        if tokenCount == 0 && self.answer.isEmpty {
                            self.phase = .errored(message: "Empty response from backend.")
                        } else {
                            self.phase = .finished
                        }
                    }
                }
                await MainActor.run {
                    if case .streaming = self.phase, !self.answer.isEmpty {
                        self.statusMessage = ""
                        self.phase = .finished
                    }
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = ""
                    self.phase = .errored(message: error.localizedDescription)
                }
            }
        }
    }

    private static func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(throwing: DrawerStoreError.unsupported("Could not read dropped file."))
            }
        }
    }
}
