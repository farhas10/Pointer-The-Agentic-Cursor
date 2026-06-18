import XCTest
@testable import Pointer

final class ChunkerTests: XCTestCase {
    func testEmptyInputProducesNoChunks() {
        XCTAssertTrue(Chunker().chunk("").isEmpty)
        XCTAssertTrue(Chunker().chunk("   \n\n  ").isEmpty)
    }

    func testShortTextProducesSingleChunk() {
        let text = "This is short."
        let chunks = Chunker().chunk(text)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, text)
    }

    func testLongTextSplitsAcrossChunks() {
        let paragraph = String(repeating: "Lorem ipsum dolor sit amet. ", count: 200)
        let twoParagraphs = "\(paragraph)\n\n\(paragraph)"
        let chunker = Chunker(targetTokens: 200, overlapTokens: 30)
        let chunks = chunker.chunk(twoParagraphs)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertGreaterThan(chunk.text.count, 0)
        }
    }

    func testHugeParagraphIsHardSplit() {
        let huge = String(repeating: "a", count: 10_000)
        // No paragraph breaks; chunker should sentence-split or emit
        // multiple pieces rather than a single 10k-token blob.
        let chunker = Chunker(targetTokens: 200, overlapTokens: 30)
        let chunks = chunker.chunk(huge)
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(
            chunks.allSatisfy { $0.estimatedTokens <= 600 },
            "no chunk should massively exceed the target"
        )
    }

    func testTokenEstimationIsPositive() {
        XCTAssertGreaterThan(Chunker().estimateTokens("hello"), 0)
        XCTAssertGreaterThan(Chunker().estimateTokens("a"), 0)
    }
}
