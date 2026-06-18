import AppKit
import CryptoKit
import Foundation

/// Persistent storage for drawers, items, chunks, and blob files.
@MainActor
public final class DrawerStore: ObservableObject {
    public static let shared = DrawerStore()

    @Published public private(set) var drawers: [Drawer] = []
    @Published public private(set) var items: [DrawerItem] = []
    @Published public var activeDrawerId: UUID?

    private var chunksByItem: [UUID: [DrawerStoredChunk]] = [:]
    private let rootURL: URL
    private let stateURL: URL
    private let blobsURL: URL
    private let chunker = Chunker(targetTokens: 500, overlapTokens: 50)
    private let embedder = Embedder()
    private let maxFileBytes = 10 * 1024 * 1024

    private struct PersistedState: Codable {
        var drawers: [Drawer]
        var items: [DrawerItem]
        var chunksByItem: [UUID: [DrawerStoredChunk]]
        var activeDrawerId: UUID?
    }

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        rootURL = appSupport.appendingPathComponent("Pointer", isDirectory: true)
        stateURL = rootURL.appendingPathComponent("drawer-state.json")
        blobsURL = rootURL.appendingPathComponent("blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        load()
        if drawers.isEmpty {
            let drawer = Drawer(name: "My drawer")
            drawers = [drawer]
            activeDrawerId = drawer.id
            save()
        } else if activeDrawerId == nil {
            activeDrawerId = drawers.first?.id
        }
    }

    public var activeDrawer: Drawer? {
        guard let activeDrawerId else { return nil }
        return drawers.first { $0.id == activeDrawerId }
    }

    public var activeItems: [DrawerItem] {
        guard let activeDrawerId else { return [] }
        return items.filter { $0.drawerId == activeDrawerId }
    }

    public func createDrawer(named: String) {
        let drawer = Drawer(name: named)
        drawers.append(drawer)
        activeDrawerId = drawer.id
        save()
    }

    public func setActiveDrawer(_ id: UUID) {
        activeDrawerId = id
        save()
    }

    public func pasteFromClipboard() async throws {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = Self.parseHttpUrl(trimmed) {
                try await addUrl(url)
                return
            }
            addText(label: "Pasted text", text: trimmed)
            return
        }
        if let png = pasteboard.data(forType: .png) {
            await ingestImageData(png, label: "Pasted image")
        } else if let tiff = pasteboard.data(forType: .tiff),
                  let image = NSImage(data: tiff),
                  let tiffPng = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiffPng),
                  let png = rep.representation(using: .png, properties: [:]) {
            await ingestImageData(png, label: "Pasted image")
        }
    }

    func chunks(for itemId: UUID) -> [DrawerStoredChunk] {
        chunksByItem[itemId] ?? []
    }

    public func importFile(url: URL) async throws {
        guard let drawerId = activeDrawerId else { return }
        let data = try Data(contentsOf: url)
        guard data.count <= maxFileBytes else {
            throw DrawerStoreError.fileTooLarge
        }

        let sha = Self.sha256(data)
        try writeBlob(sha: sha, data: data)

        let filename = url.lastPathComponent
        switch DrawerTextExtractor.extract(filename: filename, data: data) {
        case .text(let text):
            let item = DrawerItem(
                drawerId: drawerId,
                kind: .file,
                label: filename,
                blobSha256: sha,
                sizeBytes: Int64(data.count)
            )
            items.append(item)
            chunksByItem[item.id] = makeChunks(text: text, itemId: item.id)
        case .image:
            await ingestImageData(data, label: filename, drawerId: drawerId, sha: sha)
        case .unsupported(let reason):
            throw DrawerStoreError.unsupported(reason)
        }
        touchDrawer(drawerId)
        save()
    }

    public func addUrl(_ urlString: String) async throws {
        guard let drawerId = activeDrawerId else { return }
        let normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let _ = Self.parseHttpUrl(normalized) else {
            throw DrawerStoreError.unsupported("Invalid URL.")
        }
        let text = try await DrawerUrlFetcher.fetchText(from: normalized)
        let host = URL(string: normalized)?.host ?? normalized
        let item = DrawerItem(
            drawerId: drawerId,
            kind: .url,
            label: host,
            sizeBytes: Int64(text.utf8.count),
            sourceUrl: normalized
        )
        items.append(item)
        chunksByItem[item.id] = makeChunks(text: text, itemId: item.id)
        touchDrawer(drawerId)
        save()
    }

    public func addText(label: String, text: String) {
        guard let drawerId = activeDrawerId, !text.isEmpty else { return }
        let item = DrawerItem(
            drawerId: drawerId,
            kind: .text,
            label: label,
            sizeBytes: Int64(text.utf8.count)
        )
        items.append(item)
        chunksByItem[item.id] = makeChunks(text: text, itemId: item.id)
        touchDrawer(drawerId)
        save()
    }

    public func addImage(label: String, pngBase64: String) {
        guard let drawerId = activeDrawerId,
              ScreenCapturer.isValidPngBase64(pngBase64),
              let data = Data(base64Encoded: pngBase64) else { return }
        Task {
            let sha = Self.sha256(data)
            try? writeBlob(sha: sha, data: data)
            await ingestImageData(data, label: label, drawerId: drawerId, sha: sha)
        }
    }

    public func addFromPanel(context: TriggerContext) {
        if let selected = context.axSnapshot?.selectedText, !selected.isEmpty {
            addText(label: "Selection", text: selected)
        } else if let value = context.axSnapshot?.value, !value.isEmpty,
                  context.axSnapshot?.redacted != true {
            addText(label: "Context", text: value)
        }
        if let image = context.imagePngBase64 {
            addImage(label: "Screenshot", pngBase64: image)
        }
    }

    public func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        chunksByItem[id] = nil
        save()
    }

    public func buildQueryRequest(
        prompt: String,
        chip: DrawerChipIntent?,
        selectedItemIds: Set<UUID>
    ) -> DrawerQueryRequest? {
        guard let drawerId = activeDrawerId,
              let drawer = drawers.first(where: { $0.id == drawerId }) else {
            return nil
        }

        let selected = activeItems.filter {
            selectedItemIds.isEmpty || selectedItemIds.contains($0.id)
        }
        guard !selected.isEmpty else { return nil }

        let rag = DrawerRAG()
        let retrieved = rag.retrieve(
            prompt: prompt,
            items: selected.filter { $0.kind != .image },
            chunksByItem: chunksByItem
        )
        let retrievedByItem = Dictionary(grouping: retrieved, by: \.itemId)

        var wireItems: [DrawerQueryItem] = []
        for item in selected {
            switch item.kind {
            case .file, .text:
                let chunks = (retrievedByItem[item.id] ?? chunksByItem[item.id] ?? [])
                    .prefix(8)
                    .map {
                        DrawerQueryChunk(
                            chunkId: $0.id.uuidString,
                            text: String($0.text.prefix(8_000))
                        )
                    }
                guard !chunks.isEmpty else { continue }
                wireItems.append(.text(
                    itemId: item.id.uuidString,
                    label: item.label,
                    chunks: Array(chunks)
                ))
            case .url:
                guard let url = item.sourceUrl else { continue }
                let chunks = (retrievedByItem[item.id] ?? chunksByItem[item.id] ?? [])
                    .prefix(8)
                    .map {
                        DrawerQueryChunk(
                            chunkId: $0.id.uuidString,
                            text: String($0.text.prefix(8_000))
                        )
                    }
                wireItems.append(.url(
                    itemId: item.id.uuidString,
                    label: item.label,
                    url: url,
                    extractedTextChunks: chunks.isEmpty ? nil : Array(chunks)
                ))
            case .image:
                guard let wire = imageWireItem(for: item) else { continue }
                wireItems.append(wire)
            }
        }

        guard !wireItems.isEmpty else { return nil }
        return DrawerQueryRequest(
            drawerId: drawerId.uuidString,
            drawerName: drawer.name,
            prompt: prompt,
            chipIntent: chip,
            items: wireItems
        )
    }

    private func makeChunks(text: String, itemId: UUID) -> [DrawerStoredChunk] {
        chunker.chunk(text).enumerated().map { index, chunk in
            DrawerStoredChunk(
                itemId: itemId,
                ord: index,
                text: chunk.text,
                tokenEst: chunk.estimatedTokens,
                embedding: embedder.embed(chunk.text)
            )
        }
    }

    private func touchDrawer(_ id: UUID) {
        guard let index = drawers.firstIndex(where: { $0.id == id }) else { return }
        drawers[index].updatedAt = .now
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return
        }
        drawers = state.drawers
        items = state.items
        chunksByItem = state.chunksByItem
        activeDrawerId = state.activeDrawerId
    }

    private func save() {
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let state = PersistedState(
            drawers: drawers,
            items: items,
            chunksByItem: chunksByItem,
            activeDrawerId: activeDrawerId
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    private func writeBlob(sha: String, data: Data) throws {
        let path = blobsURL.appendingPathComponent(sha)
        guard !FileManager.default.fileExists(atPath: path.path) else { return }
        try data.write(to: path, options: .atomic)
    }

    private func imageWireItem(for item: DrawerItem) -> DrawerQueryItem? {
        guard let sha = item.blobSha256 else { return nil }
        let path = blobsURL.appendingPathComponent(sha)
        guard let data = try? Data(contentsOf: path) else { return nil }
        let ext = (item.label as NSString).pathExtension.lowercased()
        let mime: String
        switch ext {
        case "jpg", "jpeg": mime = "image/jpeg"
        case "webp": mime = "image/webp"
        default: mime = "image/png"
        }
        let ocr = (chunksByItem[item.id] ?? []).map(\.text).joined(separator: "\n")
        return .image(
            itemId: item.id.uuidString,
            label: item.label,
            imageB64: data.base64EncodedString(),
            imageMime: mime,
            ocrText: ocr.isEmpty ? nil : String(ocr.prefix(4_000))
        )
    }

    private func ingestImageData(
        _ data: Data,
        label: String,
        drawerId: UUID? = nil,
        sha: String? = nil
    ) async {
        guard let drawerId = drawerId ?? activeDrawerId else { return }
        let blobSha = sha ?? Self.sha256(data)
        if sha == nil { try? writeBlob(sha: blobSha, data: data) }
        let item = DrawerItem(
            drawerId: drawerId,
            kind: .image,
            label: label,
            blobSha256: blobSha,
            sizeBytes: Int64(data.count)
        )
        items.append(item)
        if let ocr = await DrawerImageOCR.recognize(pngData: data) {
            chunksByItem[item.id] = makeChunks(text: ocr, itemId: item.id)
        }
        touchDrawer(drawerId)
        save()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func parseHttpUrl(_ string: String) -> String? {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return string
    }
}

enum DrawerStoreError: Error, LocalizedError {
    case fileTooLarge
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "File is too large (max 10 MB)."
        case .unsupported(let reason):
            return reason
        }
    }
}
