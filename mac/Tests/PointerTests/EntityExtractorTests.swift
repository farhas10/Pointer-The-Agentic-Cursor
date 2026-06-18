import XCTest
@testable import Pointer

final class EntityExtractorTests: XCTestCase {
    func testExtractsNumberedList() {
        let text = """
        Here are options:
        1. **Ballston Local** — American, $$$
        2. **Me Jana** — Lebanese
        3. **True Food Kitchen**
        """
        let entities = EntityExtractor.extract(from: text, kind: .place)
        XCTAssertEqual(entities.count, 3)
        XCTAssertEqual(entities[0].name, "Ballston Local")
        XCTAssertEqual(entities[0].subtitle, "American, $$$")
        XCTAssertEqual(entities[1].index, 2)
    }

    func testExtractsMarkdownLinks() {
        let text = "- [OpenAI](https://openai.com) is an AI lab."
        let entities = EntityExtractor.extract(from: text)
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities[0].name, "OpenAI")
        XCTAssertEqual(entities[0].url, "https://openai.com")
        XCTAssertEqual(entities[0].kind, .link)
    }

    func testEntityResolverHashIndex() {
        let entities = [
            PanelEntity(index: 1, name: "Alpha"),
            PanelEntity(index: 2, name: "Beta", url: "https://example.com"),
        ]
        let resolved = EntityResolver.resolve(prompt: "open #2", entities: entities)
        XCTAssertTrue(resolved.contains("Beta"))
        XCTAssertTrue(resolved.contains("https://example.com"))
    }

    func testEntityStoreMergeReindexes() {
        let existing = [PanelEntity(index: 1, name: "Alpha")]
        let new = [PanelEntity(index: 1, name: "Beta")]
        let merged = EntityStore.merge(existing: existing, new: new)
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[1].name, "Beta")
        XCTAssertEqual(merged[1].index, 2)
    }
}
