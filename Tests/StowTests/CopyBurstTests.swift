import XCTest

final class CopyBurstTests: XCTestCase {
    func testGroupsSameAppWithinGap() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clips = [
            makeClip(text: "c", createdAt: t0.addingTimeInterval(4), bundle: "com.apple.Safari", hash: "c"),
            makeClip(text: "b", createdAt: t0.addingTimeInterval(2), bundle: "com.apple.Safari", hash: "b"),
            makeClip(text: "a", createdAt: t0, bundle: "com.apple.Safari", hash: "a"),
        ]
        let entries = CopyBurst.entries(from: clips, gap: 5)
        XCTAssertEqual(entries.count, 1)
        guard case .burst(let burst) = entries[0] else {
            return XCTFail("expected one burst")
        }
        XCTAssertEqual(burst.count, 3)
        XCTAssertEqual(burst.clips.map(\.text), ["c", "b", "a"])
        XCTAssertEqual(burst.id, clips[0].id)
    }

    func testBreaksOnGap() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clips = [
            makeClip(text: "new", createdAt: t0.addingTimeInterval(20), bundle: "com.apple.Safari", hash: "n"),
            makeClip(text: "old", createdAt: t0, bundle: "com.apple.Safari", hash: "o"),
        ]
        let entries = CopyBurst.entries(from: clips, gap: 5)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.representative.text), ["new", "old"])
    }

    func testBreaksOnDifferentApp() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clips = [
            makeClip(text: "safari", createdAt: t0.addingTimeInterval(1), app: "Safari", bundle: "com.apple.Safari", hash: "s"),
            makeClip(text: "notes", createdAt: t0, app: "Notes", bundle: "com.apple.Notes", hash: "n"),
        ]
        let entries = CopyBurst.entries(from: clips, gap: 5)
        XCTAssertEqual(entries.count, 2)
        if case .burst = entries[0] { XCTFail("single clips must not burst") }
        if case .burst = entries[1] { XCTFail("single clips must not burst") }
    }

    func testBreaksOnPinnedMismatch() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let clips = [
            makeClip(text: "free", pinned: false, createdAt: t0.addingTimeInterval(1), hash: "f"),
            makeClip(text: "pin", pinned: true, createdAt: t0, hash: "p"),
        ]
        let entries = CopyBurst.entries(from: clips, gap: 5)
        XCTAssertEqual(entries.count, 2)
    }

    func testSingletonsStayAsClips() {
        let clips = [makeClip(text: "alone", hash: "a")]
        let entries = CopyBurst.entries(from: clips, gap: 5)
        XCTAssertEqual(entries.count, 1)
        guard case .clip(let clip) = entries[0] else {
            return XCTFail("expected clip")
        }
        XCTAssertEqual(clip.text, "alone")
    }

    func testOrganizerSectionsApplyBurstsInsideBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clips = [
            makeClip(text: "c", createdAt: now.addingTimeInterval(-1), bundle: "com.apple.Safari", hash: "c"),
            makeClip(text: "b", createdAt: now.addingTimeInterval(-2), bundle: "com.apple.Safari", hash: "b"),
            makeClip(text: "a", createdAt: now.addingTimeInterval(-3), bundle: "com.apple.Safari", hash: "a"),
        ]
        let sections = HistoryOrganizer.sections(clips: clips, now: now, calendar: calendar, burstGap: 5)
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].entries.count, 1)
        guard case .burst(let burst) = sections[0].entries[0] else {
            return XCTFail("expected burst in Today")
        }
        XCTAssertEqual(burst.count, 3)
        XCTAssertEqual(sections[0].clips.count, 3)
    }

    func testFlattenedRepresentativesExpandBursts() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = makeClip(text: "a", createdAt: t0.addingTimeInterval(2), bundle: "com.a", hash: "a")
        let b = makeClip(text: "b", createdAt: t0, bundle: "com.a", hash: "b")
        let sections = [
            HistorySection(
                id: "today",
                title: "Today",
                entries: [.burst(CopyBurst(id: a.id, clips: [a, b]))]
            ),
        ]
        let collapsed = HistoryOrganizer.flattenedRepresentatives(sections, expandedBurstIDs: [])
        XCTAssertEqual(collapsed.map(\.text), ["a"])
        let expanded = HistoryOrganizer.flattenedRepresentatives(sections, expandedBurstIDs: [a.id])
        XCTAssertEqual(expanded.map(\.text), ["a", "b"])
    }
}
