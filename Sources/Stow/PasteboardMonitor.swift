import AppKit

@MainActor
final class PasteboardMonitor {
    private let model: AppModel
    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?

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
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
