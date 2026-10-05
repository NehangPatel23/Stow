import CryptoKit
import Foundation

enum SyncStatus: Equatable, Sendable {
    case idle
    case watching
    case syncing
    case lastSynced(Date)
    case error(String)

    var title: String {
        switch self {
        case .idle:
            "Sync is off"
        case .watching:
            "Watching sync folder"
        case .syncing:
            "Syncing…"
        case .lastSynced(let date):
            "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        case .error(let message):
            message
        }
    }
}

struct SyncPullResult: Equatable, Sendable {
    var addedClips: Int
    var addedSnippets: Int
    var addedCollections: Int
    var packageClips: Int
    var packageSnippets: Int
}

/// Pushes and pulls an encrypted archive in a user-chosen folder.
@MainActor
final class SyncEngine {
    private let store: HistoryStore
    private var pushTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var isWriting = false
    /// Blocks outbound push until the first pull after enable finishes.
    private var readyToPush = false
    private var lastPackageFingerprint: Data?
    /// Item count from the last package we successfully opened. Blocks shrinking pushes.
    private var lastPulledItemCount = 0
    private(set) var status: SyncStatus = .idle
    var onStatusChange: (@MainActor (SyncStatus) -> Void)?
    var onLibraryMerged: (@MainActor () -> Void)?

    init(store: HistoryStore) {
        self.store = store
    }

    func apply(preferences: Preferences) {
        pushTask?.cancel()
        pollTask?.cancel()
        pushTask = nil
        pollTask = nil
        readyToPush = false
        lastPackageFingerprint = nil

        guard preferences.syncEnabled else {
            setStatus(.idle)
            return
        }
        guard preferences.canEnableSync else {
            setStatus(.error("Choose a folder and set a passphrase to sync."))
            return
        }
        setStatus(.watching)
        // Pull first. Never schedule a push here — an empty local library used to
        // overwrite the sync file before the package was restored.
        pollTask = Task { [weak self] in
            await self?.runSession(preferences: preferences)
        }
    }

    func noteLocalChange(preferences: Preferences) {
        guard preferences.syncEnabled, preferences.canEnableSync, readyToPush else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.push(preferences: preferences)
        }
    }

    func syncNow(preferences: Preferences) async {
        guard preferences.canEnableSync else {
            setStatus(.error("Choose a folder and set a passphrase to sync."))
            return
        }
        lastPackageFingerprint = nil
        _ = await pull(preferences: preferences, requireEnabled: false)
        readyToPush = true
        if preferences.syncEnabled {
            await push(preferences: preferences)
        }
    }

    /// One-shot restore from the sync folder. Works even when the sync toggle is off.
    @discardableResult
    func restore(preferences: Preferences) async -> SyncPullResult? {
        guard preferences.canEnableSync else {
            setStatus(.error("Choose a folder and set a passphrase to sync."))
            return nil
        }
        lastPackageFingerprint = nil
        let result = await pull(preferences: preferences, requireEnabled: false)
        readyToPush = preferences.syncEnabled
        return result
    }

    private func runSession(preferences: Preferences) async {
        _ = await pull(preferences: preferences, requireEnabled: true)
        readyToPush = true
        // After a successful restore, publish the merged library once.
        noteLocalChange(preferences: preferences)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await pull(preferences: preferences, requireEnabled: true)
        }
    }

    private func push(preferences: Preferences) async {
        guard preferences.syncEnabled, readyToPush else { return }
        guard let passphrase = SyncKeychain.loadPassphrase() else {
            setStatus(.error("Set a sync passphrase first."))
            return
        }
        guard let bookmark = preferences.syncFolderBookmark else {
            setStatus(.error("Choose a sync folder first."))
            return
        }
        guard preferences.syncHistory || preferences.syncSnippets else {
            setStatus(.error("Turn on history or snippets sync."))
            return
        }

        // Merge anything newer from the folder before writing.
        _ = await pull(preferences: preferences, requireEnabled: true)

        setStatus(.syncing)
        do {
            let resolved = try SyncFolderAccess.resolve(bookmark)
            defer { resolved.stopAccessing() }

            let destination = resolved.url.appendingPathComponent(SyncCrypto.fileName)
            let history = (try? store.foldedHistory()) ?? []
            let snippets = (try? store.snippets()) ?? []
            let localCount = history.count + snippets.count

            if let existing = try? Data(contentsOf: destination), existing.count > 64 {
                // Keep a richer remote package when this Mac is empty or thinner.
                if localCount == 0 || (lastPulledItemCount > 0 && localCount < lastPulledItemCount) {
                    setStatus(.lastSynced(Date()))
                    return
                }
            }

            let tempArchive = FileManager.default.temporaryDirectory
                .appendingPathComponent("StowSyncOut-\(UUID().uuidString).\(LocalArchive.pathExtension)")
            defer { try? FileManager.default.removeItem(at: tempArchive) }

            var options = ArchiveExportOptions.default
            options.includeHistory = preferences.syncHistory
            options.includeSnippets = preferences.syncSnippets
            options.excludeSecretClips = true
            _ = try LocalArchive.export(from: store, to: tempArchive, options: options)

            let plaintext = try Data(contentsOf: tempArchive)
            let package = try SyncCrypto.seal(plaintext: plaintext, passphrase: passphrase)

            isWriting = true
            defer { isWriting = false }
            let staging = resolved.url.appendingPathComponent(".\(SyncCrypto.fileName).tmp")
            try package.write(to: staging, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            lastPackageFingerprint = Data(SHA256.hash(data: package))
            lastPulledItemCount = max(lastPulledItemCount, localCount)
            setStatus(.lastSynced(Date()))
        } catch {
            setStatus(.error(Self.message(for: error)))
        }
    }

    @discardableResult
    private func pull(preferences: Preferences, requireEnabled: Bool) async -> SyncPullResult? {
        if requireEnabled {
            guard preferences.syncEnabled else { return nil }
        }
        guard !isWriting else { return nil }
        guard let passphrase = SyncKeychain.loadPassphrase() else {
            setStatus(.error("Set a sync passphrase first."))
            return nil
        }
        guard let bookmark = preferences.syncFolderBookmark else {
            setStatus(.error("Choose a sync folder first."))
            return nil
        }

        do {
            let resolved = try SyncFolderAccess.resolve(bookmark)
            defer { resolved.stopAccessing() }

            let packageURL = resolved.url.appendingPathComponent(SyncCrypto.fileName)
            guard FileManager.default.fileExists(atPath: packageURL.path) else {
                setStatus(.error("No library.stowsync in the sync folder yet."))
                return nil
            }

            let package = try Data(contentsOf: packageURL)
            let fingerprint = Data(SHA256.hash(data: package))
            if fingerprint == lastPackageFingerprint {
                return SyncPullResult(
                    addedClips: 0,
                    addedSnippets: 0,
                    addedCollections: 0,
                    packageClips: 0,
                    packageSnippets: 0
                )
            }

            setStatus(.syncing)
            let plaintext = try SyncCrypto.open(package: package, passphrase: passphrase)
            let tempArchive = FileManager.default.temporaryDirectory
                .appendingPathComponent("StowSyncIn-\(UUID().uuidString).\(LocalArchive.pathExtension)")
            defer { try? FileManager.default.removeItem(at: tempArchive) }
            try plaintext.write(to: tempArchive)

            let result = try LocalArchive.importArchive(from: tempArchive, into: store, mode: .merge)
            lastPackageFingerprint = fingerprint
            let packageCount = result.manifest.counts.clips + result.manifest.counts.snippets
            lastPulledItemCount = max(lastPulledItemCount, packageCount)
            if result.addedClips > 0 || result.addedSnippets > 0 || result.addedCollections > 0 {
                onLibraryMerged?()
            }
            setStatus(.lastSynced(Date()))
            return SyncPullResult(
                addedClips: result.addedClips,
                addedSnippets: result.addedSnippets,
                addedCollections: result.addedCollections,
                packageClips: result.manifest.counts.clips,
                packageSnippets: result.manifest.counts.snippets
            )
        } catch {
            setStatus(.error(Self.message(for: error)))
            return nil
        }
    }

    private func setStatus(_ status: SyncStatus) {
        self.status = status
        onStatusChange?(status)
    }

    private static func message(for error: Error) -> String {
        if let sync = error as? SyncCryptoError { return sync.description }
        if let archive = error as? ArchiveError { return archive.description }
        if let store = error as? StoreError { return store.description }
        return "Couldn't sync that folder."
    }
}
