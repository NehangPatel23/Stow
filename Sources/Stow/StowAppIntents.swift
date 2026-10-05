import AppIntents
import Foundation

/// Opens the same on-disk library the running app uses.
enum StowIntentSupport {
    static let libraryDidChangeNotification = Notification.Name("com.nehangpatel.Stow.libraryDidChange")

    static func openStore() throws -> HistoryStore {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try HistoryStore(directory: root.appendingPathComponent("Stow", isDirectory: true))
    }

    static func notifyLibraryChanged() {
        DistributedNotificationCenter.default().post(
            name: libraryDidChangeNotification,
            object: nil
        )
    }

    static func text(for clip: Clip, store: HistoryStore) throws -> String? {
        let full = try store.payload(id: clip.id) ?? clip
        if let text = full.text, !ClipText.isBlank(text) {
            return text
        }
        if !ClipText.isBlank(full.preview) {
            return full.preview
        }
        return nil
    }
}

enum StowIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyHistory
    case noText
    case store(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyHistory:
            "Stow history is empty."
        case .noText:
            "That clip has no text to save."
        case .store(let message):
            "\(message)"
        }
    }
}

/// Returns the newest folded history item.
struct GetLatestClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Clip"
    static let description = IntentDescription("Returns the newest item in Stow history.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let store = try StowIntentSupport.openStore()
            guard let clip = try store.foldedHistory(limit: 40).first else {
                throw StowIntentError.emptyHistory
            }
            guard let value = try StowIntentSupport.text(for: clip, store: store) else {
                throw StowIntentError.noText
            }
            return .result(value: value, dialog: IntentDialog(stringLiteral: value))
        } catch let error as StowIntentError {
            throw error
        } catch {
            throw StowIntentError.store(error.localizedDescription)
        }
    }
}

/// Searches history with the same query language as the panel.
struct SearchClipsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Clips"
    static let description = IntentDescription("Searches Stow history. Supports operators like type:link and from:today.")
    static let openAppWhenRun = false

    @Parameter(title: "Query", description: "Search text or operators such as type:image.")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Stow for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let store = try StowIntentSupport.openStore()
            let parsed = SearchQuery.parse(query)
            let now = Date()
            let matches = try store.foldedHistory()
                .filter { parsed.matches($0, now: now) }
                .prefix(10)
            if matches.isEmpty {
                return .result(value: "", dialog: "No clips matched.")
            }
            let lines = matches.enumerated().map { index, clip in
                "\(index + 1). \(clip.preview)"
            }
            let value = lines.joined(separator: "\n")
            return .result(value: value, dialog: IntentDialog(stringLiteral: value))
        } catch let error as StowIntentError {
            throw error
        } catch {
            throw StowIntentError.store(error.localizedDescription)
        }
    }
}

/// Saves text as a Stow snippet. Uses the latest clip when text is omitted.
struct SaveAsSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Save as Snippet"
    static let description = IntentDescription("Saves text as a Stow snippet. Leave Text empty to use the latest clip.")
    static let openAppWhenRun = false

    @Parameter(title: "Text", description: "Snippet body. Empty uses the latest history clip.")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) as a Stow snippet")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            let store = try StowIntentSupport.openStore()
            let body: String
            if let text, !ClipText.isBlank(text) {
                body = text
            } else if let clip = try store.foldedHistory(limit: 40).first,
                      let value = try StowIntentSupport.text(for: clip, store: store) {
                body = value
            } else {
                throw StowIntentError.noText
            }

            let title = ClipText.previewLine(from: body, limit: 48)
            let kind = ClipClassifier.classify(
                text: body,
                html: nil,
                hasRTF: false,
                hasImage: false,
                fileURLs: []
            )
            let snippet = try store.addSnippet(title: title, text: body, kind: kind)
            StowIntentSupport.notifyLibraryChanged()
            let message = "Saved snippet “\(snippet.title)”"
            return .result(value: snippet.title, dialog: IntentDialog(stringLiteral: message))
        } catch let error as StowIntentError {
            throw error
        } catch {
            throw StowIntentError.store(error.localizedDescription)
        }
    }
}

struct StowAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestClipIntent(),
            phrases: [
                "Get latest clip in \(.applicationName)",
                "Latest clip in \(.applicationName)",
            ],
            shortTitle: "Latest Clip",
            systemImageName: "clipboard"
        )
        AppShortcut(
            intent: SearchClipsIntent(),
            phrases: [
                "Search clips in \(.applicationName)",
                "Search \(.applicationName) history",
            ],
            shortTitle: "Search Clips",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: SaveAsSnippetIntent(),
            phrases: [
                "Save as snippet in \(.applicationName)",
                "Save snippet in \(.applicationName)",
            ],
            shortTitle: "Save Snippet",
            systemImageName: "text.badge.plus"
        )
    }
}
