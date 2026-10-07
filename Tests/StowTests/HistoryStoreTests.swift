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

    func testSnippetCollectionsAndReorder() throws {
        let support = try store.addCollection(name: "Support")
        let git = try store.addCollection(name: "Git")
        let first = try store.addSnippet(title: "Hello", text: "Hi there", kind: .text, collectionID: support.id)
        let second = try store.addSnippet(title: "Thanks", text: "Thank you", kind: .text, collectionID: support.id)
        _ = try store.addSnippet(title: "Clone", text: "git clone", kind: .code, collectionID: git.id)
        _ = try store.addSnippet(title: "Loose", text: "unfiled", kind: .text)

        XCTAssertEqual(try store.collections().map(\.name), ["Support", "Git"])
        var supportSnippets = try store.snippets().filter { $0.collectionID == support.id }
        XCTAssertEqual(supportSnippets.map(\.title), ["Hello", "Thanks"])

        try store.reorderSnippets(ids: [second.id, first.id])
        supportSnippets = try store.snippets().filter { $0.collectionID == support.id }
        XCTAssertEqual(supportSnippets.map(\.title), ["Thanks", "Hello"])

        try store.setSnippetCollection(id: first.id, collectionID: nil)
        XCTAssertNil(try store.snippets().first { $0.id == first.id }?.collectionID)

        try store.deleteCollection(id: support.id)
        XCTAssertEqual(try store.collections().map(\.name), ["Git"])
        XCTAssertNil(try store.snippets().first { $0.id == second.id }?.collectionID)
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

    func testDeleteExpiredUsesSeparateSchedulesAndKeepsPins() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 10_000)
        _ = try store.record(makeDraft(text: "old-text", createdAt: old))
        _ = try store.record(makeDraft(text: "pinned-old", createdAt: old))
        try store.setPinned(contentHash: ContentHash.text("pinned-old"), pinned: true)
        _ = try store.record(makeDraft(text: "fresh-text", createdAt: recent))

        let imageBytes = Data([0x89, 0x50, 0x4E, 0x47])
        var oldImage = makeDraft(text: "old-image", kind: .image, createdAt: old, hash: ContentHash.image(imageBytes))
        oldImage.imagePNG = imageBytes
        oldImage.thumbnailPNG = Data([0x01])
        _ = try store.record(oldImage)

        var freshImage = makeDraft(
            text: "fresh-image",
            kind: .image,
            createdAt: recent,
            hash: ContentHash.image(Data([0x02, 0x03]))
        )
        freshImage.imagePNG = Data([0x02, 0x03])
        freshImage.thumbnailPNG = Data([0x04])
        _ = try store.record(freshImage)

        let textCutoff = Date(timeIntervalSince1970: 5_000)
        let imageCutoff = Date(timeIntervalSince1970: 5_000)
        let removed = try store.deleteExpired(textOlderThan: textCutoff, imageOlderThan: imageCutoff)
        XCTAssertEqual(Set(removed.map(\.preview)), ["old-text", "old-image"])

        let remaining = try store.foldedHistory().map(\.preview)
        XCTAssertEqual(Set(remaining), ["pinned-old", "fresh-text", "fresh-image"])
        XCTAssertTrue(remaining.contains("pinned-old"))
    }

    func testDeleteExpiredCanTargetOnlyImages() throws {
        let old = Date(timeIntervalSince1970: 1_000)
        _ = try store.record(makeDraft(text: "keep-text", createdAt: old))
        let imageBytes = Data([0x11, 0x22])
        var image = makeDraft(text: "drop-image", kind: .image, createdAt: old, hash: ContentHash.image(imageBytes))
        image.imagePNG = imageBytes
        image.thumbnailPNG = Data([0x33])
        _ = try store.record(image)

        let removed = try store.deleteExpired(
            textOlderThan: nil,
            imageOlderThan: Date(timeIntervalSince1970: 5_000)
        )
        XCTAssertEqual(removed.map(\.preview), ["drop-image"])
        XCTAssertEqual(try store.foldedHistory().map(\.preview), ["keep-text"])
    }

    func testSnippetAbbreviationRoundTripAndUniqueness() throws {
        let first = try store.addSnippet(
            title: "Address",
            text: "1 Main St",
            kind: .text,
            abbreviation: "Addr"
        )
        XCTAssertEqual(first.abbreviation, "addr")
        XCTAssertEqual(try store.snippets().first?.normalizedAbbreviation, "addr")

        XCTAssertThrowsError(
            try store.addSnippet(title: "Other", text: "2 Main", kind: .text, abbreviation: "addr")
        )

        try store.updateSnippet(
            id: first.id,
            title: "Home",
            text: "1 Main Street",
            kind: .text,
            abbreviation: "home"
        )
        XCTAssertEqual(try store.snippets().first?.abbreviation, "home")

        try store.updateSnippet(
            id: first.id,
            title: "Home",
            text: "1 Main Street",
            kind: .text,
            abbreviation: ""
        )
        XCTAssertNil(try store.snippets().first?.normalizedAbbreviation)
    }

    func testRecordPasteIncrementsByHashAndFoldingKeepsSharedCount() throws {
        let hash = ContentHash.text("paste-me")
        _ = try store.record(makeDraft(text: "paste-me", createdAt: Date(timeIntervalSince1970: 1_000)))
        _ = try store.record(makeDraft(text: "paste-me", createdAt: Date(timeIntervalSince1970: 2_000)))

        let before = try store.foldedHistory().first { $0.contentHash == hash }
        XCTAssertEqual(before?.pasteCount, 0)
        XCTAssertNil(before?.lastPastedAt)

        let firstPaste = Date(timeIntervalSince1970: 3_000)
        try store.recordPaste(contentHash: hash, at: firstPaste)
        try store.recordPaste(contentHash: hash, at: Date(timeIntervalSince1970: 4_000))

        let folded = try store.foldedHistory().first { $0.contentHash == hash }
        XCTAssertEqual(folded?.pasteCount, 2)
        XCTAssertEqual(folded?.lastPastedAt, Date(timeIntervalSince1970: 4_000))
        XCTAssertEqual(folded?.copyCount, 2)

        let copies = try store.copies(contentHash: hash)
        XCTAssertTrue(copies.allSatisfy { $0.pasteCount == 2 })
    }

    func testMergeLibraryKeepsHigherPasteCountOnCollision() throws {
        let hash = ContentHash.text("shared")
        _ = try store.record(makeDraft(text: "shared", createdAt: Date(timeIntervalSince1970: 1_000)))
        try store.recordPaste(contentHash: hash, at: Date(timeIntervalSince1970: 2_000))

        var incoming = makeClip(
            text: "shared",
            createdAt: Date(timeIntervalSince1970: 1_500),
            hash: hash,
            pasteCount: 5,
            lastPastedAt: Date(timeIntervalSince1970: 9_000)
        )
        incoming.id = UUID()
        _ = try store.mergeLibrary(clips: [incoming], snippets: [], collections: [])

        let folded = try store.foldedHistory().first { $0.contentHash == hash }
        XCTAssertEqual(folded?.pasteCount, 5)
        XCTAssertEqual(folded?.lastPastedAt, Date(timeIntervalSince1970: 9_000))
    }

    func testStorageByteCountAndOrphanReap() throws {
        let before = store.storageByteCount()
        XCTAssertGreaterThan(before, 0)

        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D])
        var draft = makeDraft(text: "sized", kind: .image, hash: ContentHash.image(bytes))
        draft.imagePNG = bytes
        draft.thumbnailPNG = Data([0xAA, 0xBB])
        _ = try store.record(draft)
        XCTAssertGreaterThan(store.storageByteCount(), before)

        let imageURL = store.url(forRelativePath: "images/\(draft.contentHash).png")
        let thumbURL = store.url(forRelativePath: "thumbs/\(draft.contentHash).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbURL.path))

        _ = try store.delete(contentHash: draft.contentHash)
        let orphanBytes = try store.reapOrphanedImages()
        XCTAssertGreaterThan(orphanBytes, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbURL.path))
        try store.compactStorage()
        XCTAssertGreaterThan(store.storageByteCount(), 0)
    }
}
