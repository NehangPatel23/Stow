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
}
