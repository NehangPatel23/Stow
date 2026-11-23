import Foundation

/// How Stow should paste when a context default applies.
enum ContextPasteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case plain
    case rich

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .plain: "Plain"
        case .rich: "Rich"
        }
    }

    var detail: String {
        switch self {
        case .auto: "Terminals and code stay plain; everything else stays rich."
        case .plain: "Always paste plain text for the default paste."
        case .rich: "Prefer rich paste, even into terminals."
        }
    }
}

/// Which library surface to open first.
struct ContextBoardChoice: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case history
        case snippetsAll
        case snippetsUnfiled
        case collection

        var id: String { rawValue }

        var title: String {
            switch self {
            case .history: "History"
            case .snippetsAll: "Snippets · All"
            case .snippetsUnfiled: "Snippets · Unfiled"
            case .collection: "Snippets · Board"
            }
        }
    }

    var kind: Kind
    /// Used when `kind == .collection`.
    var collectionID: UUID?

    static let history = ContextBoardChoice(kind: .history, collectionID: nil)
    static let snippetsAll = ContextBoardChoice(kind: .snippetsAll, collectionID: nil)
    static let snippetsUnfiled = ContextBoardChoice(kind: .snippetsUnfiled, collectionID: nil)

    static func collection(_ id: UUID) -> ContextBoardChoice {
        ContextBoardChoice(kind: .collection, collectionID: id)
    }

    func resolved(knownCollections: Set<UUID>) -> ContextBoardChoice {
        guard kind == .collection else { return self }
        guard let collectionID, knownCollections.contains(collectionID) else {
            return .snippetsAll
        }
        return self
    }
}

struct PerAppContextRule: Codable, Equatable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var board: ContextBoardChoice
    var pasteMode: ContextPasteMode

    var id: String { bundleID }
}

/// Defaults when macOS Focus is on or off. Named Focus modes are not readable publicly.
struct FocusContextDefaults: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var board: ContextBoardChoice = .history
    var pasteMode: ContextPasteMode = .auto
}

struct ContextResolvedDefaults: Equatable, Sendable {
    var board: ContextBoardChoice?
    var pasteMode: ContextPasteMode?
    var source: Source

    enum Source: Equatable, Sendable {
        case none
        case perApp
        case focusOn
        case focusOff
    }
}

enum ContextDefaultsResolver {
    /// Per-app wins over Focus. Missing / unauthorized Focus skips Focus rules.
    static func resolve(
        bundleID: String?,
        isFocused: Bool?,
        perAppRules: [PerAppContextRule],
        focusOn: FocusContextDefaults,
        focusOff: FocusContextDefaults,
        knownCollections: Set<UUID>
    ) -> ContextResolvedDefaults {
        if let bundleID,
           let rule = perAppRules.first(where: { $0.bundleID == bundleID }) {
            return ContextResolvedDefaults(
                board: rule.board.resolved(knownCollections: knownCollections),
                pasteMode: rule.pasteMode,
                source: .perApp
            )
        }

        if let isFocused {
            if isFocused, focusOn.enabled {
                return ContextResolvedDefaults(
                    board: focusOn.board.resolved(knownCollections: knownCollections),
                    pasteMode: focusOn.pasteMode,
                    source: .focusOn
                )
            }
            if !isFocused, focusOff.enabled {
                return ContextResolvedDefaults(
                    board: focusOff.board.resolved(knownCollections: knownCollections),
                    pasteMode: focusOff.pasteMode,
                    source: .focusOff
                )
            }
        }

        return ContextResolvedDefaults(board: nil, pasteMode: nil, source: .none)
    }
}

enum ContextPasteResolver {
    /// Explicit plain always wins. Session mode then Auto (code + PasteTarget).
    static func shouldPastePlain(
        requestedPlain: Bool,
        clipKind: ClipKind,
        bundleID: String?,
        appName: String?,
        sessionMode: ContextPasteMode?
    ) -> Bool {
        if requestedPlain { return true }
        switch sessionMode ?? .auto {
        case .plain:
            return true
        case .rich:
            // Code stays plain even under rich defaults — code paste should not inject RTF.
            return clipKind == .code
        case .auto:
            return clipKind == .code
                || PasteTarget.prefersPlainText(bundleID: bundleID, appName: appName)
        }
    }
}
