import AppKit
import SwiftUI

struct PanelRootView: View {
    @Bindable var model: AppModel
    var surface: StowSurface = .library
    @Environment(\.colorScheme) private var scheme
    @FocusState private var searchFocused: Bool

    var body: some View {
        let theme = Theme(scheme: scheme)
        Group {
            if surface == .library, model.showsSettings {
                SettingsPage(model: model)
            } else {
                libraryContent(theme)
            }
        }
        .animation(.snappy(duration: 0.22), value: model.notice?.id)
        .sheet(item: $model.clipBeingEdited) { clip in
            ClipEditorView(clip: clip) { attributed in
                model.saveEditedClip(clip, attributed: attributed)
            } onCancel: {
                model.clipBeingEdited = nil
            }
        }
        .sheet(item: $model.snippetBeingEdited) { snippet in
            SnippetEditorView(
                snippet: snippet,
                theme: theme,
                onSave: { title, text, abbreviation in
                    model.saveEditedSnippet(
                        id: snippet.id,
                        title: title,
                        text: text,
                        abbreviation: abbreviation
                    )
                },
                onCancel: { model.cancelSnippetEdit() }
            )
        }
        .sheet(item: $model.templateFill) { request in
            TemplateFillView(
                request: request,
                theme: theme,
                onPaste: { model.completeTemplateFill($0) },
                onCancel: { model.cancelTemplateFill() }
            )
        }
        .sheet(item: $model.archiveExportPicker) { picker in
            ArchiveExportPickerView(
                clips: picker.clips,
                theme: theme,
                onExport: { excluded in
                    model.confirmArchiveExportPicker(excludedContentHashes: excluded)
                },
                onCancel: { model.cancelArchiveExportPicker() }
            )
        }
    }

    @ViewBuilder
    private func toastOverlay(_ theme: Theme) -> some View {
            if let notice = model.notice {
                ToastBanner(notice: notice, theme: theme) {
                    model.performUndo()
                }
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
    }

    private func libraryContent(_ theme: Theme) -> some View {
        VStack(spacing: 0) {
            header(theme)
            HStack(spacing: 0) {
                listColumn(theme)
                    .frame(width: surface == .quickPick ? 320 : 360)
                    .frame(maxHeight: surface == .library ? .infinity : PanelMetrics.quickBand(for: model))
                Rectangle().fill(theme.separator).frame(width: 1)
                PreviewPaneView(model: model, theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: surface == .library ? .infinity : PanelMetrics.quickBand(for: model))
            }
            .overlay(alignment: .top) { toastOverlay(theme) }
            footer(theme)
        }
        .frame(width: surface == .quickPick ? PanelMetrics.quickWidth : nil, alignment: .top)
        .frame(maxWidth: surface == .library ? .infinity : nil, maxHeight: surface == .library ? .infinity : nil, alignment: .top)
        .background(theme.background)
        .environment(model)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _, _ in searchFocused = true }
        .onChange(of: model.query) { _, _ in
            model.reconcileSelection()
            relayout()
        }
        .onChange(of: model.chipKind) { _, _ in
            model.reconcileSelection()
            relayout()
        }
        .onChange(of: model.chipPinned) { _, _ in
            model.reconcileSelection()
            relayout()
        }
        .onChange(of: model.chipFrequent) { _, _ in
            model.reconcileSelection()
            relayout()
        }
        .onChange(of: model.library) { _, _ in
            model.reconcileSelection()
            relayout()
        }
        .onChange(of: model.selectedID) { _, _ in relayout() }
        .onChange(of: model.banner) { _, _ in relayout() }
        .onChange(of: model.undo) { _, _ in relayout() }
        .onChange(of: model.showPermission) { _, _ in relayout() }
        .onChange(of: model.preferences.showShortcutFooter) { _, _ in relayout() }
        .animation(.snappy(duration: 0.22), value: model.selectedID)
        .animation(.snappy(duration: 0.22), value: model.library)
    }

    private func relayout() {
        guard surface == .quickPick else { return }
        model.relayoutQuickPanel?()
    }

    private func header(_ theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AppIconMark(size: surface == .library ? 48 : 32)
                Text("Stow")
                    .font(.system(size: surface == .library ? 20 : 15, weight: .semibold))
                Text(model.activeHotkeyLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(theme.chipActive))
                Spacer()
                Picker("Library", selection: $model.library) {
                    ForEach(Library.allCases) { library in
                        Text(library.title).tag(library)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                Button {
                    model.preferences.keepPanelOpen.toggle()
                } label: {
                    Image(systemName: model.preferences.keepPanelOpen ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.preferences.keepPanelOpen ? theme.accent : theme.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(model.preferences.keepPanelOpen ? theme.chipActive : theme.chip))
                }
                .buttonStyle(.plain)
                .help(model.preferences.keepPanelOpen ? "Panel stays open while pasting" : "Keep panel open while pasting")
                panelMenu(theme)
            }
            .padding(.leading, surface == .quickPick ? 54 : 0)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondary)
                TextField(
                    model.library == .snippets
                        ? "Search snippets, or board:Support"
                        : "Search, or type:image, app:Safari, from:today",
                    text: $model.query
                )
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.separator, lineWidth: 1)
            )
            chips(theme)
            if model.library == .snippets {
                collectionChips(theme)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, surface == .library ? 8 : 16)
        .padding(.bottom, 12)
    }

    private func panelMenu(_ theme: Theme) -> some View {
        Menu {
            Button(model.isPaused ? "Resume recording" : "Pause recording") { model.togglePause() }
            Button("Pause for an hour") { model.pauseForOneHour() }
            Button("Ignore next copy") { model.ignoreNextCopy() }
            if let skipped = model.skipped {
                Button("Keep skipped \(skipped.reason.title)") { model.keepSkipped() }
                Button("Discard skipped copy") { model.discardSkipped() }
            }
            Divider()
            Button("Clear unpinned history") { model.clearHistory(includingPinned: false) }
            Button("Clear everything") { model.clearHistory(includingPinned: true) }
            Divider()
            Button("Settings…") { model.openSettings?() }
            Button("Quit Stow") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(theme.chip))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28)
        .help("Pause, clear, settings")
    }

    private func chips(_ theme: Theme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(
                    "All",
                    symbol: "square.grid.2x2",
                    active: model.chipKind == nil && !model.chipPinned && !model.chipFrequent,
                    theme: theme
                ) {
                    model.chipKind = nil
                    model.chipPinned = false
                    model.chipFrequent = false
                }
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    chip(kind.title, symbol: kind.symbolName, active: model.chipKind == kind, theme: theme) {
                        model.chipKind = model.chipKind == kind ? nil : kind
                    }
                }
                chip("Pinned", symbol: "pin", active: model.chipPinned, theme: theme) {
                    model.chipPinned.toggle()
                }
                chip("Frequent", symbol: "chart.bar", active: model.chipFrequent, theme: theme) {
                    model.chipFrequent.toggle()
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func collectionChips(_ theme: Theme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All boards", symbol: "square.stack", active: model.collectionFilter == .all, theme: theme) {
                    model.collectionFilter = .all
                }
                chip("Unfiled", symbol: "tray", active: model.collectionFilter == .unfiled, theme: theme) {
                    model.collectionFilter = .unfiled
                }
                ForEach(model.collections) { collection in
                    chip(
                        collection.name,
                        symbol: "folder",
                        active: model.collectionFilter == .collection(collection.id),
                        theme: theme
                    ) {
                        model.collectionFilter = .collection(collection.id)
                    }
                    .contextMenu {
                        Button("Rename…") { model.renameCollection(collection.id) }
                        Button("Delete Board", role: .destructive) { model.deleteCollection(collection.id) }
                    }
                }
                chip("New", symbol: "plus", active: false, theme: theme) {
                    model.createCollection()
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func chip(_ title: String, symbol: String, active: Bool, theme: Theme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(active ? theme.accent : theme.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(active ? theme.chipActive : theme.chip))
        }
        .buttonStyle(.plain)
    }

    private func listColumn(_ theme: Theme) -> some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                Text(banner)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if model.library == .history {
                            historyList(theme)
                        } else {
                            snippetList(theme)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func historyList(_ theme: Theme) -> some View {
        if model.flattenedHistory.isEmpty {
            emptyState(
                title: model.history.isEmpty ? "Nothing copied yet" : "No matches",
                detail: model.history.isEmpty ? "Copies land here as you work." : "Try a different word or filter.",
                symbol: model.history.isEmpty ? "clipboard" : "magnifyingglass",
                theme: theme
            )
        } else {
            ForEach(model.historySections) { section in
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                ForEach(section.clips) { clip in
                    ClipRowView(clip: clip, theme: theme)
                        .id(clip.id)
                }
            }
        }
    }

    @ViewBuilder
    private func snippetList(_ theme: Theme) -> some View {
        if model.visibleSnippets.isEmpty {
            emptyState(
                title: model.snippets.isEmpty ? "No snippets yet" : "No matches",
                detail: model.snippets.isEmpty
                    ? "Save a clip with ⌘S. Put it on a board when you want it grouped."
                    : "Try a different word or board.",
                symbol: "text.badge.plus",
                theme: theme
            )
        } else {
            ForEach(model.snippetSections) { section in
                Text(section.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                ForEach(section.snippets) { snippet in
                    SnippetRowView(snippet: snippet, theme: theme)
                        .id(snippet.id)
                }
            }
        }
    }

    private func emptyState(title: String, detail: String, symbol: String, theme: Theme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.chip))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func footer(_ theme: Theme) -> some View {
        VStack(spacing: 8) {
            if model.preferences.showShortcutFooter {
                HStack(spacing: 12) {
                    footerKey("⌥↩", "Paste", theme)
                    footerKey("⇧⌥↩", "Plain", theme)
                    footerKey("⌘⌥↩", "Once", theme)
                    footerKey("↩", "Copy", theme)
                    footerKey("⌘P", "Pin", theme)
                    footerKey("⌘⌫", "Delete", theme)
                    Spacer()
                    Button {
                        model.preferences.showShortcutFooter = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Hide shortcut footer")
                }
            } else {
                HStack {
                    Spacer()
                    Button("Show shortcuts") { model.preferences.showShortcutFooter = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.card.opacity(0.55))
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1) }
    }

    private func footerKey(_ shortcut: String, _ name: String, _ theme: Theme) -> some View {
        HStack(spacing: 5) {
            Text(shortcut)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(theme.keycap))
            Text(name)
                .font(.system(size: 11))
        }
        .foregroundStyle(theme.secondary)
    }
}
