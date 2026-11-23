import XCTest

final class IgnorePatternPolicyTests: XCTestCase {
    func testNormalizeDropsBlank() {
        XCTAssertNil(IgnorePatternPolicy.normalize("   "))
        XCTAssertEqual(IgnorePatternPolicy.normalize("  foo  "), "foo")
    }

    func testLiteralSubstringIsCaseInsensitive() {
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "Reset password link", pattern: "password"))
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "Reset PASSWORD link", pattern: "Password"))
        XCTAssertFalse(IgnorePatternPolicy.matches(text: "hello", pattern: "password"))
    }

    func testAsteriskMeansContains() {
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "utm_source=newsletter", pattern: "*utm_*"))
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "before-utm_after", pattern: "*utm_"))
        XCTAssertFalse(IgnorePatternPolicy.matches(text: "hello", pattern: "*utm_*"))
    }

    func testSlashWrappedRegex() {
        XCTAssertFalse(IgnorePatternPolicy.matches(text: "code 482913", pattern: #"/^\d{6}$/"#))
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "482913", pattern: #"/^\d{6}$/"#))
        XCTAssertTrue(IgnorePatternPolicy.matches(text: "ABC-123", pattern: #"/[a-z]+-\d+/"#))
        XCTAssertFalse(IgnorePatternPolicy.matches(text: "no digits", pattern: #"/\d{4}/"#))
        XCTAssertFalse(IgnorePatternPolicy.matches(text: "anything", pattern: "//"))
    }

    func testFirstMatchWinsAndSkipsEmpty() {
        let patterns = ["", "  ", "token", "password"]
        XCTAssertEqual(
            IgnorePatternPolicy.firstMatch(in: "my password is secret", patterns: patterns),
            "password"
        )
        XCTAssertEqual(
            IgnorePatternPolicy.firstMatch(in: "bearer token here", patterns: patterns),
            "token"
        )
        XCTAssertNil(IgnorePatternPolicy.firstMatch(in: "plain note", patterns: patterns))
        XCTAssertNil(IgnorePatternPolicy.firstMatch(in: nil, patterns: patterns))
        XCTAssertNil(IgnorePatternPolicy.firstMatch(in: "", patterns: ["password"]))
    }
}
