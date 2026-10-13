import Foundation

enum ClipText {
    static func previewLine(from text: String, limit: Int = 180) -> String {
        let collapsed = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Character, word, and line counts for text shown in the preview pane.
enum TextLength {
    struct Stats: Equatable, Sendable {
        var characters: Int
        var words: Int
        var lines: Int
    }

    static func stats(for text: String) -> Stats {
        let characters = text.count
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .count
        let lines: Int
        if text.isEmpty {
            lines = 0
        } else {
            lines = ClipLineOps.normalizeNewlines(text)
                .components(separatedBy: "\n")
                .count
        }
        return Stats(characters: characters, words: words, lines: lines)
    }

    static func caption(for text: String) -> String {
        let value = stats(for: text)
        return [
            unit(value.characters, "character", "characters"),
            unit(value.words, "word", "words"),
            unit(value.lines, "line", "lines"),
        ].joined(separator: " · ")
    }

    private static func unit(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

/// Ephemeral preview edits for paste/copy. Never writes to the history store.
enum PreviewPasteDraft {
    static func supports(_ kind: ClipKind) -> Bool {
        switch kind {
        case .image, .file, .color:
            return false
        case .text, .richText, .code, .link, .email:
            return true
        }
    }

    /// Clipboard payload with the draft text. Keeps `contentHash` so paste counts stay on the stored clip.
    /// When the draft matches the stored text, returns the original so rich formats remain.
    static func applying(_ draft: String, to clip: Clip) -> Clip {
        let original = clip.text ?? clip.preview
        if draft == original {
            return clip
        }
        var edited = clip
        edited.text = draft
        edited.html = nil
        edited.rtf = nil
        edited.preview = ClipText.previewLine(from: draft)
        edited.kind = ClipClassifier.classify(
            text: draft,
            html: nil,
            hasRTF: false,
            hasImage: clip.imageRelativePath != nil,
            fileURLs: clip.fileURLs
        )
        edited.colorHex = ColorValue.parse(draft.trimmingCharacters(in: .whitespacesAndNewlines))?.hex
        edited.byteSize = draft.utf8.count
        return edited
    }
}
