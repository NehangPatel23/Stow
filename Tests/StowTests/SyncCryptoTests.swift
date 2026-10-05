import XCTest

final class SyncCryptoTests: XCTestCase {
    func testSealOpenRoundTrip() throws {
        let plaintext = Data("stow-library-bytes".utf8)
        let package = try SyncCrypto.seal(plaintext: plaintext, passphrase: "correct horse")
        let opened = try SyncCrypto.open(package: package, passphrase: "correct horse")
        XCTAssertEqual(opened, plaintext)
        XCTAssertNotEqual(package, plaintext)
    }

    func testWrongPassphraseFails() throws {
        let package = try SyncCrypto.seal(plaintext: Data("payload".utf8), passphrase: "alpha")
        XCTAssertThrowsError(try SyncCrypto.open(package: package, passphrase: "beta")) { error in
            XCTAssertEqual(error as? SyncCryptoError, .wrongPassphrase)
        }
    }

    func testEmptyPassphraseRejected() {
        XCTAssertThrowsError(try SyncCrypto.seal(plaintext: Data("x".utf8), passphrase: "   ")) { error in
            XCTAssertEqual(error as? SyncCryptoError, .emptyPassphrase)
        }
    }

    func testInvalidPackageRejected() {
        XCTAssertThrowsError(try SyncCrypto.open(package: Data("nope".utf8), passphrase: "alpha")) { error in
            XCTAssertEqual(error as? SyncCryptoError, .invalidFormat)
        }
    }

    func testExportExcludesSecretClipsWhenAsked() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)

        _ = try store.record(makeDraft(text: "safe note"))
        let secret = "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----"
        _ = try store.record(makeDraft(text: secret))

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LocalArchive.pathExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var options = ArchiveExportOptions.default
        options.excludeSecretClips = true
        let manifest = try LocalArchive.export(from: store, to: archiveURL, options: options)
        XCTAssertEqual(manifest.counts.clips, 1)

        let otherDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: otherDir) }
        let other = try HistoryStore(directory: otherDir)
        _ = try LocalArchive.importArchive(from: archiveURL, into: other, mode: .replace)
        let texts = Set(try other.foldedHistory().compactMap(\.text))
        XCTAssertEqual(texts, ["safe note"])
    }

    func testExportCanOmitHistoryOrSnippets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        _ = try store.record(makeDraft(text: "clip"))
        _ = try store.addSnippet(title: "Hi", text: "hello", kind: .text)

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).\(LocalArchive.pathExtension)")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var options = ArchiveExportOptions.default
        options.includeHistory = false
        options.includeSnippets = true
        let manifest = try LocalArchive.export(from: store, to: archiveURL, options: options)
        XCTAssertEqual(manifest.counts.clips, 0)
        XCTAssertEqual(manifest.counts.snippets, 1)
    }

    func testEncryptedFolderSyncPushPullMerges() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDir)
            try? FileManager.default.removeItem(at: destDir)
        }

        let source = try HistoryStore(directory: sourceDir)
        let dest = try HistoryStore(directory: destDir)
        _ = try source.record(makeDraft(text: "from-source"))
        _ = try dest.record(makeDraft(text: "already-local"))

        let passphrase = "shared-secret"
        let tempArchive = folder.appendingPathComponent("plain.\(LocalArchive.pathExtension)")
        var options = ArchiveExportOptions.default
        options.excludeSecretClips = true
        _ = try LocalArchive.export(from: source, to: tempArchive, options: options)
        let sealed = try SyncCrypto.seal(plaintext: Data(contentsOf: tempArchive), passphrase: passphrase)
        let packageURL = folder.appendingPathComponent(SyncCrypto.fileName)
        try sealed.write(to: packageURL)

        let opened = try SyncCrypto.open(package: Data(contentsOf: packageURL), passphrase: passphrase)
        let inbound = folder.appendingPathComponent("inbound.\(LocalArchive.pathExtension)")
        try opened.write(to: inbound)
        let result = try LocalArchive.importArchive(from: inbound, into: dest, mode: .merge)
        XCTAssertEqual(result.addedClips, 1)

        let previews = Set(try dest.foldedHistory().map(\.preview))
        XCTAssertEqual(previews, ["from-source", "already-local"])
    }
}
