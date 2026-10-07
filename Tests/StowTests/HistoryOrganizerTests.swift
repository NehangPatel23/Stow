import XCTest

final class HistoryOrganizerTests: XCTestCase {
    func testPinnedSectionStaysAboveTimeGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let older = calendar.date(byAdding: .day, value: -10, to: now)!
        let clips = [
            makeClip(text: "now", createdAt: today, hash: "a"),
            makeClip(text: "pin", pinned: true, createdAt: older, hash: "b"),
            makeClip(text: "yday", createdAt: yesterday, hash: "c"),
        ]
        let sections = HistoryOrganizer.sections(clips: clips, now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Today", "Yesterday"])
        XCTAssertEqual(sections[0].clips.map(\.text), ["pin"])
    }

    func testFrequentSectionsRankByPasteCountWithPinnedFirst() {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let clips = [
            makeClip(text: "unused", createdAt: newer, hash: "u", pasteCount: 0),
            makeClip(text: "common", createdAt: older, hash: "c", pasteCount: 3, lastPastedAt: older),
            makeClip(text: "pin-low", pinned: true, createdAt: older, hash: "p", pasteCount: 1),
            makeClip(
                text: "recent-use",
                createdAt: older,
                hash: "r",
                pasteCount: 3,
                lastPastedAt: newer
            ),
        ]
        let sections = HistoryOrganizer.frequentSections(clips: clips)
        XCTAssertEqual(sections.map(\.title), ["Pinned", "Frequent"])
        XCTAssertEqual(sections[0].clips.map(\.text), ["pin-low"])
        XCTAssertEqual(sections[1].clips.map(\.text), ["recent-use", "common", "unused"])
    }
}
