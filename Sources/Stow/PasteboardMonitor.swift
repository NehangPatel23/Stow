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

        let source = NSWorkspace.shared.frontmostApplication
        if source?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        if let bundleID = source?.bundleIdentifier, model.isExcluded(bundleID) {
            return
        }

        guard let draft = ClipIngest.makeDraft(from: pasteboard, source: source) else { return }
        let secret = draft.text.flatMap { SecretDetector.detect(in: $0) }
        model.ingest(draft: draft, secret: secret)
    }
}
