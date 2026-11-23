import AppKit
import SwiftUI

/// Floating, non-activating chip near the current text selection.
@MainActor
final class SelectionChipController {
    private let model: AppModel
    private let panelIsChromeVisible: () -> Bool

    private var panel: NonActivatingPanel?
    private var host: NSHostingView<SelectionChipView>?
    private var timer: Timer?
    private var debouncer = SelectionChipPolicy.Debouncer()
    private var shownText: String?
    private var suppressedText: String?
    private var lastBounds: CGRect?

    private let pollInterval: TimeInterval = 0.28
    private let chipSize = NSSize(width: 320, height: 40)

    init(model: AppModel, panelIsChromeVisible: @escaping () -> Bool) {
        self.model = model
        self.panelIsChromeVisible = panelIsChromeVisible
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        hide()
        debouncer.reset()
        suppressedText = nil
    }

    private func tick() {
        let enabled = model.preferences.selectionChipEnabled
        let trusted = AccessibilityClient.isTrusted(prompt: false)
        guard SelectionChipPolicy.shouldMonitor(enabled: enabled, accessibilityTrusted: trusted) else {
            hide()
            debouncer.reset()
            return
        }

        let front = NSWorkspace.shared.frontmostApplication
        let frontBundle = front?.bundleIdentifier
        let stowBundle = Bundle.main.bundleIdentifier
        let stowIsFrontmost = frontBundle == stowBundle || NSApp.isActive
        let stowChrome = panelIsChromeVisible()

        var selectedText: String?
        var isSecure = false
        var bounds: CGRect?
        if let front, !stowIsFrontmost {
            if let result = FocusedSelection.read(pid: front.processIdentifier) {
                isSecure = result.isSecure
                selectedText = result.text.isEmpty ? nil : result.text
                bounds = result.bounds
            }
        }

        let excluded = Set(model.preferences.excludedApps.map(\.bundleID))
        let gate = SelectionChipPolicy.GateInput(
            enabled: enabled,
            accessibilityTrusted: trusted,
            stowIsFrontmost: stowIsFrontmost,
            stowWindowIsKey: stowChrome,
            isSecureField: isSecure,
            isPaused: model.isPaused,
            excludedBundleIDs: excluded,
            frontBundleID: frontBundle,
            selectedText: selectedText
        )
        var candidate = SelectionChipPolicy.shouldShow(for: gate)
        if candidate == suppressedText {
            candidate = nil
        } else if candidate != nil {
            suppressedText = nil
        }
        let now = Date()
        let toShow = debouncer.tick(normalized: candidate, now: now)

        if let bounds {
            lastBounds = bounds
        }

        guard let toShow else {
            hide()
            return
        }
        show(text: toShow, bounds: lastBounds)
    }

    private func show(text: String, bounds: CGRect?) {
        shownText = text
        let preview = ClipText.previewLine(from: text, limit: 28)
        let view = SelectionChipView(
            preview: preview,
            onCopy: { [weak self] in
                guard let self, let shown = self.shownText else { return }
                self.model.copyPlainTextFromSelectionChip(shown)
            },
            onSaveSnippet: { [weak self] in
                guard let self, let shown = self.shownText else { return }
                self.model.saveSnippetFromSelectionChip(shown)
            },
            onDismiss: { [weak self] in
                self?.userDismiss()
            }
        )

        if panel == nil {
            let panel = NonActivatingPanel(
                contentRect: NSRect(origin: .zero, size: chipSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.ignoresMouseEvents = false
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: chipSize)
            panel.contentView = host
            self.panel = panel
            self.host = host
        } else {
            host?.rootView = view
        }

        position(near: bounds)
        panel?.orderFront(nil)
    }

    private func position(near bounds: CGRect?) {
        guard let panel else { return }
        var frame = panel.frame
        frame.size = chipSize

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? bounds.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } }
            ?? NSScreen.main

        if let bounds, bounds.width > 1, bounds.height > 1 {
            frame.origin.x = bounds.midX - frame.width / 2
            frame.origin.y = bounds.minY - frame.height - 8
        } else {
            frame.origin.x = mouse.x - frame.width / 2
            frame.origin.y = mouse.y - frame.height - 16
        }

        if let screen {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
            if frame.minY < visible.minY {
                if let bounds, bounds.width > 1 {
                    frame.origin.y = bounds.maxY + 8
                } else {
                    frame.origin.y = visible.minY
                }
            }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        }
        panel.setFrame(frame, display: true)
    }

    private func userDismiss() {
        suppressedText = shownText
        hide()
        debouncer.reset()
        lastBounds = nil
    }

    private func hide() {
        panel?.orderOut(nil)
        shownText = nil
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
