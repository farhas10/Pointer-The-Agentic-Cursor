import Foundation
import NaturalLanguage

/// Phase 2: produces embedding vectors using Apple's `NLEmbedding`.
///
/// The default `wordEmbedding(for: .english)` is fine for retrieval
/// over English text; for multilingual drawers we'll fall back to a
/// language-detect-then-embed approach.
public struct Embedder {
    public init() {}

    /// Returns a fixed-size mean-pooled vector for the given text. Returns
    /// nil if no embedding is available for the detected language.
    public func embed(_ text: String) -> [Float]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else {
            return nil
        }
        // Tokenize words; mean-pool their vectors.
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var sum: [Double] = Array(repeating: 0, count: embedding.dimension)
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if let vector = embedding.vector(for: token) {
                for (i, v) in vector.enumerated() {
                    sum[i] += v
                }
                count += 1
            }
            return true
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }

    /// Cosine similarity between two vectors of the same dimension.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "dim mismatch")
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }
}
