import XCTest

final class LocalArchiveTests: XCTestCase {
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

    func testExportImportRoundTripReplacesLibrary() throws {
        let board = try store.addCollection(name: "Support")
        _ = try store.addSnippet(
            title: "Hello",
            text: "Hi {{name}}",
            kind: .text,
            collectionID: board.id,
            abbreviation: "hi"
        )
        _ = try store.record(makeDraft(text: "keep-me", createdAt: Date(timeIntervalSince1970: 1_000)))
        try store.setPinned(contentHash: ContentHash.text("keep-me"), pinned: true)

        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        var image = makeDraft(text: "shot", kind: .image, createdAt: Date(timeIntervalSince1970: 2_000), hash: ContentHash.image(bytes))
        image.imagePNG = bytes
        image.thumbnailPNG = Data([0x01, 0x02])
        _ = try store.record(image)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LocalArchive.pathExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let exported = try LocalArchive.export(from: store, to: archiveURL)
        XCTAssertEqual(exported.counts.clips, 2)
        XCTAssertEqual(exported.counts.snippets, 1)
        XCTAssertEqual(exported.counts.collections, 1)
        XCTAssertEqual(exported.counts.images, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))

        _ = try store.record(makeDraft(text: "should-vanish"))
        _ = try store.addSnippet(title: "Extra", text: "nope", kind: .text)
        XCTAssertEqual(try store.foldedHistory().count, 3)

        let imported = try LocalArchive.importArchive(from: archiveURL, into: store, mode: .replace)
        XCTAssertEqual(imported.addedClips, 2)

        let history = try store.foldedHistory()
        XCTAssertEqual(Set(history.map(\.preview)), ["keep-me", "shot"])
        XCTAssertTrue(history.contains(where: { $0.preview == "keep-me" && $0.pinned }))

        let snippets = try store.snippets()
        XCTAssertEqual(snippets.count, 1)
        XCTAssertEqual(snippets[0].title, "Hello")
        XCTAssertEqual(snippets[0].normalizedAbbreviation, "hi")
        XCTAssertEqual(try store.collections().map(\.name), ["Support"])

        let imageURL = store.url(forRelativePath: "images/\(ContentHash.image(bytes)).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageURL.path))
        XCTAssertFalse(try store.foldedHistory().contains(where: { $0.preview == "should-vanish" }))
    }

    func testMergeKeepsExistingAndAddsOnlyNew() throws {
        _ = try store.record(makeDraft(text: "local-only", createdAt: Date(timeIntervalSince1970: 500)))
        _ = try store.record(makeDraft(text: "shared", createdAt: Date(timeIntervalSince1970: 800)))
        _ = try store.addSnippet(title: "Local", text: "mine", kind: .text)

        let otherDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: otherDir) }
        let other = try HistoryStore(directory: otherDir)
        _ = try other.record(makeDraft(text: "shared", createdAt: Date(timeIntervalSince1970: 900)))
        _ = try other.record(makeDraft(text: "from-archive", createdAt: Date(timeIntervalSince1970: 1_200)))
        let board = try other.addCollection(name: "Imported")
        _ = try other.addSnippet(title: "Remote", text: "theirs", kind: .text, collectionID: board.id)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LocalArchive.pathExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        _ = try LocalArchive.export(from: other, to: archiveURL)

        let result = try LocalArchive.importArchive(from: archiveURL, into: store, mode: .merge)
        XCTAssertEqual(result.addedClips, 1)
        XCTAssertEqual(result.addedSnippets, 1)
        XCTAssertEqual(result.addedCollections, 1)

        let previews = Set(try store.foldedHistory().map(\.preview))
        XCTAssertEqual(previews, ["local-only", "shared", "from-archive"])
        XCTAssertEqual(Set(try store.snippets().map(\.title)), ["Local", "Remote"])
        XCTAssertEqual(try store.collections().map(\.name), ["Imported"])
    }

    func testExportCanExcludeClipsByContentHash() throws {
        _ = try store.record(makeDraft(text: "keep", createdAt: Date(timeIntervalSince1970: 1)))
        _ = try store.record(makeDraft(text: "drop", createdAt: Date(timeIntervalSince1970: 2)))
        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LocalArchive.pathExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let exported = try LocalArchive.export(
            from: store,
            to: archiveURL,
            excludingContentHashes: [ContentHash.text("drop")]
        )
        XCTAssertEqual(exported.counts.clips, 1)

        let freshDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: freshDir) }
        let fresh = try HistoryStore(directory: freshDir)
        _ = try LocalArchive.importArchive(from: archiveURL, into: fresh, mode: .replace)
        XCTAssertEqual(try fresh.foldedHistory().map(\.preview), ["keep"])
    }

    func testRejectsInvalidArchive() throws {
        let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: bogus) }
        try Data([0x00, 0x01, 0x02]).write(to: bogus)
        XCTAssertThrowsError(try LocalArchive.importArchive(from: bogus, into: store, mode: .replace))
    }
}
