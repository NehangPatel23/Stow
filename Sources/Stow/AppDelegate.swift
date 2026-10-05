import AppKit
import Carbon

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var monitor: PasteboardMonitor?
    private var hotkeys: HotkeyController?
    private var abbreviations: AbbreviationExpander?
    private var status: StatusItemController?
    private var panel: PanelController?
    private var launch: LaunchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        let store: HistoryStore
        do {
            store = try HistoryStore(directory: Self.supportDirectory())
        } catch {
            let alert = NSAlert()
            alert.messageText = "Stow couldn't open its history."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let model = AppModel(store: store)
        let monitor = PasteboardMonitor(model: model)
        let hotkeys = HotkeyController()
        let abbreviations = AbbreviationExpander()
        let status = StatusItemController(model: model)
        let panel = PanelController(model: model)

        model.notePasteboardWrite = { [weak monitor] in
            monitor?.noteOwnWrite()
        }
        abbreviations.noteOwnWrite = { [weak monitor] in
            monitor?.noteOwnWrite()
        }
        abbreviations.expansions = { [weak model] in
            model?.abbreviationExpansions ?? [:]
        }
        abbreviations.shouldExpand = { [weak model] in
            guard let model else { return false }
            guard model.canExpandAbbreviations else { return false }
            if NSApp.isActive { return false }
            if let front = NSWorkspace.shared.frontmostApplication,
               front.bundleIdentifier == Bundle.main.bundleIdentifier {
                return false
            }
            if let front = NSWorkspace.shared.frontmostApplication {
                return !FocusedField.isSecureTextField(pid: front.processIdentifier)
            }
            return true
        }
        model.onChromeChange = { [weak status] in
            status?.refresh()
        }
        model.onHotkeyChange = { [weak self] in
            self?.registerHotkey()
        }
        hotkeys.onPress = { [weak panel] in
            panel?.toggle()
        }
        status.onOpenLibrary = { [weak panel] in
            panel?.focusLibrary()
        }
        status.onSettings = { [weak panel] in
            panel?.showSettings()
        }
        status.onAbout = { [weak self] in
            self?.showAbout()
        }
        status.onQuit = {
            NSApp.terminate(nil)
        }

        let launch = LaunchController(model: model)
        // Stay menu-bar first after launch; the library opens from "More clips…".
        launch.onFinished = nil

        self.model = model
        self.monitor = monitor
        self.hotkeys = hotkeys
        self.abbreviations = abbreviations
        self.status = status
        self.panel = panel
        self.launch = launch

        registerHotkey()
        monitor.start()
        abbreviations.start()
        model.notePreviousApp(NSWorkspace.shared.frontmostApplication)
        launch.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(libraryChangedFromIntent(_:)),
            name: StowIntentSupport.libraryDidChangeNotification,
            object: nil
        )
    }

    @objc private func frontAppChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        model?.notePreviousApp(app)
    }

    @objc private func libraryChangedFromIntent(_ notification: Notification) {
        model?.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.showLibrary()
        return true
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        panel?.showSettings()
    }

    @objc private func showAboutFromMenu(_ sender: Any?) {
        showAbout()
    }

    private func showAbout() {
        AboutWindowController.shared.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.refreshAccessibilityTrust()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys?.unregister()
        abbreviations?.stop()
        monitor?.stop()
    }

    private func registerHotkey() {
        guard let model, let hotkeys else { return }
        let fallbackControlOptionCommand = UInt32(cmdKey | optionKey | controlKey)
        let candidates: [(UInt32, UInt32, String)] = [
            (model.preferences.hotkeyKeyCode, model.preferences.hotkeyCarbonModifiers, model.preferences.hotkeyLabel),
            (UInt32(KeyCode.c), UInt32(cmdKey | shiftKey), "⌘⇧C"),
            (UInt32(KeyCode.v), UInt32(cmdKey | shiftKey), "⌘⇧V"),
            (UInt32(KeyCode.v), fallbackControlOptionCommand, "⌃⌥⌘V"),
        ]
        var seen = Set<String>()
        for candidate in candidates {
            let key = "\(candidate.0)-\(candidate.1)"
            guard seen.insert(key).inserted else { continue }
            if hotkeys.register(keyCode: candidate.0, modifiers: candidate.1) {
                model.activeHotkeyLabel = candidate.2
                if candidate.0 != model.preferences.hotkeyKeyCode || candidate.1 != model.preferences.hotkeyCarbonModifiers {
                    model.banner = "\(model.preferences.hotkeyLabel) is already in use. This launch opens with \(candidate.2)."
                }
                status?.refresh()
                return
            }
        }
        model.banner = "Stow couldn't register a shortcut. Change it in Settings."
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        let about = appMenu.addItem(withTitle: "About Stow", action: #selector(showAboutFromMenu(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Stow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private static func supportDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return root.appendingPathComponent("Stow", isDirectory: true)
    }
}

@MainActor
@main
enum StowMain {
    static func main() {
        if CommandLine.arguments.contains("--smoke") {
            do {
                try SmokeCheck.run()
                fputs("stow smoke ok\n", stdout)
                fflush(stdout)
                exit(0)
            } catch {
                fputs("stow smoke failed: \(error)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

enum SmokeCheck {
    static func run() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowSmoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HistoryStore(directory: directory)
        let draft = ClipDraft(
            sourceAppName: "Smoke",
            sourceBundleID: "smoke.test",
            kind: .text,
            preview: "hello",
            text: "hello",
            html: nil,
            rtf: nil,
            imagePNG: nil,
            thumbnailPNG: nil,
            fileURLs: [],
            colorHex: nil,
            contentHash: ContentHash.text("hello"),
            imageWidth: nil,
            imageHeight: nil,
            byteSize: 5,
            createdAt: Date(),
            ocrText: nil
        )
        _ = try store.record(draft)
        let folded = try store.foldedHistory()
        guard folded.count == 1, folded[0].preview == "hello" else {
            throw StoreError.sqlite("Smoke check read back the wrong history.")
        }
        _ = try store.addSnippet(title: "Hi", text: "hello", kind: .text)
        _ = try store.clearHistory(includingPinned: true)
        guard try store.snippets().count == 1 else {
            throw StoreError.sqlite("Clearing history removed a snippet.")
        }
        let concealed: Set<String> = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]
        guard PasteboardPolicy.shouldIgnore(types: concealed) else {
            throw StoreError.sqlite("A concealed pasteboard type was not ignored.")
        }
    }
}
