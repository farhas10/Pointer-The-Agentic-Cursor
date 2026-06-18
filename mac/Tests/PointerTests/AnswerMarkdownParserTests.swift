import XCTest
@testable import Pointer

final class AnswerMarkdownParserTests: XCTestCase {
    func testParsesHeadingAndBullets() {
        let text = """
        ## Purpose
        *   **Axes** The map shows axes.
        *   **Example:** bank pays attention.
        """
        let blocks = AnswerMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 2)
        if case .bulletList(let items) = blocks[1] {
            XCTAssertEqual(items[0].title, "Axes")
            XCTAssertEqual(items[1].title, "Example")
        } else {
            XCTFail("expected bullet list")
        }
    }

    func testParsesCitationInline() {
        let inlines = AnswerMarkdownParser.parseInlines(
            "The map shows attention [A580A63E-0FB6-4848-8BED-888287A922D4]."
        )
        XCTAssertTrue(inlines.contains {
            if case .citation(let id, nil) = $0 {
                return id == "A580A63E-0FB6-4848-8BED-888287A922D4"
            }
            return false
        })
    }

    func testSeparatesCitationsFromBody() {
        let inlines = AnswerMarkdownParser.parseInlines(
            "Receipt total $50 [A580A63E-0FB6-4848-8BED-888287A922D4]."
        )
        let split = AnswerMarkdownParser.separateCitations(inlines)
        XCTAssertEqual(split.citations.count, 1)
        XCTAssertFalse(split.body.contains { if case .citation = $0 { return true }; return false })
    }

    func testDedupesConsecutiveCitations() {
        let inlines = AnswerMarkdownParser.parseInlines(
            "Claim [A580A63E-0FB6-4848-8BED-888287A922D4] [A580A63E-0FB6-4848-8BED-888287A922D4]"
        )
        let citations = inlines.filter {
            if case .citation = $0 { return true }
            return false
        }
        XCTAssertEqual(citations.count, 1)
    }

    func testAllCitationsDedupesAcrossBlocks() {
        let id = "A580A63E-0FB6-4848-8BED-888287A922D4"
        let text = """
        *   **Location:** Chicago [\(id)]
        *   **Payment:** Total $50 [\(id)]
        """
        let blocks = AnswerMarkdownParser.parse(text)
        let citations = AnswerMarkdownParser.allCitations(in: blocks)
        XCTAssertEqual(citations.count, 1)
        XCTAssertEqual(citations[0].itemId, id)
    }

    func testParsesNumberedListOnSeparateLines() {
        let text = """
        1. **Carbonara** - cozy Italian eatery. Rating: 4.8
        2. **JINYA Ramen Bar** - Japanese ramen spot. Rating: 4.8
        """
        let blocks = AnswerMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 1)
        if case .bulletList(let items) = blocks[0] {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0].number, 1)
            XCTAssertEqual(items[0].title, "Carbonara")
            XCTAssertEqual(items[1].number, 2)
            XCTAssertEqual(items[1].title, "JINYA Ramen Bar")
        } else {
            XCTFail("expected numbered list")
        }
    }

    func testSplitsInlineNumberedListOntoSeparateLines() {
        let text = """
        1. **Carbonara** - Italian. 2. **JINYA Ramen Bar** - Ramen. 3. **Andy's Pizza** - Pizza.
        """
        let blocks = AnswerMarkdownParser.parse(text)
        if case .bulletList(let items) = blocks[0] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items.map(\.number), [1, 2, 3])
        } else {
            XCTFail("expected numbered list")
        }
    }

    func testSplitsInlineNumberedListAfterRating() {
        let text = """
        1. **Carbonara** - cozy Italian eatery. Rating: 4.8 2. **JINYA Ramen Bar** - Japanese ramen. Rating: 4.8 3. **Andy's Pizza** - Pizza.
        """
        let blocks = AnswerMarkdownParser.parse(text)
        if case .bulletList(let items) = blocks[0] {
            XCTAssertEqual(items.count, 3)
            XCTAssertEqual(items.map(\.number), [1, 2, 3])
            XCTAssertEqual(items[0].title, "Carbonara")
            XCTAssertEqual(items[2].title, "Andy's Pizza")
        } else {
            XCTFail("expected numbered list")
        }
    }

    func testParsesInlineLaTeX() {
        let inlines = AnswerMarkdownParser.parseInlines(
            "Since $40 = 4 \\times 10$ we simplify."
        )
        XCTAssertEqual(inlines.count, 3)
        if case .text(let prefix) = inlines[0] {
            XCTAssertTrue(prefix.hasPrefix("Since"))
        } else {
            XCTFail("expected text prefix")
        }
        if case .latexInline(let latex) = inlines[1] {
            XCTAssertEqual(latex, "40 = 4 \\times 10")
        } else {
            XCTFail("expected inline latex")
        }
    }

    func testParsesDisplayLaTeXBlock() {
        let text = """
        $$x = 2\\sqrt{10}, \\quad x = -2\\sqrt{10}$$
        """
        let blocks = AnswerMarkdownParser.parse(text)
        XCTAssertEqual(blocks.count, 1)
        if case .mathBlock(let latex) = blocks[0] {
            XCTAssertTrue(latex.contains("2\\sqrt{10}"))
        } else {
            XCTFail("expected math block")
        }
    }

    func testParsesMixedInlineAndDisplayLaTeX() {
        let inlines = AnswerMarkdownParser.parseInlines(
            "Since $40 = 4 \\times 10$: $$x = \\pm\\sqrt{4 \\cdot 10}$$"
        )
        XCTAssertTrue(inlines.contains {
            if case .latexInline(let latex) = $0 {
                return latex.contains("40 = 4")
            }
            return false
        })
        XCTAssertTrue(inlines.contains {
            if case .latexDisplay(let latex) = $0 {
                return latex.contains("\\pm\\sqrt")
            }
            return false
        })
    }

    func testParsesDotPrefixedSubBullets() {
        let text = """
        *   **Payment:** Total $100
            . Card was VISA.
        """
        let blocks = AnswerMarkdownParser.parse(text)
        if case .bulletList(let items) = blocks[0] {
            XCTAssertEqual(items.count, 2)
            XCTAssertEqual(items[0].title, "Payment")
            XCTAssertEqual(items[1].level, 1)
        } else {
            XCTFail("expected bullet list")
        }
    }
}
