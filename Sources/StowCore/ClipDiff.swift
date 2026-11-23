import Foundation

enum ClipDiffLine: Equatable, Sendable {
    case unchanged(String)
    case removed(String)
    case added(String)

    var text: String {
        switch self {
        case .unchanged(let value), .removed(let value), .added(let value):
            value
        }
    }

    var prefix: String {
        switch self {
        case .unchanged: " "
        case .removed: "-"
        case .added: "+"
        }
    }
}

struct ClipDiffResult: Equatable, Sendable {
    var lines: [ClipDiffLine]
    var removedCount: Int
    var addedCount: Int

    var isIdentical: Bool { removedCount == 0 && addedCount == 0 }

    var caption: String {
        if isIdentical { return "No differences" }
        var parts: [String] = []
        if removedCount > 0 {
            parts.append(removedCount == 1 ? "1 removed" : "\(removedCount) removed")
        }
        if addedCount > 0 {
            parts.append(addedCount == 1 ? "1 added" : "\(addedCount) added")
        }
        return parts.joined(separator: " · ")
    }
}

/// Line-based diff for clipboard-sized text. Older uses `-`, newer uses `+`.
enum ClipDiff {
    /// Soft cap so a huge paste does not freeze the panel.
    static let maxLines = 8_000
    /// LCS table size limit after stripping a shared prefix and suffix.
    private static let maxCellCount = 2_000_000

    enum Failure: Error, Equatable, Sendable {
        case tooLarge
    }

    static func compare(_ older: String, _ newer: String) -> Result<ClipDiffResult, Failure> {
        let left = lines(in: older)
        let right = lines(in: newer)
        guard left.count <= maxLines, right.count <= maxLines else {
            return .failure(.tooLarge)
        }
        return .success(diff(left: left, right: right))
    }

    private static func lines(in text: String) -> [String] {
        if text.isEmpty { return [] }
        return ClipLineOps.normalizeNewlines(text).components(separatedBy: "\n")
    }

    private static func diff(left: [String], right: [String]) -> ClipDiffResult {
        if left == right {
            return ClipDiffResult(
                lines: left.map { .unchanged($0) },
                removedCount: 0,
                addedCount: 0
            )
        }

        var prefix = 0
        while prefix < left.count, prefix < right.count, left[prefix] == right[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < left.count - prefix,
              suffix < right.count - prefix,
              left[left.count - 1 - suffix] == right[right.count - 1 - suffix] {
            suffix += 1
        }

        let leftMid = Array(left[prefix..<(left.count - suffix)])
        let rightMid = Array(right[prefix..<(right.count - suffix)])

        let mid: [ClipDiffLine]
        if leftMid.isEmpty {
            mid = rightMid.map { .added($0) }
        } else if rightMid.isEmpty {
            mid = leftMid.map { .removed($0) }
        } else if (leftMid.count + 1) * (rightMid.count + 1) > maxCellCount {
            // Too large for LCS table — fall back to delete-all / add-all for the middle.
            mid = leftMid.map { .removed($0) } + rightMid.map { .added($0) }
        } else {
            mid = lcsDiff(left: leftMid, right: rightMid)
        }

        var lines: [ClipDiffLine] = []
        lines.append(contentsOf: left.prefix(prefix).map { .unchanged($0) })
        lines.append(contentsOf: mid)
        if suffix > 0 {
            lines.append(contentsOf: left.suffix(suffix).map { .unchanged($0) })
        }

        let removed = lines.reduce(0) { partial, line in
            if case .removed = line { return partial + 1 }
            return partial
        }
        let added = lines.reduce(0) { partial, line in
            if case .added = line { return partial + 1 }
            return partial
        }
        return ClipDiffResult(lines: lines, removedCount: removed, addedCount: added)
    }

    private static func lcsDiff(left: [String], right: [String]) -> [ClipDiffLine] {
        let n = left.count
        let m = right.count
        var lengths = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if left[i - 1] == right[j - 1] {
                    lengths[i][j] = lengths[i - 1][j - 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
                }
            }
        }

        var result: [ClipDiffLine] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, left[i - 1] == right[j - 1] {
                result.append(.unchanged(left[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || lengths[i][j - 1] >= lengths[i - 1][j]) {
                result.append(.added(right[j - 1]))
                j -= 1
            } else if i > 0 {
                result.append(.removed(left[i - 1]))
                i -= 1
            }
        }
        return result.reversed()
    }
}
