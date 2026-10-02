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
                byte_size INTEGER NOT NULL
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
        try addSnippetPinnedColumnIfNeeded()
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
                    image_width, image_height, byte_size
                ) VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                copyCount: 1
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
                return newest
            }
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

    func addSnippet(title: String, text: String, kind: ClipKind, createdAt: Date = Date()) throws -> Snippet {
        try lock.withLock {
            let snippet = Snippet(id: UUID(), createdAt: createdAt, title: title, text: text, kind: kind)
            try execute(
                "INSERT INTO snippets (id, created_at, title, text, kind, pinned) VALUES (?, ?, ?, ?, ?, 0)",
                bindings: { [self] in 
                    bind(snippet.id.uuidString, at: 1, on: $0)
                    sqlite3_bind_double($0, 2, createdAt.timeIntervalSince1970)
                    bind(title, at: 3, on: $0)
                    bind(text, at: 4, on: $0)
                    bind(kind.rawValue, at: 5, on: $0)
                }
            )
            return snippet
        }
    }

    func snippets() throws -> [Snippet] {
        try lock.withLock {
            try fetchSnippets("SELECT id, created_at, title, text, kind, pinned FROM snippets ORDER BY pinned DESC, created_at DESC")
        }
    }

    @discardableResult
    func deleteSnippet(id: UUID) throws -> Snippet? {
        try lock.withLock {
            let rows = try fetchSnippets(
                "SELECT id, created_at, title, text, kind, pinned FROM snippets WHERE id = ?",
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

    func restoreSnippets(_ snippets: [Snippet]) throws {
        try lock.withLock {
            for snippet in snippets {
                try execute(
                    "INSERT OR REPLACE INTO snippets (id, created_at, title, text, kind, pinned) VALUES (?, ?, ?, ?, ?, ?)",
                    bindings: { [self] in 
                        bind(snippet.id.uuidString, at: 1, on: $0)
                        sqlite3_bind_double($0, 2, snippet.createdAt.timeIntervalSince1970)
                        bind(snippet.title, at: 3, on: $0)
                        bind(snippet.text, at: 4, on: $0)
                        bind(snippet.kind.rawValue, at: 5, on: $0)
                        sqlite3_bind_int($0, 6, snippet.pinned ? 1 : 0)
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
    NULL, image_path, thumb_path, file_urls, color_hex, content_hash, image_width, image_height, byte_size
    """

    private static let fullColumns = """
    id, created_at, pinned, source_app_name, source_bundle_id, kind, preview, text, html,
    rtf, image_path, thumb_path, file_urls, color_hex, content_hash, image_width, image_height, byte_size
    """

    private func insert(_ clip: Clip) throws {
        try execute(
            """
            INSERT OR REPLACE INTO clips (
                id, created_at, pinned, source_app_name, source_bundle_id, kind, preview,
                text, html, rtf, image_path, thumb_path, file_urls, color_hex, content_hash,
                image_width, image_height, byte_size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            }
        )
    }

    private func writeImageFiles(for draft: ClipDraft) throws {
        if let image = draft.imagePNG {
            let url = fileURL("images/\(draft.contentHash).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try image.write(to: url)
            }
        }
        if let thumb = draft.thumbnailPNG {
            let url = fileURL("thumbs/\(draft.contentHash).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                try thumb.write(to: url)
            }
        }
    }

    private func addSnippetPinnedColumnIfNeeded() throws {
        let statement = try prepare("PRAGMA table_info(snippets)")
        defer { sqlite3_finalize(statement) }
        var found = false
        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, 1) == "pinned" {
                found = true
            }
        }
        guard !found else { return }
        try execute("ALTER TABLE snippets ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0")
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
                    copyCount: 1
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
            snippets.append(
                Snippet(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    title: columnText(statement, 2) ?? "",
                    text: columnText(statement, 3) ?? "",
                    kind: kind,
                    pinned: sqlite3_column_int(statement, 5) != 0
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
