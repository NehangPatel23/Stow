import Foundation

enum SyncFolderAccess {
    /// Creates a security-scoped bookmark for a user-chosen directory.
    static func bookmark(for folderURL: URL) throws -> Data {
        try folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Resolves a bookmark and starts security-scoped access. Caller must call `stopAccessing`.
    static func resolve(_ bookmark: Data) throws -> (url: URL, stopAccessing: () -> Void) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard url.startAccessingSecurityScopedResource() else {
            throw StoreError.sqlite("Couldn't open the sync folder.")
        }
        return (url, { url.stopAccessingSecurityScopedResource() })
    }

    static func displayPath(for folderURL: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = folderURL.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
