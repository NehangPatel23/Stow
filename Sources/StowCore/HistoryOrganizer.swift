import Foundation

struct HistorySection: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var entries: [HistoryEntry]

    var clips: [Clip] {
        entries.flatMap(\.members)
    }
}

enum HistoryOrganizer {
    static func sections(
        clips: [Clip],
        now: Date,
        calendar: Calendar = .current,
        burstGap: TimeInterval? = nil
    ) -> [HistorySection] {
        let pinned = clips.filter(\.pinned).sorted { $0.createdAt > $1.createdAt }
        let rest = clips.filter { !$0.pinned }
        var sections: [HistorySection] = []
        if !pinned.isEmpty {
            sections.append(
                HistorySection(
                    id: "pinned",
                    title: "Pinned",
                    entries: entries(from: pinned, burstGap: burstGap)
                )
            )
        }
        for bucket in TimeBucket.allCases {
            let items = rest
                .filter { TimeBucket.bucket(for: $0.createdAt, now: now, calendar: calendar) == bucket }
                .sorted { $0.createdAt > $1.createdAt }
            if !items.isEmpty {
                sections.append(
                    HistorySection(
                        id: bucket.rawValue,
                        title: bucket.title,
                        entries: entries(from: items, burstGap: burstGap)
                    )
                )
            }
        }
        return sections
    }

    /// Pinned first, then a single Frequent section, both ranked by paste count.
    /// Bursts stay off here — frequency order is not chronological.
    static func frequentSections(clips: [Clip]) -> [HistorySection] {
        let pinned = clips.filter(\.pinned).sorted(by: byPasteFrequency)
        let rest = clips.filter { !$0.pinned }.sorted(by: byPasteFrequency)
        var sections: [HistorySection] = []
        if !pinned.isEmpty {
            sections.append(
                HistorySection(
                    id: "pinned",
                    title: "Pinned",
                    entries: pinned.map { .clip($0) }
                )
            )
        }
        if !rest.isEmpty {
            sections.append(
                HistorySection(
                    id: "frequent",
                    title: "Frequent",
                    entries: rest.map { .clip($0) }
                )
            )
        }
        return sections
    }

    static func flattened(_ sections: [HistorySection]) -> [Clip] {
        sections.flatMap(\.clips)
    }

    /// Top-level rows for keyboard and shortcuts. Expanded bursts list every member.
    static func flattenedRepresentatives(
        _ sections: [HistorySection],
        expandedBurstIDs: Set<UUID>
    ) -> [Clip] {
        sections.flatMap { section in
            section.entries.flatMap { entry -> [Clip] in
                switch entry {
                case .clip(let clip):
                    return [clip]
                case .burst(let burst):
                    if expandedBurstIDs.contains(burst.id) {
                        return burst.clips
                    }
                    return [burst.newest]
                }
            }
        }
    }

    private static func entries(from clips: [Clip], burstGap: TimeInterval?) -> [HistoryEntry] {
        guard let burstGap else {
            return clips.map { .clip($0) }
        }
        return CopyBurst.entries(from: clips, gap: burstGap)
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
