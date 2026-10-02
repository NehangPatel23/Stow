import AppKit
import SwiftUI

struct SettingsPage: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(scheme: scheme)
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button {
                        model.showsSettings = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
                Text("Settings")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 4)
            SettingsView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                ToastBanner(notice: notice, theme: theme) {
                    model.performUndo()
                }
                    .padding(.top, 48)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.notice?.id)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var ignoredType = ""
    @State private var recording = false

    var body: some View {
        let theme = Theme(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsSection("Shortcut", theme: theme) {
                    HStack {
                        Text("Open Stow")
                        Spacer()
                        Text(model.preferences.hotkeyLabel)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                    }
                    Button(recording ? "Press a shortcut…" : "Change shortcut") {
                        recording = true
                    }
                    .disabled(recording)
                    Text("Use at least one of Control, Option, or Command. Escape cancels.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                }
                settingsSection("Apps that are never recorded", theme: theme) {
                    if model.preferences.excludedApps.isEmpty {
                        Text("None yet.")
                            .foregroundStyle(theme.secondary)
                    } else {
                        ForEach(model.preferences.excludedApps) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                    Text(app.bundleID).font(.caption).foregroundStyle(theme.secondary)
                                }
                                Spacer()
                                Button("Remove") { model.removeExcludedApp(app) }
                            }
                        }
                    }
                    Button("Exclude the app you were just in") { model.excludeCurrentApp() }
                    Button("Pause that app for an hour") { model.pauseFrontAppForOneHour() }
                }
                settingsSection("Extra pasteboard types to ignore", theme: theme) {
                    Text("Concealed, transient, and password-manager types are always ignored.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondary)
                    ForEach(model.preferences.extraIgnoredPasteboardTypes, id: \.self) { type in
                        HStack {
                            Text(type).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Remove") { model.removeIgnoredType(type) }
                        }
                    }
                    HStack {
                        TextField("com.example.type", text: $ignoredType)
                            .textFieldStyle(.plain)
                        Button("Add") {
                            model.addIgnoredType(ignoredType)
                            ignoredType = ""
                        }
                        .disabled(ignoredType.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                settingsSection("Window", theme: theme) {
                    Toggle("Show shortcut footer", isOn: Binding(
                        get: { model.preferences.showShortcutFooter },
                        set: { model.preferences.showShortcutFooter = $0 }
                    ))
                    Button("Accessibility Settings…") { AccessibilityClient.openSettings() }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .leading)
            .background(ClearScrollBackground())
        }
        .scrollContentBackground(.hidden)
        .background(theme.background)
        .background(ShortcutRecorder(isRecording: $recording) { event in
            apply(event)
        })
        .onDisappear { HotkeyController.passThrough = false }
    }

    private func settingsSection<Content: View>(_ title: String, theme: Theme, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func apply(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { return }
        if event.keyCode == KeyCode.escape {
            recording = false
            return
        }
        let modifiers = HotkeyController.carbonModifiers(from: flags)
        let label = HotkeyController.label(
            keyCode: event.keyCode,
            flags: flags,
            characters: event.charactersIgnoringModifiers
        )
        var updated = model.preferences
        updated.hotkeyKeyCode = UInt32(event.keyCode)
        updated.hotkeyCarbonModifiers = modifiers
        updated.hotkeyLabel = label
        model.preferences = updated
        model.activeHotkeyLabel = label
        recording = false
    }
}

/// Stops the system scroll view from painting a lighter gray behind Settings.
private struct ClearScrollBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scroll = nsView.enclosingScrollView else { return }
            scroll.drawsBackground = false
            scroll.backgroundColor = .clear
            scroll.contentView.drawsBackground = false
        }
    }
}

/// Listens for one shortcut while Settings is recording.
private struct ShortcutRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onEvent: (NSEvent) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onEvent = onEvent
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.isRecording = isRecording
        view.onEvent = onEvent
        HotkeyController.passThrough = isRecording
    }
}

private final class RecorderView: NSView {
    var isRecording = false
    var onEvent: ((NSEvent) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        install()
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let shouldConsume = self.isRecording && event.window === self.window
            guard shouldConsume else { return event }
            if event.keyCode == KeyCode.escape {
                self.onEvent?(event)
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else {
                return event
            }
            self.onEvent?(event)
            return nil
        }
    }
}
