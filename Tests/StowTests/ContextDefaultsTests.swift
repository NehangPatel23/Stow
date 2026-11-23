import XCTest

final class ContextDefaultsTests: XCTestCase {
    func testPerAppBeatsFocus() {
        let boardID = UUID()
        let rules = [
            PerAppContextRule(
                bundleID: "com.apple.Terminal",
                name: "Terminal",
                board: .snippetsUnfiled,
                pasteMode: .plain
            ),
        ]
        let focusOn = FocusContextDefaults(enabled: true, board: .collection(boardID), pasteMode: .rich)
        let resolved = ContextDefaultsResolver.resolve(
            bundleID: "com.apple.Terminal",
            isFocused: true,
            perAppRules: rules,
            focusOn: focusOn,
            focusOff: FocusContextDefaults(),
            knownCollections: [boardID]
        )
        XCTAssertEqual(resolved.source, .perApp)
        XCTAssertEqual(resolved.board, .snippetsUnfiled)
        XCTAssertEqual(resolved.pasteMode, .plain)
    }

    func testFocusOnAppliesWhenEnabled() {
        let resolved = ContextDefaultsResolver.resolve(
            bundleID: "com.apple.mail",
            isFocused: true,
            perAppRules: [],
            focusOn: FocusContextDefaults(enabled: true, board: .snippetsAll, pasteMode: .plain),
            focusOff: FocusContextDefaults(enabled: true, board: .history, pasteMode: .auto),
            knownCollections: []
        )
        XCTAssertEqual(resolved.source, .focusOn)
        XCTAssertEqual(resolved.board, .snippetsAll)
        XCTAssertEqual(resolved.pasteMode, .plain)
    }

    func testFocusOffAppliesWhenEnabled() {
        let resolved = ContextDefaultsResolver.resolve(
            bundleID: nil,
            isFocused: false,
            perAppRules: [],
            focusOn: FocusContextDefaults(enabled: true, board: .snippetsAll, pasteMode: .plain),
            focusOff: FocusContextDefaults(enabled: true, board: .history, pasteMode: .rich),
            knownCollections: []
        )
        XCTAssertEqual(resolved.source, .focusOff)
        XCTAssertEqual(resolved.pasteMode, .rich)
    }

    func testMissingFocusStatusSkipsFocusRules() {
        let resolved = ContextDefaultsResolver.resolve(
            bundleID: nil,
            isFocused: nil,
            perAppRules: [],
            focusOn: FocusContextDefaults(enabled: true, board: .snippetsAll, pasteMode: .plain),
            focusOff: FocusContextDefaults(enabled: true, board: .history, pasteMode: .rich),
            knownCollections: []
        )
        XCTAssertEqual(resolved.source, .none)
        XCTAssertNil(resolved.board)
        XCTAssertNil(resolved.pasteMode)
    }

    func testDeletedCollectionFallsBackToSnippetsAll() {
        let missing = UUID()
        let resolved = ContextDefaultsResolver.resolve(
            bundleID: "com.apple.Safari",
            isFocused: nil,
            perAppRules: [
                PerAppContextRule(
                    bundleID: "com.apple.Safari",
                    name: "Safari",
                    board: .collection(missing),
                    pasteMode: .auto
                ),
            ],
            focusOn: FocusContextDefaults(),
            focusOff: FocusContextDefaults(),
            knownCollections: []
        )
        XCTAssertEqual(resolved.board, .snippetsAll)
    }

    func testPasteResolverPrecedence() {
        XCTAssertTrue(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: true,
                clipKind: .text,
                bundleID: "com.apple.mail",
                appName: "Mail",
                sessionMode: .rich
            )
        )
        XCTAssertTrue(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: false,
                clipKind: .text,
                bundleID: "com.apple.mail",
                appName: "Mail",
                sessionMode: .plain
            )
        )
        XCTAssertFalse(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: false,
                clipKind: .text,
                bundleID: "com.apple.Terminal",
                appName: "Terminal",
                sessionMode: .rich
            )
        )
        XCTAssertTrue(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: false,
                clipKind: .code,
                bundleID: "com.apple.mail",
                appName: "Mail",
                sessionMode: .rich
            )
        )
        XCTAssertTrue(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: false,
                clipKind: .text,
                bundleID: "com.apple.Terminal",
                appName: "Terminal",
                sessionMode: .auto
            )
        )
        XCTAssertFalse(
            ContextPasteResolver.shouldPastePlain(
                requestedPlain: false,
                clipKind: .text,
                bundleID: "com.apple.mail",
                appName: "Mail",
                sessionMode: .auto
            )
        )
    }
}
