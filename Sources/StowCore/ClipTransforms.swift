import Foundation

/// Explicit text rewrites. Nothing here runs unless the user chooses it.
enum ClipTransform: String, CaseIterable, Identifiable, Sendable {
    case htmlToMarkdown
    case prettyJSON
    case unwrapLines
    case stripTracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .htmlToMarkdown: "HTML to Markdown"
        case .prettyJSON: "Pretty JSON"
        case .unwrapLines: "Unwrap lines"
        case .stripTracking: "Strip tracking"
        }
    }

    var symbolName: String {
        switch self {
        case .htmlToMarkdown: "text.badge.checkmark"
        case .prettyJSON: "curlybraces"
        case .unwrapLines: "text.alignleft"
        case .stripTracking: "link"
        }
    }

    static func available(text: String, html: String?) -> [ClipTransform] {
        allCases.filter { $0.output(text: text, html: html) != nil }
    }

    func output(text: String, html: String?) -> String? {
        switch self {
        case .htmlToMarkdown:
            let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var sources: [String] = []
            if Self.containsMarkup(plain) {
                sources.append(plain)
            }
            if let markup = html?.trimmingCharacters(in: .whitespacesAndNewlines),
               Self.containsMarkup(markup),
               markup != plain {
                sources.append(markup)
            }
            for source in sources {
                let markdown = Self.htmlToMarkdown(source)
                if !markdown.isEmpty, markdown != plain {
                    return markdown
                }
            }
            return nil
        case .prettyJSON:
            return Self.prettyJSON(text)
        case .unwrapLines:
            let unwrapped = Self.unwrapLines(text)
            guard unwrapped != text else { return nil }
            return unwrapped
        case .stripTracking:
            return Self.stripTracking(text)
        }
    }

    private static func containsMarkup(_ value: String) -> Bool {
        value.range(of: "<[a-zA-Z/!]", options: .regularExpression) != nil
    }

    private static func htmlToMarkdown(_ html: String) -> String {
        var source = html.replacingOccurrences(of: "\r\n", with: "\n")
        source = replace(source, pattern: #"<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#, template: #"[$2]($1)"#)
        source = replace(source, pattern: #"<(strong|b)\b[^>]*>(.*?)</\1>"#, template: #"**$2**"#)
        source = replace(source, pattern: #"<(em|i)\b[^>]*>(.*?)</\1>"#, template: #"*$2*"#)
        source = replace(source, pattern: #"<code\b[^>]*>(.*?)</code>"#, template: #"`$1`"#)
        source = replace(source, pattern: #"<h[1-6]\b[^>]*>(.*?)</h[1-6]>"#, template: "\n\n$1\n\n")
        source = replace(source, pattern: #"<li\b[^>]*>(.*?)</li>"#, template: "\n- $1")
        source = replace(source, pattern: #"<(br|hr)\s*/?>"#, template: "\n")
        source = replace(source, pattern: #"</(p|div|tr|blockquote|pre|ul|ol|h[1-6])>"#, template: "\n\n")
        source = replace(source, pattern: #"<[^>]+>"#, template: "")
        source = decodeEntities(source)
        source = source.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        source = source.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prettyJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let rendered = String(data: pretty, encoding: .utf8)
        else { return nil }
        let normalized = rendered.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized != trimmed else { return nil }
        return normalized
    }

    private static func unwrapLines(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.contains("\n") else { return normalized }
        let paragraphs = normalized.components(separatedBy: "\n\n")
        return paragraphs.map { paragraph in
            let lines = paragraph.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            var joined: [String] = []
            var current = ""
            for line in lines where !line.isEmpty {
                if current.isEmpty {
                    current = line
                } else if continuesParagraph(current, next: line) {
                    current += " " + line
                } else {
                    joined.append(current)
                    current = line
                }
            }
            if !current.isEmpty { joined.append(current) }
            return joined.joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func continuesParagraph(_ current: String, next: String) -> Bool {
        if next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("#") || next.hasPrefix(">") {
            return false
        }
        if current.hasPrefix("- ") || current.hasPrefix("* ") || current.hasPrefix("#") {
            return false
        }
        return true
    }

    private static let trackingNames: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id",
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "mc_cid", "mc_eid",
        "igshid", "igsh", "_hsenc", "_hsmi", "mkt_tok", "ref_src", "yclid", "twclid", "ttclid",
    ]

    private static func stripTracking(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme == "http" || components.scheme == "https",
              let items = components.queryItems,
              items.contains(where: { trackingNames.contains($0.name.lowercased()) })
        else { return nil }
        var cleaned = components
        let kept = items.filter { !trackingNames.contains($0.name.lowercased()) }
        cleaned.queryItems = kept.isEmpty ? nil : kept
        return cleaned.string
    }

    private static func replace(_ source: String, pattern: String, template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private static func decodeEntities(_ source: String) -> String {
        var text = source
        let named = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text
    }
}

/// Explicit line edits that produce new history rows. Separate from `ClipTransform`, which only copies.
enum ClipLineOps {
    static let title = "Split lines"
    static let symbolName = "rectangle.split.1x2"

    /// Non-empty lines after normalizing CRLF. `nil` when fewer than two lines remain.
    static func splitLines(_ text: String) -> [String]? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        return lines
    }

    static func canSplit(_ text: String) -> Bool {
        splitLines(text) != nil
    }
}
