import XCTest

final class SearchQueryTests: XCTestCase {
    func testOperators() {
        let query = SearchQuery.parse("type:image vacation from:today app:Safari pin:true")
        XCTAssertEqual(query.kind, .image)
        XCTAssertEqual(query.terms, ["vacation"])
        XCTAssertEqual(query.bucket, .today)
        XCTAssertEqual(query.app, "Safari")
        XCTAssertTrue(query.pinnedOnly)
    }

    func testConflictingKindsAreImpossible() {
        let query = SearchQuery.parse("type:image").merging(kind: .text, pinned: false)
        XCTAssertTrue(query.impossible)
        XCTAssertFalse(query.matches(makeClip(kind: .image), now: Date()))
    }

    func testHighlightRanges() {
        let query = SearchQuery.parse("ship")
        let ranges = query.highlightRanges(in: "Ship the shipment")
        XCTAssertEqual(ranges.count, 2)
    }

    func testMatchIsCaseInsensitive() {
        let query = SearchQuery.parse("Notes")
        XCTAssertTrue(query.matches(makeClip(text: "from notes", app: "Mail"), now: Date()))
    }

    func testBoardOperatorMatchesSnippets() {
        let boardID = UUID()
        let query = SearchQuery.parse("board:Support")
        let onBoard = Snippet(
            id: UUID(),
            createdAt: Date(),
            title: "Reply",
            text: "Thanks",
            kind: .text,
            collectionID: boardID
        )
        let unfiled = Snippet(id: UUID(), createdAt: Date(), title: "Loose", text: "Hi", kind: .text)
        XCTAssertTrue(query.matches(onBoard) { $0 == boardID ? "Support" : nil })
        XCTAssertFalse(query.matches(unfiled) { $0 == boardID ? "Support" : nil })
        XCTAssertTrue(SearchQuery.parse("board:unfiled").matches(unfiled))
    }

    func testAbbreviationOperatorAndTermMatchSnippets() {
        let marked = Snippet(
            id: UUID(),
            createdAt: Date(),
            title: "Address",
            text: "1 Main",
            kind: .text,
            abbreviation: "addr"
        )
        let plain = Snippet(id: UUID(), createdAt: Date(), title: "Note", text: "hello", kind: .text)
        XCTAssertTrue(SearchQuery.parse("abbr:addr").matches(marked))
        XCTAssertFalse(SearchQuery.parse("abbr:addr").matches(plain))
        XCTAssertTrue(SearchQuery.parse("addr").matches(marked))
        XCTAssertFalse(SearchQuery.parse("addr").matches(plain))
    }
}
