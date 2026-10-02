import XCTest

final class PasteTargetTests: XCTestCase {
    func testTerminalsAndEditorsPreferPlainText() {
        XCTAssertTrue(PasteTarget.prefersPlainText(bundleID: "com.apple.Terminal", appName: "Terminal"))
        XCTAssertTrue(PasteTarget.prefersPlainText(bundleID: "com.microsoft.VSCode", appName: "Code"))
        XCTAssertTrue(PasteTarget.prefersPlainText(bundleID: "com.jetbrains.intellij", appName: "IntelliJ IDEA"))
        XCTAssertTrue(PasteTarget.prefersPlainText(bundleID: "com.todesktop.230313mzl4w4u92", appName: "Cursor"))
    }

    func testMailStaysRich() {
        XCTAssertFalse(PasteTarget.prefersPlainText(bundleID: "com.apple.mail", appName: "Mail"))
        XCTAssertFalse(PasteTarget.prefersPlainText(bundleID: "com.apple.TextEdit", appName: "TextEdit"))
    }
}
