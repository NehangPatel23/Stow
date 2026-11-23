import Foundation

/// Shared snapshot + pause mirror for the snippets widget (Application Support, no App Group).
enum StowAppGroup {
    /// Kept as the widget kind id; not an App Group container.
    static let identifier = "com.nehangpatel.Stow.widget"
    static let snapshotFileName = "widget-snapshot.json"
    static let widgetKind = "StowSnippetsWidget"
    static let pauseDidChangeNotification = Notification.Name("com.nehangpatel.Stow.pauseDidChange")
    static let pauseGenerationKey = "Stow.Widget.PauseGeneration"
    static let manuallyPausedKey = "Stow.Widget.ManuallyPaused"
    private static let defaultsSuite = "com.nehangpatel.Stow.widgetbridge"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: defaultsSuite) ?? .standard
    }

    static var supportDirectory: URL? {
        guard let root = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return root.appendingPathComponent("Stow", isDirectory: true)
    }

    static var snapshotURL: URL? {
        supportDirectory?.appendingPathComponent(snapshotFileName, isDirectory: false)
    }
}

struct WidgetSnippetItem: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var preview: String
    var text: String
    var kind: String
    var symbolName: String
    var pinned: Bool
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var isPaused: Bool
    var snippets: [WidgetSnippetItem]

    static let empty = WidgetSnapshot(updatedAt: .distantPast, isPaused: false, snippets: [])
    static let maxSnippets = 6

    static func make(snippets: [WidgetSnippetItem], isPaused: Bool, now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: now,
            isPaused: isPaused,
            snippets: Array(snippets.prefix(maxSnippets))
        )
    }
}

enum WidgetSnapshotStore {
    static func load() -> WidgetSnapshot {
        guard let url = StowAppGroup.snapshotURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return decoded
    }

    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = StowAppGroup.snapshotURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Pinned first, then sort order, then newest — same spirit as the snippets list.
    static func orderedItems(
        from snippets: [(id: UUID, title: String, text: String, kind: String, symbolName: String, pinned: Bool, sortOrder: Int, createdAt: Date)]
    ) -> [WidgetSnippetItem] {
        let sorted = snippets.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt > $1.createdAt
        }
        return sorted.prefix(WidgetSnapshot.maxSnippets).map { item in
            WidgetSnippetItem(
                id: item.id,
                title: item.title,
                preview: previewLine(item.text, limit: 72),
                text: item.text,
                kind: item.kind,
                symbolName: item.symbolName,
                pinned: item.pinned
            )
        }
    }

    private static func previewLine(_ text: String, limit: Int) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        let collapsed: String = {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return trimmed }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }
}

enum WidgetPauseBridge {
    static func readMirroredPaused() -> Bool {
        StowAppGroup.defaults.bool(forKey: StowAppGroup.manuallyPausedKey)
    }

    static func pauseGeneration() -> Int {
        StowAppGroup.defaults.integer(forKey: StowAppGroup.pauseGenerationKey)
    }

    /// Writes pause for the widget / Shortcuts and bumps a generation the app can observe.
    static func publishPaused(_ paused: Bool) {
        let defaults = StowAppGroup.defaults
        defaults.set(paused, forKey: StowAppGroup.manuallyPausedKey)
        defaults.set(pauseGeneration() + 1, forKey: StowAppGroup.pauseGenerationKey)
        defaults.synchronize()
        DistributedNotificationCenter.default().post(
            name: StowAppGroup.pauseDidChangeNotification,
            object: nil
        )
    }

    /// Keeps the mirror aligned when the main app toggles pause itself.
    static func mirrorPaused(_ paused: Bool) {
        let defaults = StowAppGroup.defaults
        defaults.set(paused, forKey: StowAppGroup.manuallyPausedKey)
        defaults.synchronize()
    }
}
