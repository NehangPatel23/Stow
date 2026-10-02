import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var lastState: MenuBarState?

    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(click)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refresh()
    }

    func refresh() {
        let state = model.menuBarState
        if state != lastState {
            let icon = image(for: state)
            icon.isTemplate = false
            statusItem.button?.image = icon
            lastState = state
        }
        statusItem.button?.toolTip = tooltip(for: state)
        statusItem.button?.setAccessibilityLabel("Stow")
    }

    @objc private func click() {
        let event = NSApp.currentEvent
        let rightClick = event?.type == .rightMouseUp
        let controlClick = event?.modifierFlags.contains(.control) == true
        if rightClick || controlClick {
            showMenu()
        } else {
            onOpen?()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("Open Stow", action: #selector(openPanel)))
        menu.addItem(.separator())
        if model.isPaused {
            menu.addItem(item("Resume recording", action: #selector(togglePause)))
        } else {
            menu.addItem(item("Pause recording", action: #selector(togglePause)))
            menu.addItem(item("Pause for an hour", action: #selector(pauseHour)))
        }
        let frontName = model.preferences.frontAppPauseName ?? "front app"
        if model.frontAppPauseIsActive {
            menu.addItem(item("Resume \(frontName)", action: #selector(resumeFrontApp)))
        } else {
            menu.addItem(item("Pause front app for an hour", action: #selector(pauseFront)))
        }
        menu.addItem(item("Ignore next copy", action: #selector(ignoreNext)))
        if let skipped = model.skipped {
            menu.addItem(item("Keep skipped \(skipped.reason.title)", action: #selector(keepSkipped)))
            menu.addItem(item("Discard skipped copy", action: #selector(discardSkipped)))
        }
        if model.undo != nil {
            menu.addItem(item("Undo", action: #selector(undo)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Clear unpinned history", action: #selector(clearUnpinned)))
        menu.addItem(item("Clear everything", action: #selector(clearAll)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", action: #selector(settings)))
        menu.addItem(item("Quit Stow", action: #selector(quit), key: "⌘Q"))
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func item(_ title: String, action: Selector, key: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let key {
            item.keyEquivalent = ""
            // The menu is transient, so the label carries the shortcut instead of a live equivalent.
            item.title = "\(title)  \(key)"
        }
        return item
    }

    private func image(for state: MenuBarState) -> NSImage {
        let length: CGFloat = 18
        let canvas = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSApp.applicationIconImage.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: state == .paused ? 0.55 : 1
            )
            if let badge = Self.badgeColor(for: state) {
                let dot = NSRect(x: rect.maxX - 7, y: rect.minY, width: 7, height: 7)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
                badge.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        canvas.isTemplate = false
        return canvas
    }

    private static func badgeColor(for state: MenuBarState) -> NSColor? {
        switch state {
        case .ready:
            return nil
        case .paused:
            return NSColor(calibratedRed: 0.77, green: 0.52, blue: 0.24, alpha: 1)
        case .ignoringNext:
            return NSColor(calibratedRed: 0.33, green: 0.48, blue: 0.72, alpha: 1)
        case .skippedSecret:
            return NSColor(calibratedRed: 0.72, green: 0.32, blue: 0.28, alpha: 1)
        }
    }

    private func tooltip(for state: MenuBarState) -> String {
        switch state {
        case .ready:
            return "Stow — \(model.activeHotkeyLabel)"
        case .paused:
            if model.frontAppPauseIsActive, let name = model.preferences.frontAppPauseName {
                return "Stow is paused for \(name)"
            }
            return "Stow is paused"
        case .ignoringNext:
            return "Stow will ignore the next copy"
        case .skippedSecret:
            return "Stow skipped a secret"
        }
    }

    @objc private func openPanel() { onOpen?() }
    @objc private func togglePause() { model.togglePause() }
    @objc private func pauseHour() { model.pauseForOneHour() }
    @objc private func pauseFront() { model.pauseFrontAppForOneHour() }
    @objc private func resumeFrontApp() {
        model.preferences.frontAppPauseUntil = nil
        model.preferences.frontAppPauseBundleID = nil
        model.preferences.frontAppPauseName = nil
    }
    @objc private func ignoreNext() { model.ignoreNextCopy() }
    @objc private func keepSkipped() { model.keepSkipped() }
    @objc private func discardSkipped() { model.discardSkipped() }
    @objc private func undo() { model.performUndo() }
    @objc private func clearUnpinned() { model.clearHistory(includingPinned: false) }
    @objc private func clearAll() { model.clearHistory(includingPinned: true) }
    @objc private func settings() { onSettings?() }
    @objc private func quit() { onQuit?() }
}
