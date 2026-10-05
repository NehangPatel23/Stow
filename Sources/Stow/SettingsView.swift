import AppKit
import SwiftUI

struct SettingsPage: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = Theme(scheme: scheme)
        ZStack {
            settingsAtmosphere(theme)
            VStack(spacing: 0) {
                settingsChrome(theme)
                SettingsView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                ToastBanner(notice: notice, theme: theme) {
                    model.performUndo()
                }
                .padding(.top, 64)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.notice?.id)
    }

    private func settingsChrome(_ theme: Theme) -> some View {
        HStack(spacing: 12) {
            Button {
                model.showsSettings = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(theme.chip))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                Text("Shortcut, storage, privacy, and how the window behaves.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            AppIconMark(size: 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func settingsAtmosphere(_ theme: Theme) -> some View {
        ZStack {
            theme.background
            RadialGradient(
                colors: [
                    theme.accent.opacity(scheme == .dark ? 0.10 : 0.08),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            LinearGradient(
                colors: [
                    theme.pin.opacity(scheme == .dark ? 0.08 : 0.05),
                    .clear,
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var ignoredType = ""
    @State private var recording = false
    @FocusState private var ignoredFocused: Bool

    private var densityBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.compactRows },
            set: { model.preferences.compactRows = $0 }
        )
    }

    var body: some View {
        let theme = Theme(scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                shortcutSection(theme)
                windowSection(theme)
                abbreviationsSection(theme)
                storageSection(theme)
                privacySection(theme)
                pasteboardSection(theme)
                accessSection(theme)
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
            .padding(.bottom, 40)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(ClearScrollBackground())
        }
        .scrollContentBackground(.hidden)
        .background(ShortcutRecorder(isRecording: $recording) { event in
            apply(event)
        })
        .onDisappear { HotkeyController.passThrough = false }
    }

    private func shortcutSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Shortcut",
            detail: "Open Stow from anywhere. Escape cancels while recording.",
            symbol: "command",
            theme: theme
        ) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open Stow")
                        .font(.system(size: 13, weight: .medium))
                    Text(recording ? "Waiting for keys…" : "Global hotkey")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
                Button {
                    recording.toggle()
                } label: {
                    HStack(spacing: 8) {
                        if recording {
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 7, height: 7)
                        }
                        Text(recording ? "Press keys" : model.preferences.hotkeyLabel)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(recording ? theme.accent : theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(recording ? theme.chipActive : theme.keycap)
                    )
                    .overlay(
                        Capsule().strokeBorder(theme.separator)
                    )
                }
                .buttonStyle(.plain)
                .animation(.snappy(duration: 0.2), value: recording)
                .help("Click, then press a shortcut with Control, Option, or Command")
            }
        }
    }

    private func windowSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Window",
            detail: "How the list and panel feel while you work.",
            symbol: "macwindow",
            theme: theme
        ) {
            VStack(spacing: 0) {
                settingsToggle(
                    title: "Shortcut footer",
                    detail: "Show Paste, Plain, Copy, Pin, and Delete at the bottom.",
                    isOn: Binding(
                        get: { model.preferences.showShortcutFooter },
                        set: { model.preferences.showShortcutFooter = $0 }
                    ),
                    theme: theme
                )
                settingsDivider(theme)
                settingsToggle(
                    title: "Keep open while pasting",
                    detail: "Leave Stow up so you can paste several clips in a row.",
                    isOn: Binding(
                        get: { model.preferences.keepPanelOpen },
                        set: { model.preferences.keepPanelOpen = $0 }
                    ),
                    theme: theme
                )
                settingsDivider(theme)
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Row density")
                            .font(.system(size: 13, weight: .medium))
                        Text("Comfortable leaves more air. Compact fits more clips.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Picker("Row density", selection: densityBinding) {
                        Text("Comfortable").tag(false)
                        Text("Compact").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func abbreviationsSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Abbreviations",
            detail: "Only snippets you mark with an abbreviation expand. Everything else stays inert.",
            symbol: "textformat.abc",
            theme: theme
        ) {
            settingsToggle(
                title: "Expand while typing",
                detail: model.abbreviationExpansions.isEmpty
                    ? "Mark a snippet with Edit Snippet…, then type that abbreviation and space or return."
                    : "\(model.abbreviationExpansions.count) marked. Skips secure fields and Stow itself.",
                isOn: Binding(
                    get: { model.preferences.abbreviationExpansionEnabled },
                    set: { model.preferences.abbreviationExpansionEnabled = $0 }
                ),
                theme: theme
            )
        }
    }

    private func storageSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Storage",
            detail: "History uses the Mac’s data protection. Text and images can expire on their own schedules.",
            symbol: "internaldrive",
            theme: theme
        ) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("On this Mac")
                            .font(.system(size: 13, weight: .medium))
                        Text("Database, images, and thumbnails in Application Support.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Text(ByteFormat.string(for: model.storageByteCount))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(theme.chipActive))
                }
                .padding(.vertical, 12)

                settingsDivider(theme)

                retentionPicker(
                    title: "Text retention",
                    detail: "Unpinned text, links, code, and files older than this are removed.",
                    selection: Binding(
                        get: { model.preferences.textRetentionDays },
                        set: { model.preferences.textRetentionDays = $0 }
                    ),
                    theme: theme
                )

                settingsDivider(theme)

                retentionPicker(
                    title: "Image retention",
                    detail: "Unpinned screenshots and images older than this are removed.",
                    selection: Binding(
                        get: { model.preferences.imageRetentionDays },
                        set: { model.preferences.imageRetentionDays = $0 }
                    ),
                    theme: theme
                )

                settingsDivider(theme)

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Trim storage")
                            .font(.system(size: 13, weight: .medium))
                        Text("Drop expired clips, remove leftover image files, and compact the database. Pins and snippets stay.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button {
                        model.trimStorage()
                    } label: {
                        Text("Trim now")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(theme.chip))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)

                settingsDivider(theme)

                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Local archive")
                            .font(.system(size: 13, weight: .medium))
                        Text("Export all or leave clips out. Import can add new items only, or replace everything.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Button {
                            model.exportArchive()
                        } label: {
                            Text("Export…")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(theme.chip))
                        }
                        .buttonStyle(.plain)
                        Button {
                            model.importArchive()
                        } label: {
                            Text("Import…")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(theme.chip))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func retentionPicker(
        title: String,
        detail: String,
        selection: Binding<Int>,
        theme: Theme
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Picker(title, selection: selection) {
                ForEach(RetentionOption.allCases) { option in
                    Text(option.title).tag(option.days)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 160)
        }
        .padding(.vertical, 12)
    }

    private func privacySection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Never record",
            detail: "Apps on this list never write to history.",
            symbol: "eye.slash",
            theme: theme
        ) {
            if model.preferences.excludedApps.isEmpty {
                emptyHint("No apps excluded yet.", theme: theme)
            } else {
                VStack(spacing: 10) {
                    ForEach(model.preferences.excludedApps) { app in
                        HStack(spacing: 12) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.chip))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(app.bundleID)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(theme.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                model.removeExcludedApp(app)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(theme.secondary)
                                    .frame(width: 26, height: 26)
                                    .background(Circle().fill(theme.chip))
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(app.name)")
                        }
                        .padding(12)
                        .background(theme.chip.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }

            HStack(spacing: 10) {
                settingsAction("Exclude last app", symbol: "minus.circle", theme: theme) {
                    model.excludeCurrentApp()
                }
                settingsAction("Pause last app 1h", symbol: "pause.circle", theme: theme) {
                    model.pauseFrontAppForOneHour()
                }
            }
            .padding(.top, 8)
        }
    }

    private func pasteboardSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Ignored pasteboard types",
            detail: "Concealed, transient, and password-manager types are always ignored.",
            symbol: "rectangle.on.rectangle.slash",
            theme: theme
        ) {
            if model.preferences.extraIgnoredPasteboardTypes.isEmpty {
                emptyHint("No extra types yet.", theme: theme)
            } else {
                FlowWrap(spacing: 6) {
                    ForEach(model.preferences.extraIgnoredPasteboardTypes, id: \.self) { type in
                        HStack(spacing: 6) {
                            Text(type)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Button {
                                model.removeIgnoredType(type)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(theme.chipActive))
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                TextField("com.example.custom-type", text: $ignoredType)
                    .textFieldStyle(.plain)
                    .focused($ignoredFocused)
                    .onSubmit(addIgnoredType)
                Button("Add") {
                    addIgnoredType()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(ignoredType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(theme.chip, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ignoredFocused ? theme.accent.opacity(0.35) : theme.separator)
            )
            .padding(.top, 8)
        }
    }

    private func accessSection(_ theme: Theme) -> some View {
        settingsSection(
            title: "Accessibility",
            detail: "Needed so Option-Return can paste into the previous app.",
            symbol: "hand.raised",
            theme: theme
        ) {
            Button {
                AccessibilityClient.openSettings()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.chipActive))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Accessibility Settings")
                            .font(.system(size: 13, weight: .medium))
                        Text("System Settings → Privacy & Security")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                }
                .padding(4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        detail: String,
        symbol: String,
        theme: Theme,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.chipActive))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.separator)
            )
            .shadow(color: theme.shadow.opacity(0.45), radius: 14, y: 6)
        }
    }

    private func settingsToggle(title: String, detail: String, isOn: Binding<Bool>, theme: Theme) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 12)
    }

    private func settingsDivider(_ theme: Theme) -> some View {
        Rectangle()
            .fill(theme.separator)
            .frame(height: 1)
    }

    private func settingsAction(_ title: String, symbol: String, theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(theme.chip, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func emptyHint(_ text: String, theme: Theme) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func addIgnoredType() {
        model.addIgnoredType(ignoredType)
        ignoredType = ""
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

struct ArchiveExportPickerView: View {
    var clips: [Clip]
    var theme: Theme
    var onExport: (Set<String>) -> Void
    var onCancel: () -> Void

    @State private var excludedContentHashes: Set<String> = []

    private var includedCount: Int {
        clips.count - excludedContentHashes.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose clips to export")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Uncheck a clip to leave it out. Snippets and boards still export.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
            }
            .padding(14)

            HStack(spacing: 10) {
                Button("Include all") { excludedContentHashes = [] }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(excludedContentHashes.isEmpty)
                Button("Exclude all") {
                    excludedContentHashes = Set(clips.map(\.contentHash))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(excludedContentHashes.count == clips.count)
                Spacer()
                Text("\(includedCount) of \(clips.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            List {
                ForEach(clips) { clip in
                    Toggle(isOn: binding(for: clip.contentHash)) {
                        HStack(spacing: 10) {
                            Image(systemName: clip.kind.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.accent)
                                .frame(width: 24, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.chip))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.preview.isEmpty ? clip.kind.title : clip.preview)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Text("\(clip.sourceAppName) · \(clip.kind.title)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    onExport(excludedContentHashes)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 480, height: 520)
    }

    private func binding(for contentHash: String) -> Binding<Bool> {
        Binding(
            get: { !excludedContentHashes.contains(contentHash) },
            set: { included in
                if included {
                    excludedContentHashes.remove(contentHash)
                } else {
                    excludedContentHashes.insert(contentHash)
                }
            }
        )
    }
}

private enum RetentionOption: Int, CaseIterable, Identifiable {
    case forever = 0
    case oneDay = 1
    case oneWeek = 7
    case twoWeeks = 14
    case oneMonth = 30
    case threeMonths = 90
    case oneYear = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .forever: "Forever"
        case .oneDay: "1 day"
        case .oneWeek: "7 days"
        case .twoWeeks: "14 days"
        case .oneMonth: "30 days"
        case .threeMonths: "90 days"
        case .oneYear: "1 year"
        }
    }
}

/// Simple wrapping layout for ignored-type chips.
private struct FlowWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            width = max(width, x + size.width)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
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
