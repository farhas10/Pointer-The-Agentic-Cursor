import Foundation

/// Retrieves the most relevant text chunks for a drawer query prompt.
struct DrawerRAG {
    private let embedder = Embedder()
    var topK: Int = 8

    func retrieve(
        prompt: String,
        items: [DrawerItem],
        chunksByItem: [UUID: [DrawerStoredChunk]]
    ) -> [DrawerStoredChunk] {
        let candidates = items.flatMap { item in
            (chunksByItem[item.id] ?? []).map { ($0, item.id) }
        }
        guard !candidates.isEmpty else { return [] }

        if let queryVec = embedder.embed(prompt) {
            let scored = candidates.compactMap { chunk, _ -> (DrawerStoredChunk, Float)? in
                guard let emb = chunk.embedding else { return nil }
                return (chunk, Embedder.cosine(queryVec, emb))
            }
            if !scored.isEmpty {
                return scored
                    .sorted { $0.1 > $1.1 }
                    .prefix(topK)
                    .map(\.0)
            }
        }

        // Fallback: first chunks from each item until topK.
        var out: [DrawerStoredChunk] = []
        for item in items {
            guard out.count < topK else { break }
            if let first = chunksByItem[item.id]?.first {
                out.append(first)
            }
        }
        return out
    }
}

/// A text chunk stored for an item, with an optional embedding vector.
struct DrawerStoredChunk: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var itemId: UUID
    var ord: Int
    var text: String
    var tokenEst: Int
    var embedding: [Float]?

    init(
        id: UUID = UUID(),
        itemId: UUID,
        ord: Int,
        text: String,
        tokenEst: Int,
        embedding: [Float]? = nil
    ) {
        self.id = id
        self.itemId = itemId
        self.ord = ord
        self.text = text
        self.tokenEst = tokenEst
        self.embedding = embedding
    }
}
