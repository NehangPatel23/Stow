import AppKit
import Foundation

struct UndoState: Equatable {
    var clips: [Clip]
    var snippets: [Snippet]
    var message: String
    var deadline: Date
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
            preferences.save()
            if hotkeyChanged {
                onHotkeyChange?()
            }
            onChromeChange?()
        }
    }

    var library: Library = .history
    var query = ""
    var chipKind: ClipKind?
    var chipPinned = false
    private(set) var history: [Clip] = []
    private(set) var snippets: [Snippet] = []
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
    var joinSeparator = ", "
    var focusToken = 0
    var activeHotkeyLabel: String
    var previousApp: NSRunningApplication?

    var closePanel: (@MainActor (Bool) -> Void)?
    var openSettings: (@MainActor () -> Void)?
    var presentJoinPrompt: (@MainActor () -> Void)?
    var relayoutQuickPanel: (@MainActor () -> Void)?
    var stepAside: (@MainActor (NSRunningApplication) -> Void)?
    var onHotkeyChange: (@MainActor () -> Void)?
    var onChromeChange: (@MainActor () -> Void)?
    var notePasteboardWrite: (@MainActor () -> Void)?
    var notice: Notice?
    private var noticeTask: Task<Void, Never>?

    init(store: HistoryStore) {
        self.store = store
        let loaded = Preferences.load()
        preferences = loaded
        activeHotkeyLabel = loaded.hotkeyLabel
        refresh()
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
        let parsed = SearchQuery.parse(query).merging(kind: chipKind, pinned: chipPinned)
        return snippets.filter { parsed.matches($0) }
    }

    var snippetSections: [SnippetSection] {
        let now = Date()
        let pinned = visibleSnippets.filter(\.pinned).sorted { $0.createdAt > $1.createdAt }
        let rest = visibleSnippets.filter { !$0.pinned }
        var sections: [SnippetSection] = []
        if !pinned.isEmpty {
            sections.append(SnippetSection(id: "pinned", title: "Pinned", snippets: pinned))
        }
        for bucket in TimeBucket.allCases {
            let items = rest
                .filter { TimeBucket.bucket(for: $0.createdAt, now: now) == bucket }
                .sorted { $0.createdAt > $1.createdAt }
            if !items.isEmpty {
                sections.append(SnippetSection(id: bucket.rawValue, title: bucket.title, snippets: items))
            }
        }
        return sections
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
        closePanel?(false)
        guard let target = previousApp else {
            notify("Copied", detail: "Switch to an app, then paste.", symbol: "doc.on.doc")
            return
        }
        stepAside?(target)
        notify(message, symbol: "arrow.down.doc")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                self.stepAside?(target)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    PasteService.sendCommandV()
                }
            } else {
                PasteService.sendCommandV()
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
        closePanel?(true)
    }

    func pasteSelected(plain requestedPlain: Bool) {
        guard let clip = selectedClip() else {
            notify("Select a clip", symbol: "arrow.down.doc")
            return
        }
        let full = materialized(clip)
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
        do {
            let snippet = try store.addSnippet(title: title, text: text, kind: kind)
            refresh()
            notify("Saved to snippets", symbol: "text.badge.plus")
            library = .snippets
            selectedID = snippet.id
            loadPreview()
        } catch {
            notify("Couldn't save that snippet", symbol: "exclamationmark.circle")
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
}
