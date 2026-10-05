import AppKit
import Foundation
import UniformTypeIdentifiers

struct UndoState: Equatable {
    var clips: [Clip]
    var snippets: [Snippet]
    var message: String
    var deadline: Date
}

struct ArchiveExportPickerState: Identifiable, Equatable {
    var id = UUID()
    var clips: [Clip]
}

struct SkippedCapture: Equatable {
    var draft: ClipDraft
    var reason: SecretDetector.Reason
}

struct SnippetSection: Identifiable, Equatable {
    var id: String
    var title: String
    var snippets: [Snippet]
}

enum Library: String, CaseIterable, Identifiable, Equatable {
    case history
    case snippets

    var id: String { rawValue }
    var title: String {
        switch self {
        case .history: "History"
        case .snippets: "Snippets"
        }
    }
}

enum CollectionFilter: Equatable, Hashable {
    case all
    case unfiled
    case collection(UUID)
}

enum MenuBarState: Equatable {
    case ready
    case paused
    case ignoringNext
    case skippedSecret
}

@MainActor
@Observable
final class AppModel {
    let store: HistoryStore

    var preferences: Preferences {
        didSet {
            let hotkeyChanged = oldValue.hotkeyKeyCode != preferences.hotkeyKeyCode
                || oldValue.hotkeyCarbonModifiers != preferences.hotkeyCarbonModifiers
            let layoutChanged = oldValue.compactRows != preferences.compactRows
                || oldValue.showShortcutFooter != preferences.showShortcutFooter
            let retentionChanged = oldValue.textRetentionDays != preferences.textRetentionDays
                || oldValue.imageRetentionDays != preferences.imageRetentionDays
            preferences.save()
            if hotkeyChanged {
                onHotkeyChange?()
            }
            if layoutChanged {
                relayoutQuickPanel?()
            }
            if retentionChanged {
                enforceStorageRules(force: true)
            }
            onChromeChange?()
        }
    }

    var library: Library = .history
    var query = ""
    var chipKind: ClipKind?
    var chipPinned = false
    var collectionFilter: CollectionFilter = .all
    private(set) var history: [Clip] = []
    private(set) var snippets: [Snippet] = []
    private(set) var collections: [SnippetCollection] = []
    var selectedID: UUID?
    var selection: Set<UUID> = []
    var selectionAnchor: UUID?
    var expandedHashes: Set<String> = []
    var copiesByHash: [String: [Clip]] = [:]
    var preview: Clip?
    var banner: String?
    var undo: UndoState?
    var skipped: SkippedCapture?
    var showPermission = false
    var showsSettings = false
    var clipBeingEdited: Clip?
    var snippetBeingEdited: Snippet?
    var templateFill: TemplateFillRequest?
    var archiveExportPicker: ArchiveExportPickerState?
    var joinSeparator = ", "
    var focusToken = 0
    var activeHotkeyLabel: String
    var previousApp: NSRunningApplication?

    var closePanel: (@MainActor (Bool) -> Void)?
    var openSettings: (@MainActor () -> Void)?
    var presentJoinPrompt: (@MainActor () -> Void)?
    var presentTextPrompt: (@MainActor (
        _ title: String,
        _ message: String,
        _ defaultValue: String,
        _ confirmTitle: String,
        _ onConfirm: @escaping @MainActor (String) -> Void
    ) -> Void)?
    var relayoutQuickPanel: (@MainActor () -> Void)?
    var stepAside: (@MainActor (_ app: NSRunningApplication, _ keepOpen: Bool) -> Void)?
    var restorePanelAfterPaste: (@MainActor () -> Void)?
    var onHotkeyChange: (@MainActor () -> Void)?
    var onChromeChange: (@MainActor () -> Void)?
    var notePasteboardWrite: (@MainActor () -> Void)?
    var notice: Notice?
    private(set) var storageByteCount = 0
    private var noticeTask: Task<Void, Never>?
    private var lastStorageEnforceAt: Date?

    init(store: HistoryStore) {
        self.store = store
        let loaded = Preferences.load()
        preferences = loaded
        activeHotkeyLabel = loaded.hotkeyLabel
        store.applyDataProtection()
        refresh()
        enforceStorageRules(force: true)
    }

    var showingFirstRun: Bool {
        !preferences.hasSeenFirstRun || showPermission
    }

    var menuBarState: MenuBarState {
        if isPaused || frontAppPauseIsActive {
            return .paused
        }
        if preferences.ignoreNextCopy {
            return .ignoringNext
        }
        if skipped != nil {
            return .skippedSecret
        }
        return .ready
    }

    var isPaused: Bool {
        if preferences.manuallyPaused { return true }
        if let until = preferences.pauseUntil, until > Date() { return true }
        return false
    }

    var frontAppPauseIsActive: Bool {
        guard let until = preferences.frontAppPauseUntil else { return false }
        return until > Date()
    }

    var extraIgnoredTypes: Set<String> {
        Set(preferences.extraIgnoredPasteboardTypes)
    }

    var visibleHistory: [Clip] {
        let parsed = SearchQuery.parse(query).merging(kind: chipKind, pinned: chipPinned)
        let now = Date()
        return history.filter { parsed.matches($0, now: now) }
    }

    var historySections: [HistorySection] {
        HistoryOrganizer.sections(clips: visibleHistory, now: Date())
    }

    var flattenedHistory: [Clip] {
        HistoryOrganizer.flattened(historySections)
    }

    var visibleSnippets: [Snippet] {
        let parsed = effectiveQuery
        let names = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0.name) })
        let filtered = snippets.filter { snippet in
            guard matchesCollectionFilter(snippet) else { return false }
            return parsed.matches(snippet) { names[$0] }
        }
        guard parsed.terms.count == 1, let term = parsed.terms.first?.lowercased() else {
            return filtered
        }
        return filtered.sorted { lhs, rhs in
            let leftExact = lhs.normalizedAbbreviation == term
            let rightExact = rhs.normalizedAbbreviation == term
            if leftExact != rightExact { return leftExact && !rightExact }
            return false
        }
    }

    /// Lowercased abbreviation → expansion text for marked snippets only.
    var abbreviationExpansions: [String: String] {
        var map: [String: String] = [:]
        for snippet in snippets {
            guard let abbr = snippet.normalizedAbbreviation else { continue }
            let fields = snippet.templateFields
            if fields.isEmpty {
                map[abbr] = snippet.text
            } else {
                map[abbr] = SnippetTemplate.render(
                    snippet.text,
                    values: SnippetTemplate.defaults(for: fields)
                )
            }
        }
        return map
    }

    var canExpandAbbreviations: Bool {
        preferences.abbreviationExpansionEnabled
            && !abbreviationExpansions.isEmpty
            && AccessibilityClient.isTrusted(prompt: false)
    }

    var snippetSections: [SnippetSection] {
        let items = visibleSnippets
        switch collectionFilter {
        case .collection(let id):
            let name = collections.first { $0.id == id }?.name ?? "Board"
            return [SnippetSection(id: id.uuidString, title: name, snippets: sortedSnippets(items))]
        case .unfiled:
            return [SnippetSection(id: "unfiled", title: "Unfiled", snippets: sortedSnippets(items))]
        case .all:
            var sections: [SnippetSection] = []
            let pinned = items.filter(\.pinned)
            if !pinned.isEmpty {
                sections.append(SnippetSection(id: "pinned", title: "Pinned", snippets: sortedSnippets(pinned)))
            }
            for collection in collections {
                let board = items.filter { !$0.pinned && $0.collectionID == collection.id }
                if !board.isEmpty {
                    sections.append(
                        SnippetSection(id: collection.id.uuidString, title: collection.name, snippets: sortedSnippets(board))
                    )
                }
            }
            let unfiled = items.filter { !$0.pinned && $0.collectionID == nil }
            if !unfiled.isEmpty {
                sections.append(SnippetSection(id: "unfiled", title: "Unfiled", snippets: sortedSnippets(unfiled)))
            }
            return sections
        }
    }

    var orderedSnippets: [Snippet] {
        snippetSections.flatMap(\.snippets)
    }

    var effectiveQuery: SearchQuery {
        SearchQuery.parse(query).merging(kind: chipKind, pinned: chipPinned)
    }

    func refresh() {
        history = (try? store.foldedHistory()) ?? []
        snippets = (try? store.snippets()) ?? []
        collections = (try? store.collections()) ?? []
        storageByteCount = store.storageByteCount()
        if case .collection(let id) = collectionFilter, !collections.contains(where: { $0.id == id }) {
            collectionFilter = .all
        }
        if let selectedID, !containsSelection(selectedID) {
            self.selectedID = nil
            preview = nil
        }
        selection.formIntersection(Set(flattenedHistory.map(\.id) + orderedSnippets.map(\.id)))
        loadPreview()
    }

    func prepareForOpen() {
        query = ""
        chipKind = nil
        chipPinned = false
        collectionFilter = .all
        expandedHashes = []
        refresh()
        if let selectedID, !containsSelection(selectedID) {
            self.selectedID = nil
            preview = nil
        }
        loadPreview()
        focusToken += 1
    }

    func notePreviousApp(_ app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousApp = app
    }

    func shouldCaptureNextCopy() -> Bool {
        if preferences.ignoreNextCopy {
            preferences.ignoreNextCopy = false
            notify("Ignored one copy", symbol: "arrow.uturn.backward.circle")
            return false
        }
        if isPaused {
            return false
        }
        if frontAppPauseIsActive,
           let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           bundleID == preferences.frontAppPauseBundleID {
            return false
        }
        return true
    }

    func isExcluded(_ bundleID: String) -> Bool {
        if frontAppPauseIsActive, bundleID == preferences.frontAppPauseBundleID {
            return true
        }
        return preferences.excludedApps.contains { $0.bundleID == bundleID }
    }

    func ingest(draft: ClipDraft, secret: SecretDetector.Reason?) {
        if let secret {
            skipped = SkippedCapture(draft: draft, reason: secret)
            notify("Skipped a \(secret.title)", detail: "Keep it from the menu if you want it stored.", symbol: "eye.slash")
            onChromeChange?()
            return
        }
        skipped = nil
        do {
            _ = try store.record(draft)
            refresh()
            onChromeChange?()
            notify(
                "Saved to Stow",
                detail: ClipText.previewLine(from: draft.preview, limit: 72),
                symbol: "checkmark.circle.fill"
            )
        } catch {
            notify("Couldn't save that copy", symbol: "exclamationmark.circle")
        }
    }

    func keepSkipped() {
        guard let skipped else { return }
        self.skipped = nil
        do {
            let clip = try store.record(skipped.draft)
            refresh()
            selectedID = clip.id
            loadPreview()
            notify("Kept the skipped copy", symbol: "checkmark.circle.fill")
        } catch {
            notify("Couldn't save that copy", symbol: "exclamationmark.circle")
        }
        onChromeChange?()
    }

    func discardSkipped() {
        skipped = nil
        notify("Discarded the skipped copy", symbol: "trash")
        onChromeChange?()
    }

    func togglePause() {
        if isPaused {
            preferences.manuallyPaused = false
            preferences.pauseUntil = nil
            notify("Recording resumed", symbol: "record.circle")
        } else {
            preferences.manuallyPaused = true
            preferences.pauseUntil = nil
            notify("Recording is paused", symbol: "pause.circle")
        }
    }

    func pauseForOneHour() {
        preferences.manuallyPaused = false
        preferences.pauseUntil = Date().addingTimeInterval(60 * 60)
        notify("Recording is paused for an hour", symbol: "pause.circle")
    }

    func pauseFrontAppForOneHour() {
        guard let app = appWorthExcluding(), let bundleID = app.bundleIdentifier else {
            notify("Bring the app forward, then try again", symbol: "exclamationmark.circle")
            return
        }
        preferences.frontAppPauseBundleID = bundleID
        preferences.frontAppPauseName = app.localizedName ?? bundleID
        preferences.frontAppPauseUntil = Date().addingTimeInterval(60 * 60)
        notify("Paused \(preferences.frontAppPauseName ?? "that app") for an hour", symbol: "pause.circle")
    }

    func ignoreNextCopy() {
        preferences.ignoreNextCopy = true
        notify("The next copy will be ignored", symbol: "arrow.uturn.backward.circle")
    }

    func excludeCurrentApp() {
        guard let app = appWorthExcluding(), let bundleID = app.bundleIdentifier else {
            notify("Bring the app forward, then try again", symbol: "exclamationmark.circle")
            return
        }
        guard !preferences.excludedApps.contains(where: { $0.bundleID == bundleID }) else {
            notify("That app is already excluded", symbol: "exclamationmark.circle")
            return
        }
        preferences.excludedApps.append(
            ExcludedApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
        )
        notify("\(app.localizedName ?? bundleID) won't be recorded", symbol: "nosign")
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        preferences.excludedApps.removeAll { $0.bundleID == app.bundleID }
        notify("\(app.name) will be recorded again", symbol: "checkmark.circle")
    }

    func addIgnoredType(_ raw: String) {
        let type = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty, !preferences.extraIgnoredPasteboardTypes.contains(type) else { return }
        preferences.extraIgnoredPasteboardTypes.append(type)
        notify("Ignoring that pasteboard type", detail: type, symbol: "nosign")
    }

    func removeIgnoredType(_ type: String) {
        preferences.extraIgnoredPasteboardTypes.removeAll { $0 == type }
        notify("Removed that pasteboard type", detail: type, symbol: "checkmark.circle")
    }

    func reconcileSelection() {
        selection.formIntersection(Set(visibleIDs()))
        switch library {
        case .history:
            if let selectedID, flattenedHistory.contains(where: { $0.id == selectedID }) { return }
            selectedID = nil
            preview = nil
        case .snippets:
            if let selectedID, visibleSnippets.contains(where: { $0.id == selectedID }) { return }
            selectedID = nil
            preview = nil
        }
    }

    func selectOnly(_ id: UUID) {
        selection = [id]
        selectionAnchor = id
        select(id)
    }

    func toggleInSelection(_ id: UUID) {
        if selection.contains(id), selection.count > 1 {
            selection.remove(id)
            if selectedID == id {
                selectedID = selection.first
                loadPreview()
            }
        } else {
            selection.insert(id)
            select(id)
        }
        selectionAnchor = id
    }

    func extendSelection(to id: UUID) {
        let ids = visibleIDs()
        guard let anchor = selectionAnchor ?? selectedID,
              let start = ids.firstIndex(of: anchor),
              let end = ids.firstIndex(of: id) else {
            selectOnly(id)
            return
        }
        let lower = min(start, end)
        let upper = max(start, end)
        selection = Set(ids[lower...upper])
        selectionAnchor = anchor
        select(id)
    }

    func askJoinSeparator() {
        presentJoinPrompt?()
    }

    func pasteSelection(separator: String) {
        let pieces = selectionTexts()
        guard !pieces.isEmpty else {
            notify("Select a clip", symbol: "arrow.down.doc")
            return
        }
        let joined = pieces.joined(separator: separator)
        PasteService.writeText(joined)
        notePasteboardWrite?()
        deliverToPreviousApp(message: pieces.count == 1 ? "Pasted" : "Pasted \(pieces.count) clips")
    }

    private func visibleIDs() -> [UUID] {
        library == .history ? flattenedHistory.map(\.id) : orderedSnippets.map(\.id)
    }

    private func selectionTexts() -> [String] {
        let chosen = selection.isEmpty ? Set(selectedID.map { [$0] } ?? []) : selection
        if library == .history {
            return flattenedHistory
                .filter { chosen.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }
                .map { clip in
                    let text = clip.text?.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (text?.isEmpty == false ? text! : clip.preview)
                }
        }
        return orderedSnippets
            .filter { chosen.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.text)
    }

    private func deliverToPreviousApp(message: String) {
        let keepOpen = preferences.keepPanelOpen
        if !keepOpen {
            closePanel?(false)
        }
        guard let target = previousApp else {
            notify("Copied", detail: "Switch to an app, then paste.", symbol: "doc.on.doc")
            return
        }
        stepAside?(target, keepOpen)
        notify(message, symbol: "arrow.down.doc")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                self.stepAside?(target, keepOpen)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    PasteService.sendCommandV()
                    if keepOpen {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            self.restorePanelAfterPaste?()
                        }
                    }
                }
            } else {
                PasteService.sendCommandV()
                if keepOpen {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.restorePanelAfterPaste?()
                    }
                }
            }
        }
    }

    func select(_ id: UUID) {
        selectedID = id
        loadPreview()
    }

    func click(_ id: UUID) {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            toggleInSelection(id)
        } else if flags.contains(.shift) {
            extendSelection(to: id)
        } else {
            selectOnly(id)
        }
    }

    func moveSelection(_ delta: Int) {
        switch library {
        case .history:
            let items = flattenedHistory
            guard !items.isEmpty else { return }
            let current = items.firstIndex { $0.id == selectedID } ?? 0
            let next = min(max(0, current + delta), items.count - 1)
            select(items[next].id)
        case .snippets:
            let items = orderedSnippets
            guard !items.isEmpty else { return }
            let current = items.firstIndex { $0.id == selectedID } ?? 0
            let next = min(max(0, current + delta), items.count - 1)
            select(items[next].id)
        }
    }

    func selectShortcut(_ number: Int) {
        let index = number - 1
        switch library {
        case .history:
            let items = flattenedHistory
            guard items.indices.contains(index) else { return }
            select(items[index].id)
        case .snippets:
            let items = orderedSnippets
            guard items.indices.contains(index) else { return }
            select(items[index].id)
        }
    }

    func toggleExpanded(_ hash: String) {
        if expandedHashes.contains(hash) {
            expandedHashes.remove(hash)
        } else {
            expandedHashes.insert(hash)
            copiesByHash[hash] = (try? store.copies(contentHash: hash)) ?? []
        }
    }

    func beginEditing(_ clip: Clip) {
        select(clip.id)
        clipBeingEdited = materialized(clip)
    }

    func saveEditedClip(_ clip: Clip, attributed: NSAttributedString) {
        let plain = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else {
            notify("That clip can't be empty", symbol: "exclamationmark.circle")
            return
        }
        let range = NSRange(location: 0, length: attributed.length)
        let rtf = attributed.rtf(from: range)
        let html = htmlString(from: attributed)
        let kind = ClipClassifier.classify(
            text: plain,
            html: html,
            hasRTF: rtf != nil,
            hasImage: clip.imageRelativePath != nil,
            fileURLs: clip.fileURLs
        )
        let colorHex = ColorValue.parse(plain)?.hex
        do {
            try store.updateContent(
                contentHash: clip.contentHash,
                text: attributed.string,
                html: html,
                rtf: rtf,
                preview: ClipText.previewLine(from: plain),
                kind: kind,
                colorHex: colorHex,
                byteSize: plain.utf8.count,
                newHash: ContentHash.text(plain)
            )
            clipBeingEdited = nil
            refresh()
            notify("Updated clip", symbol: "pencil")
        } catch {
            notify("Couldn't update that clip", symbol: "exclamationmark.circle")
        }
    }

    private func htmlString(from attributed: NSAttributedString) -> String? {
        let range = NSRange(location: 0, length: attributed.length)
        let attributes: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
        ]
        guard let data = try? attributed.data(from: range, documentAttributes: attributes),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return html
    }

    func copySelected() {
        guard writeSelection(plain: false) else {
            notify("Nothing to copy", symbol: "exclamationmark.circle")
            return
        }
        notify("Copied", symbol: "doc.on.doc")
        if !preferences.keepPanelOpen {
            closePanel?(true)
        }
    }

    func pasteSelected(plain requestedPlain: Bool) {
        if library == .snippets, let snippet = selectedSnippet() {
            let fields = snippet.templateFields
            if !fields.isEmpty {
                templateFill = TemplateFillRequest(
                    title: snippet.title,
                    template: snippet.text,
                    fields: fields,
                    values: SnippetTemplate.defaults(for: fields),
                    plain: requestedPlain
                )
                return
            }
        }

        guard let clip = selectedClip() else {
            notify("Select a clip", symbol: "arrow.down.doc")
            return
        }
        let full = materialized(clip)
        pasteClip(full, plain: requestedPlain)
    }

    func completeTemplateFill(_ filled: String) {
        let plain = templateFill?.plain ?? false
        templateFill = nil
        PasteService.writeText(filled)
        notePasteboardWrite?()
        deliverToPreviousApp(message: plain ? "Pasted as plain text" : "Pasted")
    }

    func cancelTemplateFill() {
        templateFill = nil
    }

    private func pasteClip(_ full: Clip, plain requestedPlain: Bool) {
        let target = previousApp
        let plain = requestedPlain || full.kind == .code || PasteTarget.prefersPlainText(
            bundleID: target?.bundleIdentifier,
            appName: target?.localizedName
        )

        if AccessibilityClient.isTrusted(prompt: false),
           let pid = target?.processIdentifier,
           FocusedField.isSecureTextField(pid: pid) {
            commitWrite(full, plain: true)
            notify("Copied", detail: "The focused field is secure, so Stow did not type into it.", symbol: "lock")
            return
        }

        commitWrite(full, plain: plain)
        deliverToPreviousApp(message: plain ? "Pasted as plain text" : "Pasted")
    }

    func copyTransform(_ transform: ClipTransform, text: String, html: String?) {
        guard let output = transform.output(text: text, html: html) else { return }
        PasteService.writeText(output)
        notePasteboardWrite?()
        notify("Copied \(transform.title)", symbol: transform.symbolName)
    }

    func copyColorFormat(_ text: String) {
        PasteService.writeText(text)
        notePasteboardWrite?()
        notify("Copied \(text)", symbol: "doc.on.doc")
    }

    func togglePin() {
        switch library {
        case .history:
            guard let clip = selectedHistoryClip() else { return }
            do {
                let willPin = !clip.pinned
                try store.setPinned(contentHash: clip.contentHash, pinned: willPin)
                refresh()
                notify(willPin ? "Pinned" : "Unpinned", symbol: willPin ? "pin.fill" : "pin.slash")
            } catch {
                notify("Couldn't update that pin", symbol: "exclamationmark.circle")
            }
        case .snippets:
            guard let snippet = selectedSnippet() else { return }
            do {
                let willPin = !snippet.pinned
                try store.setSnippetPinned(id: snippet.id, pinned: willPin)
                refresh()
                notify(willPin ? "Pinned" : "Unpinned", symbol: willPin ? "pin.fill" : "pin.slash")
            } catch {
                notify("Couldn't update that pin", symbol: "exclamationmark.circle")
            }
        }
    }

    func deleteSelected() {
        switch library {
        case .history:
            guard let clip = selectedHistoryClip() else { return }
            do {
                let removed = try store.delete(contentHash: clip.contentHash)
                stageUndo(clips: removed, snippets: [], message: "Deleted clip")
                refresh()
            } catch {
                notify("Couldn't delete that clip", symbol: "exclamationmark.circle")
            }
        case .snippets:
            guard let snippet = selectedSnippet() else { return }
            do {
                if let removed = try store.deleteSnippet(id: snippet.id) {
                    stageUndo(clips: [], snippets: [removed], message: "Deleted snippet")
                }
                refresh()
            } catch {
                notify("Couldn't delete that snippet", symbol: "exclamationmark.circle")
            }
        }
    }

    func deleteCopy(id: UUID) {
        do {
            if let removed = try store.delete(id: id) {
                stageUndo(clips: [removed], snippets: [], message: "Deleted one copy")
            }
            refresh()
        } catch {
            notify("Couldn't delete that copy", symbol: "exclamationmark.circle")
        }
    }

    func clearHistory(includingPinned: Bool) {
        do {
            let removed = try store.clearHistory(includingPinned: includingPinned)
            guard !removed.isEmpty else {
                notify("History is already empty", symbol: "tray")
                return
            }
            let message = includingPinned ? "Cleared history" : "Cleared unpinned history"
            stageUndo(clips: removed, snippets: [], message: message)
            refresh()
        } catch {
            notify("Couldn't clear history", symbol: "exclamationmark.circle")
        }
    }

    func exportArchive() {
        let alert = NSAlert()
        alert.messageText = "Export Stow archive"
        alert.informativeText = "Include every clip, or leave some out. Snippets and boards always export."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Export All")
        alert.addButton(withTitle: "Choose Clips…")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            finishExport(excludingContentHashes: [])
        case .alertSecondButtonReturn:
            let candidates = (try? store.foldedHistory()) ?? history
            guard !candidates.isEmpty else {
                finishExport(excludingContentHashes: [])
                return
            }
            archiveExportPicker = ArchiveExportPickerState(clips: candidates)
        default:
            break
        }
    }

    func cancelArchiveExportPicker() {
        archiveExportPicker = nil
    }

    func confirmArchiveExportPicker(excludedContentHashes: Set<String>) {
        archiveExportPicker = nil
        finishExport(excludingContentHashes: excludedContentHashes)
    }

    func importArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Import Stow Archive"
        if let type = UTType(filenameExtension: LocalArchive.pathExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "Import Stow archive"
        alert.informativeText = "Add new only keeps what you already have and imports the rest. Replace clears history, snippets, and boards first. Preferences stay as they are."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Add New Only")
        alert.addButton(withTitle: "Replace Everything")
        alert.addButton(withTitle: "Cancel")
        let mode: ArchiveImportMode
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            mode = .merge
        case .alertSecondButtonReturn:
            mode = .replace
        default:
            return
        }

        do {
            let result = try LocalArchive.importArchive(from: url, into: store, mode: mode)
            selectedID = nil
            selection = []
            preview = nil
            library = .history
            collectionFilter = .all
            refresh()
            switch mode {
            case .merge:
                if result.addedClips == 0 && result.addedSnippets == 0 && result.addedCollections == 0 {
                    notify("Nothing new to import", symbol: "square.and.arrow.down")
                } else {
                    notify(
                        "Added from archive",
                        detail: "\(result.addedClips) clips · \(result.addedSnippets) snippets",
                        symbol: "square.and.arrow.down"
                    )
                }
            case .replace:
                notify(
                    "Imported archive",
                    detail: "\(result.manifest.counts.clips) clips · \(result.manifest.counts.snippets) snippets",
                    symbol: "square.and.arrow.down"
                )
            }
        } catch {
            let message = (error as? ArchiveError)?.description
                ?? (error as? StoreError)?.description
                ?? "Couldn't import that archive"
            notify(message, symbol: "exclamationmark.circle")
        }
    }

    private func finishExport(excludingContentHashes: Set<String>) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = "Export Stow Archive"
        panel.nameFieldStringValue = "Stow Archive"
        if let type = UTType(filenameExtension: LocalArchive.pathExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let manifest = try LocalArchive.export(
                from: store,
                to: url,
                excludingContentHashes: excludingContentHashes
            )
            let excluded = excludingContentHashes.isEmpty
                ? nil
                : "Left out \(excludingContentHashes.count) \(excludingContentHashes.count == 1 ? "clip" : "clips")"
            notify(
                "Exported archive",
                detail: excluded ?? "\(manifest.counts.clips) clips · \(manifest.counts.snippets) snippets",
                symbol: "square.and.arrow.up"
            )
        } catch {
            let message = (error as? ArchiveError)?.description
                ?? (error as? StoreError)?.description
                ?? "Couldn't export that archive"
            notify(message, symbol: "exclamationmark.circle")
        }
    }

    /// Removes expired unpinned clips, orphaned image files, and compacts the database.
    func trimStorage() {
        let before = store.storageByteCount()
        do {
            let removed = try store.deleteExpired(
                textOlderThan: retentionCutoff(days: preferences.textRetentionDays),
                imageOlderThan: retentionCutoff(days: preferences.imageRetentionDays)
            )
            let orphanBytes = try store.reapOrphanedImages()
            if !removed.isEmpty {
                try store.reapImages(hashes: Set(removed.map(\.contentHash)))
            }
            try store.compactStorage()
            lastStorageEnforceAt = Date()
            refresh()
            let freed = max(0, before - storageByteCount)
            if removed.isEmpty && orphanBytes == 0 && freed == 0 {
                notify("Nothing to trim", symbol: "internaldrive")
            } else if freed > 0 {
                notify(
                    "Trimmed \(ByteFormat.string(for: freed))",
                    detail: removed.isEmpty ? nil : "Removed \(removed.count) expired \(removed.count == 1 ? "clip" : "clips")",
                    symbol: "internaldrive"
                )
            } else {
                notify(
                    removed.isEmpty ? "Storage cleaned up" : "Removed \(removed.count) expired \(removed.count == 1 ? "clip" : "clips")",
                    symbol: "internaldrive"
                )
            }
        } catch {
            notify("Couldn't trim storage", symbol: "exclamationmark.circle")
        }
    }

    @discardableResult
    func enforceStorageRules(force: Bool = false) -> Int {
        if !force, let lastStorageEnforceAt, Date().timeIntervalSince(lastStorageEnforceAt) < 60 {
            return 0
        }
        let textCutoff = retentionCutoff(days: preferences.textRetentionDays)
        let imageCutoff = retentionCutoff(days: preferences.imageRetentionDays)
        guard textCutoff != nil || imageCutoff != nil else {
            lastStorageEnforceAt = Date()
            storageByteCount = store.storageByteCount()
            return 0
        }
        do {
            let removed = try store.deleteExpired(textOlderThan: textCutoff, imageOlderThan: imageCutoff)
            if !removed.isEmpty {
                try store.reapImages(hashes: Set(removed.map(\.contentHash)))
                refresh()
            } else {
                storageByteCount = store.storageByteCount()
            }
            lastStorageEnforceAt = Date()
            return removed.count
        } catch {
            lastStorageEnforceAt = Date()
            return 0
        }
    }

    func performUndo() {
        guard let undo else { return }
        do {
            try store.restore(clips: undo.clips)
            try store.restoreSnippets(undo.snippets)
            self.undo = nil
            notify("Undone", symbol: "arrow.uturn.backward")
            refresh()
        } catch {
            notify("Couldn't undo that", symbol: "exclamationmark.circle")
        }
    }

    func saveSnippetFromSelection() {
        guard let clip = selectedClip() else { return }
        let full = materialized(clip)
        guard let text = full.text, !ClipText.isBlank(text) else {
            notify("That clip has no text to save", symbol: "exclamationmark.circle")
            return
        }
        let title = ClipText.previewLine(from: text, limit: 48)
        let kind: ClipKind = full.kind == .image || full.kind == .file ? .text : full.kind
        let board: UUID? = {
            if case .collection(let id) = collectionFilter { return id }
            return nil
        }()
        do {
            let snippet = try store.addSnippet(title: title, text: text, kind: kind, collectionID: board)
            refresh()
            notify("Saved to snippets", symbol: "text.badge.plus")
            library = .snippets
            selectedID = snippet.id
            selection = [snippet.id]
            loadPreview()
        } catch {
            notify("Couldn't save that snippet", symbol: "exclamationmark.circle")
        }
    }

    func beginEditingSnippet(_ snippet: Snippet? = nil) {
        let target = snippet ?? selectedSnippet()
        guard let target else { return }
        snippetBeingEdited = target
    }

    func saveEditedSnippet(id: UUID, title: String, text: String, abbreviation: String?) {
        do {
            let kind = ClipClassifier.classify(
                text: text,
                html: nil,
                hasRTF: false,
                hasImage: false,
                fileURLs: []
            )
            try store.updateSnippet(
                id: id,
                title: title,
                text: text,
                kind: kind,
                abbreviation: abbreviation
            )
            snippetBeingEdited = nil
            refresh()
            selectedID = id
            selection = [id]
            notify(
                SnippetAbbreviation.normalize(abbreviation) == nil
                    ? "Snippet updated"
                    : "Abbreviation ready",
                symbol: "textformat.abc"
            )
        } catch {
            let message = (error as? StoreError)?.description ?? "Couldn't update that snippet"
            notify(message, symbol: "exclamationmark.circle")
        }
    }

    func cancelSnippetEdit() {
        snippetBeingEdited = nil
    }

    func createCollection() {
        presentTextPrompt?(
            "New collection",
            "Snippets on this board stay when you clear history.",
            "",
            "Create"
        ) { [weak self] name in
            self?.addCollection(named: name)
        }
    }

    func renameCollection(_ id: UUID) {
        let current = collections.first { $0.id == id }?.name ?? ""
        presentTextPrompt?(
            "Rename collection",
            "The snippets on this board keep their place.",
            current,
            "Rename"
        ) { [weak self] name in
            self?.renameCollection(id, to: name)
        }
    }

    func addCollection(named name: String) {
        do {
            let collection = try store.addCollection(name: name)
            if library == .snippets, let selectedID {
                try store.setSnippetCollection(id: selectedID, collectionID: collection.id)
            }
            refresh()
            collectionFilter = .collection(collection.id)
            notify("Created \(collection.name)", symbol: "folder.badge.plus")
            relayoutQuickPanel?()
        } catch {
            notify("Couldn't create that collection", symbol: "exclamationmark.circle")
        }
    }

    func renameCollection(_ id: UUID, to name: String) {
        do {
            try store.renameCollection(id: id, name: name)
            refresh()
            notify("Renamed collection", symbol: "pencil")
        } catch {
            notify("Couldn't rename that collection", symbol: "exclamationmark.circle")
        }
    }

    func deleteCollection(_ id: UUID) {
        let name = collections.first { $0.id == id }?.name ?? "collection"
        do {
            try store.deleteCollection(id: id)
            if case .collection(let selected) = collectionFilter, selected == id {
                collectionFilter = .all
            }
            refresh()
            notify("Deleted \(name)", detail: "Snippets moved to Unfiled.", symbol: "folder")
            relayoutQuickPanel?()
        } catch {
            notify("Couldn't delete that collection", symbol: "exclamationmark.circle")
        }
    }

    func moveSnippet(_ id: UUID, to collectionID: UUID?) {
        do {
            try store.setSnippetCollection(id: id, collectionID: collectionID)
            refresh()
            if let collectionID, let name = collections.first(where: { $0.id == collectionID })?.name {
                notify("Moved to \(name)", symbol: "folder")
            } else {
                notify("Moved to Unfiled", symbol: "folder")
            }
        } catch {
            notify("Couldn't move that snippet", symbol: "exclamationmark.circle")
        }
    }

    func moveSelectedSnippet(to collectionID: UUID?) {
        guard library == .snippets, let id = selectedID else { return }
        moveSnippet(id, to: collectionID)
    }

    func reorderSelectedSnippet(by delta: Int) {
        guard library == .snippets, let id = selectedID else { return }
        reorderSnippet(id, by: delta)
    }

    func dropSnippet(_ draggedID: UUID, onto targetID: UUID) {
        guard draggedID != targetID,
              let dragged = snippets.first(where: { $0.id == draggedID }),
              let target = snippets.first(where: { $0.id == targetID }) else { return }
        do {
            if dragged.collectionID != target.collectionID {
                try store.setSnippetCollection(id: draggedID, collectionID: target.collectionID)
                refresh()
            }
            let peers = snippets
                .filter { $0.collectionID == target.collectionID }
                .sorted {
                    if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
                    if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                    return $0.createdAt > $1.createdAt
                }
                .map(\.id)
                .filter { $0 != draggedID }
            guard let targetIndex = peers.firstIndex(of: targetID) else { return }
            var ordered = peers
            ordered.insert(draggedID, at: targetIndex)
            try store.reorderSnippets(ids: ordered)
            refresh()
            selectOnly(draggedID)
        } catch {
            notify("Couldn't reorder that snippet", symbol: "exclamationmark.circle")
        }
    }

    private func reorderSnippet(_ id: UUID, by delta: Int) {
        guard let snippet = snippets.first(where: { $0.id == id }) else { return }
        let peers = snippets
            .filter { $0.collectionID == snippet.collectionID }
            .sorted {
                if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.createdAt > $1.createdAt
            }
        guard let index = peers.firstIndex(where: { $0.id == id }) else { return }
        let next = index + delta
        guard peers.indices.contains(next) else { return }
        var ordered = peers.map(\.id)
        ordered.swapAt(index, next)
        do {
            try store.reorderSnippets(ids: ordered)
            refresh()
            select(id)
        } catch {
            notify("Couldn't reorder that snippet", symbol: "exclamationmark.circle")
        }
    }

    private func matchesCollectionFilter(_ snippet: Snippet) -> Bool {
        switch collectionFilter {
        case .all: true
        case .unfiled: snippet.collectionID == nil
        case .collection(let id): snippet.collectionID == id
        }
    }

    private func sortedSnippets(_ items: [Snippet]) -> [Snippet] {
        items.sorted {
            if $0.pinned != $1.pinned { return $0.pinned && !$1.pinned }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt > $1.createdAt
        }
    }

    func finishFirstRun() {
        preferences.hasSeenFirstRun = true
        showPermission = false
        focusToken += 1
    }

    func notify(_ title: String, detail: String? = nil, symbol: String = "checkmark.circle.fill", offersUndo: Bool = false) {
        let notice = Notice(title: title, detail: detail, symbol: symbol, offersUndo: offersUndo)
        self.notice = notice
        noticeTask?.cancel()
        noticeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(offersUndo ? 6 : 2.2))
            guard !Task.isCancelled, self.notice?.id == notice.id else { return }
            self.notice = nil
            if offersUndo, let pending = self.undo {
                let hashes = Set(pending.clips.map(\.contentHash))
                try? self.store.reapImages(hashes: hashes)
                self.undo = nil
            }
        }
    }

    func refreshAccessibilityTrust() {
        guard AccessibilityClient.isTrusted(prompt: false) else { return }
        showPermission = false
    }

    func expireTransientState() {
        let before = menuBarState
        if let undo, Date() >= undo.deadline {
            let hashes = Set(undo.clips.map(\.contentHash))
            try? store.reapImages(hashes: hashes)
            self.undo = nil
        }
        if let until = preferences.pauseUntil, Date() >= until {
            preferences.pauseUntil = nil
        }
        if let until = preferences.frontAppPauseUntil, Date() >= until {
            preferences.frontAppPauseUntil = nil
            preferences.frontAppPauseBundleID = nil
            preferences.frontAppPauseName = nil
        }
        enforceStorageRules()
        if before != menuBarState {
            onChromeChange?()
        }
    }

    func shortcutIndex(for clip: Clip) -> Int? {
        guard let index = flattenedHistory.firstIndex(where: { $0.id == clip.id }), index < 9 else { return nil }
        return index + 1
    }

    func shortcutIndex(for snippet: Snippet) -> Int? {
        guard query.isEmpty, let index = orderedSnippets.firstIndex(where: { $0.id == snippet.id }), index < 9 else {
            return nil
        }
        return index + 1
    }

    func selectedHistoryClip() -> Clip? {
        flattenedHistory.first { $0.id == selectedID }
    }

    func selectedSnippet() -> Snippet? {
        visibleSnippets.first { $0.id == selectedID }
    }

    private func selectedClip() -> Clip? {
        if library == .snippets, let snippet = selectedSnippet() {
            return Clip(
                id: snippet.id,
                createdAt: snippet.createdAt,
                pinned: false,
                sourceAppName: "Snippet",
                sourceBundleID: "",
                kind: snippet.kind,
                preview: snippet.preview,
                text: snippet.text,
                html: nil,
                rtf: nil,
                imageRelativePath: nil,
                thumbRelativePath: nil,
                fileURLs: [],
                colorHex: ColorValue.parse(snippet.text)?.hex,
                contentHash: snippet.id.uuidString,
                imageWidth: nil,
                imageHeight: nil,
                byteSize: snippet.text.utf8.count,
                copyCount: 1
            )
        }
        if let selectedID,
           let match = copiesByHash.values.joined().first(where: { $0.id == selectedID }) {
            return match
        }
        return selectedHistoryClip()
    }

    private func materialized(_ clip: Clip) -> Clip {
        if library == .snippets { return clip }
        return (try? store.payload(id: clip.id)) ?? clip
    }

    private func writeSelection(plain: Bool) -> Bool {
        guard let clip = selectedClip() else { return false }
        commitWrite(materialized(clip), plain: plain || clip.kind == .code)
        return true
    }

    private func commitWrite(_ clip: Clip, plain: Bool) {
        let image = PasteService.imageData(for: clip, store: store)
        PasteService.write(clip, plain: plain, imageData: image)
        notePasteboardWrite?()
    }

    private func loadPreview() {
        guard library == .history, let clip = selectedClip() else {
            preview = selectedClip()
            return
        }
        preview = materialized(clip)
    }

    private func containsSelection(_ id: UUID) -> Bool {
        if flattenedHistory.contains(where: { $0.id == id }) { return true }
        if visibleSnippets.contains(where: { $0.id == id }) { return true }
        return copiesByHash.values.joined().contains { $0.id == id }
    }

    private func stageUndo(clips: [Clip], snippets: [Snippet], message: String) {
        if let existing = undo {
            try? store.reapImages(hashes: Set(existing.clips.map(\.contentHash)))
        }
        undo = UndoState(clips: clips, snippets: snippets, message: message, deadline: Date().addingTimeInterval(6))
        notify(message, symbol: "trash", offersUndo: true)
    }

    private func appWorthExcluding() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return previousApp
    }

    private func retentionCutoff(days: Int) -> Date? {
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}
