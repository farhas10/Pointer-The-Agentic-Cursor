import Foundation

/// A structured result the panel remembers so "that" / "#2" resolve reliably.
public struct PanelEntity: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case place
        case link
        case product
        case generic
    }

    public enum Action: String, Sendable {
        case open
        case reviews
        case directions
        case copy
    }

    public var id: String
    public var index: Int
    public var name: String
    public var subtitle: String?
    public var url: String?
    public var kind: Kind

    public init(
        id: String = UUID().uuidString,
        index: Int,
        name: String,
        subtitle: String? = nil,
        url: String? = nil,
        kind: Kind = .generic
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.subtitle = subtitle
        self.url = url
        self.kind = kind
    }

    public var availableActions: [Action] {
        var actions: [Action] = []
        if url != nil { actions.append(.open) }
        if kind == .place { actions.append(.directions) }
        actions.append(.reviews)
        actions.append(.copy)
        return actions
    }
}

/// Wire format for `entity_context` on `POST /v1/agent/ask`.
public struct EntityContextEntry: Codable, Sendable {
    public var index: Int
    public var name: String
    public var subtitle: String?
    public var url: String?
    public var kind: String?

    public init(from entity: PanelEntity) {
        index = entity.index
        name = entity.name
        subtitle = entity.subtitle
        url = entity.url
        kind = entity.kind.rawValue
    }
}

/// Parses numbered lists and markdown links from agent answers and tool output.
enum EntityExtractor {
    static let maxEntities = 12

    static func extract(from text: String, kind: PanelEntity.Kind = .generic) -> [PanelEntity] {
        var found: [PanelEntity] = []
        var seen = Set<String>()

        func add(name: String, subtitle: String? = nil, url: String? = nil, entityKind: PanelEntity.Kind) {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.count <= 120 else { return }
            let key = "\(trimmed.lowercased())|\(url ?? "")"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            let index = found.count + 1
            found.append(PanelEntity(
                index: index,
                name: trimmed,
                subtitle: subtitle,
                url: url,
                kind: entityKind
            ))
        }

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if let match = numberedLine(trimmed) {
                add(name: match.name, subtitle: match.subtitle, url: match.url, entityKind: kind)
                continue
            }
            if let match = markdownLinkLine(trimmed) {
                add(name: match.name, url: match.url, entityKind: .link)
            }
        }

        if found.isEmpty {
            for match in allMarkdownLinks(in: text) {
                add(name: match.name, url: match.url, entityKind: .link)
            }
        }

        return Array(found.prefix(maxEntities))
    }

    private struct LineMatch {
        var name: String
        var subtitle: String?
        var url: String?
    }

    private static func numberedLine(_ line: String) -> LineMatch? {
        let pattern = #"^\d+[\.\)]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let bodyRange = Range(match.range(at: 1), in: line) else { return nil }

        var body = String(line[bodyRange])
        var url: String?
        if let link = firstMarkdownLink(in: body) {
            body = link.name
            url = link.url
        }
        body = stripInlineMarkdown(body)

        let parts = body.split(separator: "—", maxSplits: 1).map(String.init)
            + body.split(separator: " - ", maxSplits: 1).map(String.init)
        let name = parts.first?.trimmingCharacters(in: .whitespaces) ?? body
        let subtitle = parts.count > 1
            ? parts[1].trimmingCharacters(in: .whitespaces)
            : nil
        guard !name.isEmpty else { return nil }
        return LineMatch(name: name, subtitle: subtitle?.isEmpty == true ? nil : subtitle, url: url)
    }

    private static func markdownLinkLine(_ line: String) -> LineMatch? {
        guard let link = firstMarkdownLink(in: line) else { return nil }
        return LineMatch(name: link.name, subtitle: nil, url: link.url)
    }

    private static func firstMarkdownLink(in text: String) -> (name: String, url: String)? {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let urlRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[nameRange]), String(text[urlRange]))
    }

    private static func allMarkdownLinks(in text: String) -> [(name: String, url: String)] {
        let pattern = #"\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let urlRange = Range(match.range(at: 2), in: text) else { return nil }
            return (String(text[nameRange]), String(text[urlRange]))
        }
    }

    private static func stripInlineMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Merges newly extracted entities and reindexes.
enum EntityStore {
    static func merge(existing: [PanelEntity], new: [PanelEntity]) -> [PanelEntity] {
        var merged = existing
        var seen = Set(existing.map { "\($0.name.lowercased())|\($0.url ?? "")" })

        for entity in new {
            let key = "\(entity.name.lowercased())|\(entity.url ?? "")"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(entity)
        }

        merged = Array(merged.prefix(EntityExtractor.maxEntities))
        return merged.enumerated().map { idx, entity in
            var copy = entity
            copy.index = idx + 1
            return copy
        }
    }
}

/// Resolves deictic references ("that", "#2") into explicit entity names.
enum EntityResolver {
    static func resolve(prompt: String, entities: [PanelEntity]) -> String {
        guard !entities.isEmpty else { return prompt }
        let lower = prompt.lowercased()

        if let index = hashIndex(in: lower), let entity = entities.first(where: { $0.index == index }) {
            return expand(prompt: prompt, entity: entity, note: "#\(index)")
        }

        if let index = ordinalIndex(in: lower, count: entities.count),
           let entity = entities.first(where: { $0.index == index }) {
            return expand(prompt: prompt, entity: entity, note: "ordinal #\(index)")
        }

        if deicticReference(in: lower) {
            if let entity = entities.last {
                return expand(prompt: prompt, entity: entity, note: "that/this")
            }
        }

        return prompt
    }

    private static func deicticReference(in text: String) -> Bool {
        let pattern = #"\b(that|this)(\s+one)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return false
        }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            || text.contains("that place")
            || text.contains("this place")
    }

    private static func hashIndex(in text: String) -> Int? {
        let pattern = #"#(\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let value = Int(text[numRange]) else { return nil }
        return value
    }

    private static func ordinalIndex(in text: String, count: Int) -> Int? {
        let map: [(String, Int)] = [
            ("first", 1), ("1st", 1),
            ("second", 2), ("2nd", 2),
            ("third", 3), ("3rd", 3),
            ("fourth", 4), ("4th", 4),
            ("fifth", 5), ("5th", 5),
        ]
        for (word, index) in map where text.contains(word) {
            return index
        }
        if text.contains("last"), count > 0 { return count }
        return nil
    }

    private static func expand(prompt: String, entity: PanelEntity, note: String) -> String {
        var parts = [
            "[Resolved \(note) → \"\(entity.name)\"",
        ]
        if let subtitle = entity.subtitle { parts.append("(\(subtitle))") }
        if let url = entity.url { parts.append("url: \(url)") }
        parts.append("]")
        return parts.joined(separator: " ") + " " + prompt
    }
}
