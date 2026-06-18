import Foundation

/// Phase 2: pure chunking logic, kept separate so it's easy to test.
///
/// Strategy: paragraph-aware, ~500-token soft target with ~50-token
/// overlap between adjacent chunks. We approximate token count as
/// `characters / 4` since `NLTokenizer` is overkill here and the
/// downstream embedder + LLM tokenize again on their side.
public struct Chunker {
    public var targetTokens: Int = 500
    public var overlapTokens: Int = 50

    public init() {}

    public init(targetTokens: Int, overlapTokens: Int) {
        self.targetTokens = targetTokens
        self.overlapTokens = overlapTokens
    }

    public struct Chunk: Equatable, Sendable {
        public let text: String
        public let estimatedTokens: Int

        public init(text: String, estimatedTokens: Int) {
            self.text = text
            self.estimatedTokens = estimatedTokens
        }
    }

    public func chunk(_ text: String) -> [Chunk] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        // Split on blank-line paragraphs first.
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [Chunk] = []
        var current: [String] = []
        var currentTokens = 0

        func flush() {
            guard !current.isEmpty else { return }
            let joined = current.joined(separator: "\n\n")
            chunks.append(
                Chunk(text: joined, estimatedTokens: currentTokens)
            )
        }

        for paragraph in paragraphs {
            let paraTokens = estimateTokens(paragraph)
            if currentTokens + paraTokens > targetTokens, !current.isEmpty {
                flush()
                // Carry overlap from the tail of the previous chunk.
                let tail = takeOverlap(from: current, overlap: overlapTokens)
                current = tail
                currentTokens = tail.reduce(0) { $0 + estimateTokens($1) }
            }
            // If a single paragraph is huge, hard-split it on sentences.
            if paraTokens > targetTokens * 2 {
                if !current.isEmpty {
                    flush()
                    current.removeAll()
                    currentTokens = 0
                }
                for piece in splitLargeParagraph(paragraph) {
                    let pieceTokens = estimateTokens(piece)
                    chunks.append(Chunk(text: piece, estimatedTokens: pieceTokens))
                }
            } else {
                current.append(paragraph)
                currentTokens += paraTokens
            }
        }
        flush()

        return chunks
    }

    public func estimateTokens(_ s: String) -> Int {
        max(1, s.count / 4)
    }

    private func takeOverlap(from paragraphs: [String], overlap: Int) -> [String] {
        var tail: [String] = []
        var tokens = 0
        for paragraph in paragraphs.reversed() {
            tokens += estimateTokens(paragraph)
            tail.insert(paragraph, at: 0)
            if tokens >= overlap { break }
        }
        return tail
    }

    private func splitLargeParagraph(_ paragraph: String) -> [String] {
        let sentences = paragraph
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // A blob with no sentence delimiters (e.g. minified code, a long
        // token stream) yields a single "sentence" that's still huge.
        // Fall back to a hard character split so no chunk can blow the
        // budget.
        guard sentences.count > 1 else {
            return hardSplitByCharacters(paragraph)
        }

        var out: [String] = []
        var current: [String] = []
        var currentTokens = 0
        for sentence in sentences {
            // Even an individual sentence can exceed the target; hard-split it.
            if estimateTokens(sentence) > targetTokens {
                if !current.isEmpty {
                    out.append(current.joined(separator: ". ") + ".")
                    current.removeAll()
                    currentTokens = 0
                }
                out.append(contentsOf: hardSplitByCharacters(sentence))
                continue
            }
            let sentenceTokens = estimateTokens(sentence)
            if currentTokens + sentenceTokens > targetTokens, !current.isEmpty {
                out.append(current.joined(separator: ". ") + ".")
                current.removeAll()
                currentTokens = 0
            }
            current.append(sentence)
            currentTokens += sentenceTokens
        }
        if !current.isEmpty {
            out.append(current.joined(separator: ". ") + ".")
        }
        return out
    }

    /// Last-resort splitter: cut a string into pieces of at most
    /// `targetTokens` worth of characters, preferring to break on the
    /// nearest whitespace so we don't slice through a word.
    private func hardSplitByCharacters(_ text: String) -> [String] {
        let maxChars = max(1, targetTokens * 4)
        var pieces: [String] = []
        var remainder = Substring(text)

        while remainder.count > maxChars {
            let hardEnd = remainder.index(remainder.startIndex, offsetBy: maxChars)
            // Try to back up to the last whitespace within the window so
            // we break on a word boundary when one exists.
            let window = remainder[remainder.startIndex..<hardEnd]
            let breakPoint = window.lastIndex(where: { $0 == " " || $0 == "\n" })
                .map { remainder.index(after: $0) } ?? hardEnd
            let piece = remainder[remainder.startIndex..<breakPoint]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }
            remainder = remainder[breakPoint...]
        }

        let tail = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }
}
