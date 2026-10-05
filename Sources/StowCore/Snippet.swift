import Foundation

struct SnippetCollection: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
}

struct Snippet: Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var title: String
    var text: String
    var kind: ClipKind
    var pinned: Bool = false
    var collectionID: UUID?
    var sortOrder: Int = 0
    /// Opt-in typing shortcut. `nil` or empty means this snippet never expands.
    var abbreviation: String? = nil

    var preview: String {
        ClipText.previewLine(from: text)
    }

    var templateFields: [TemplateField] {
        SnippetTemplate.fields(in: text)
    }

    var normalizedAbbreviation: String? {
        SnippetAbbreviation.normalize(abbreviation)
    }
}

enum SnippetAbbreviation {
    static let maxLength = 32
    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))

    /// Trims, lowercases, and validates. Empty or invalid input becomes `nil` (off).
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard trimmed.first?.isLetter == true || trimmed.first?.isNumber == true else { return nil }
        return trimmed
    }

    static func isDelimiter(_ character: Character) -> Bool {
        character.isWhitespace || character.isNewline || ".,;:!?)]}'\"/\\".contains(character)
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

struct TemplateField: Identifiable, Equatable, Hashable, Sendable {
    var key: String
    var id: String { key }

    var label: String {
        key
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

enum SnippetTemplate {
    private static let pattern = #"\{\{\s*([A-Za-z][A-Za-z0-9_ ]*)\s*\}\}"#

    static func fields(in text: String) -> [TemplateField] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var seen = Set<String>()
        var fields: [TemplateField] = []
        expression.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: text) else { return }
            let key = text[keyRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            fields.append(TemplateField(key: key))
        }
        return fields
    }

    static func defaults(for fields: [TemplateField], now: Date = Date()) -> [String: String] {
        var values: [String: String] = [:]
        for field in fields {
            switch field.key {
            case "date":
                values[field.key] = now.formatted(date: .abbreviated, time: .omitted)
            case "time":
                values[field.key] = now.formatted(date: .omitted, time: .shortened)
            case "datetime", "date_time":
                values[field.key] = now.formatted(date: .abbreviated, time: .shortened)
            default:
                values[field.key] = ""
            }
        }
        return values
    }

    static func render(_ text: String, values: [String: String]) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var output = text
        let matches = expression.matches(in: text, range: range).reversed()
        for match in matches {
            guard match.numberOfRanges > 1,
                  let full = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: text) else { continue }
            let key = text[keyRange]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            output.replaceSubrange(full, with: values[key] ?? "")
        }
        return output
    }
}
