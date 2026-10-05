import AppKit
import XCTest

final class ImageOCRTests: XCTestCase {
    func testRecognizesRenderedText() throws {
        let phrase = "ERROR-CODE-42"
        let png = try XCTUnwrap(renderPNG(text: phrase))
        let recognized = try XCTUnwrap(ImageOCR.recognizeText(in: png))
        XCTAssertTrue(
            recognized.uppercased().contains(phrase),
            "Expected OCR to find \(phrase), got: \(recognized)"
        )
    }

    func testEmptyDataReturnsNil() {
        XCTAssertNil(ImageOCR.recognizeText(in: Data()))
    }

    func testSearchMatchesOCRTextOnImageClips() {
        let clip = makeClip(
            text: "800 × 600 · 12 KB",
            kind: .image,
            ocrText: "Connection refused on port 5432"
        )
        XCTAssertTrue(SearchQuery.parse("5432").matches(clip, now: Date()))
        XCTAssertTrue(SearchQuery.parse("type:image refused").matches(clip, now: Date()))
        XCTAssertFalse(SearchQuery.parse("missing-token").matches(clip, now: Date()))
    }

    func testStorePersistsOCRAndListsPendingHashes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)

        let bytes = try XCTUnwrap(renderPNG(text: "PENDING-OCR"))
        var draft = makeDraft(text: "shot", kind: .image, hash: ContentHash.image(bytes))
        draft.imagePNG = bytes
        draft.thumbnailPNG = Data([0x01])
        let clip = try store.record(draft)
        XCTAssertNil(clip.ocrText)
        XCTAssertEqual(try store.imageHashesNeedingOCR(), [clip.contentHash])

        try store.updateOCRText(contentHash: clip.contentHash, ocrText: "PENDING-OCR")
        XCTAssertTrue(try store.imageHashesNeedingOCR().isEmpty)

        let loaded = try XCTUnwrap(store.payload(id: clip.id))
        XCTAssertEqual(loaded.ocrText, "PENDING-OCR")
        XCTAssertTrue(SearchQuery.parse("PENDING").matches(loaded, now: Date()))
    }

    private func renderPNG(text: String) -> Data? {
        let size = NSSize(width: 520, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .semibold),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(at: NSPoint(x: 24, y: 40), withAttributes: attributes)
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
