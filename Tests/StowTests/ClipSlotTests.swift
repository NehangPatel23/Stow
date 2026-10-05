import XCTest

final class ClipSlotTests: XCTestCase {
    func testDefaultsProvideFiveEmptySlotsWithControlOptionDigits() {
        let slots = SlotStore.defaults()
        XCTAssertEqual(slots.count, 5)
        XCTAssertTrue(slots.allSatisfy(\.isEmpty))
        XCTAssertEqual(slots.map(\.hotkeyLabel), ["⌃⌥1", "⌃⌥2", "⌃⌥3", "⌃⌥4", "⌃⌥5"])
        XCTAssertEqual(Set(slots.map(\.hotkeyCarbonModifiers)).count, 1)
        XCTAssertEqual(slots[0].hotkeyCarbonModifiers, SlotStore.defaultCarbonModifiers)
    }

    func testPayloadRoundTripThroughUserDefaults() {
        let suite = "Stow.ClipSlotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var slots = SlotStore.defaults()
        let clip = Clip(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            pinned: false,
            sourceAppName: "Safari",
            sourceBundleID: "com.apple.Safari",
            kind: .text,
            preview: "hello slot",
            text: "hello slot",
            html: nil,
            rtf: nil,
            imageRelativePath: nil,
            thumbRelativePath: nil,
            fileURLs: [],
            colorHex: nil,
            contentHash: "abc",
            imageWidth: nil,
            imageHeight: nil,
            byteSize: 10,
            copyCount: 1,
            ocrText: nil
        )
        slots[1].payload = SlotPayload.from(clip: clip, imagePNG: nil)
        SlotStore.save(slots, defaults: defaults)

        let loaded = SlotStore.load(defaults: defaults)
        XCTAssertEqual(loaded[1].payload?.text, "hello slot")
        XCTAssertEqual(loaded[1].payload?.asClip().kind, .text)
        XCTAssertTrue(loaded[0].isEmpty)
    }

    func testMergeFillsMissingSlotIndexes() {
        let partial = [
            ClipSlot(
                index: 2,
                name: "Scratch",
                payload: nil,
                hotkeyKeyCode: 19,
                hotkeyCarbonModifiers: SlotStore.defaultCarbonModifiers,
                hotkeyLabel: "⌃⌥2"
            ),
        ]
        let merged = SlotStore.merge(partial)
        XCTAssertEqual(merged.count, 5)
        XCTAssertEqual(merged[1].name, "Scratch")
        XCTAssertEqual(merged[0].name, "Slot 1")
    }
}
