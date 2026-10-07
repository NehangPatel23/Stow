import Foundation

struct HistorySection: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var clips: [Clip]
}

enum HistoryOrganizer {
    static func sections(clips: [Clip], now: Date, calendar: Calendar = .current) -> [HistorySection] {
        let pinned = clips.filter(\.pinned).sorted { $0.createdAt > $1.createdAt }
        let rest = clips.filter { !$0.pinned }
        var sections: [HistorySection] = []
        if !pinned.isEmpty {
            sections.append(HistorySection(id: "pinned", title: "Pinned", clips: pinned))
        }
        for bucket in TimeBucket.allCases {
            let items = rest
                .filter { TimeBucket.bucket(for: $0.createdAt, now: now, calendar: calendar) == bucket }
                .sorted { $0.createdAt > $1.createdAt }
            if !items.isEmpty {
                sections.append(HistorySection(id: bucket.rawValue, title: bucket.title, clips: items))
            }
        }
        return sections
    }

    /// Pinned first, then a single Frequent section, both ranked by paste count.
    static func frequentSections(clips: [Clip]) -> [HistorySection] {
        let pinned = clips.filter(\.pinned).sorted(by: byPasteFrequency)
        let rest = clips.filter { !$0.pinned }.sorted(by: byPasteFrequency)
        var sections: [HistorySection] = []
        if !pinned.isEmpty {
            sections.append(HistorySection(id: "pinned", title: "Pinned", clips: pinned))
        }
        if !rest.isEmpty {
            sections.append(HistorySection(id: "frequent", title: "Frequent", clips: rest))
        }
        return sections
    }

    static func flattened(_ sections: [HistorySection]) -> [Clip] {
        sections.flatMap(\.clips)
    }

    private static func byPasteFrequency(_ lhs: Clip, _ rhs: Clip) -> Bool {
        if lhs.pasteCount != rhs.pasteCount {
            return lhs.pasteCount > rhs.pasteCount
        }
        switch (lhs.lastPastedAt, rhs.lastPastedAt) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.createdAt > rhs.createdAt
        }
    }
}
