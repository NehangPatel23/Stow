import Foundation

/// Consecutive copies from the same app within a short gap, shown as one session.
struct CopyBurst: Identifiable, Equatable, Sendable {
    /// Newest member id — used as the collapsed row selection target.
    var id: UUID
    /// Newest first.
    var clips: [Clip]

    var newest: Clip { clips[0] }
    var count: Int { clips.count }
    var sourceAppName: String { newest.sourceAppName }
    var sourceBundleID: String { newest.sourceBundleID }
    var createdAt: Date { newest.createdAt }
    var pinned: Bool { clips.contains(where: \.pinned) }

    /// Default window for “a few seconds apart.”
    static let defaultGap: TimeInterval = 5

    /// Collapse adjacent same-app clips whose timestamps are within `gap`.
    /// Input must be newest-first. Singletons stay as `.clip`.
    static func entries(from clips: [Clip], gap: TimeInterval = defaultGap) -> [HistoryEntry] {
        guard !clips.isEmpty else { return [] }
        var result: [HistoryEntry] = []
        var current: [Clip] = [clips[0]]

        for index in 1..<clips.count {
            let next = clips[index]
            let previous = current[current.count - 1]
            if canJoin(previous, next, gap: gap) {
                current.append(next)
            } else {
                result.append(entry(from: current))
                current = [next]
            }
        }
        result.append(entry(from: current))
        return result
    }

    private static func canJoin(_ newer: Clip, _ older: Clip, gap: TimeInterval) -> Bool {
        guard newer.sourceBundleID == older.sourceBundleID else { return false }
        guard newer.pinned == older.pinned else { return false }
        return newer.createdAt.timeIntervalSince(older.createdAt) <= gap
    }

    private static func entry(from clips: [Clip]) -> HistoryEntry {
        if clips.count == 1 {
            return .clip(clips[0])
        }
        return .burst(CopyBurst(id: clips[0].id, clips: clips))
    }
}

enum HistoryEntry: Identifiable, Equatable, Sendable {
    case clip(Clip)
    case burst(CopyBurst)

    var id: UUID {
        switch self {
        case .clip(let clip): clip.id
        case .burst(let burst): burst.id
        }
    }

    var representative: Clip {
        switch self {
        case .clip(let clip): clip
        case .burst(let burst): burst.newest
        }
    }

    /// All clips in this entry, newest first.
    var members: [Clip] {
        switch self {
        case .clip(let clip): [clip]
        case .burst(let burst): burst.clips
        }
    }
}
