import AppKit

@MainActor
final class PasteboardMonitor {
    private let model: AppModel
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?
    private var localPasteMonitor: Any?
    private var globalPasteMonitor: Any?

    init(model: AppModel) {
        self.model = model
        changeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        startPasteUseMonitors()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let localPasteMonitor {
            NSEvent.removeMonitor(localPasteMonitor)
            self.localPasteMonitor = nil
        }
        if let globalPasteMonitor {
            NSEvent.removeMonitor(globalPasteMonitor)
            self.globalPasteMonitor = nil
        }
    }

    /// Counts ⌘V of a clip Stow put on the clipboard (Return then paste in another app).
    private func startPasteUseMonitors() {
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command),
                  !flags.contains(.option),
                  !flags.contains(.control),
                  event.keyCode == KeyCode.v else { return }
            self.model.noteCommandVPaste()
        }
        localPasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return event
        }
        globalPasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handle)
    }

    func noteOwnWrite() {
        changeCount = pasteboard.changeCount
    }

    private func poll() {
        model.expireTransientState()
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount

        guard model.shouldCaptureNextCopy() else { return }

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if PasteboardPolicy.shouldIgnore(types: types, extraIgnored: model.extraIgnoredTypes) {
            return
        }

        let fromUniversalClipboard = PasteboardPolicy.isUniversalClipboard(types: types)
        if fromUniversalClipboard, !model.preferences.includeUniversalClipboard {
            return
        }

        let source = NSWorkspace.shared.frontmostApplication
        if !fromUniversalClipboard {
            if source?.bundleIdentifier == Bundle.main.bundleIdentifier {
                return
            }
            if let bundleID = source?.bundleIdentifier, model.isExcluded(bundleID) {
                return
            }
        }

        guard var draft = ClipIngest.makeDraft(from: pasteboard, source: source) else { return }
        if fromUniversalClipboard {
            draft.sourceAppName = "Universal Clipboard"
            draft.sourceBundleID = PasteboardPolicy.universalClipboardType
        }
        let secret = draft.text.flatMap { SecretDetector.detect(in: $0) }
        model.ingest(draft: draft, secret: secret)
    }
}
