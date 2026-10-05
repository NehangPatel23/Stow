import AppKit
import SwiftUI

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: KeyPanel
    private let library: NSWindow
    private var keyMonitor: Any?
    private var placedLibrary = false
    private var ignorePanelResignUntil = Date.distantPast

    init(model: AppModel) {
        self.model = model
        panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.quickWidth, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        library = NSWindow(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.librarySize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configureQuickPanel()
        configureLibrary()

        model.closePanel = { [weak self] returnFocus in
            self?.closeQuick(returnFocus: returnFocus)
        }
        model.openSettings = { [weak self] in
            self?.showSettings()
        }
        model.relayoutQuickPanel = { [weak self] in
            self?.resizeQuick(animated: true)
        }
        model.stepAside = { [weak self] app, keepOpen in
            self?.stepAside(for: app, keepOpen: keepOpen)
        }
        model.restorePanelAfterPaste = { [weak self] in
            self?.restoreAfterPaste()
        }
        model.presentJoinPrompt = { [weak self] in
            self?.presentJoinPrompt()
        }
        model.presentTextPrompt = { [weak self] title, message, defaultValue, confirmTitle, onConfirm in
            self?.presentTextPrompt(
                title: title,
                message: message,
                defaultValue: defaultValue,
                confirmTitle: confirmTitle,
                onConfirm: onConfirm
            )
        }
    }

    func showLibrary() {
        if !placedLibrary {
            if !library.setFrameUsingName("StowLibraryStage") {
                library.setFrame(Self.stageFrame(), display: false)
            }
            library.setFrameAutosaveName("StowLibraryStage")
            placedLibrary = true
        }
        let fadingIn = !library.isVisible
        if fadingIn {
            library.alphaValue = 0
        }
        NSApp.activate()
        library.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        guard fadingIn else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            library.animator().alphaValue = 1
        }
    }

    /// Matches the large Stage Manager window: the screen minus the menu bar and Dock.
    private static func stageFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return NSRect(origin: .zero, size: PanelMetrics.librarySize)
        }
        return screen.visibleFrame.insetBy(dx: 12, dy: 10)
    }

    /// Menu bar click should surface the window already on screen, not a second one.
    func focusLibrary() {
        if panel.isVisible {
            closeQuick(returnFocus: false)
        }
        showLibrary()
    }

    func stepAside(for app: NSRunningApplication, keepOpen: Bool) {
        if keepOpen {
            panel.makeFirstResponder(nil)
            library.makeFirstResponder(nil)
            if library.isKeyWindow {
                library.orderBack(nil)
            }
        } else {
            panel.orderOut(nil)
            library.makeFirstResponder(nil)
            library.orderBack(nil)
        }
        NSApp.yieldActivation(to: app)
        app.unhide()
        app.activate(from: .current)
    }

    func restoreAfterPaste() {
        guard model.preferences.keepPanelOpen else { return }
        ignorePanelResignUntil = Date().addingTimeInterval(0.6)
        NSApp.activate()
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
        } else if library.isVisible {
            library.makeKeyAndOrderFront(nil)
        } else {
            openQuick()
        }
    }

    func toggle() {
        if panel.isVisible {
            closeQuick(returnFocus: true)
        } else {
            openQuick()
        }
    }

    func openQuick() {
        ignorePanelResignUntil = Date().addingTimeInterval(0.45)
        model.notePreviousApp(NSWorkspace.shared.frontmostApplication)
        model.prepareForOpen()
        resizeQuick(animated: false)
        positionUnderCursor()
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
    }

    func closeQuick(returnFocus: Bool) {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        if library.isVisible == false {
            removeKeyMonitor()
        }
        guard wasVisible, returnFocus, let app = model.previousApp else { return }
        app.activate(options: [])
    }

    func presentJoinPrompt() {
        presentTextPrompt(
            title: "Join with",
            message: "The selected clips are pasted in the order you copied them, separated by what you type.",
            defaultValue: model.joinSeparator,
            confirmTitle: "Paste",
            placeholder: "Separator"
        ) { [weak self] value in
            self?.model.joinSeparator = value
            self?.model.pasteSelection(separator: value)
        }
    }

    func presentTextPrompt(
        title: String,
        message: String,
        defaultValue: String,
        confirmTitle: String,
        placeholder: String = "Name",
        onConfirm: @escaping @MainActor (String) -> Void
    ) {
        let window = NSApp.keyWindow ?? (library.isVisible ? library : panel)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: defaultValue)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                onConfirm(field.stringValue)
            }
        }
        DispatchQueue.main.async {
            field.currentEditor()?.selectAll(nil)
        }
    }

    func showSettings() {
        closeQuick(returnFocus: false)
        model.showsSettings = true
        showLibrary()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === panel {
            closeQuick(returnFocus: true)
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === library else { return }
        if panel.isVisible == false {
            removeKeyMonitor()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        guard panel.isVisible, !NSApp.isActive, Date() > ignorePanelResignUntil else { return }
        if model.preferences.keepPanelOpen { return }
        closeQuick(returnFocus: false)
    }

    private func configureQuickPanel() {
        panel.title = "Stow"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentMinSize = NSSize(width: 680, height: 300)
        panel.contentMaxSize = NSSize(width: PanelMetrics.quickWidth, height: 640)
        panel.delegate = self
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = host(for: PanelRootView(model: model, surface: .quickPick))
    }

    private func configureLibrary() {
        library.title = "Stow"
        library.titleVisibility = .hidden
        library.titlebarAppearsTransparent = true
        library.titlebarSeparatorStyle = .none
        library.isMovableByWindowBackground = true
        library.isReleasedWhenClosed = false
        library.minSize = NSSize(width: 820, height: 520)
        library.delegate = self
        library.backgroundColor = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if dark {
                return NSColor(srgbRed: 0.11, green: 0.098, blue: 0.09, alpha: 1)
            }
            return NSColor(srgbRed: 0.965, green: 0.953, blue: 0.933, alpha: 1)
        }
        library.contentView = host(for: PanelRootView(model: model, surface: .library))
    }

    private func host(for root: PanelRootView) -> NSView {
        let host = NSHostingView(rootView: root.environment(model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        return host
    }

    private func resizeQuick(animated: Bool) {
        guard let screen = screenForPanel() else { return }
        let size = PanelMetrics.quickSize(for: model, screenHeight: screen.visibleFrame.height)
        var frame = panel.frame
        let heightDelta = size.height - frame.height
        frame.size = size
        if panel.isVisible {
            frame.origin.y -= heightDelta
        }
        frame = clamped(frame, on: screen)
        if animated && panel.isVisible {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: panel.isVisible)
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                let quick = event.window === self.panel
                let library = event.window === self.library
                guard quick || library else { return false }
                return self.handle(event, quick: quick)
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handle(_ event: NSEvent, quick: Bool) -> Bool {
        if !quick, model.showsSettings { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.keyCode
        let command = flags.contains(.command)
        let option = flags.contains(.option)
        let shift = flags.contains(.shift)

        if key == KeyCode.escape {
            if quick {
                closeQuick(returnFocus: true)
            } else if !model.query.isEmpty {
                model.query = ""
            }
            return true
        }
        if key == KeyCode.up {
            if command && option {
                model.reorderSelectedSnippet(by: -1)
            } else {
                model.moveSelection(-1)
            }
            return true
        }
        if key == KeyCode.down {
            if command && option {
                model.reorderSelectedSnippet(by: 1)
            } else {
                model.moveSelection(1)
            }
            return true
        }
        if key == KeyCode.return || key == KeyCode.enter {
            if option && shift {
                model.pasteSelected(plain: true)
            } else if option {
                model.pasteSelected(plain: false)
            } else {
                model.copySelected()
            }
            return true
        }
        if command && key == KeyCode.p {
            model.togglePin()
            return true
        }
        if command && key == KeyCode.s {
            model.saveSnippetFromSelection()
            return true
        }
        if command && key == KeyCode.z {
            model.performUndo()
            return true
        }
        if key == KeyCode.delete || key == KeyCode.forwardDelete {
            if command || model.query.isEmpty {
                model.deleteSelected()
                return true
            }
            return false
        }
        if model.query.isEmpty, let number = KeyCode.digits[key], flags.isDisjoint(with: [.command, .control]) {
            model.selectShortcut(number)
            if option && shift {
                model.pasteSelected(plain: true)
            } else if option {
                model.pasteSelected(plain: false)
            } else {
                model.copySelected()
            }
            return true
        }
        return false
    }

    private func positionUnderCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }
        var frame = panel.frame
        frame.origin.x = mouse.x - frame.width / 2
        frame.origin.y = mouse.y - frame.height - 12
        panel.setFrame(clamped(frame, on: screen), display: false)
    }

    private func screenForPanel() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? panel.screen ?? NSScreen.main
    }

    private func clamped(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        var frame = frame
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        return frame
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
