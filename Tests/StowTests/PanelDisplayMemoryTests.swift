import AppKit
import XCTest

final class PanelDisplayMemoryTests: XCTestCase {
    func testPreferredScreenFallsBackWhenMissing() {
        let fallback = NSScreen.main
        XCTAssertEqual(
            PanelDisplayMemory.preferredScreen(savedDisplayID: 0xDEAD_BEEF, fallback: fallback),
            fallback
        )
    }

    func testDisplayIDRoundTripOnMainScreen() {
        guard let main = NSScreen.main, let id = PanelDisplayMemory.displayID(for: main) else {
            XCTFail("Expected a main screen with a display ID")
            return
        }
        XCTAssertEqual(PanelDisplayMemory.screen(forDisplayID: id), main)
        XCTAssertEqual(
            PanelDisplayMemory.preferredScreen(savedDisplayID: id, fallback: nil),
            main
        )
    }
}
