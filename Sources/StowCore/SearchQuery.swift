import Foundation

struct SearchQuery: Equatable, Sendable {
    var terms: [String]
    var kind: ClipKind?
    var app: String?
    var bucket: TimeBucket?
    var pinnedOnly: Bool
    var collection: String?
    var abbreviation: String?
    /// Set when two kind filters disagree, so the list stays empty instead of guessing.
    var impossible: Bool

    static let empty = SearchQuery(
        terms: [],
        kind: nil,
        app: nil,
        bucket: nil,
        pinnedOnly: false,
        collection: nil,
        abbreviation: nil,
        impossible: false
    )

    static func parse(_ raw: String) -> SearchQuery {
        var query = SearchQuery.empty
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        var terms: [String] = []
        for token in tokens {
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, !parts[1].isEmpty else {
                terms.append(token)
                continue
            }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "type", "kind":
                if let kind = ClipKind.fromSearchToken(value) {
                    if let existing = query.kind, existing != kind {
                        query.impossible = true
                    }
                    query.kind = kind
                } else {
                    terms.append(token)
                }
            case "app", "fromapp":
                query.app = value
            case "from":
                if let bucket = TimeBucket.fromSearchToken(value) {
                    query.bucket = bucket
                } else {
                    terms.append(token)
                }
            case "pin", "pinned", "is":
                let normalized = value.lowercased()
                if normalized == "true" || normalized == "yes" || normalized == "pinned" || normalized == "1" {
                    query.pinnedOnly = true
                } else {
                    terms.append(token)
                }
            case "board", "collection":
                query.collection = value
            case "abbr", "abbreviation":
                query.abbreviation = value
            default:
                terms.append(token)
            }
        }
        query.terms = terms
        return query
    }

    func merging(kind chipKind: ClipKind?, pinned chipPinned: Bool) -> SearchQuery {
        var query = self
        if chipPinned {
            query.pinnedOnly = true
        }
        if let chipKind {
            if let existing = query.kind, existing != chipKind {
                query.impossible = true
            } else {
                query.kind = chipKind
            }
        }
        return query
    }

    func matches(_ clip: Clip, now: Date, calendar: Calendar = .current) -> Bool {
        guard !impossible else { return false }
        if let kind, clip.kind != kind { return false }
        if pinnedOnly && !clip.pinned { return false }
        if let bucket, TimeBucket.bucket(for: clip.createdAt, now: now, calendar: calendar) != bucket {
            return false
        }
        if let app {
            let haystack = (clip.sourceAppName + " " + clip.sourceBundleID).lowercased()
            if !haystack.contains(app.lowercased()) { return false }
        }
        let searchable = [clip.preview, clip.text ?? "", clip.sourceAppName].joined(separator: "\n").lowercased()
        return terms.allSatisfy { searchable.contains($0.lowercased()) }
    }

    func matches(_ snippet: Snippet, collectionName: ((UUID) -> String?)? = nil) -> Bool {
        guard !impossible else { return false }
        if pinnedOnly && !snippet.pinned { return false }
        if bucket != nil || app != nil { return false }
        if let kind, snippet.kind != kind { return false }
        if let abbreviation {
            guard let marked = snippet.normalizedAbbreviation,
                  marked == abbreviation.lowercased() || marked.contains(abbreviation.lowercased()) else {
                return false
            }
        }
        if let collection {
            let needle = collection.lowercased()
            if needle == "none" || needle == "unfiled" {
                if snippet.collectionID != nil { return false }
            } else if let id = snippet.collectionID {
                let name = collectionName?(id)?.lowercased() ?? ""
                if !name.contains(needle) { return false }
            } else {
                return false
            }
        }
        let searchable = [
            snippet.title,
            snippet.text,
            snippet.normalizedAbbreviation ?? "",
        ].joined(separator: "\n").lowercased()
        return terms.allSatisfy { searchable.contains($0.lowercased()) }
    }

    func highlightRanges(in text: String) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        let lowered = text.lowercased()
        for term in terms {
            let needle = term.lowercased()
            guard !needle.isEmpty else { continue }
            var searchStart = lowered.startIndex
            while searchStart < lowered.endIndex,
                  let found = lowered.range(of: needle, range: searchStart..<lowered.endIndex) {
                ranges.append(found)
                searchStart = found.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }
}
