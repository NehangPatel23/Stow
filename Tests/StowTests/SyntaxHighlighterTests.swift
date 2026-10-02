import XCTest

final class SyntaxHighlighterTests: XCTestCase {
    func testKeywordsStringsAndComments() {
        let runs = SyntaxHighlighter.runs(for: "func add() {\n  // note\n  return \"ok\"\n}\n")
        XCTAssertTrue(runs.contains(SyntaxRun(text: "func", kind: .keyword)))
        XCTAssertTrue(runs.contains { $0.kind == .comment && $0.text.contains("note") })
        XCTAssertTrue(runs.contains { $0.kind == .string && $0.text.contains("ok") })
    }
}
