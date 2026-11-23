import Foundation

/// User-written patterns that mean a copy should never enter history.
/// Empty list by default. Order is first match wins.
///
/// Syntax (after trim):
/// - `/pattern/` — case-insensitive regular expression (contents between the slashes)
/// - `*token*` — case-insensitive substring (asterisks stripped from ends only)
/// - anything else — case-insensitive literal substring
enum IgnorePatternPolicy {
    static func normalize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// First matching pattern string, or nil if none match / text is empty.
    static func firstMatch(in text: String?, patterns: [String]) -> String? {
        guard let text, !text.isEmpty else { return nil }
        for raw in patterns {
            guard let pattern = normalize(raw) else { continue }
            if matches(text: text, pattern: pattern) {
                return pattern
            }
        }
        return nil
    }

    static func matches(text: String, pattern: String) -> Bool {
        if pattern.count >= 2, pattern.first == "/", pattern.last == "/" {
            let body = String(pattern.dropFirst().dropLast())
            guard !body.isEmpty else { return false }
            return text.range(of: body, options: [.regularExpression, .caseInsensitive]) != nil
        }

        var needle = pattern
        if needle.hasPrefix("*") { needle = String(needle.dropFirst()) }
        if needle.hasSuffix("*") { needle = String(needle.dropLast()) }
        guard !needle.isEmpty else { return false }
        return text.range(of: needle, options: .caseInsensitive) != nil
    }
}
