import Foundation

/// Parses assistant markdown into a small block model for rich rendering.
enum AnswerMarkdownParser {
    enum Inline: Equatable, Sendable {
        case text(String)
        case bold(String)
        case italic(String)
        case code(String)
        case citation(itemId: String, chunkId: String?)
        case latexInline(String)
        case latexDisplay(String)
    }

    struct CitationRef: Equatable, Sendable {
        var itemId: String
        var chunkId: String?
    }

    enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(body: [Inline], citations: [CitationRef])
        case bulletList(items: [BulletItem])
        case codeBlock(String)
        case mathBlock(String)
    }

    struct BulletItem: Equatable, Sendable {
        var level: Int
        /// Set for `1.` / `2.` style lists.
        var number: Int?
        /// When the bullet starts with `**Label:**`, rendered as a subheading.
        var title: String?
        var body: [Inline]
        var citations: [CitationRef]
    }

    static func parse(_ text: String) -> [Block] {
        let lines = normalizeListBreaks(
            text.replacingOccurrences(of: "\r\n", with: "\n")
        )
        .components(separatedBy: "\n")

        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let level = headingLevel(trimmed) {
                let title = String(trimmed.dropFirst(level + 1))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: title))
                index += 1
                continue
            }

            if listItemPrefix(raw) != nil {
                var items: [BulletItem] = []
                while index < lines.count {
                    let line = lines[index]
                    let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
                    if lineTrimmed.isEmpty { break }
                    guard let next = listItemPrefix(line) else { break }
                    items.append(parseBulletItem(
                        level: next.level,
                        number: next.number,
                        content: next.content
                    ))
                    index += 1
                }
                if !items.isEmpty {
                    blocks.append(.bulletList(items: items))
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    let line = lines[index]
                    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(line)
                    index += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                continue
            }

            if let math = displayMathBlock(in: lines, start: index) {
                blocks.append(.mathBlock(math.content))
                index = math.nextIndex
                continue
            }

            var paragraphLines: [String] = [raw]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty { break }
                if headingLevel(nextTrimmed) != nil { break }
                if listItemPrefix(next) != nil { break }
                if nextTrimmed.hasPrefix("```") { break }
                paragraphLines.append(next)
                index += 1
            }

            if paragraphLines.count == 1,
               let solo = paragraphLines.first?.trimmingCharacters(in: .whitespaces),
               solo.hasSuffix(":"),
               solo.count < 72,
               !solo.contains("**"),
               !solo.contains("[") {
                let title = String(solo.dropLast()).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    blocks.append(.heading(level: 3, text: title))
                    continue
                }
            }

            let joined = paragraphLines.joined(separator: " ")
            let inlines = parseInlines(joined)
            let split = separateCitations(inlines)
            blocks.append(.paragraph(body: split.body, citations: split.citations))
        }

        return blocks
    }

    static func parseInlines(_ text: String) -> [Inline] {
        var inlines: [Inline] = []
        var remaining = Substring(text)

        while !remaining.isEmpty {
            if let latex = nextLaTeX(in: remaining) {
                if latex.start > remaining.startIndex {
                    inlines.append(contentsOf: parseStyledInlines(from: remaining[..<latex.start]))
                }
                switch latex.kind {
                case .inline:
                    inlines.append(.latexInline(latex.content))
                case .display:
                    inlines.append(.latexDisplay(latex.content))
                }
                remaining = remaining[latex.end...]
                continue
            }

            if let delimiter = nextLaTeXDelimiter(in: remaining),
               delimiter > remaining.startIndex {
                inlines.append(contentsOf: parseStyledInlines(from: remaining[..<delimiter]))
                remaining = remaining[delimiter...]
                continue
            }

            inlines.append(contentsOf: parseStyledInlines(from: remaining))
            break
        }

        return dedupeConsecutiveCitations(inlines)
    }

    private static func nextLaTeXDelimiter(in text: Substring) -> Substring.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "$" { return index }
            if text[index] == "\\" {
                let next = text.index(after: index)
                if next < text.endIndex {
                    let marker = text[next]
                    if marker == "(" || marker == "[" { return index }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private enum LaTeXKind {
        case inline
        case display
    }

    private struct LaTeXMatch {
        var kind: LaTeXKind
        var content: String
        var start: Substring.Index
        var end: Substring.Index
    }

    private static func nextLaTeX(in text: Substring) -> LaTeXMatch? {
        var best: LaTeXMatch?

        func consider(_ candidate: LaTeXMatch?) {
            guard let candidate else { return }
            if best == nil || candidate.start < best!.start {
                best = candidate
            }
        }

        consider(matchDoubleDollar(in: text))
        consider(matchSingleDollar(in: text))
        consider(matchDelimiter(in: text, open: "\\(", close: "\\)", kind: .inline))
        consider(matchDelimiter(in: text, open: "\\[", close: "\\]", kind: .display))

        return best
    }

    private static func matchDoubleDollar(in text: Substring) -> LaTeXMatch? {
        guard text.hasPrefix("$$") else { return nil }
        let contentStart = text.index(text.startIndex, offsetBy: 2)
        guard let close = text[contentStart...].range(of: "$$") else { return nil }
        let content = String(text[contentStart..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return LaTeXMatch(
            kind: .display,
            content: content,
            start: text.startIndex,
            end: close.upperBound
        )
    }

    private static func matchSingleDollar(in text: Substring) -> LaTeXMatch? {
        guard text.first == "$", !text.hasPrefix("$$") else { return nil }
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let ch = text[index]
            if ch == "$" {
                let content = String(text[text.index(after: text.startIndex)..<index])
                    .trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty else { return nil }
                return LaTeXMatch(
                    kind: .inline,
                    content: content,
                    start: text.startIndex,
                    end: text.index(after: index)
                )
            }
            index = text.index(after: index)
        }
        return nil
    }

    private static func matchDelimiter(
        in text: Substring,
        open: String,
        close: String,
        kind: LaTeXKind
    ) -> LaTeXMatch? {
        guard text.hasPrefix(open) else { return nil }
        let contentStart = text.index(text.startIndex, offsetBy: open.count)
        guard let closeRange = text[contentStart...].range(of: close) else { return nil }
        let content = String(text[contentStart..<closeRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return LaTeXMatch(
            kind: kind,
            content: content,
            start: text.startIndex,
            end: closeRange.upperBound
        )
    }

    private static func displayMathBlock(
        in lines: [String],
        start: Int
    ) -> (content: String, nextIndex: Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
            let inner = String(trimmed.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespaces)
            guard !inner.isEmpty else { return nil }
            return (inner, start + 1)
        }

        if trimmed == "$$" || trimmed.hasPrefix("$$") {
            var parts: [String] = []
            var index = start
            if trimmed.count > 2, !trimmed.hasSuffix("$$") {
                parts.append(String(trimmed.dropFirst(2)))
            }
            index += 1
            while index < lines.count {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                if line.hasSuffix("$$") {
                    parts.append(String(line.dropLast(2)))
                    index += 1
                    break
                }
                parts.append(line)
                index += 1
            }
            let content = parts.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { return nil }
            return (content, index)
        }

        if trimmed.hasPrefix("\\[") {
            if trimmed.hasSuffix("\\]"), trimmed.count > 4 {
                let inner = String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespaces)
                guard !inner.isEmpty else { return nil }
                return (inner, start + 1)
            }
            var parts: [String] = []
            var index = start
            if trimmed.count > 2 {
                parts.append(String(trimmed.dropFirst(2)))
            }
            index += 1
            while index < lines.count {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                if line.hasSuffix("\\]") {
                    parts.append(String(line.dropLast(2)))
                    index += 1
                    break
                }
                parts.append(line)
                index += 1
            }
            let content = parts.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { return nil }
            return (content, index)
        }

        return nil
    }

    private static func parseStyledInlines(from text: Substring) -> [Inline] {
        var inlines: [Inline] = []
        var remaining = text

        while !remaining.isEmpty {
            if let match = remaining.range(
                of: #"\[[0-9A-Fa-f-]{36}(?::[0-9A-Fa-f-]{36})?\]"#,
                options: .regularExpression
            ) {
                if match.lowerBound > remaining.startIndex {
                    appendStyled(inlines: &inlines, from: remaining[..<match.lowerBound])
                }
                let token = String(remaining[match])
                inlines.append(contentsOf: citationInlines(from: token))
                remaining = remaining[match.upperBound...]
                continue
            }

            if remaining.hasPrefix("**"),
               let end = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...]
                   .range(of: "**") {
                let inner = remaining[
                    remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound
                ]
                inlines.append(.bold(String(inner)))
                remaining = remaining[end.upperBound...]
                continue
            }

            if remaining.hasPrefix("`"),
               let end = remaining[remaining.index(after: remaining.startIndex)...]
                   .firstIndex(of: "`") {
                let inner = remaining[
                    remaining.index(after: remaining.startIndex)..<end
                ]
                inlines.append(.code(String(inner)))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            if remaining.hasPrefix("*"),
               let end = remaining[remaining.index(after: remaining.startIndex)...]
                   .firstIndex(of: "*") {
                let inner = remaining[
                    remaining.index(after: remaining.startIndex)..<end
                ]
                inlines.append(.italic(String(inner)))
                remaining = remaining[remaining.index(after: end)...]
                continue
            }

            let nextSpecial = remaining.firstIndex(where: { char in
                char == "[" || char == "*" || char == "`" || char == "$" || char == "\\"
            }) ?? remaining.endIndex
            if nextSpecial > remaining.startIndex {
                inlines.append(.text(String(remaining[..<nextSpecial])))
            }
            if nextSpecial == remaining.endIndex {
                break
            }
            let ch = remaining[nextSpecial]
            if ch == "[" || ch == "*" || ch == "`" {
                inlines.append(.text(String(ch)))
                remaining = remaining[remaining.index(after: nextSpecial)...]
            } else {
                break
            }
        }

        return inlines
    }

    /// Unique sources across an entire answer, in first-seen order.
    static func allCitations(in blocks: [Block]) -> [CitationRef] {
        var seen = Set<String>()
        var out: [CitationRef] = []
        for block in blocks {
            switch block {
            case .paragraph(_, let citations):
                appendUnique(citations, to: &out, seen: &seen)
            case .bulletList(let items):
                for item in items {
                    appendUnique(item.citations, to: &out, seen: &seen)
                }
            default:
                break
            }
        }
        return out
    }

    private static func appendUnique(
        _ citations: [CitationRef],
        to out: inout [CitationRef],
        seen: inout Set<String>
    ) {
        for ref in citations {
            if seen.insert(ref.itemId).inserted {
                out.append(ref)
            }
        }
    }

    static func separateCitations(_ inlines: [Inline]) -> (body: [Inline], citations: [CitationRef]) {
        var body: [Inline] = []
        var citations: [CitationRef] = []
        var seen = Set<String>()

        for inline in inlines {
            if case .citation(let itemId, let chunkId) = inline {
                trimTrailingWhitespace(from: &body)
                let key = "\(itemId)|\(chunkId ?? "")"
                if !seen.contains(key) {
                    seen.insert(key)
                    citations.append(CitationRef(itemId: itemId, chunkId: chunkId))
                }
            } else {
                body.append(inline)
            }
        }
        trimTrailingWhitespace(from: &body)
        return (body, citations)
    }

    private static func parseBulletItem(
        level: Int,
        number: Int?,
        content: String
    ) -> BulletItem {
        let (title, rest) = extractLeadingBoldLabel(content)
        let inlines = parseInlines(rest)
        let split = separateCitations(inlines)
        return BulletItem(
            level: level,
            number: number,
            title: title,
            body: split.body,
            citations: split.citations
        )
    }

    /// Splits `1. foo 2. bar` onto separate lines so lists render as items.
    private static func normalizeListBreaks(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("*"), result.hasSuffix("*"), result.count > 2 {
            let inner = String(result.dropFirst().dropLast())
            if inner.range(of: #"\d+\.\s"#, options: .regularExpression) != nil {
                result = inner
            }
        }

        // Split inline lists like "Rating: 4.8 2. Next Place" — the old
        // lookbehind rejected splits when a rating digit preceded the space.
        let patterns = [
            #"\s+(?=\d+\.\s+(?:\*\*|[A-Z]))"#,
            #"\s+(?=\d+\)\s+(?:\*\*|[A-Z]))"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "\n"
            )
        }
        return result
    }

    /// Pulls `**Location:**` / `**Items Purchased**` off the front of a bullet.
    private static func extractLeadingBoldLabel(_ content: String) -> (title: String?, rest: String) {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("**"),
              let close = trimmed.range(
                  of: "**",
                  range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex
              ) else {
            return (nil, trimmed)
        }

        var label = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<close.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        if label.hasSuffix(":") {
            label = String(label.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        var rest = String(trimmed[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") {
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        guard !label.isEmpty else { return (nil, trimmed) }
        return (label, rest)
    }

    private static func headingLevel(_ line: String) -> Int? {
        if line.hasPrefix("### ") { return 3 }
        if line.hasPrefix("## ") { return 2 }
        if line.hasPrefix("# ") { return 1 }
        return nil
    }

    private static func listItemPrefix(
        _ line: String
    ) -> (level: Int, content: String, number: Int?)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let numbered = numberedListPrefix(trimmed) {
            return (max(0, leading / 2), numbered.content, numbered.number)
        }

        if trimmed.hasPrefix(". ") {
            let content = String(trimmed.dropFirst(2))
            return (max(1, leading / 4), content, nil)
        }
        guard trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") else { return nil }
        let content = String(trimmed.dropFirst(2))
        let level = leading / 2
        return (level, content, nil)
    }

    private static func numberedListPrefix(
        _ trimmed: String
    ) -> (number: Int, content: String)? {
        let pattern = #"^(\d+)[\.\)]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: trimmed,
                  range: NSRange(trimmed.startIndex..., in: trimmed)
              ),
              let numRange = Range(match.range(at: 1), in: trimmed),
              let contentRange = Range(match.range(at: 2), in: trimmed),
              let number = Int(trimmed[numRange]) else {
            return nil
        }
        return (number, String(trimmed[contentRange]))
    }

    private static func citationInlines(from token: String) -> [Inline] {
        let inner = token.dropFirst().dropLast()
        let parts = inner.split(separator: ":", maxSplits: 1).map(String.init)
        guard let itemId = parts.first else { return [.text(token)] }
        let chunkId = parts.count > 1 ? parts[1] : nil
        return [.citation(itemId: itemId, chunkId: chunkId)]
    }

    private static func appendStyled(inlines: inout [Inline], from text: Substring) {
        guard !text.isEmpty else { return }
        inlines.append(.text(String(text)))
    }

    private static func dedupeConsecutiveCitations(_ inlines: [Inline]) -> [Inline] {
        var out: [Inline] = []
        for inline in inlines {
            if case .citation(let itemId, let chunkId) = inline {
                trimTrailingWhitespace(from: &out)
                if let last = out.last,
                   case .citation(let lastItem, let lastChunk) = last,
                   lastItem == itemId, lastChunk == chunkId {
                    continue
                }
            }
            out.append(inline)
        }
        return out
    }

    private static func trimTrailingWhitespace(from inlines: inout [Inline]) {
        while let last = inlines.last {
            if case .text(let s) = last,
               s.trimmingCharacters(in: .whitespaces).isEmpty {
                inlines.removeLast()
            } else if case .text(let s) = last {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if trimmed != s {
                    if trimmed.isEmpty {
                        inlines.removeLast()
                    } else {
                        inlines[inlines.count - 1] = .text(trimmed)
                    }
                }
                break
            } else {
                break
            }
        }
    }
}
