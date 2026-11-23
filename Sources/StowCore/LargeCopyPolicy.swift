import Foundation

enum LargeCopyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case reference
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reference: "Store a reference"
        case .skip: "Skip"
        }
    }

    var detail: String {
        switch self {
        case .reference:
            "Keep a thumbnail or file path and a size warning. The full image bytes stay off disk."
        case .skip:
            "Do not store the copy. Keep it from the menu if you want it anyway."
        }
    }
}

/// Cap how much one copy can add to Application Support (and how huge file copies are treated).
enum LargeCopyPolicy {
    static let maxByteChoices = [
        10 * 1024 * 1024,
        25 * 1024 * 1024,
        50 * 1024 * 1024,
        100 * 1024 * 1024,
        250 * 1024 * 1024,
    ]
    static let defaultMaxBytes = 50 * 1024 * 1024

    static func normalizedMaxBytes(_ bytes: Int) -> Int {
        maxByteChoices.contains(bytes) ? bytes : defaultMaxBytes
    }

    static func maxBytesTitle(_ bytes: Int) -> String {
        ByteFormat.string(for: normalizedMaxBytes(bytes))
    }

    /// Bytes Stow would keep for this draft, plus on-disk size of referenced files.
    static func estimatedStorageBytes(_ draft: ClipDraft) -> Int {
        var total = 0
        total += draft.imagePNG?.count ?? 0
        total += draft.thumbnailPNG?.count ?? 0
        total += draft.text?.utf8.count ?? 0
        total += draft.html?.utf8.count ?? 0
        total += draft.rtf?.count ?? 0
        total += fileBytes(draft.fileURLs)
        return total
    }

    static func exceedsCap(_ draft: ClipDraft, maxBytes: Int) -> Bool {
        estimatedStorageBytes(draft) > normalizedMaxBytes(maxBytes)
    }

    /// Drop full image / rich payloads; keep thumb, paths, and a size warning in the preview.
    static func applyReferenceStorage(_ draft: inout ClipDraft, estimatedBytes: Int) {
        let sizeLabel = ByteFormat.string(for: estimatedBytes)
        if draft.imagePNG != nil {
            draft.imagePNG = nil
            if draft.kind == .image {
                if let width = draft.imageWidth, let height = draft.imageHeight {
                    draft.preview = "\(width) × \(height) · \(sizeLabel) · Reference only"
                } else {
                    draft.preview = "Image · \(sizeLabel) · Reference only"
                }
            }
        }
        if draft.rtf != nil {
            draft.rtf = nil
        }
        if draft.html != nil {
            draft.html = nil
        }
        if draft.kind == .file {
            let names = draft.fileURLs.map { URL(fileURLWithPath: $0).lastPathComponent }
            let base = names.isEmpty ? "File" : names.joined(separator: ", ")
            draft.preview = "\(base) · \(sizeLabel) · Reference only"
        }
        draft.byteSize = estimatedBytes
    }

    private static func fileBytes(_ paths: [String]) -> Int {
        var total = 0
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        return total
    }
}
