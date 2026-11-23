import XCTest

final class SelectionChipPolicyTests: XCTestCase {
    func testNormalizedSelectionTrimsAndCaps() {
        XCTAssertNil(SelectionChipPolicy.normalizedSelection(nil))
        XCTAssertNil(SelectionChipPolicy.normalizedSelection("   \n"))
        XCTAssertEqual(SelectionChipPolicy.normalizedSelection("  hello  "), "hello")
        let long = String(repeating: "a", count: SelectionChipPolicy.maxCharacters + 40)
        let capped = SelectionChipPolicy.normalizedSelection(long)
        XCTAssertEqual(capped?.count, SelectionChipPolicy.maxCharacters)
    }

    func testShouldMonitorRequiresTrustAndToggle() {
        XCTAssertFalse(SelectionChipPolicy.shouldMonitor(enabled: true, accessibilityTrusted: false))
        XCTAssertFalse(SelectionChipPolicy.shouldMonitor(enabled: false, accessibilityTrusted: true))
        XCTAssertTrue(SelectionChipPolicy.shouldMonitor(enabled: true, accessibilityTrusted: true))
    }

    func testShouldShowGates() {
        let base = SelectionChipPolicy.GateInput(
            enabled: true,
            accessibilityTrusted: true,
            stowIsFrontmost: false,
            stowWindowIsKey: false,
            isSecureField: false,
            isPaused: false,
            excludedBundleIDs: ["com.excluded"],
            frontBundleID: "com.apple.TextEdit",
            selectedText: "  selected  "
        )
        XCTAssertEqual(SelectionChipPolicy.shouldShow(for: base), "selected")

        var paused = base
        paused.isPaused = true
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: paused))

        var secure = base
        secure.isSecureField = true
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: secure))

        var stowFront = base
        stowFront.stowIsFrontmost = true
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: stowFront))

        var chrome = base
        chrome.stowWindowIsKey = true
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: chrome))

        var excluded = base
        excluded.frontBundleID = "com.excluded"
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: excluded))

        var off = base
        off.enabled = false
        XCTAssertNil(SelectionChipPolicy.shouldShow(for: off))
    }

    func testDebouncerShowAndHide() {
        var debouncer = SelectionChipPolicy.Debouncer()
        let t0 = Date()
        XCTAssertNil(debouncer.tick(normalized: "one", now: t0))
        XCTAssertNil(debouncer.tick(normalized: "one", now: t0.addingTimeInterval(0.1)))
        XCTAssertEqual(
            debouncer.tick(normalized: "one", now: t0.addingTimeInterval(SelectionChipPolicy.showDebounce)),
            "one"
        )
        XCTAssertEqual(
            debouncer.tick(normalized: "one", now: t0.addingTimeInterval(SelectionChipPolicy.showDebounce + 0.05)),
            "one"
        )

        let hideStart = t0.addingTimeInterval(1)
        XCTAssertEqual(debouncer.tick(normalized: nil, now: hideStart), "one")
        XCTAssertNil(
            debouncer.tick(
                normalized: nil,
                now: hideStart.addingTimeInterval(SelectionChipPolicy.hideDebounce)
            )
        )
    }

    func testDebouncerResetsShowClockWhenTextChanges() {
        var debouncer = SelectionChipPolicy.Debouncer()
        let t0 = Date()
        XCTAssertNil(debouncer.tick(normalized: "a", now: t0))
        XCTAssertNil(debouncer.tick(normalized: "b", now: t0.addingTimeInterval(0.2)))
        XCTAssertNil(debouncer.tick(normalized: "b", now: t0.addingTimeInterval(0.3)))
        XCTAssertEqual(
            debouncer.tick(normalized: "b", now: t0.addingTimeInterval(0.2 + SelectionChipPolicy.showDebounce)),
            "b"
        )
    }
}
