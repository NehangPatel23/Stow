import Foundation
import SQLite3

enum StoreError: Error, Equatable, CustomStringConvertible {
    case open(String)
    case sqlite(String)

    var description: String {
        switch self {
        case .open(let message): message
        case .sqlite(let message): message
        }
    }
}

/// On-device history and snippets. History deletes never touch the snippet table.
final class HistoryStore: @unchecked Sendable {
    let directory: URL
    private var database: OpaquePointer?
    private let lock = NSLock()

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("history.db").path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            throw StoreError.open(message(from: handle))
        }
        database = handle
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS clips (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                pinned INTEGER NOT NULL,
                source_app_name TEXT NOT NULL,
                source_bundle_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                preview TEXT NOT NULL,
                text TEXT,
                html TEXT,
                rtf BLOB,
                image_path TEXT,
                thumb_path TEXT,
                file_urls TEXT NOT NULL,
                color_hex TEXT,
                content_hash TEXT NOT NULL,
                image_width INTEGER,
                image_height INTEGER,
                byte_size INTEGER NOT NULL,
                ocr_text TEXT,
                paste_count INTEGER NOT NULL DEFAULT 0,
                last_pasted_at REAL
            )
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS clips_created ON clips(created_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS clips_hash ON clips(content_hash)")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS snippets (
                id TEXT PRIMARY KEY NOT NULL,
                created_at REAL NOT NULL,
                title TEXT NOT NULL,
                text TEXT NOT NULL,
                kind TEXT NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                sort_order INTEGER NOT NULL
            )
            """
        )
        try addClipOCRColumnIfNeeded()
        try addClipPasteColumnsIfNeeded()
        try addSnippetPinnedColumnIfNeeded()
        try addSnippetCollectionColumnsIfNeeded()
        try addSnippetAbbreviationColumnIfNeeded()
        applyDataProtection()
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
    }

    func record(_ draft: ClipDraft) throws -> Clip {
        try lock.withLock {
            try writeImageFiles(for: draft)
            let id = UUID()
            let imagePath = draft.imagePNG == nil ? nil : "images/\(draft.contentHash).png"
            let thumbPath = draft.thumbnailPNG == nil ? nil : "thumbs/\(draft.contentHash).png"
            try execute(
                """
                INSERT INTO clips (
                    id, created_at, pinned, source_app_name, source_bundle_id, kind, preview,
                    text, html, rtf, image_path, thumb_path, file_urls, color_hex, content_hash,
                    image_width, image_height, byte_size, ocr_text, paste_count, last_pasted_at
                ) VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL)
                """,
                bindings: { [self] statement in
                    bind(id.uuidString, at: 1, on: statement)
                    sqlite3_bind_double(statement, 2, draft.createdAt.timeIntervalSince1970)
                    bind(draft.sourceAppName, at: 3, on: statement)
                    bind(draft.sourceBundleID, at: 4, on: statement)
                    bind(draft.kind.rawValue, at: 5, on: statement)
                    bind(draft.preview, at: 6, on: statement)
                    bindOptional(draft.text, at: 7, on: statement)
                    bindOptional(draft.html, at: 8, on: statement)
                    bindOptional(draft.rtf, at: 9, on: statement)
                    bindOptional(imagePath, at: 10, on: statement)
                    bindOptional(thumbPath, at: 11, on: statement)
                    bind(encode(draft.fileURLs), at: 12, on: statement)
                    bindOptional(draft.colorHex, at: 13, on: statement)
                    bind(draft.contentHash, at: 14, on: statement)
                    bindOptional(draft.imageWidth, at: 15, on: statement)
                    bindOptional(draft.imageHeight, at: 16, on: statement)
                    sqlite3_bind_int(statement, 17, Int32(draft.byteSize))
                    bindOptional(draft.ocrText, at: 18, on: statement)
                }
            )
            return Clip(
                id: id,
                createdAt: draft.createdAt,
                pinned: false,
                sourceAppName: draft.sourceAppName,
                sourceBundleID: draft.sourceBundleID,
                kind: draft.kind,
                preview: draft.preview,
                text: draft.text,
                html: draft.html,
                rtf: draft.rtf,
                imageRelativePath: imagePath,
                thumbRelativePath: thumbPath,
                fileURLs: draft.fileURLs,
                colorHex: draft.colorHex,
                contentHash: draft.contentHash,
                imageWidth: draft.imageWidth,
                imageHeight: draft.imageHeight,
                byteSize: draft.byteSize,
                copyCount: 1,
                ocrText: draft.ocrText,
                pasteCount: 0,
                lastPastedAt: nil
            )
        }
    }

    /// Newest copy of each distinct payload, newest groups first.
    func foldedHistory(limit: Int = 2000) throws -> [Clip] {
        try lock.withLock {
            let rows = try fetch(
                """
                SELECT \(Self.listColumns)
                FROM clips
                ORDER BY created_at DESC
                LIMIT ?
                """,
                bindings: { [self] in sqlite3_bind_int($0, 1, Int32(limit)) },
                includeRTF: false
            )
            var groups: [String: [Clip]] = [:]
            var order: [String] = []
            for row in rows {
                if groups[row.contentHash] == nil {
                    order.append(row.contentHash)
                }
                groups[row.contentHash, default: []].append(row)
            }
            return order.compactMap { hash in
                guard var newest = groups[hash]?.first else { return nil }
                let group = groups[hash] ?? []
                newest.copyCount = group.count
                newest.pinned = group.contains(where: \.pinned)
                // Rows in a fold share the same paste_count (recordPaste updates every copy).
                newest.pasteCount = group.map(\.pasteCount).max() ?? 0
                newest.lastPastedAt = group.compactMap(\.lastPastedAt).max()
                return newest
            }
        }
    }

    /// Increments paste usage for every stored copy of this payload.
    func recordPaste(contentHash: String, at date: Date = Date()) throws {
        try lock.withLock {
            try execute(
                """
                UPDATE clips
                SET paste_count = paste_count + 1,
                    last_pasted_at = ?
                WHERE content_hash = ?
                """,
                bindings: { [self] statement in
                    sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
                    bind(contentHash, at: 2, on: statement)
                }
            )
        }
    }

    func copies(contentHash: String) throws -> [Clip] {
        try lock.withLock {
            try fetch(
                """
                SELECT \(Self.listColumns)
                FROM clips
                WHERE content_hash = ?
                ORDER BY created_at DESC
                """,
                bindings: { [self] in bind(contentHash, at: 1, on: $0) },
                includeRTF: false
            )
        }
    }

    func payload(id: UUID) throws -> Clip? {
        try lock.withLock {
            try fetch(
                """
                SELECT \(Self.fullColumns)
                FROM clips
                WHERE id = ?
                """,
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) },
                includeRTF: true
            ).first
        }
    }

    func updateContent(
        contentHash: String,
        text: String,
        html: String?,
        rtf: Data?,
        preview: String,
        kind: ClipKind,
        colorHex: String?,
        byteSize: Int,
        newHash: String
    ) throws {
        try lock.withLock {
            try execute(
                """
                UPDATE clips
                SET text = ?, html = ?, rtf = ?, preview = ?, kind = ?, color_hex = ?,
                    byte_size = ?, content_hash = ?
                WHERE content_hash = ?
                """,
                bindings: { [self] in
                    bind(text, at: 1, on: $0)
                    bindOptional(html, at: 2, on: $0)
                    bindOptional(rtf, at: 3, on: $0)
                    bind(preview, at: 4, on: $0)
                    bind(kind.rawValue, at: 5, on: $0)
                    bindOptional(colorHex, at: 6, on: $0)
                    sqlite3_bind_int($0, 7, Int32(byteSize))
                    bind(newHash, at: 8, on: $0)
                    bind(contentHash, at: 9, on: $0)
                }
            )
        }
    }

    func setPinned(contentHash: String, pinned: Bool) throws {
        try lock.withLock {
            try execute(
                "UPDATE clips SET pinned = ? WHERE content_hash = ?",
                bindings: { [self] in 
                    sqlite3_bind_int($0, 1, pinned ? 1 : 0)
                    bind(contentHash, at: 2, on: $0)
                }
            )
        }
    }

    /// Writes OCR for every row sharing this payload. Empty string marks "indexed, no text".
    func updateOCRText(contentHash: String, ocrText: String) throws {
        try lock.withLock {
            try execute(
                "UPDATE clips SET ocr_text = ? WHERE content_hash = ?",
                bindings: { [self] in
                    bind(ocrText, at: 1, on: $0)
                    bind(contentHash, at: 2, on: $0)
                }
            )
        }
    }

    /// Content hashes for image clips that still need on-device OCR.
    func imageHashesNeedingOCR(limit: Int = 50) throws -> [String] {
        try lock.withLock {
            let statement = try prepare(
                """
                SELECT DISTINCT content_hash
                FROM clips
                WHERE kind = 'image'
                  AND image_path IS NOT NULL
                  AND ocr_text IS NULL
                ORDER BY created_at DESC
                LIMIT ?
                """
            )
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int(statement, 1, Int32(limit))
            var hashes: [String] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let hash = columnText(statement, 0), !hash.isEmpty {
                    hashes.append(hash)
                }
            }
            return hashes
        }
    }

    @discardableResult
    func delete(contentHash: String) throws -> [Clip] {
        try lock.withLock {
            let rows = try fetch(
                "SELECT \(Self.fullColumns) FROM clips WHERE content_hash = ?",
                bindings: { [self] in bind(contentHash, at: 1, on: $0) },
                includeRTF: true
            )
            try execute(
                "DELETE FROM clips WHERE content_hash = ?",
                bindings: { [self] in bind(contentHash, at: 1, on: $0) }
            )
            return rows
        }
    }

    @discardableResult
    func delete(id: UUID) throws -> Clip? {
        try lock.withLock {
            let rows = try fetch(
                "SELECT \(Self.fullColumns) FROM clips WHERE id = ?",
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) },
                includeRTF: true
            )
            try execute(
                "DELETE FROM clips WHERE id = ?",
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) }
            )
            return rows.first
        }
    }

    @discardableResult
    func clearHistory(includingPinned: Bool) throws -> [Clip] {
        try lock.withLock {
            let sql = includingPinned
                ? "SELECT \(Self.fullColumns) FROM clips"
                : "SELECT \(Self.fullColumns) FROM clips WHERE pinned = 0"
            let rows = try fetch(sql, bindings: { [self] _ in }, includeRTF: true)
            if includingPinned {
                try execute("DELETE FROM clips")
            } else {
                try execute("DELETE FROM clips WHERE pinned = 0")
            }
            return rows
        }
    }

    /// Every stored copy with full payloads, oldest first — used for local archives.
    func allClips() throws -> [Clip] {
        try lock.withLock {
            try fetch(
                """
                SELECT \(Self.fullColumns)
                FROM clips
                ORDER BY created_at ASC
                """,
                bindings: { [self] _ in },
                includeRTF: true
            )
        }
    }

    /// Replaces history, snippets, and boards. Caller must install image files first or after.
    func replaceLibrary(
        clips: [Clip],
        snippets: [Snippet],
        collections: [SnippetCollection]
    ) throws {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("DELETE FROM clips")
                try execute("DELETE FROM snippets")
                try execute("DELETE FROM collections")
                try insertLibraryLocked(clips: clips, snippets: snippets, collections: collections)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
        _ = try reapOrphanedImages()
        applyDataProtection()
    }

    /// Keeps existing rows. Adds collections/snippets/clips that are not already present.
    /// Clips match on id or content hash. Conflicting snippet abbreviations are cleared.
    @discardableResult
    func mergeLibrary(
        clips: [Clip],
        snippets: [Snippet],
        collections: [SnippetCollection]
    ) throws -> (clips: Int, snippets: Int, collections: Int) {
        let added = try lock.withLock { () -> (Int, Int, Int) in
            try execute("BEGIN IMMEDIATE")
            do {
                var existingCollectionIDs = try idSet("SELECT id FROM collections")
                var existingSnippetIDs = try idSet("SELECT id FROM snippets")
                var existingClipIDs = try idSet("SELECT id FROM clips")
                var existingHashes = try stringSet("SELECT DISTINCT content_hash FROM clips")
                var takenAbbreviations = try stringSet(
                    "SELECT abbreviation FROM snippets WHERE abbreviation IS NOT NULL AND abbreviation != ''"
                )
                let incomingCollectionIDs = Set(collections.map(\.id))

                var addedCollections = 0
                for collection in collections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                    guard !existingCollectionIDs.contains(collection.id) else { continue }
                    try insertCollectionLocked(collection)
                    existingCollectionIDs.insert(collection.id)
                    addedCollections += 1
                }

                var addedSnippets = 0
                for snippet in snippets {
                    guard !existingSnippetIDs.contains(snippet.id) else { continue }
                    var incoming = snippet
                    if let abbr = incoming.normalizedAbbreviation, takenAbbreviations.contains(abbr) {
                        incoming.abbreviation = nil
                    }
                    if let board = incoming.collectionID,
                       !existingCollectionIDs.contains(board),
                       !incomingCollectionIDs.contains(board) {
                        incoming.collectionID = nil
                    }
                    try insertSnippetLocked(incoming)
                    existingSnippetIDs.insert(incoming.id)
                    if let abbr = incoming.normalizedAbbreviation {
                        takenAbbreviations.insert(abbr)
                    }
                    addedSnippets += 1
                }

                var addedClips = 0
                for clip in clips {
                    if existingClipIDs.contains(clip.id) || existingHashes.contains(clip.contentHash) {
                        try mergePasteStatsLocked(
                            contentHash: clip.contentHash,
                            pasteCount: clip.pasteCount,
                            lastPastedAt: clip.lastPastedAt
                        )
                        continue
                    }
                    try insert(clip)
                    existingClipIDs.insert(clip.id)
                    existingHashes.insert(clip.contentHash)
                    addedClips += 1
                }
                try execute("COMMIT")
                return (addedClips, addedSnippets, addedCollections)
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
        applyDataProtection()
        return added
    }

    func installImageFiles(hash: String, imagePNG: Data?, thumbnailPNG: Data?) throws {
        try lock.withLock {
            if let imagePNG {
                let url = fileURL("images/\(hash).png")
                try imagePNG.write(to: url, options: .atomic)
                protectFile(url)
            }
            if let thumbnailPNG {
                let url = fileURL("thumbs/\(hash).png")
                try thumbnailPNG.write(to: url, options: .atomic)
                protectFile(url)
            }
        }
    }

    func restore(clips: [Clip]) throws {
        try lock.withLock {
            try execute("BEGIN IMMEDIATE")
            do {
                for clip in clips {
                    try insert(clip)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    func reapImages(hashes: Set<String>) throws {
        try lock.withLock {
            for hash in hashes {
                let count = try int(
                    "SELECT COUNT(*) FROM clips WHERE content_hash = ?",
                    bindings: { [self] in bind(hash, at: 1, on: $0) }
                )
                guard count == 0 else { continue }
                let image = fileURL("images/\(hash).png")
                let thumb = fileURL("thumbs/\(hash).png")
                try? FileManager.default.removeItem(at: image)
                try? FileManager.default.removeItem(at: thumb)
            }
        }
    }

    /// Bytes used by the history database and image folders on disk.
    func storageByteCount() -> Int {
        lock.withLock {
            Self.directoryByteCount(at: directory)
        }
    }

    /// Deletes unpinned clips past the given cutoffs. Image kinds use `imageOlderThan`; everything else uses `textOlderThan`.
    @discardableResult
    func deleteExpired(textOlderThan textCutoff: Date?, imageOlderThan imageCutoff: Date?) throws -> [Clip] {
        try lock.withLock {
            guard textCutoff != nil || imageCutoff != nil else { return [] }
            var clauses: [String] = []
            var cutoffs: [Date] = []
            if let textCutoff {
                clauses.append("(kind != 'image' AND created_at < ?)")
                cutoffs.append(textCutoff)
            }
            if let imageCutoff {
                clauses.append("(kind = 'image' AND created_at < ?)")
                cutoffs.append(imageCutoff)
            }
            let predicate = clauses.joined(separator: " OR ")
            let selectSQL = """
            SELECT \(Self.fullColumns)
            FROM clips
            WHERE pinned = 0 AND (\(predicate))
            """
            let rows = try fetch(
                selectSQL,
                bindings: { [self] statement in
                    for (index, cutoff) in cutoffs.enumerated() {
                        sqlite3_bind_double(statement, Int32(index + 1), cutoff.timeIntervalSince1970)
                    }
                },
                includeRTF: true
            )
            guard !rows.isEmpty else { return [] }
            let deleteSQL = "DELETE FROM clips WHERE pinned = 0 AND (\(predicate))"
            try execute(
                deleteSQL,
                bindings: { [self] statement in
                    for (index, cutoff) in cutoffs.enumerated() {
                        sqlite3_bind_double(statement, Int32(index + 1), cutoff.timeIntervalSince1970)
                    }
                }
            )
            return rows
        }
    }

    /// Removes image and thumb files that no clip still references. Returns bytes removed.
    @discardableResult
    func reapOrphanedImages() throws -> Int {
        try lock.withLock {
            var removed = 0
            removed += try removeOrphans(in: "images")
            removed += try removeOrphans(in: "thumbs")
            return removed
        }
    }

    func compactStorage() throws {
        try lock.withLock {
            try execute("VACUUM")
            applyDataProtectionLocked()
        }
    }

    /// Applies the Mac's data-protection class to the store directory and known files.
    func applyDataProtection() {
        lock.withLock {
            applyDataProtectionLocked()
        }
    }

    func addSnippet(
        title: String,
        text: String,
        kind: ClipKind,
        createdAt: Date = Date(),
        collectionID: UUID? = nil,
        abbreviation: String? = nil
    ) throws -> Snippet {
        try lock.withLock {
            let normalized = try validatedAbbreviation(abbreviation, excludingID: nil)
            let sortOrder = try nextSnippetSortOrder(collectionID: collectionID)
            let snippet = Snippet(
                id: UUID(),
                createdAt: createdAt,
                title: title,
                text: text,
                kind: kind,
                collectionID: collectionID,
                sortOrder: sortOrder,
                abbreviation: normalized
            )
            try execute(
                """
                INSERT INTO snippets
                (id, created_at, title, text, kind, pinned, collection_id, sort_order, abbreviation)
                VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?)
                """,
                bindings: { [self] in
                    bind(snippet.id.uuidString, at: 1, on: $0)
                    sqlite3_bind_double($0, 2, createdAt.timeIntervalSince1970)
                    bind(title, at: 3, on: $0)
                    bind(text, at: 4, on: $0)
                    bind(kind.rawValue, at: 5, on: $0)
                    bindOptional(collectionID?.uuidString, at: 6, on: $0)
                    sqlite3_bind_int($0, 7, Int32(sortOrder))
                    bindOptional(normalized, at: 8, on: $0)
                }
            )
            return snippet
        }
    }

    func snippets() throws -> [Snippet] {
        try lock.withLock {
            try fetchSnippets(
                """
                SELECT id, created_at, title, text, kind, pinned, collection_id, sort_order, abbreviation
                FROM snippets
                ORDER BY pinned DESC, sort_order ASC, created_at DESC
                """
            )
        }
    }

    func updateSnippet(
        id: UUID,
        title: String,
        text: String,
        kind: ClipKind,
        abbreviation: String?
    ) throws {
        try lock.withLock {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                throw StoreError.sqlite("A snippet needs a title.")
            }
            let normalized = try validatedAbbreviation(abbreviation, excludingID: id)
            try execute(
                """
                UPDATE snippets
                SET title = ?, text = ?, kind = ?, abbreviation = ?
                WHERE id = ?
                """,
                bindings: { [self] in
                    bind(trimmedTitle, at: 1, on: $0)
                    bind(text, at: 2, on: $0)
                    bind(kind.rawValue, at: 3, on: $0)
                    bindOptional(normalized, at: 4, on: $0)
                    bind(id.uuidString, at: 5, on: $0)
                }
            )
        }
    }

    @discardableResult
    func deleteSnippet(id: UUID) throws -> Snippet? {
        try lock.withLock {
            let rows = try fetchSnippets(
                """
                SELECT id, created_at, title, text, kind, pinned, collection_id, sort_order, abbreviation
                FROM snippets WHERE id = ?
                """,
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) }
            )
            try execute(
                "DELETE FROM snippets WHERE id = ?",
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) }
            )
            return rows.first
        }
    }

    func setSnippetPinned(id: UUID, pinned: Bool) throws {
        try lock.withLock {
            try execute(
                "UPDATE snippets SET pinned = ? WHERE id = ?",
                bindings: { [self] in
                    sqlite3_bind_int($0, 1, pinned ? 1 : 0)
                    bind(id.uuidString, at: 2, on: $0)
                }
            )
        }
    }

    func setSnippetCollection(id: UUID, collectionID: UUID?) throws {
        try lock.withLock {
            let sortOrder = try nextSnippetSortOrder(collectionID: collectionID)
            try execute(
                "UPDATE snippets SET collection_id = ?, sort_order = ? WHERE id = ?",
                bindings: { [self] in
                    bindOptional(collectionID?.uuidString, at: 1, on: $0)
                    sqlite3_bind_int($0, 2, Int32(sortOrder))
                    bind(id.uuidString, at: 3, on: $0)
                }
            )
        }
    }

    func reorderSnippets(ids: [UUID]) throws {
        try lock.withLock {
            for (index, id) in ids.enumerated() {
                try execute(
                    "UPDATE snippets SET sort_order = ? WHERE id = ?",
                    bindings: { [self] in
                        sqlite3_bind_int($0, 1, Int32(index))
                        bind(id.uuidString, at: 2, on: $0)
                    }
                )
            }
        }
    }

    func collections() throws -> [SnippetCollection] {
        try lock.withLock {
            try fetchCollections("SELECT id, name, sort_order FROM collections ORDER BY sort_order ASC, name ASC")
        }
    }

    func addCollection(name: String) throws -> SnippetCollection {
        try lock.withLock {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.sqlite("A collection needs a name.")
            }
            let order = (try scalarInt("SELECT COALESCE(MAX(sort_order), -1) FROM collections")) + 1
            let collection = SnippetCollection(id: UUID(), name: trimmed, sortOrder: order)
            try execute(
                "INSERT INTO collections (id, name, sort_order) VALUES (?, ?, ?)",
                bindings: { [self] in
                    bind(collection.id.uuidString, at: 1, on: $0)
                    bind(collection.name, at: 2, on: $0)
                    sqlite3_bind_int($0, 3, Int32(order))
                }
            )
            return collection
        }
    }

    func renameCollection(id: UUID, name: String) throws {
        try lock.withLock {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw StoreError.sqlite("A collection needs a name.")
            }
            try execute(
                "UPDATE collections SET name = ? WHERE id = ?",
                bindings: { [self] in
                    bind(trimmed, at: 1, on: $0)
                    bind(id.uuidString, at: 2, on: $0)
                }
            )
        }
    }

    func deleteCollection(id: UUID) throws {
        try lock.withLock {
            try execute(
                "UPDATE snippets SET collection_id = NULL WHERE collection_id = ?",
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) }
            )
            try execute(
                "DELETE FROM collections WHERE id = ?",
                bindings: { [self] in bind(id.uuidString, at: 1, on: $0) }
            )
        }
    }

    func reorderCollections(ids: [UUID]) throws {
        try lock.withLock {
            for (index, id) in ids.enumerated() {
                try execute(
                    "UPDATE collections SET sort_order = ? WHERE id = ?",
                    bindings: { [self] in
                        sqlite3_bind_int($0, 1, Int32(index))
                        bind(id.uuidString, at: 2, on: $0)
                    }
                )
            }
        }
    }

    func restoreSnippets(_ snippets: [Snippet]) throws {
        try lock.withLock {
            for snippet in snippets {
                try execute(
                    """
                    INSERT OR REPLACE INTO snippets
                    (id, created_at, title, text, kind, pinned, collection_id, sort_order, abbreviation)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: { [self] in
                        bind(snippet.id.uuidString, at: 1, on: $0)
                        sqlite3_bind_double($0, 2, snippet.createdAt.timeIntervalSince1970)
                        bind(snippet.title, at: 3, on: $0)
                        bind(snippet.text, at: 4, on: $0)
                        bind(snippet.kind.rawValue, at: 5, on: $0)
                        sqlite3_bind_int($0, 6, snippet.pinned ? 1 : 0)
                        bindOptional(snippet.collectionID?.uuidString, at: 7, on: $0)
                        sqlite3_bind_int($0, 8, Int32(snippet.sortOrder))
                        bindOptional(snippet.normalizedAbbreviation, at: 9, on: $0)
                    }
                )
            }
        }
    }

    func url(forRelativePath path: String) -> URL {
        fileURL(path)
    }

    private func fileURL(_ relative: String) -> URL {
        relative.split(separator: "/").reduce(directory) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    // MARK: - SQL

    private static let listColumns = """
    id, created_at, pinned, source_app_name, source_bundle_id, kind, preview, text, html,
    NULL, image_path, thumb_path, file_urls, color_hex, content_hash, image_width, image_height, byte_size, ocr_text,
    paste_count, last_pasted_at
    """

    private static let fullColumns = """
    id, created_at, pinned, source_app_name, source_bundle_id, kind, preview, text, html,
    rtf, image_path, thumb_path, file_urls, color_hex, content_hash, image_width, image_height, byte_size, ocr_text,
    paste_count, last_pasted_at
    """

    private func insert(_ clip: Clip) throws {
        try execute(
            """
            INSERT OR REPLACE INTO clips (
                id, created_at, pinned, source_app_name, source_bundle_id, kind, preview,
                text, html, rtf, image_path, thumb_path, file_urls, color_hex, content_hash,
                image_width, image_height, byte_size, ocr_text, paste_count, last_pasted_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: { [self] statement in
                bind(clip.id.uuidString, at: 1, on: statement)
                sqlite3_bind_double(statement, 2, clip.createdAt.timeIntervalSince1970)
                sqlite3_bind_int(statement, 3, clip.pinned ? 1 : 0)
                bind(clip.sourceAppName, at: 4, on: statement)
                bind(clip.sourceBundleID, at: 5, on: statement)
                bind(clip.kind.rawValue, at: 6, on: statement)
                bind(clip.preview, at: 7, on: statement)
                bindOptional(clip.text, at: 8, on: statement)
                bindOptional(clip.html, at: 9, on: statement)
                bindOptional(clip.rtf, at: 10, on: statement)
                bindOptional(clip.imageRelativePath, at: 11, on: statement)
                bindOptional(clip.thumbRelativePath, at: 12, on: statement)
                bind(encode(clip.fileURLs), at: 13, on: statement)
                bindOptional(clip.colorHex, at: 14, on: statement)
                bind(clip.contentHash, at: 15, on: statement)
                bindOptional(clip.imageWidth, at: 16, on: statement)
                bindOptional(clip.imageHeight, at: 17, on: statement)
                sqlite3_bind_int(statement, 18, Int32(clip.byteSize))
                bindOptional(clip.ocrText, at: 19, on: statement)
                sqlite3_bind_int(statement, 20, Int32(clip.pasteCount))
                if let lastPastedAt = clip.lastPastedAt {
                    sqlite3_bind_double(statement, 21, lastPastedAt.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 21)
                }
            }
        )
    }

    /// Keeps the higher paste count (and newer last-pasted time) when an import/sync collides.
    private func mergePasteStatsLocked(
        contentHash: String,
        pasteCount: Int,
        lastPastedAt: Date?
    ) throws {
        guard pasteCount > 0 || lastPastedAt != nil else { return }
        let rows = try fetch(
            "SELECT \(Self.listColumns) FROM clips WHERE content_hash = ?",
            bindings: { [self] in bind(contentHash, at: 1, on: $0) },
            includeRTF: false
        )
        guard !rows.isEmpty else { return }
        let existingCount = rows.map(\.pasteCount).max() ?? 0
        let existingLast = rows.compactMap(\.lastPastedAt).max()
        let nextCount = max(existingCount, pasteCount)
        let nextLast = [existingLast, lastPastedAt].compactMap { $0 }.max()
        guard nextCount != existingCount || nextLast != existingLast else { return }
        try execute(
            """
            UPDATE clips
            SET paste_count = ?,
                last_pasted_at = ?
            WHERE content_hash = ?
            """,
            bindings: { [self] statement in
                sqlite3_bind_int(statement, 1, Int32(nextCount))
                if let nextLast {
                    sqlite3_bind_double(statement, 2, nextLast.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 2)
                }
                bind(contentHash, at: 3, on: statement)
            }
        )
    }

    private func insertLibraryLocked(
        clips: [Clip],
        snippets: [Snippet],
        collections: [SnippetCollection]
    ) throws {
        for collection in collections.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            try insertCollectionLocked(collection)
        }
        for snippet in snippets {
            try insertSnippetLocked(snippet)
        }
        for clip in clips {
            try insert(clip)
        }
    }

    private func insertCollectionLocked(_ collection: SnippetCollection) throws {
        try execute(
            "INSERT INTO collections (id, name, sort_order) VALUES (?, ?, ?)",
            bindings: { [self] in
                bind(collection.id.uuidString, at: 1, on: $0)
                bind(collection.name, at: 2, on: $0)
                sqlite3_bind_int($0, 3, Int32(collection.sortOrder))
            }
        )
    }

    private func insertSnippetLocked(_ snippet: Snippet) throws {
        try execute(
            """
            INSERT INTO snippets
            (id, created_at, title, text, kind, pinned, collection_id, sort_order, abbreviation)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            bindings: { [self] in
                bind(snippet.id.uuidString, at: 1, on: $0)
                sqlite3_bind_double($0, 2, snippet.createdAt.timeIntervalSince1970)
                bind(snippet.title, at: 3, on: $0)
                bind(snippet.text, at: 4, on: $0)
                bind(snippet.kind.rawValue, at: 5, on: $0)
                sqlite3_bind_int($0, 6, snippet.pinned ? 1 : 0)
                bindOptional(snippet.collectionID?.uuidString, at: 7, on: $0)
                sqlite3_bind_int($0, 8, Int32(snippet.sortOrder))
                bindOptional(snippet.normalizedAbbreviation, at: 9, on: $0)
            }
        )
    }

    private func idSet(_ sql: String) throws -> Set<UUID> {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var values = Set<UUID>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let id = UUID(uuidString: columnText(statement, 0) ?? "") {
                values.insert(id)
            }
        }
        return values
    }

    private func stringSet(_ sql: String) throws -> Set<String> {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        var values = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = columnText(statement, 0), !value.isEmpty {
                values.insert(value)
            }
        }
        return values
    }

    private func writeImageFiles(for draft: ClipDraft) throws {
        if let image = draft.imagePNG {
            let url = fileURL("images/\(draft.contentHash).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try image.write(to: url)
                protectFile(url)
            }
        }
        if let thumb = draft.thumbnailPNG {
            let url = fileURL("thumbs/\(draft.contentHash).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try thumb.write(to: url)
                protectFile(url)
            }
        }
    }

    private func removeOrphans(in folder: String) throws -> Int {
        let root = fileURL(folder)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var removed = 0
        for item in items {
            let hash = item.deletingPathExtension().lastPathComponent
            guard !hash.isEmpty else { continue }
            let count = try int(
                "SELECT COUNT(*) FROM clips WHERE content_hash = ?",
                bindings: { [self] in bind(hash, at: 1, on: $0) }
            )
            guard count == 0 else { continue }
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try? FileManager.default.removeItem(at: item)
            removed += size
        }
        return removed
    }

    private func applyDataProtectionLocked() {
        protectFile(directory)
        protectFile(directory.appendingPathComponent("images", isDirectory: true))
        protectFile(directory.appendingPathComponent("thumbs", isDirectory: true))
        for name in ["history.db", "history.db-wal", "history.db-shm"] {
            protectFile(directory.appendingPathComponent(name))
        }
        for folder in ["images", "thumbs"] {
            let root = directory.appendingPathComponent(folder, isDirectory: true)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            ) else { continue }
            for item in items {
                protectFile(item)
            }
        }
    }

    private func protectFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private static func directoryByteCount(at root: URL) -> Int {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += values.fileSize ?? 0
        }
        return total
    }

    private func addClipOCRColumnIfNeeded() throws {
        let columns = try clipColumns()
        guard !columns.contains("ocr_text") else { return }
        try execute("ALTER TABLE clips ADD COLUMN ocr_text TEXT")
    }

    private func addClipPasteColumnsIfNeeded() throws {
        let columns = try clipColumns()
        if !columns.contains("paste_count") {
            try execute("ALTER TABLE clips ADD COLUMN paste_count INTEGER NOT NULL DEFAULT 0")
        }
        if !columns.contains("last_pasted_at") {
            try execute("ALTER TABLE clips ADD COLUMN last_pasted_at REAL")
        }
    }

    private func addSnippetPinnedColumnIfNeeded() throws {
        let columns = try snippetColumns()
        guard !columns.contains("pinned") else { return }
        try execute("ALTER TABLE snippets ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
    }

    private func addSnippetCollectionColumnsIfNeeded() throws {
        let columns = try snippetColumns()
        if !columns.contains("collection_id") {
            try execute("ALTER TABLE snippets ADD COLUMN collection_id TEXT")
        }
        if !columns.contains("sort_order") {
            try execute("ALTER TABLE snippets ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0")
        }
    }

    private func addSnippetAbbreviationColumnIfNeeded() throws {
        let columns = try snippetColumns()
        guard !columns.contains("abbreviation") else { return }
        try execute("ALTER TABLE snippets ADD COLUMN abbreviation TEXT")
    }

    private func validatedAbbreviation(_ raw: String?, excludingID: UUID?) throws -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return nil }
        guard let normalized = SnippetAbbreviation.normalize(trimmed) else {
            throw StoreError.sqlite("Abbreviations use letters, numbers, '.', '_', or '-', up to 32 characters.")
        }
        var sql = "SELECT COUNT(*) FROM snippets WHERE abbreviation = ?"
        if excludingID != nil {
            sql += " AND id != ?"
        }
        let count = try int(sql) { [self] statement in
            bind(normalized, at: 1, on: statement)
            if let excludingID {
                bind(excludingID.uuidString, at: 2, on: statement)
            }
        }
        if count > 0 {
            throw StoreError.sqlite("That abbreviation is already used by another snippet.")
        }
        return normalized
    }

    private func clipColumns() throws -> Set<String> {
        try tableColumns("clips")
    }

    private func snippetColumns() throws -> Set<String> {
        try tableColumns("snippets")
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = columnText(statement, 1) {
                columns.insert(name)
            }
        }
        return columns
    }

    private func nextSnippetSortOrder(collectionID: UUID?) throws -> Int {
        if let collectionID {
            return (try scalarInt(
                "SELECT COALESCE(MAX(sort_order), -1) FROM snippets WHERE collection_id = ?",
                bindings: { [self] in bind(collectionID.uuidString, at: 1, on: $0) }
            )) + 1
        }
        return (try scalarInt(
            "SELECT COALESCE(MAX(sort_order), -1) FROM snippets WHERE collection_id IS NULL"
        )) + 1
    }

    private func fetchCollections(_ sql: String, bindings: ((OpaquePointer) -> Void)? = nil) throws -> [SnippetCollection] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings?(statement)
        var collections: [SnippetCollection] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(statement, 0) ?? "") else { continue }
            collections.append(
                SnippetCollection(
                    id: id,
                    name: columnText(statement, 1) ?? "",
                    sortOrder: Int(sqlite3_column_int(statement, 2))
                )
            )
        }
        return collections
    }

    private func scalarInt(_ sql: String, bindings: ((OpaquePointer) -> Void)? = nil) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings?(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(_ sql: String, bindings: ((OpaquePointer) -> Void)? = nil) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings?(statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw StoreError.sqlite(message(from: database))
        }
    }

    private func int(_ sql: String, bindings: (OpaquePointer) -> Void) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func fetch(
        _ sql: String,
        bindings: (OpaquePointer) -> Void,
        includeRTF: Bool
    ) throws -> [Clip] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        var clips: [Clip] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(statement, 0) ?? ""),
                  let kind = ClipKind(rawValue: columnText(statement, 5) ?? "") else { continue }
            clips.append(
                Clip(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    pinned: sqlite3_column_int(statement, 2) != 0,
                    sourceAppName: columnText(statement, 3) ?? "",
                    sourceBundleID: columnText(statement, 4) ?? "",
                    kind: kind,
                    preview: columnText(statement, 6) ?? "",
                    text: columnText(statement, 7),
                    html: columnText(statement, 8),
                    rtf: includeRTF ? columnData(statement, 9) : nil,
                    imageRelativePath: columnText(statement, 10),
                    thumbRelativePath: columnText(statement, 11),
                    fileURLs: decode(columnText(statement, 12)),
                    colorHex: columnText(statement, 13),
                    contentHash: columnText(statement, 14) ?? "",
                    imageWidth: columnInt(statement, 15),
                    imageHeight: columnInt(statement, 16),
                    byteSize: Int(sqlite3_column_int(statement, 17)),
                    copyCount: 1,
                    ocrText: columnText(statement, 18),
                    pasteCount: Int(sqlite3_column_int(statement, 19)),
                    lastPastedAt: columnDate(statement, 20)
                )
            )
        }
        return clips
    }

    private func fetchSnippets(_ sql: String, bindings: ((OpaquePointer) -> Void)? = nil) throws -> [Snippet] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindings?(statement)
        var snippets: [Snippet] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(statement, 0) ?? ""),
                  let kind = ClipKind(rawValue: columnText(statement, 4) ?? "") else { continue }
            let collectionID = columnText(statement, 6).flatMap(UUID.init(uuidString:))
            snippets.append(
                Snippet(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    title: columnText(statement, 2) ?? "",
                    text: columnText(statement, 3) ?? "",
                    kind: kind,
                    pinned: sqlite3_column_int(statement, 5) != 0,
                    collectionID: collectionID,
                    sortOrder: Int(sqlite3_column_int(statement, 7)),
                    abbreviation: columnText(statement, 8)
                )
            )
        }
        return snippets
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw StoreError.open("Database is closed.") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.sqlite(message(from: database))
        }
        return statement
    }

    private func message(from handle: OpaquePointer?) -> String {
        if let handle, let cString = sqlite3_errmsg(handle) {
            return String(cString: cString)
        }
        return "Unknown database error."
    }

    private func bind(_ value: String, at index: Int32, on statement: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
    }

    private func bindOptional(_ value: String?, at index: Int32, on statement: OpaquePointer) {
        if let value {
            bind(value, at: index, on: statement)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptional(_ value: Data?, at index: Int32, on statement: OpaquePointer) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let value {
            _ = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(value.count), transient)
            }
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptional(_ value: Int?, at index: Int32, on statement: OpaquePointer) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func columnData(_ statement: OpaquePointer, _ index: Int32) -> Data? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        guard let pointer = sqlite3_column_blob(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: pointer, count: count)
    }

    private func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func columnDate(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private func encode(_ urls: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: urls),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }

    private func decode(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return values
    }
}
