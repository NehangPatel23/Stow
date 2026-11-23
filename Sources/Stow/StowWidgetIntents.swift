import AppIntents
import AppKit
import Foundation
import WidgetKit

/// Pause or resume clipboard recording from the widget or Shortcuts.
struct ToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Stow Recording"
    static let description = IntentDescription("Pauses or resumes Stow clipboard recording.")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var snapshot = WidgetSnapshotStore.load()
        let next = !snapshot.isPaused
        snapshot.isPaused = next
        snapshot.updatedAt = Date()
        _ = WidgetSnapshotStore.save(snapshot)
        WidgetPauseBridge.publishPaused(next)
        WidgetCenter.shared.reloadTimelines(ofKind: StowAppGroup.widgetKind)
        let message = next ? "Recording paused" : "Recording resumed"
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Copies a snippet from the widget snapshot onto the pasteboard.
struct CopyWidgetSnippetIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Stow Snippet"
    static let description = IntentDescription("Copies a Stow snippet from the desktop widget.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    @Parameter(title: "Snippet ID")
    var snippetID: String

    init() {
        snippetID = ""
    }

    init(snippetID: UUID) {
        self.snippetID = snippetID.uuidString
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Copy snippet \(\.$snippetID)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let id = UUID(uuidString: snippetID) else {
            return .result(dialog: "That snippet is missing.")
        }
        let snapshot = WidgetSnapshotStore.load()
        guard let item = snapshot.snippets.first(where: { $0.id == id }) else {
            return .result(dialog: "That snippet is missing.")
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        return .result(dialog: IntentDialog(stringLiteral: "Copied “\(item.title)”"))
    }
}
