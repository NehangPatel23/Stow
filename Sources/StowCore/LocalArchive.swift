import Foundation

enum ArchiveError: Error, Equatable, CustomStringConvertible {
    case invalidFormat
    case unsupportedVersion(Int)
    case missingFile(String)
    case process(String)

    var description: String {
        switch self {
        case .invalidFormat:
            "That file is not a Stow archive."
        case .unsupportedVersion(let version):
            "This Stow build cannot read archive version \(version)."
        case .missingFile(let name):
            "The archive is missing \(name)."
        case .process(let message):
            message
        }
    }
}

enum ArchiveImportMode: Equatable, Sendable {
    /// Wipe history, snippets, and boards, then load the archive.
    case replace
    /// Keep what is already on this Mac; only add items that are not already present.
    case merge
}

struct ArchiveManifest: Codable, Equatable, Sendable {
    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String?
    var counts: Counts

    struct Counts: Codable, Equatable, Sendable {
        var clips: Int
        var snippets: Int
        var collections: Int
        var images: Int
    }
}

struct ArchiveImportResult: Equatable, Sendable {
    var mode: ArchiveImportMode
    var manifest: ArchiveManifest
    var addedClips: Int
    var addedSnippets: Int
    var addedCollections: Int
}

/// Versioned zip of JSON + image files. History leaves the Mac only when the user saves this file.
enum LocalArchive {
    static let pathExtension = "stowarchive"
    static let formatID = "stow.archive"
    static let formatVersion = 1

    @discardableResult
    static func export(
        from store: HistoryStore,
        to url: URL,
        excludingContentHashes: Set<String> = []
    ) throws -> ArchiveManifest {
        let clips = try store.allClips().filter { !excludingContentHashes.contains($0.contentHash) }
        let snippets = try store.snippets()
        let collections = try store.collections()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowArchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try FileManager.default.createDirectory(at: temp.appendingPathComponent("images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp.appendingPathComponent("thumbs"), withIntermediateDirectories: true)

        var imageHashes = Set<String>()
        for clip in clips {
            guard clip.imageRelativePath != nil || clip.thumbRelativePath != nil else { continue }
            imageHashes.insert(clip.contentHash)
            try copyIfPresent(
                from: store.url(forRelativePath: "images/\(clip.contentHash).png"),
                to: temp.appendingPathComponent("images/\(clip.contentHash).png")
            )
            try copyIfPresent(
                from: store.url(forRelativePath: "thumbs/\(clip.contentHash).png"),
                to: temp.appendingPathComponent("thumbs/\(clip.contentHash).png")
            )
        }

        let manifest = ArchiveManifest(
            format: formatID,
            version: formatVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            counts: .init(
                clips: clips.count,
                snippets: snippets.count,
                collections: collections.count,
                images: imageHashes.count
            )
        )

        try encoder.encode(manifest).write(to: temp.appendingPathComponent("manifest.json"))
        try encoder.encode(clips.map(ArchiveClip.init(clip:))).write(to: temp.appendingPathComponent("clips.json"))
        try encoder.encode(snippets.map(ArchiveSnippet.init(snippet:))).write(to: temp.appendingPathComponent("snippets.json"))
        try encoder.encode(collections.map(ArchiveCollection.init(collection:)))
            .write(to: temp.appendingPathComponent("collections.json"))

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try zip(directory: temp, to: url)
        return manifest
    }

    @discardableResult
    static func importArchive(
        from url: URL,
        into store: HistoryStore,
        mode: ArchiveImportMode
    ) throws -> ArchiveImportResult {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowImport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        try unzip(url, to: temp)
        let root = try archiveRoot(in: temp)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestURL = root.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ArchiveError.missingFile("manifest.json")
        }
        let manifest = try decoder.decode(ArchiveManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == formatID else { throw ArchiveError.invalidFormat }
        guard manifest.version == formatVersion else {
            throw ArchiveError.unsupportedVersion(manifest.version)
        }

        let clipsURL = root.appendingPathComponent("clips.json")
        let snippetsURL = root.appendingPathComponent("snippets.json")
        let collectionsURL = root.appendingPathComponent("collections.json")
        guard FileManager.default.fileExists(atPath: clipsURL.path) else {
            throw ArchiveError.missingFile("clips.json")
        }
        guard FileManager.default.fileExists(atPath: snippetsURL.path) else {
            throw ArchiveError.missingFile("snippets.json")
        }
        guard FileManager.default.fileExists(atPath: collectionsURL.path) else {
            throw ArchiveError.missingFile("collections.json")
        }

        let archiveClips = try decoder.decode([ArchiveClip].self, from: Data(contentsOf: clipsURL))
        let archiveSnippets = try decoder.decode([ArchiveSnippet].self, from: Data(contentsOf: snippetsURL))
        let archiveCollections = try decoder.decode([ArchiveCollection].self, from: Data(contentsOf: collectionsURL))

        let clips = try archiveClips.map { try $0.makeClip() }
        let snippets = try archiveSnippets.map { try $0.makeSnippet() }
        let collections = archiveCollections.map(\.collection)

        var hashes = Set<String>()
        for clip in clips {
            guard clip.imageRelativePath != nil || clip.thumbRelativePath != nil else { continue }
            hashes.insert(clip.contentHash)
        }
        for hash in hashes {
            let image = try? Data(contentsOf: root.appendingPathComponent("images/\(hash).png"))
            let thumb = try? Data(contentsOf: root.appendingPathComponent("thumbs/\(hash).png"))
            if image != nil || thumb != nil {
                try store.installImageFiles(hash: hash, imagePNG: image, thumbnailPNG: thumb)
            }
        }

        switch mode {
        case .replace:
            try store.replaceLibrary(clips: clips, snippets: snippets, collections: collections)
            return ArchiveImportResult(
                mode: .replace,
                manifest: manifest,
                addedClips: clips.count,
                addedSnippets: snippets.count,
                addedCollections: collections.count
            )
        case .merge:
            let added = try store.mergeLibrary(clips: clips, snippets: snippets, collections: collections)
            return ArchiveImportResult(
                mode: .merge,
                manifest: manifest,
                addedClips: added.clips,
                addedSnippets: added.snippets,
                addedCollections: added.collections
            )
        }
    }
}

// MARK: - DTOs

private struct ArchiveClip: Codable {
    var id: UUID
    var createdAt: Date
    var pinned: Bool
    var sourceAppName: String
    var sourceBundleID: String
    var kind: String
    var preview: String
    var text: String?
    var html: String?
    var rtfBase64: String?
    var imageRelativePath: String?
    var thumbRelativePath: String?
    var fileURLs: [String]
    var colorHex: String?
    var contentHash: String
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int

    init(clip: Clip) {
        id = clip.id
        createdAt = clip.createdAt
        pinned = clip.pinned
        sourceAppName = clip.sourceAppName
        sourceBundleID = clip.sourceBundleID
        kind = clip.kind.rawValue
        preview = clip.preview
        text = clip.text
        html = clip.html
        rtfBase64 = clip.rtf?.base64EncodedString()
        imageRelativePath = clip.imageRelativePath
        thumbRelativePath = clip.thumbRelativePath
        fileURLs = clip.fileURLs
        colorHex = clip.colorHex
        contentHash = clip.contentHash
        imageWidth = clip.imageWidth
        imageHeight = clip.imageHeight
        byteSize = clip.byteSize
    }

    func makeClip() throws -> Clip {
        guard let kind = ClipKind(rawValue: kind) else {
            throw ArchiveError.invalidFormat
        }
        return Clip(
            id: id,
            createdAt: createdAt,
            pinned: pinned,
            sourceAppName: sourceAppName,
            sourceBundleID: sourceBundleID,
            kind: kind,
            preview: preview,
            text: text,
            html: html,
            rtf: rtfBase64.flatMap { Data(base64Encoded: $0) },
            imageRelativePath: imageRelativePath,
            thumbRelativePath: thumbRelativePath,
            fileURLs: fileURLs,
            colorHex: colorHex,
            contentHash: contentHash,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            byteSize: byteSize,
            copyCount: 1
        )
    }
}

private struct ArchiveSnippet: Codable {
    var id: UUID
    var createdAt: Date
    var title: String
    var text: String
    var kind: String
    var pinned: Bool
    var collectionID: UUID?
    var sortOrder: Int
    var abbreviation: String?

    init(snippet: Snippet) {
        id = snippet.id
        createdAt = snippet.createdAt
        title = snippet.title
        text = snippet.text
        kind = snippet.kind.rawValue
        pinned = snippet.pinned
        collectionID = snippet.collectionID
        sortOrder = snippet.sortOrder
        abbreviation = snippet.normalizedAbbreviation
    }

    func makeSnippet() throws -> Snippet {
        guard let kind = ClipKind(rawValue: kind) else {
            throw ArchiveError.invalidFormat
        }
        return Snippet(
            id: id,
            createdAt: createdAt,
            title: title,
            text: text,
            kind: kind,
            pinned: pinned,
            collectionID: collectionID,
            sortOrder: sortOrder,
            abbreviation: abbreviation
        )
    }
}

private struct ArchiveCollection: Codable {
    var id: UUID
    var name: String
    var sortOrder: Int

    init(collection: SnippetCollection) {
        id = collection.id
        name = collection.name
        sortOrder = collection.sortOrder
    }

    var collection: SnippetCollection {
        SnippetCollection(id: id, name: name, sortOrder: sortOrder)
    }
}

// MARK: - Zip helpers

private func copyIfPresent(from: URL, to: URL) throws {
    guard FileManager.default.fileExists(atPath: from.path) else { return }
    if FileManager.default.fileExists(atPath: to.path) {
        try FileManager.default.removeItem(at: to)
    }
    try FileManager.default.copyItem(at: from, to: to)
}

private func zip(directory: URL, to destination: URL) throws {
    try runDitto(arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, destination.path])
}

private func unzip(_ archive: URL, to destination: URL) throws {
    try runDitto(arguments: ["-x", "-k", archive.path, destination.path])
}

private func runDitto(arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = arguments
    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw ArchiveError.process("Couldn't read or write that archive.")
    }
    guard process.terminationStatus == 0 else {
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw ArchiveError.process(message?.isEmpty == false ? message! : "Couldn't read or write that archive.")
    }
}

/// `ditto -c -k --keepParent` nests files under the temp folder name; accept either layout.
private func archiveRoot(in extracted: URL) throws -> URL {
    let direct = extracted.appendingPathComponent("manifest.json")
    if FileManager.default.fileExists(atPath: direct.path) {
        return extracted
    }
    let children = try FileManager.default.contentsOfDirectory(
        at: extracted,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    for child in children {
        let candidate = child.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return child
        }
    }
    throw ArchiveError.missingFile("manifest.json")
}
