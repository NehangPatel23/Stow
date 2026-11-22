import Foundation

enum ClipText {
    static func previewLine(from text: String, limit: Int = 180) -> String {
        let collapsed = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    static func isBlank(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Character, word, and line counts for text shown in the preview pane.
enum TextLength {
    struct Stats: Equatable, Sendable {
        var characters: Int
        var words: Int
        var lines: Int
    }

    static func stats(for text: String) -> Stats {
        let characters = text.count
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .count
        let lines: Int
        if text.isEmpty {
            lines = 0
        } else {
            lines = ClipLineOps.normalizeNewlines(text)
                .components(separatedBy: "\n")
                .count
        }
        return Stats(characters: characters, words: words, lines: lines)
    }

    static func caption(for text: String) -> String {
        let value = stats(for: text)
        return [
            unit(value.characters, "character", "characters"),
            unit(value.words, "word", "words"),
            unit(value.lines, "line", "lines"),
        ].joined(separator: " · ")
    }

    private static func unit(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

/// Derived sum, currency, or unit conversion shown in the preview. Never rewrites the stored clip.
enum InlineResult: Equatable, Sendable {
    case sum(Double)
    case currency(Double, symbol: String)
    case conversion(Double, unit: String)

    static let maxScanLength = 200
    static let maxScanLines = 40

    var caption: String {
        switch self {
        case .sum(let value):
            return "= \(Self.formatNumber(value))"
        case .currency(let value, let symbol):
            return "= \(Self.formatCurrency(value, symbol: symbol))"
        case .conversion(let value, let unit):
            return "= \(Self.formatNumber(value)) \(unit)"
        }
    }

    static func detect(in text: String, kind: ClipKind? = nil) -> InlineResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let kind {
            switch kind {
            case .image, .file, .color, .code, .link, .email:
                return nil
            case .text, .richText:
                break
            }
        }

        guard trimmed.count <= maxScanLength else { return nil }
        let normalized = ClipLineOps.normalizeNewlines(trimmed)
        let lines = normalized.components(separatedBy: "\n")
        guard lines.count <= maxScanLines else { return nil }

        if let conversion = detectConversion(in: trimmed) {
            return conversion
        }
        if let currency = detectCurrency(in: trimmed) {
            return currency
        }
        if let column = detectColumnSum(in: lines) {
            return column
        }
        if let expression = detectExpression(in: trimmed) {
            return expression
        }
        return nil
    }

    // MARK: - Unit conversion

    private static func detectConversion(in text: String) -> InlineResult? {
        let pattern = #"^\s*(-?\d+(?:\.\d+)?)\s*([A-Za-z°]+)\s*(?:to|in|→|->|as)\s*([A-Za-z°]+)\s*$"#
        guard let match = firstMatch(pattern, in: text),
              match.numberOfRanges >= 4,
              let amount = Double(group(match, 1, in: text)),
              let fromRaw = optionalGroup(match, 2, in: text),
              let toRaw = optionalGroup(match, 3, in: text) else {
            return nil
        }
        let from = normalizeUnit(fromRaw)
        let to = normalizeUnit(toRaw)
        guard from != to, let value = convert(amount, from: from, to: to) else { return nil }
        return .conversion(value, unit: displayUnit(to))
    }

    private static func normalizeUnit(_ raw: String) -> String {
        let value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "°", with: "")
            .lowercased()
        switch value {
        case "f", "fahrenheit": return "f"
        case "c", "celsius": return "c"
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": return "km"
        case "mi", "mile", "miles": return "mi"
        case "m", "meter", "meters", "metre", "metres": return "m"
        case "ft", "foot", "feet": return "ft"
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres": return "cm"
        case "in", "inch", "inches", "\"": return "in"
        case "kg", "kilogram", "kilograms": return "kg"
        case "lb", "lbs", "pound", "pounds": return "lb"
        case "l", "liter", "liters", "litre", "litres": return "l"
        case "gal", "gallon", "gallons": return "gal"
        default: return value
        }
    }

    private static func displayUnit(_ unit: String) -> String {
        switch unit {
        case "f": return "°F"
        case "c": return "°C"
        case "km": return "km"
        case "mi": return "mi"
        case "m": return "m"
        case "ft": return "ft"
        case "cm": return "cm"
        case "in": return "in"
        case "kg": return "kg"
        case "lb": return "lb"
        case "l": return "L"
        case "gal": return "gal"
        default: return unit
        }
    }

    private static func convert(_ amount: Double, from: String, to: String) -> Double? {
        switch (from, to) {
        case ("f", "c"): return (amount - 32) * 5 / 9
        case ("c", "f"): return amount * 9 / 5 + 32
        case ("km", "mi"): return amount * 0.621_371_192
        case ("mi", "km"): return amount / 0.621_371_192
        case ("m", "ft"): return amount * 3.280_839_895
        case ("ft", "m"): return amount / 3.280_839_895
        case ("cm", "in"): return amount / 2.54
        case ("in", "cm"): return amount * 2.54
        case ("kg", "lb"): return amount * 2.204_622_622
        case ("lb", "kg"): return amount / 2.204_622_622
        case ("l", "gal"): return amount * 0.264_172_052
        case ("gal", "l"): return amount / 0.264_172_052
        default: return nil
        }
    }

    // MARK: - Currency

    private static func detectCurrency(in text: String) -> InlineResult? {
        let compact = text.replacingOccurrences(of: ",", with: "")
        let pattern = #"(\$|€|£|¥)\s*(-?\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(compact.startIndex..<compact.endIndex, in: compact)
        let matches = regex.matches(in: compact, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        // The whole clip should be currency amounts and light arithmetic, not prose.
        let remainder = regex.stringByReplacingMatches(
            in: compact,
            options: [],
            range: range,
            withTemplate: ""
        )
        let leftover = remainder.replacingOccurrences(
            of: #"[+\-*/()\s]"#,
            with: "",
            options: .regularExpression
        )
        guard leftover.isEmpty else { return nil }

        var symbol: String?
        var total = 0.0
        var count = 0
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let nextSymbol = optionalGroup(match, 1, in: compact),
                  let amount = Double(group(match, 2, in: compact)) else {
                return nil
            }
            if let symbol, symbol != nextSymbol {
                return nil
            }
            symbol = nextSymbol
            total += amount
            count += 1
        }
        guard let symbol, count >= 1 else { return nil }
        return .currency(total, symbol: symbol)
    }

    // MARK: - Column sum

    private static func detectColumnSum(in lines: [String]) -> InlineResult? {
        let numbers = lines.compactMap { line -> Double? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return parsePlainNumber(trimmed)
        }
        guard numbers.count >= 2, numbers.count == lines.filter({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count else {
            return nil
        }
        return .sum(numbers.reduce(0, +))
    }

    // MARK: - Arithmetic expression

    private static func detectExpression(in text: String) -> InlineResult? {
        guard !text.contains("\n"), text.count >= 3 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789+-*/().% \t")
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard text.contains(where: { "+-*/%".contains($0) }) else { return nil }

        let compact = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\t", with: "")
        // Need at least two numbers joined by an operator: 2+2, not a lone "-3".
        let numberPattern = #"-?\d+(?:\.\d+)?"#
        guard let numberRegex = try? NSRegularExpression(pattern: numberPattern) else { return nil }
        let range = NSRange(compact.startIndex..<compact.endIndex, in: compact)
        let numberCount = numberRegex.numberOfMatches(in: compact, options: [], range: range)
        guard numberCount >= 2 else { return nil }

        // Reject leading operators other than unary minus on the first number.
        guard compact.first.map({ "0123456789-(".contains($0) }) == true else { return nil }

        // Turn 50% into (50/100.0) before evaluating.
        let percentPattern = #"(\d+(?:\.\d+)?)%"#
        guard let percentRegex = try? NSRegularExpression(pattern: percentPattern) else { return nil }
        let percentRange = NSRange(compact.startIndex..<compact.endIndex, in: compact)
        let sanitized = percentRegex.stringByReplacingMatches(
            in: compact,
            options: [],
            range: percentRange,
            withTemplate: "($1/100.0)"
        )
        guard !sanitized.contains("%") else { return nil }
        guard let value = evaluate(sanitized) else { return nil }
        return .sum(value)
    }

    private static func evaluate(_ expression: String) -> Double? {
        // Digits and arithmetic only — never pass free-form text to NSExpression.
        let allowed = CharacterSet(charactersIn: "0123456789+-*/().")
        guard !expression.isEmpty,
              expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        let expr = NSExpression(format: expression)
        guard let number = expr.expressionValue(with: nil, context: nil) as? NSNumber else {
            return nil
        }
        let value = number.doubleValue
        guard value.isFinite else { return nil }
        return value
    }

    // MARK: - Formatting

    private static func parsePlainNumber(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: "")
        guard cleaned.range(of: #"^-?\d+(?:\.\d+)?$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Double(cleaned)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 1e15 {
            return String(Int(value.rounded()))
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func formatCurrency(_ value: Double, symbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        let body = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "\(symbol)\(body)"
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
        optionalGroup(match, index, in: text) ?? ""
    }

    private static func optionalGroup(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }
}

/// Browser page URL kept beside a selection, plus Markdown-link paste.
enum PageURL {
    static let title = "Paste as Markdown Link"
    static let symbolName = "link.badge.plus"
    /// Chromium family pasteboard type for the tab URL when the selection is separate.
    static let chromiumSourceType = "org.chromium.source-url"

    static func resolve(
        selection: String?,
        publicURLs: [String],
        chromiumURL: String?,
        bundleID: String
    ) -> String? {
        guard let selection, !ClipText.isBlank(selection) else { return nil }
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)

        if let chromium = normalize(chromiumURL), !matches(chromium, trimmed) {
            return chromium
        }

        guard isBrowser(bundleID) else { return nil }
        for raw in publicURLs {
            guard let url = normalize(raw), !matches(url, trimmed) else { continue }
            return url
        }
        return nil
    }

    static func normalize(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.lowercased().hasPrefix("www.") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url.absoluteString
    }

    static func isBrowser(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        let prefixes = [
            "com.apple.safari",
            "com.google.chrome",
            "com.microsoft.edgemac",
            "com.brave.browser",
            "org.mozilla.firefox",
            "com.operasoftware.opera",
            "com.vivaldi.vivaldi",
            "company.thebrowser.browser",
            "com.sigmaos.sigmaos",
            "com.kagi.kagibrowser",
        ]
        return prefixes.contains { id.hasPrefix($0) }
    }

    static func markdownLink(text: String, pageURL: String) -> String? {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = normalize(pageURL) else { return nil }
        return "[\(escapeMarkdownLabel(title))](\(url))"
    }

    private static func matches(_ url: String, _ text: String) -> Bool {
        let left = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if left == right { return true }
        if let normalizedText = normalize(text) {
            return normalizedText.lowercased() == left
        }
        return false
    }

    private static func escapeMarkdownLabel(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}

/// Ephemeral preview edits for paste/copy. Never writes to the history store.
enum PreviewPasteDraft {
    static func supports(_ kind: ClipKind) -> Bool {
        switch kind {
        case .image, .file, .color:
            return false
        case .text, .richText, .code, .link, .email:
            return true
        }
    }

    /// Clipboard payload with the draft text. Keeps `contentHash` so paste counts stay on the stored clip.
    /// When the draft matches the stored text, returns the original so rich formats remain.
    static func applying(_ draft: String, to clip: Clip) -> Clip {
        let original = clip.text ?? clip.preview
        if draft == original {
            return clip
        }
        var edited = clip
        edited.text = draft
        edited.html = nil
        edited.rtf = nil
        edited.preview = ClipText.previewLine(from: draft)
        edited.kind = ClipClassifier.classify(
            text: draft,
            html: nil,
            hasRTF: false,
            hasImage: clip.imageRelativePath != nil,
            fileURLs: clip.fileURLs
        )
        edited.colorHex = ColorValue.parse(draft.trimmingCharacters(in: .whitespacesAndNewlines))?.hex
        edited.byteSize = draft.utf8.count
        return edited
    }
}
