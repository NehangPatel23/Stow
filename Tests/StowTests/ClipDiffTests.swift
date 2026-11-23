import XCTest

final class ClipDiffTests: XCTestCase {
    func testIdenticalStringsHaveNoChanges() {
        let result = try! ClipDiff.compare("a\nb\nc", "a\nb\nc").get()
        XCTAssertTrue(result.isIdentical)
        XCTAssertEqual(result.lines, [
            .unchanged("a"),
            .unchanged("b"),
            .unchanged("c"),
        ])
        XCTAssertEqual(result.caption, "No differences")
    }

    func testSingleLineChange() {
        let result = try! ClipDiff.compare("hello", "world").get()
        XCTAssertEqual(result.lines, [
            .removed("hello"),
            .added("world"),
        ])
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.addedCount, 1)
    }

    func testInsertedAndDeletedLines() {
        let older = "a\nb\nc"
        let newer = "a\nx\nc\nd"
        let result = try! ClipDiff.compare(older, newer).get()
        XCTAssertEqual(result.lines, [
            .unchanged("a"),
            .removed("b"),
            .added("x"),
            .unchanged("c"),
            .added("d"),
        ])
        XCTAssertEqual(result.caption, "1 removed · 2 added")
    }

    func testBlankLinesArePreserved() {
        let result = try! ClipDiff.compare("a\n\nb", "a\nb").get()
        XCTAssertEqual(result.lines, [
            .unchanged("a"),
            .removed(""),
            .unchanged("b"),
        ])
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.addedCount, 0)
    }

    func testNormalizesCRLF() {
        let result = try! ClipDiff.compare("a\r\nb\r\nc", "a\nb\nx").get()
        XCTAssertEqual(result.lines, [
            .unchanged("a"),
            .unchanged("b"),
            .removed("c"),
            .added("x"),
        ])
    }

    func testEmptyVersusNonEmpty() {
        let result = try! ClipDiff.compare("", "line").get()
        XCTAssertEqual(result.lines, [.added("line")])
        XCTAssertEqual(result.addedCount, 1)
    }

    func testMultipleHunks() {
        let older = """
        keep
        old-one
        mid
        old-two
        end
        """
        let newer = """
        keep
        new-one
        mid
        new-two
        end
        """
        let result = try! ClipDiff.compare(older, newer).get()
        XCTAssertEqual(result.removedCount, 2)
        XCTAssertEqual(result.addedCount, 2)
        XCTAssertEqual(result.lines.filter {
            if case .unchanged("keep") = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(result.lines.filter {
            if case .unchanged("mid") = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(result.lines.filter {
            if case .unchanged("end") = $0 { return true }
            return false
        }.count, 1)
    }

    func testTooLargeFails() {
        let line = String(repeating: "x", count: 8)
        let older = (0..<(ClipDiff.maxLines + 1)).map { "\(line)-\($0)" }.joined(separator: "\n")
        let newer = older + "\nextra"
        let outcome = ClipDiff.compare(older, newer)
        guard case .failure(.tooLarge) = outcome else {
            return XCTFail("expected tooLarge")
        }
    }
}
