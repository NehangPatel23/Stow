import AppKit
import XCTest

final class PasteboardSnapshotTests: XCTestCase {
    func testSnapshotRoundTripRestoresPlainText() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("before-oneshot", forType: .string)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        XCTAssertNotNil(snapshot)

        pasteboard.clearContents()
        pasteboard.setString("temporary-paste-payload", forType: .string)
        XCTAssertEqual(pasteboard.string(forType: .string), "temporary-paste-payload")

        snapshot!.restore(onto: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), "before-oneshot")
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        XCTAssertTrue(types.contains(PasteboardPolicy.originType))
    }

    func testSnapshotSkipsEmptyPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        XCTAssertNil(PasteboardSnapshot.capture(from: pasteboard))
    }
}
