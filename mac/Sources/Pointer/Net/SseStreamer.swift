import Foundation

/// Parses an `text/event-stream` body into typed `SseEvent`s.
///
/// Pure logic, no networking. Easy to unit-test by feeding fake byte
/// chunks. The wire format we expect is the one the backend emits:
///
///     event: token
///     data: {"text":"hello"}
///
///     event: done
///     data: {"finish_reason":"stop"}
///
/// Lines starting with `:` are comments and ignored.
struct SseStreamer {
    /// Consumes a complete SSE response body and invokes `onEvent` per frame.
    static func consume(
        text: String,
        onEvent: (SseEvent) async throws -> Void
    ) async throws {
        var event = ""
        var dataLines: [String] = []
        // Blank lines delimit SSE frames; default split omits empties and
        // merges multi-token streams into one broken frame.
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty {
                if let parsed = parse(event: event, dataLines: dataLines) {
                    try await onEvent(parsed)
                }
                event = ""
                dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if line.hasPrefix(":") { continue }
            if let prefixEnd = line.range(of: ":") {
                let key = String(line[..<prefixEnd.lowerBound])
                let value = String(line[prefixEnd.upperBound...])
                    .drop(while: { $0 == " " })
                switch key {
                case "event": event = String(value)
                case "data": dataLines.append(String(value))
                default: break
                }
            }
        }
        if let parsed = parse(event: event, dataLines: dataLines) {
            try await onEvent(parsed)
        }
    }

    /// Consumes an SSE byte stream and invokes `onEvent` for each frame.
    static func consume(
        from bytes: URLSession.AsyncBytes,
        onEvent: (SseEvent) async throws -> Void
    ) async throws {
        var event = ""
        var dataLines: [String] = []
        for try await line in bytes.lines {
            let line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty {
                if let parsed = parse(event: event, dataLines: dataLines) {
                    try await onEvent(parsed)
                }
                event = ""
                dataLines.removeAll(keepingCapacity: true)
                continue
            }
            if line.hasPrefix(":") { continue }
            if let prefixEnd = line.range(of: ":") {
                let key = String(line[..<prefixEnd.lowerBound])
                let value = String(line[prefixEnd.upperBound...])
                    .drop(while: { $0 == " " })
                switch key {
                case "event": event = String(value)
                case "data": dataLines.append(String(value))
                default: break
                }
            }
        }
        if let parsed = parse(event: event, dataLines: dataLines) {
            try await onEvent(parsed)
        }
    }

    /// Streams parsed events from a `URLSession.AsyncBytes` stream.
    /// Kept for unit tests; production code uses `consume(from:onEvent:)`.
    static func events(
        from bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<SseEvent, Error> {
        AsyncThrowingStream(SseEvent.self, bufferingPolicy: .unbounded) { continuation in
            Task {
                do {
                    try await consume(from: bytes) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Test seam: parse a single event from already-extracted lines.
    static func parse(event: String, dataLines: [String]) -> SseEvent? {
        guard !event.isEmpty else { return nil }
        let dataString = dataLines.joined(separator: "\n")
        guard let dataBytes = dataString.data(using: .utf8) else { return nil }

        struct TokenData: Decodable { let text: String }
        struct ToolCallData: Decodable {
            let name: String
            let input: AnyCodableValue
            let id: String
            let session_id: String
            let tier: String?
        }
        struct CitationData: Decodable { let item_id: String; let chunk_id: String? }
        struct ErrorData: Decodable { let message: String }
        struct DoneData: Decodable {
            let finish_reason: String
            let session_id: String?
            let agent_mode: String?
        }

        switch event {
        case "token":
            guard let payload = try? JSONDecoder().decode(TokenData.self, from: dataBytes) else { return nil }
            return .token(payload.text)
        case "tool_call":
            guard let payload = try? JSONDecoder().decode(ToolCallData.self, from: dataBytes),
                  let inputJson = payload.input.toJsonString()
            else { return nil }
            return .toolCall(
                name: payload.name,
                inputJson: inputJson,
                id: payload.id,
                sessionId: payload.session_id,
                tier: payload.tier ?? "safe"
            )
        case "citation":
            guard let payload = try? JSONDecoder().decode(CitationData.self, from: dataBytes) else { return nil }
            return .citation(itemId: payload.item_id, chunkId: payload.chunk_id)
        case "error":
            guard let payload = try? JSONDecoder().decode(ErrorData.self, from: dataBytes) else { return nil }
            return .error(payload.message)
        case "done":
            guard let payload = try? JSONDecoder().decode(DoneData.self, from: dataBytes) else { return nil }
            return .done(
                finishReason: payload.finish_reason,
                sessionId: payload.session_id,
                agentMode: payload.agent_mode
            )
        default:
            return nil
        }
    }
}

/// Tiny JSON-any decoder used only for tool_call inputs (we round-trip
/// to a JSON string and hand it to the action executor).
private struct AnyCodableValue: Decodable {
    let raw: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            raw = NSNull()
        } else if let v = try? container.decode(Bool.self) {
            raw = v
        } else if let v = try? container.decode(Double.self) {
            raw = v
        } else if let v = try? container.decode(String.self) {
            raw = v
        } else if let v = try? container.decode([AnyCodableValue].self) {
            raw = v.map { $0.raw as Any }
        } else if let v = try? container.decode([String: AnyCodableValue].self) {
            raw = v.mapValues { $0.raw as Any }
        } else {
            raw = nil
        }
    }

    func toJsonString() -> String? {
        guard let raw, JSONSerialization.isValidJSONObject(["x": raw]) || raw is NSNull else {
            return nil
        }
        let wrapped: Any = raw
        guard JSONSerialization.isValidJSONObject(wrapped) else {
            // Top-level isn't an object/array; encode via wrapper.
            let data = try? JSONSerialization.data(
                withJSONObject: ["v": wrapped],
                options: []
            )
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }
        let data = try? JSONSerialization.data(withJSONObject: wrapped, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) }
    }
}
