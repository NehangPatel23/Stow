import AppKit
import SwiftUI

struct PreviewPaneView: View {
    var model: AppModel
    var theme: Theme

    var body: some View {
        Group {
            if model.library == .snippets, let snippet = model.selectedSnippet() {
                snippetPreview(snippet)
            } else if let clip = model.preview {
                clipPreview(clip)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.and.text.magnifyingglass")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.chip))
                    Text("Select a clip")
                        .font(.system(size: 16, weight: .semibold))
                    Text("The full text, image, or color shows here.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func clipPreview(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(clip.kind.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary)
                Spacer()
                Text("\(clip.sourceAppName) · \(clip.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
            }
            transformRow(text: clip.text ?? clip.preview, html: clip.html)
            switch clip.kind {
            case .image:
                imagePreview(clip)
            case .file:
                filePreview(clip)
            case .color:
                colorPreview(clip)
            case .code:
                codePreview(clip.text ?? "")
            case .richText:
                if let rtf = clip.rtf {
                    RichTextPreview(rtf: rtf)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    textPreview(clip.text ?? clip.preview, kind: .richText, title: nil)
                }
            default:
                textPreview(clip.text ?? clip.preview, kind: clip.kind, title: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func imagePreview(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let path = clip.imageRelativePath {
                ThumbView(url: model.store.url(forRelativePath: path))
                    .frame(maxWidth: .infinity, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onDrag {
                        ClipDrag.provider(for: clip, store: model.store) ?? NSItemProvider()
                    }
                    .help("Drag into Finder, Mail, or a browser")
            }
            Text(imageCaption(clip))
                .font(.system(size: 12))
                .foregroundStyle(theme.secondary)
            if let ocr = clip.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines), !ocr.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Text in image")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondary)
                    Text(ocr)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.card))
            }
        }
    }

    private func imageCaption(_ clip: Clip) -> String {
        var parts: [String] = []
        if let width = clip.imageWidth, let height = clip.imageHeight {
            parts.append("\(width) × \(height)")
        }
        parts.append(ByteFormat.string(for: clip.byteSize))
        return parts.joined(separator: " · ")
    }

    private func filePreview(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if clip.fileURLs.isEmpty {
                Text(clip.preview)
            } else {
                ForEach(clip.fileURLs, id: \.self) { path in
                    HStack {
                        Image(systemName: "doc")
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Text("Drag")
                            .foregroundStyle(theme.secondary)
                    }
                    .font(.system(size: 13))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.card))
                    .onDrag { ClipDrag.provider(forFilePath: path) ?? NSItemProvider() }
                }
            }
        }
    }

    private func colorPreview(_ clip: Clip) -> some View {
        let parsed = clip.text.flatMap { ColorValue.parse($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            ?? clip.colorHex.flatMap(ColorValue.parse)
        return VStack(alignment: .leading, spacing: 12) {
            if let parsed {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: parsed.red, green: parsed.green, blue: parsed.blue))
                    .frame(height: 120)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.separator))
                HStack(spacing: 8) {
                    colorButton("Hex", parsed.hex)
                    colorButton("RGB", parsed.rgbString())
                    colorButton("HSL", parsed.hslString())
                }
            }
            if let text = clip.text {
                Text(text)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func colorButton(_ title: String, _ value: String) -> some View {
        Button {
            model.copyColorFormat(value)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(theme.secondary)
                Text(value).lineLimit(1)
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(theme.card))
        }
        .buttonStyle(.plain)
        .help("Copy \(value)")
    }

    private func codePreview(_ source: String) -> some View {
        ScrollView {
            Text(highlightedCode(source))
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func highlightedCode(_ source: String) -> AttributedString {
        let limited = source.count > 50_000 ? String(source.prefix(50_000)) : source
        var result = AttributedString()
        for run in SyntaxHighlighter.runs(for: limited) {
            var piece = AttributedString(run.text)
            piece.foregroundColor = color(for: run.kind)
            result += piece
        }
        return result
    }

    private func color(for kind: SyntaxTokenKind) -> Color {
        switch kind {
        case .plain: return Color.primary
        case .keyword: return Color(red: 0.78, green: 0.45, blue: 0.28)
        case .string: return Color(red: 0.35, green: 0.55, blue: 0.38)
        case .comment: return theme.secondary
        case .number: return Color(red: 0.62, green: 0.48, blue: 0.22)
        }
    }

    private func snippetPreview(_ snippet: Snippet) -> some View {
        let fields = snippet.templateFields
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snippet.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Edit") {
                        model.beginEditingSnippet(snippet)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if let abbr = snippet.normalizedAbbreviation {
                    Text("Abbreviation \(abbr) · type it, then space or return")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                transformRow(text: snippet.text, html: nil)
                if !fields.isEmpty {
                    Text("Fill-in fields: \(fields.map(\.label).joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondary)
                    Button("Fill and Paste") {
                        model.pasteSelected(plain: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Text(snippet.text.isEmpty ? "Empty snippet" : snippet.text)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func textPreview(_ text: String, kind: ClipKind, title: String?) -> some View {
        let fields = SnippetTemplate.fields(in: text)
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    transformRow(text: text, html: nil)
                }
                if !fields.isEmpty {
                    Text("Fill-in fields: \(fields.map(\.label).joined(separator: ", "))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondary)
                    Button("Fill and Paste") {
                        model.pasteSelected(plain: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Text(text.isEmpty ? "Empty clip" : text)
                    .font(.system(size: 13, design: kind == .link || kind == .email ? .default : .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func transformRow(text: String, html: String?) -> some View {
        let actions = ClipTransform.available(text: text, html: html)
        if !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(actions) { transform in
                        Button {
                            model.copyTransform(transform, text: text, html: html)
                        } label: {
                            Label(transform.title, systemImage: transform.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(theme.chip))
                        }
                        .buttonStyle(.plain)
                        .help("Copy \(transform.title). The saved clip stays as it is.")
                    }
                }
            }
        }
    }
}

struct RichTextPreview: NSViewRepresentable {
    var rtf: Data

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Self.surface
        scroll.borderType = .noBorder
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = true
        text.backgroundColor = Self.surface
        text.textColor = .labelColor
        text.textContainerInset = NSSize(width: 12, height: 12)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.heightTracksTextView = false
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let width = max(scroll.contentSize.width, 1)
        text.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        text.frame.size.width = width
        let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) ?? NSAttributedString(string: "")
        let readable = Self.readable(attributed)
        if text.textStorage?.string != readable.string || text.textStorage?.length != readable.length {
            text.textStorage?.setAttributedString(readable)
        }
    }

    private static let surface = NSColor(srgbRed: 0.16, green: 0.145, blue: 0.133, alpha: 1)

    private static func readable(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let full = NSRange(location: 0, length: result.length)
        guard full.length > 0 else { return result }
        result.enumerateAttribute(.foregroundColor, in: full) { value, range, _ in
            let color = (value as? NSColor)?.usingColorSpace(.sRGB)
            let tooDark = color.map { 0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent < 0.55 } ?? true
            if tooDark {
                result.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        return result
    }
}
