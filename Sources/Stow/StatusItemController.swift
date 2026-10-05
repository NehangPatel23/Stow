import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var lastState: MenuBarState?

    /// Opens the library window ("More clips…").
    var onOpenLibrary: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let recentLimit = 8

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        statusItem.menu = menu
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let recent = Array(model.history.prefix(recentLimit))
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No recent clips", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for (index, clip) in recent.enumerated() {
                menu.addItem(clipItem(clip, index: index))
            }
        }

        menu.addItem(item("More clips…", action: #selector(openLibrary)))
        menu.addItem(.separator())

        let filledSlots = model.slots.filter { !$0.isEmpty }
        if !filledSlots.isEmpty {
            for slot in filledSlots {
                menu.addItem(slotItem(slot))
            }
            menu.addItem(.separator())
        }

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

        let clear = NSMenuItem(title: "Clear", action: #selector(clearUnpinned), keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!))
        clear.keyEquivalentModifierMask = [.command, .option]
        clear.target = self
        menu.addItem(clear)

        let preferences = NSMenuItem(title: "Preferences…", action: #selector(settings), keyEquivalent: ",")
        preferences.keyEquivalentModifierMask = .command
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(item("About", action: #selector(about)))

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        quit.target = self
        menu.addItem(quit)
    }

    private func clipItem(_ clip: Clip, index: Int) -> NSMenuItem {
        let title = menuTitle(for: clip)
        let key = index < 9 ? "\(index + 1)" : ""
        let item = NSMenuItem(title: title, action: #selector(pasteClip(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = clip.id.uuidString
        item.image = menuImage(for: clip)
        item.toolTip = "\(clip.kind.title) · \(clip.sourceAppName)"
        return item
    }

    private func slotItem(_ slot: ClipSlot) -> NSMenuItem {
        let item = NSMenuItem(title: slot.menuTitle, action: #selector(pasteSlot(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = slot.index
        item.toolTip = "\(slot.hotkeyLabel) · paste \(slot.name)"
        if let payload = slot.payload {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            item.image = NSImage(
                systemSymbolName: payload.kind.symbolName,
                accessibilityDescription: payload.kind.title
            )?.withSymbolConfiguration(config)
        }
        return item
    }

    private func menuTitle(for clip: Clip) -> String {
        let line = ClipText.previewLine(from: clip.preview, limit: 72)
        if line.isEmpty {
            return clip.kind.title
        }
        return line
    }

    private func menuImage(for clip: Clip) -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        if clip.kind == .image, let path = clip.thumbRelativePath {
            let url = model.store.url(forRelativePath: path)
            if let image = NSImage(contentsOf: url) {
                return resized(image, to: size)
            }
        }
        if clip.kind == .color, let hex = clip.colorHex, let value = ColorValue.parse(hex) {
            let swatch = NSImage(size: size, flipped: false) { rect in
                NSColor(calibratedRed: value.red, green: value.green, blue: value.blue, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
                return true
            }
            return swatch
        }
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        return NSImage(systemSymbolName: clip.kind.symbolName, accessibilityDescription: clip.kind.title)?
            .withSymbolConfiguration(config)
    }

    private func resized(_ image: NSImage, to size: NSSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
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

    @objc private func pasteClip(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = UUID(uuidString: raw) else { return }
        model.pasteMenuClip(id: id)
    }

    @objc private func pasteSlot(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        model.pasteSlot(index)
    }

    @objc private func openLibrary() { onOpenLibrary?() }
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
    @objc private func settings() { onSettings?() }
    @objc private func about() { onAbout?() }
    @objc private func quit() { onQuit?() }
}
