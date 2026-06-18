import Foundation
import os

/// Thin HTTP client for the Pointer backend.
///
/// Uses `URLSession.data(for:)` to read the full SSE body. On macOS,
/// `URLSession.AsyncBytes` against chunked `text/event-stream` responses
/// was closing early (0 events) because the connection dropped before
/// Gemini finished. Waiting for the complete body keeps the connection
/// alive and matches how curl behaves.
final class BackendClient: Sendable {
    private static let log = Logger(subsystem: "app.pointer.Pointer", category: "BackendClient")

    let baseURL: URL
    private let session: URLSession
    private let bearerToken: String?

    init(
        baseURL: URL,
        bearerToken: String? = nil,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120
            config.timeoutIntervalForResource = 300
            config.waitsForConnectivity = true
            self.session = URLSession(configuration: config)
        }
    }

    /// Quick probe used at launch to verify the dev backend is up.
    func checkHealth() async -> Bool {
        let url = baseURL.appending(path: "healthz")
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            Self.log.info("healthz ok: \(body, privacy: .public)")
            return body.contains("\"ok\":true")
        } catch {
            Self.log.error("healthz failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// POST /v1/agent/ask, parse the SSE body, call `onEvent` per frame.
    func streamAsk(
        _ request: AskRequest,
        onEvent: @escaping @Sendable @MainActor (SseEvent) -> Void
    ) async throws {
        let url = baseURL.appending(path: "v1/agent/ask")
        let bodyBytes = try JSONEncoder().encode(request)
        Self.log.info(
            "POST \(url.absoluteString, privacy: .public) body_bytes=\(bodyBytes.count)"
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            Self.log.error("HTTP \(http.statusCode)")
            throw BackendError.httpStatus(http.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            Self.log.error("empty response body (bytes=\(data.count))")
            throw BackendError.decoding("Empty response from backend.")
        }

        Self.log.info("response_bytes=\(data.count)")

        var eventCount = 0
        try await SseStreamer.consume(text: text) { event in
            eventCount += 1
            await onEvent(event)
        }
        if eventCount == 0 {
            Self.log.error("0 SSE events; body_preview=\(text.prefix(300), privacy: .public)")
            if let fallback = Self.fallbackEvent(from: text) {
                eventCount = 1
                await onEvent(fallback)
            }
        }
        Self.log.info("parsed events=\(eventCount)")
    }

    /// POST /v1/agent/continue after client-side tool execution.
    func streamAgentContinue(
        _ request: AgentContinueRequest,
        onEvent: @escaping @Sendable @MainActor (SseEvent) -> Void
    ) async throws {
        let url = baseURL.appending(path: "v1/agent/continue")
        let bodyBytes = try JSONEncoder().encode(request)
        Self.log.info(
            "POST \(url.absoluteString, privacy: .public) tools=\(request.toolResults.count)"
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw BackendError.httpStatus(http.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw BackendError.decoding("Empty response from agent continue.")
        }

        try await SseStreamer.consume(text: text) { event in
            await onEvent(event)
        }
    }

    /// POST /v1/agent/search — Gemini Google Search grounding (server-side).
    func webSearch(query: String) async throws -> WebSearchResponse {
        let url = baseURL.appending(path: "v1/agent/search")
        let body = WebSearchRequest(query: query)
        let bodyBytes = try JSONEncoder().encode(body)
        Self.log.info("POST \(url.absoluteString, privacy: .public) query=\(query, privacy: .public)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(BackendErrorPayload.self, from: data) {
                throw BackendError.decoding(err.message ?? "Web search failed (HTTP \(http.statusCode)).")
            }
            throw BackendError.httpStatus(http.statusCode)
        }

        return try JSONDecoder().decode(WebSearchResponse.self, from: data)
    }

    /// POST /v1/agent/places — Gemini Google Maps grounding (server-side).
    func placesSearch(query: String, location: UserLocation?) async throws -> PlacesSearchResponse {
        let url = baseURL.appending(path: "v1/agent/places")
        let body = PlacesSearchRequest(query: query, location: location)
        let bodyBytes = try JSONEncoder().encode(body)
        Self.log.info("POST \(url.absoluteString, privacy: .public) places_query=\(query, privacy: .public)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(BackendErrorPayload.self, from: data) {
                throw BackendError.decoding(err.message ?? "Places search failed (HTTP \(http.statusCode)).")
            }
            throw BackendError.httpStatus(http.statusCode)
        }

        return try JSONDecoder().decode(PlacesSearchResponse.self, from: data)
    }

    /// POST /v1/agent/transcribe — Gemini multimodal speech-to-text (server-side).
    func transcribeAudio(audioData: Data, mimeType: String) async throws -> TranscribeResponse {
        let url = baseURL.appending(path: "v1/agent/transcribe")
        let body = TranscribeRequest(
            audioB64: audioData.base64EncodedString(),
            audioMime: mimeType
        )
        let bodyBytes = try JSONEncoder().encode(body)
        Self.log.info("POST \(url.absoluteString, privacy: .public) audio_bytes=\(audioData.count)")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let err = try? JSONDecoder().decode(BackendErrorPayload.self, from: data) {
                throw BackendError.decoding(err.message ?? "Transcription failed (HTTP \(http.statusCode)).")
            }
            throw BackendError.httpStatus(http.statusCode)
        }

        return try JSONDecoder().decode(TranscribeResponse.self, from: data)
    }

    /// POST /v1/drawer/query, parse the SSE body, call `onEvent` per frame.
    func streamDrawerQuery(
        _ request: DrawerQueryRequest,
        onEvent: @escaping @Sendable @MainActor (SseEvent) -> Void
    ) async throws {
        let url = baseURL.appending(path: "v1/drawer/query")
        let bodyBytes = try JSONEncoder().encode(request)
        Self.log.info(
            "POST \(url.absoluteString, privacy: .public) drawer_items=\(request.items.count) body_bytes=\(bodyBytes.count)"
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = bodyBytes

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            Self.log.error("drawer HTTP \(http.statusCode)")
            throw BackendError.httpStatus(http.statusCode)
        }

        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw BackendError.decoding("Empty response from drawer query.")
        }

        var eventCount = 0
        try await SseStreamer.consume(text: text) { event in
            eventCount += 1
            await onEvent(event)
        }
        if eventCount == 0, let fallback = Self.fallbackEvent(from: text) {
            await onEvent(fallback)
        }
        Self.log.info("drawer parsed events=\(eventCount)")
    }

    /// Last-resort parse when the body is valid text but our line parser
    /// found zero frames (seen with some chunked SSE edge cases).
    private static func fallbackEvent(from text: String) -> SseEvent? {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("data:") else { continue }
            let json = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = json.data(using: .utf8) else { continue }
            struct Payload: Decodable { let message: String?; let text: String? }
            if let payload = try? JSONDecoder().decode(Payload.self, from: data) {
                if let message = payload.message { return .error(message) }
                if let text = payload.text { return .token(text) }
            }
        }
        return nil
    }
}

struct WebSearchRequest: Encodable, Sendable {
    let query: String
}

struct WebSearchResponse: Decodable, Sendable {
    let text: String
    let sources: [String]
}

struct PlacesSearchRequest: Encodable, Sendable {
    let query: String
    let latitude: Double?
    let longitude: Double?
    let city: String?

    init(query: String, location: UserLocation?) {
        self.query = query
        self.latitude = location?.latitude
        self.longitude = location?.longitude
        self.city = location?.city
    }
}

struct PlacesSearchResponse: Decodable, Sendable {
    let text: String
    let sources: [String]
}

struct TranscribeRequest: Encodable, Sendable {
    let audioB64: String
    let audioMime: String

    enum CodingKeys: String, CodingKey {
        case audioB64 = "audio_b64"
        case audioMime = "audio_mime"
    }
}

struct TranscribeResponse: Decodable, Sendable {
    let text: String
}

private struct BackendErrorPayload: Decodable {
    let message: String?
}

enum BackendError: Error, CustomStringConvertible {
    case httpStatus(Int)
    case decoding(String)

    var description: String {
        switch self {
        case .httpStatus(let code): return "Backend returned HTTP \(code)."
        case .decoding(let msg): return "Failed to decode backend response: \(msg)"
        }
    }
}
