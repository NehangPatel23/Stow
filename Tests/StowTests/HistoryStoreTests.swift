import XCTest

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: HistoryStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = try HistoryStore(directory: directory)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
    }

    func testDuplicateCopiesFoldAndKeepTheNewestSource() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        _ = try store.record(makeDraft(text: "same", app: "Mail", createdAt: older))
        _ = try store.record(makeDraft(text: "other", createdAt: Date(timeIntervalSince1970: 1_500)))
        _ = try store.record(makeDraft(text: "same", app: "Safari", createdAt: newer))

        let visible = try store.foldedHistory()
        XCTAssertEqual(visible.map(\.preview), ["same", "other"])
        XCTAssertEqual(visible[0].copyCount, 2)
        XCTAssertEqual(visible[0].sourceAppName, "Safari")

        let copies = try store.copies(contentHash: ContentHash.text("same"))
        XCTAssertEqual(copies.map(\.sourceAppName), ["Safari", "Mail"])
    }

    func testPinClearAndSnippetSurvival() throws {
        _ = try store.record(makeDraft(text: "keep"))
        _ = try store.record(makeDraft(text: "drop"))
        try store.setPinned(contentHash: ContentHash.text("keep"), pinned: true)
        _ = try store.addSnippet(title: "Address", text: "1 Main", kind: .text)

        let removed = try store.clearHistory(includingPinned: false)
        XCTAssertEqual(removed.count, 1)
        let remaining = try store.foldedHistory()
        XCTAssertEqual(remaining.map(\.preview), ["keep"])
        XCTAssertTrue(remaining[0].pinned)
        XCTAssertEqual(try store.snippets().map(\.title), ["Address"])

        let everything = try store.clearHistory(includingPinned: true)
        XCTAssertEqual(everything.count, 1)
        XCTAssertTrue(try store.foldedHistory().isEmpty)
        XCTAssertEqual(try store.snippets().count, 1)
    }

    func testDeleteAndRestore() throws {
        _ = try store.record(makeDraft(text: "gone"))
        let deleted = try store.delete(contentHash: ContentHash.text("gone"))
        XCTAssertTrue(try store.foldedHistory().isEmpty)
        try store.restore(clips: deleted)
        XCTAssertEqual(try store.foldedHistory().map(\.preview), ["gone"])
    }

    func testImageFileIsWrittenOnceForTheSameBytes() throws {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        var draft = makeDraft(text: "shot", kind: .image, hash: ContentHash.image(bytes))
        draft.imagePNG = bytes
        draft.thumbnailPNG = Data([0x01, 0x02])
        _ = try store.record(draft)
        _ = try store.record(draft)
        let folded = try store.foldedHistory()
        XCTAssertEqual(folded.count, 1)
        XCTAssertEqual(folded[0].copyCount, 2)
        let imageURL = store.url(forRelativePath: "images/\(draft.contentHash).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        try store.reapImages(hashes: [draft.contentHash])
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        _ = try store.delete(contentHash: draft.contentHash)
        try store.reapImages(hashes: [draft.contentHash])
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }
}
