import XCTest
@testable import Pointer

final class SseStreamerTests: XCTestCase {
    func testParsesTokenEvent() {
        let event = SseStreamer.parse(
            event: "token",
            dataLines: ["{\"text\":\"hello\"}"]
        )
        if case let .token(text) = event {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("expected .token, got \(String(describing: event))")
        }
    }

    func testParsesDoneEvent() {
        let event = SseStreamer.parse(
            event: "done",
            dataLines: ["{\"finish_reason\":\"stop\"}"]
        )
        if case let .done(reason, _, mode) = event {
            XCTAssertEqual(reason, "stop")
            XCTAssertNil(mode)
        } else {
            XCTFail("expected .done")
        }
    }

    func testParsesDoneEventWithAgentMode() {
        let event = SseStreamer.parse(
            event: "done",
            dataLines: ["{\"finish_reason\":\"tool_use\",\"agent_mode\":\"automation\"}"]
        )
        if case let .done(reason, _, mode) = event {
            XCTAssertEqual(reason, "tool_use")
            XCTAssertEqual(mode, "automation")
        } else {
            XCTFail("expected .done")
        }
    }

    func testParsesErrorEvent() {
        let event = SseStreamer.parse(
            event: "error",
            dataLines: ["{\"message\":\"boom\"}"]
        )
        if case let .error(message) = event {
            XCTAssertEqual(message, "boom")
        } else {
            XCTFail("expected .error")
        }
    }

    func testParsesCitationEvent() {
        let event = SseStreamer.parse(
            event: "citation",
            dataLines: ["{\"item_id\":\"abc\",\"chunk_id\":\"3\"}"]
        )
        if case let .citation(itemId, chunkId) = event {
            XCTAssertEqual(itemId, "abc")
            XCTAssertEqual(chunkId, "3")
        } else {
            XCTFail("expected .citation")
        }
    }

    func testEmptyEventReturnsNil() {
        XCTAssertNil(SseStreamer.parse(event: "", dataLines: ["{}"]))
        XCTAssertNil(SseStreamer.parse(event: "unknown", dataLines: ["{}"]))
    }

    func testEscapedNewlineInTokenDecodes() {
        let event = SseStreamer.parse(
            event: "token",
            dataLines: ["{\"text\":\"line1\\nline2\"}"]
        )
        if case let .token(text) = event {
            XCTAssertEqual(text, "line1\nline2")
        } else {
            XCTFail("expected .token with decoded newline")
        }
    }

    func testConsumeTextParsesMultipleTokenFrames() async throws {
        let body = """
        event: token
        data: {"text":"You are"}

        event: token
        data: {"text":" looking at a lake."}

        event: done
        data: {"finish_reason":"stop","usage":{"input_tokens":1,"output_tokens":2}}

        """
        var events: [SseEvent] = []
        try await SseStreamer.consume(text: body) { events.append($0) }
        XCTAssertEqual(events.count, 3)
        if case let .token(first) = events[0] {
            XCTAssertEqual(first, "You are")
        } else {
            XCTFail("expected first token")
        }
        if case let .token(second) = events[1] {
            XCTAssertEqual(second, " looking at a lake.")
        } else {
            XCTFail("expected second token")
        }
        if case let .done(reason, _, _) = events[2] {
            XCTAssertEqual(reason, "stop")
        } else {
            XCTFail("expected done")
        }
    }

    func testConsumeTextParsesGeminiErrorFrame() async throws {
        let body = """
        event: error
        data: {"message":"Unable to process input image."}

        """
        var events: [SseEvent] = []
        try await SseStreamer.consume(text: body) { events.append($0) }
        XCTAssertEqual(events.count, 1)
        if case let .error(message) = events[0] {
            XCTAssertTrue(message.contains("Unable to process"))
        } else {
            XCTFail("expected .error, got \(events)")
        }
    }

    func testInvalidJsonDataReturnsNil() {
        let event = SseStreamer.parse(
            event: "token",
            dataLines: ["{\"text\":\"oops", "broken\"}"]
        )
        XCTAssertNil(event)
    }
}
