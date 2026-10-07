import Foundation
import XCTest

func makeDraft(
    text: String,
    kind: ClipKind = .text,
    app: String = "Notes",
    bundle: String = "com.apple.Notes",
    createdAt: Date = Date(),
    hash: String? = nil,
    pinnedIgnored: Bool = false
) -> ClipDraft {
    ClipDraft(
        sourceAppName: app,
        sourceBundleID: bundle,
        kind: kind,
        preview: ClipText.previewLine(from: text),
        text: text,
        html: nil,
        rtf: nil,
        imagePNG: nil,
        thumbnailPNG: nil,
        fileURLs: [],
        colorHex: kind == .color ? ColorValue.parse(text)?.hex : nil,
        contentHash: hash ?? ContentHash.text(text),
        imageWidth: nil,
        imageHeight: nil,
        byteSize: text.utf8.count,
        createdAt: createdAt,
        ocrText: nil
    )
}

func makeClip(
    text: String = "hello",
    kind: ClipKind = .text,
    pinned: Bool = false,
    createdAt: Date = Date(),
    app: String = "Notes",
    bundle: String = "com.apple.Notes",
    hash: String = "hash",
    ocrText: String? = nil,
    pasteCount: Int = 0,
    lastPastedAt: Date? = nil
) -> Clip {
    Clip(
        id: UUID(),
        createdAt: createdAt,
        pinned: pinned,
        sourceAppName: app,
        sourceBundleID: bundle,
        kind: kind,
        preview: text,
        text: text,
        html: nil,
        rtf: nil,
        imageRelativePath: nil,
        thumbRelativePath: nil,
        fileURLs: [],
        colorHex: nil,
        contentHash: hash,
        imageWidth: nil,
        imageHeight: nil,
        byteSize: text.utf8.count,
        copyCount: 1,
        ocrText: ocrText,
        pasteCount: pasteCount,
        lastPastedAt: lastPastedAt
    )
}
