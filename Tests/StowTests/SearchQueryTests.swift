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
}
