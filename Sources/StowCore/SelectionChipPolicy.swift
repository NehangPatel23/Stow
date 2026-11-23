import Foundation

/// Pure gates and debounce for the selection chip (no AppKit / AX).
enum SelectionChipPolicy {
    static let showDebounce: TimeInterval = 0.25
    static let hideDebounce: TimeInterval = 0.12
    static let maxCharacters = 8_000

    struct Snapshot: Equatable, Sendable {
        var text: String
        var bundleID: String?
    }

    struct GateInput: Equatable, Sendable {
        var enabled: Bool
        var accessibilityTrusted: Bool
        var stowIsFrontmost: Bool
        var stowWindowIsKey: Bool
        var isSecureField: Bool
        var isPaused: Bool
        var excludedBundleIDs: Set<String>
        var frontBundleID: String?
        var selectedText: String?
    }

    static func normalizedSelection(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > maxCharacters {
            return String(trimmed.prefix(maxCharacters))
        }
        return trimmed
    }

    static func shouldMonitor(enabled: Bool, accessibilityTrusted: Bool) -> Bool {
        enabled && accessibilityTrusted
    }

    static func shouldShow(for input: GateInput) -> String? {
        guard input.enabled else { return nil }
        guard input.accessibilityTrusted else { return nil }
        guard !input.stowIsFrontmost else { return nil }
        guard !input.stowWindowIsKey else { return nil }
        guard !input.isSecureField else { return nil }
        guard !input.isPaused else { return nil }
        if let front = input.frontBundleID, input.excludedBundleIDs.contains(front) {
            return nil
        }
        return normalizedSelection(input.selectedText)
    }

    /// Debounce machine: returns the text to display (nil = hide).
    struct Debouncer: Equatable, Sendable {
        private(set) var candidate: String?
        private(set) var candidateSince: Date?
        private(set) var shown: String?
        private(set) var emptySince: Date?

        mutating func tick(normalized: String?, now: Date) -> String? {
            if let normalized {
                emptySince = nil
                if normalized == shown {
                    candidate = normalized
                    candidateSince = now
                    return shown
                }
                if normalized != candidate {
                    candidate = normalized
                    candidateSince = now
                    return shown
                }
                if let since = candidateSince, now.timeIntervalSince(since) >= showDebounce {
                    shown = normalized
                    return shown
                }
                return shown
            }

            candidate = nil
            candidateSince = nil
            if shown == nil {
                emptySince = nil
                return nil
            }
            if emptySince == nil {
                emptySince = now
                return shown
            }
            if let since = emptySince, now.timeIntervalSince(since) >= hideDebounce {
                shown = nil
                emptySince = nil
                return nil
            }
            return shown
        }

        mutating func reset() {
            candidate = nil
            candidateSince = nil
            shown = nil
            emptySince = nil
        }
    }
}
