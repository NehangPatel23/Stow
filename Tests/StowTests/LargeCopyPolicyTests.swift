import Foundation
import XCTest

final class LargeCopyPolicyTests: XCTestCase {
    func testNormalization() {
        XCTAssertEqual(LargeCopyPolicy.normalizedMaxBytes(50 * 1024 * 1024), 50 * 1024 * 1024)
        XCTAssertEqual(LargeCopyPolicy.normalizedMaxBytes(99), LargeCopyPolicy.defaultMaxBytes)
        XCTAssertEqual(LargeCopyPolicy.maxBytesTitle(10 * 1024 * 1024), "10 MB")
    }

    func testEstimatesImageAndTextPayload() {
        let png = Data(repeating: 0xAB, count: 1_024)
        let thumb = Data(repeating: 0xCD, count: 64)
        var draft = makeDraft(text: "hello", kind: .image)
        draft.imagePNG = png
        draft.thumbnailPNG = thumb
        draft.rtf = Data(repeating: 0x01, count: 200)
        draft.html = "<b>hi</b>"
        let expected = 1_024 + 64 + "hello".utf8.count + "<b>hi</b>".utf8.count + 200
        XCTAssertEqual(LargeCopyPolicy.estimatedStorageBytes(draft), expected)
        draft.imagePNG = Data(repeating: 0xAB, count: 11 * 1024 * 1024)
        XCTAssertTrue(LargeCopyPolicy.exceedsCap(draft, maxBytes: 10 * 1024 * 1024))
        XCTAssertFalse(LargeCopyPolicy.exceedsCap(draft, maxBytes: 50 * 1024 * 1024))
    }

    func testReferenceDropsFullImageAndRichPayload() {
        var draft = makeDraft(text: "note", kind: .image)
        draft.imagePNG = Data(repeating: 0x11, count: 4_096)
        draft.thumbnailPNG = Data(repeating: 0x22, count: 32)
        draft.imageWidth = 2000
        draft.imageHeight = 1000
        draft.rtf = Data(repeating: 0x33, count: 500)
        draft.html = "<p>x</p>"
        let estimated = LargeCopyPolicy.estimatedStorageBytes(draft)
        LargeCopyPolicy.applyReferenceStorage(&draft, estimatedBytes: estimated)
        XCTAssertNil(draft.imagePNG)
        XCTAssertNotNil(draft.thumbnailPNG)
        XCTAssertNil(draft.rtf)
        XCTAssertNil(draft.html)
        XCTAssertEqual(draft.byteSize, estimated)
        XCTAssertTrue(draft.preview.contains("Reference only"))
        XCTAssertTrue(draft.preview.contains("2000 × 1000"))
    }

    func testReferenceMarksFilePreview() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowLargeCopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("movie.mov")
        let payload = Data(repeating: 0x55, count: 2_048)
        try payload.write(to: file)

        var draft = makeDraft(text: "", kind: .file)
        draft.fileURLs = [file.path]
        draft.preview = "movie.mov"
        let estimated = LargeCopyPolicy.estimatedStorageBytes(draft)
        XCTAssertEqual(estimated, 2_048)
        LargeCopyPolicy.applyReferenceStorage(&draft, estimatedBytes: estimated)
        XCTAssertTrue(draft.preview.contains("movie.mov"))
        XCTAssertTrue(draft.preview.contains("Reference only"))
        XCTAssertEqual(draft.byteSize, 2_048)
    }
}
