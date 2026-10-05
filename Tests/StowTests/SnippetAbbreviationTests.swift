import XCTest

final class SnippetAbbreviationTests: XCTestCase {
    func testNormalizeAcceptsSimpleShortcuts() {
        XCTAssertEqual(SnippetAbbreviation.normalize(" Addr "), "addr")
        XCTAssertEqual(SnippetAbbreviation.normalize("sig1"), "sig1")
        XCTAssertEqual(SnippetAbbreviation.normalize("git.clone"), "git.clone")
    }

    func testNormalizeRejectsInvalidShortcuts() {
        XCTAssertNil(SnippetAbbreviation.normalize(""))
        XCTAssertNil(SnippetAbbreviation.normalize("  "))
        XCTAssertNil(SnippetAbbreviation.normalize("has space"))
        XCTAssertNil(SnippetAbbreviation.normalize("bad!"))
        XCTAssertNil(SnippetAbbreviation.normalize(String(repeating: "a", count: 33)))
        XCTAssertNil(SnippetAbbreviation.normalize(".leading"))
    }

    func testDelimitersAndWordCharacters() {
        XCTAssertTrue(SnippetAbbreviation.isDelimiter(" "))
        XCTAssertTrue(SnippetAbbreviation.isDelimiter("\n"))
        XCTAssertTrue(SnippetAbbreviation.isDelimiter("."))
        XCTAssertFalse(SnippetAbbreviation.isDelimiter("a"))
        XCTAssertTrue(SnippetAbbreviation.isWordCharacter("a"))
        XCTAssertTrue(SnippetAbbreviation.isWordCharacter("9"))
        XCTAssertTrue(SnippetAbbreviation.isWordCharacter("-"))
        XCTAssertFalse(SnippetAbbreviation.isWordCharacter(" "))
    }
}
