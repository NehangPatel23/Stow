import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipRowView: View {
    var clip: Clip
    var theme: Theme
    @Environment(AppModel.self) private var model

    private var isSelected: Bool { model.selection.contains(clip.id) }
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                typeMark
                VStack(alignment: .leading, spacing: 2) {
                    highlighted(rowTitle)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(clip.sourceAppName)
                        Text("·")
                        Text(timeLabel(clip.createdAt))
                        if clip.copyCount > 1 {
                            Text("·")
                            Button {
                                model.toggleExpanded(clip.contentHash)
                            } label: {
                                HStack(spacing: 3) {
                                    Text(expanded ? "Hide" : "\(clip.copyCount) copies")
                                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    if let index = model.shortcutIndex(for: clip), model.query.isEmpty {
                        Text("\(index)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.secondary)
                    }
                    if clip.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.pin)
                    }
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(olderCopies) { copy in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(copy.sourceAppName)
                                    .lineLimit(1)
                                Text(timeLabel(copy.createdAt))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            Spacer(minLength: 8)
                            Button {
                                model.deleteCopy(id: copy.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(theme.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                            .help("Delete this copy")
                        }
                        .padding(.vertical, 5)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.leading, 34)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, model.preferences.compactRows ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.highlight : (hovered ? theme.chip.opacity(0.85) : Color.clear))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, model.preferences.compactRows ? 5 : 8)
                    .padding(.leading, 3)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) {
            model.selectOnly(clip.id)
            model.pasteSelected(plain: false)
        }
        .onTapGesture { model.click(clip.id) }
        .onDrag {
            ClipDrag.provider(for: clip, store: model.store) ?? NSItemProvider(object: clip.preview as NSString)
        }
        .contextMenu { clipMenu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.kind.title), \(rowTitle), \(clip.sourceAppName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var clipMenu: some View {
        Group {
            Button("Paste") {
                model.select(clip.id)
                model.pasteSelected(plain: false)
            }
            Button("Paste Plain") {
                model.select(clip.id)
                model.pasteSelected(plain: true)
            }
            Button("Paste Once") {
                model.select(clip.id)
                model.pasteSelected(plain: false, oneShot: true)
            }
            Button("Paste Plain Once") {
                model.select(clip.id)
                model.pasteSelected(plain: true, oneShot: true)
            }
            Button("Copy") {
                model.select(clip.id)
                model.copySelected()
            }
            Button("Edit Clip") {
                model.beginEditing(clip)
            }
            Button(clip.pinned ? "Unpin" : "Pin") {
                model.select(clip.id)
                model.togglePin()
            }
            if !(clip.text ?? clip.preview).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Save as Snippet") {
                    model.select(clip.id)
                    model.saveSnippetFromSelection()
                }
            }
            if model.selection.count > 1, model.selection.contains(clip.id) {
                Divider()
                Button("Paste in order") { model.pasteSelection(separator: "\n") }
                Button("Join with comma") { model.pasteSelection(separator: ", ") }
                Button("Join with…") { model.askJoinSeparator() }
            }
            Divider()
            Button("Delete") {
                model.select(clip.id)
                model.deleteSelected()
            }
        }
    }

    private var expanded: Bool {
        clip.copyCount > 1 && model.expandedHashes.contains(clip.contentHash)
    }

    private var olderCopies: [Clip] {
        (model.copiesByHash[clip.contentHash] ?? []).filter { $0.id != clip.id }
    }

    /// When a search hits OCR inside an image, show that text instead of dimensions.
    private var rowTitle: String {
        guard clip.kind == .image,
              let ocr = clip.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !ocr.isEmpty,
              !model.effectiveQuery.terms.isEmpty else {
            return clip.preview
        }
        let haystack = ocr.lowercased()
        guard model.effectiveQuery.terms.allSatisfy({ haystack.contains($0.lowercased()) }) else {
            return clip.preview
        }
        return ClipText.previewLine(from: ocr)
    }

    private var typeMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chip)
                .frame(width: 26, height: 26)
            if clip.kind == .image, let path = clip.thumbRelativePath {
                ThumbView(url: model.store.url(forRelativePath: path))
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if clip.kind == .color, let hex = clip.colorHex, let color = ColorValue.parse(hex) {
                Circle()
                    .fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: clip.kind.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private func highlighted(_ text: String) -> Text {
        var attributed = AttributedString(text)
        for range in model.effectiveQuery.highlightRanges(in: text) {
            guard let start = AttributedString.Index(range.lowerBound, within: attributed),
                  let end = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[start..<end].backgroundColor = theme.pin.opacity(0.35)
        }
        return Text(attributed)
    }

    private func timeLabel(_ date: Date) -> String {
        let now = Date()
        let time = date.formatted(date: .omitted, time: .shortened)
        switch TimeBucket.bucket(for: date, now: now) {
        case .today: return time
        case .yesterday: return "Yesterday, \(time)"
        case .older: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }
}

struct SnippetRowView: View {
    var snippet: Snippet
    var theme: Theme
    @Environment(AppModel.self) private var model
    @State private var hovered = false

    private var isSelected: Bool { model.selection.contains(snippet.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: snippet.kind.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(theme.chip))
                VStack(alignment: .leading, spacing: 2) {
                    Text(snippet.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(snippetSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondary)
                }
                Spacer()
                if let abbr = snippet.normalizedAbbreviation {
                    Text(abbr)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .help("Abbreviation: \(abbr)")
                }
                if !snippet.templateFields.isEmpty {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                        .help("Fill-in template")
                }
                if snippet.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.pin)
                }
                if let index = model.shortcutIndex(for: snippet) {
                    Text("\(index)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, model.preferences.compactRows ? 5 : 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? theme.highlight : (hovered ? theme.chip.opacity(0.85) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovered = $0 }
        .onTapGesture { model.click(snippet.id) }
        .onTapGesture(count: 2) {
            model.selectOnly(snippet.id)
            model.pasteSelected(plain: false)
        }
        .contextMenu {
            Button("Paste") {
                model.selectOnly(snippet.id)
                model.pasteSelected(plain: false)
            }
            Button("Paste Once") {
                model.selectOnly(snippet.id)
                model.pasteSelected(plain: false, oneShot: true)
            }
            Button("Copy") {
                model.selectOnly(snippet.id)
                model.copySelected()
            }
            Button("Edit Snippet…") {
                model.selectOnly(snippet.id)
                model.beginEditingSnippet(snippet)
            }
            Menu("Move to Board") {
                Button("Unfiled") { model.moveSnippet(snippet.id, to: nil) }
                if !model.collections.isEmpty {
                    Divider()
                    ForEach(model.collections) { collection in
                        Button(collection.name) { model.moveSnippet(snippet.id, to: collection.id) }
                    }
                }
                Divider()
                Button("New Collection…") {
                    model.selectOnly(snippet.id)
                    model.createCollection()
                }
            }
            Button("Move Up") {
                model.selectOnly(snippet.id)
                model.reorderSelectedSnippet(by: -1)
            }
            Button("Move Down") {
                model.selectOnly(snippet.id)
                model.reorderSelectedSnippet(by: 1)
            }
            if model.selection.count > 1, model.selection.contains(snippet.id) {
                Divider()
                Button("Paste in order") { model.pasteSelection(separator: "\n") }
                Button("Join with comma") { model.pasteSelection(separator: ", ") }
                Button("Join with…") { model.askJoinSeparator() }
            }
            Divider()
            Button("Delete") {
                model.selectOnly(snippet.id)
                model.deleteSelected()
            }
        }
        .onDrag {
            NSItemProvider(object: snippet.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let value = object as? String, let dragged = UUID(uuidString: value) else { return }
                Task { @MainActor in
                    model.dropSnippet(dragged, onto: snippet.id)
                }
            }
            return true
        }
    }

    private var snippetSubtitle: String {
        let day: String = {
            switch TimeBucket.bucket(for: snippet.createdAt, now: Date()) {
            case .today: "Today"
            case .yesterday: "Yesterday"
            case .older: snippet.createdAt.formatted(date: .abbreviated, time: .omitted)
            }
        }()
        let time = snippet.createdAt.formatted(date: .omitted, time: .shortened)
        var parts: [String] = []
        if let abbr = snippet.normalizedAbbreviation {
            parts.append(abbr)
        }
        if let id = snippet.collectionID, let name = model.collections.first(where: { $0.id == id })?.name {
            parts.append(name)
        }
        parts.append(day)
        parts.append(time)
        return parts.joined(separator: " · ")
    }
}

struct SnippetEditorView: View {
    var snippet: Snippet
    var theme: Theme
    var onSave: (String, String, String?) -> Void
    var onCancel: () -> Void

    @State private var title: String
    @State private var text: String
    @State private var abbreviation: String
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case title, abbreviation, body
    }

    init(
        snippet: Snippet,
        theme: Theme,
        onSave: @escaping (String, String, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.snippet = snippet
        self.theme = theme
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: snippet.title)
        _text = State(initialValue: snippet.text)
        _abbreviation = State(initialValue: snippet.abbreviation ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Edit Snippet")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(14)

            VStack(alignment: .leading, spacing: 12) {
                labeledField("Title") {
                    TextField("Support reply", text: $title)
                        .textFieldStyle(.plain)
                        .focused($focused, equals: .title)
                        .padding(10)
                        .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                labeledField("Abbreviation") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("addr", text: $abbreviation)
                            .textFieldStyle(.plain)
                            .focused($focused, equals: .abbreviation)
                            .padding(10)
                            .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("Leave blank to keep expansion off. Type the abbreviation, then space or return.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                labeledField("Snippet") {
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .focused($focused, equals: .body)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 180)
                        .background(theme.chip, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.horizontal, 14)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(title, text, abbreviation)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 460)
        .onAppear { focused = .abbreviation }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondary)
            content()
        }
    }
}

struct ThumbView: View {
    var url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 10))
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _, _ in load() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        image = NSImage(data: data)
    }
}

private struct RightClickSelector: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

private final class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
        super.rightMouseDown(with: event)
    }
}

struct ClipEditorView: View {
    var clip: Clip
    var onSave: (NSAttributedString) -> Void
    var onCancel: () -> Void
    @StateObject private var editor = RichTextEditorState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Edit Clip")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Bold") { editor.toggleTrait(.boldFontMask) }
                Button("Italic") { editor.toggleTrait(.italicFontMask) }
                Button("Underline") { editor.toggleUnderline() }
            }
            .padding(12)
            RichTextEditor(state: editor, clip: clip)
                .frame(minWidth: 560, minHeight: 320)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { onSave(editor.attributedString()) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 640, height: 460)
    }
}

@MainActor
final class RichTextEditorState: ObservableObject {
    fileprivate weak var textView: NSTextView?

    func toggleTrait(_ trait: NSFontTraitMask) {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let font = (range.length > 0
            ? textView.textStorage?.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            : textView.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
        let manager = NSFontManager.shared
        let hasTrait = manager.traits(of: font).contains(trait)
        let updated = hasTrait
            ? manager.convert(font, toNotHaveTrait: trait)
            : manager.convert(font, toHaveTrait: trait)
        if range.length > 0 {
            textView.textStorage?.addAttribute(.font, value: updated, range: range)
        } else {
            var typing = textView.typingAttributes
            typing[.font] = updated
            textView.typingAttributes = typing
        }
    }

    func toggleUnderline() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        let range = textView.selectedRange()
        let current = (range.length > 0
            ? textView.textStorage?.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
            : textView.typingAttributes[.underlineStyle] as? Int) ?? 0
        let style = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        if range.length > 0 {
            textView.textStorage?.addAttribute(.underlineStyle, value: style, range: range)
        } else {
            var typing = textView.typingAttributes
            typing[.underlineStyle] = style
            textView.typingAttributes = typing
        }
    }

    func attributedString() -> NSAttributedString {
        textView?.attributedString() ?? NSAttributedString(string: "")
    }
}

private struct RichTextEditor: NSViewRepresentable {
    var state: RichTextEditorState
    var clip: Clip

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let text = NSTextView()
        text.isRichText = true
        text.importsGraphics = false
        text.isEditable = true
        text.isSelectable = true
        text.allowsUndo = true
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.font = .systemFont(ofSize: 13)
        if let rtf = clip.rtf, let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            text.textStorage?.setAttributedString(attributed)
        } else {
            text.string = clip.text ?? clip.preview
        }
        scroll.documentView = text
        state.textView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        state.textView = scroll.documentView as? NSTextView
    }
}
