import Foundation

enum ClipClassifier {
    static func classify(
        text: String?,
        html: String?,
        hasRTF: Bool,
        hasImage: Bool,
        fileURLs: [String]
    ) -> ClipKind {
        if hasImage {
            return .image
        }
        if !fileURLs.isEmpty {
            return .file
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, isEmail(trimmed) {
            return .email
        }
        if !trimmed.isEmpty, isLink(trimmed) {
            return .link
        }
        if !trimmed.isEmpty, ColorValue.parse(trimmed) != nil {
            return .color
        }
        if !trimmed.isEmpty, looksLikeCode(trimmed) {
            return .code
        }
        if hasRTF || !(html ?? "").isEmpty {
            return .richText
        }
        return .text
    }

    static func isEmail(_ text: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isLink(_ text: String) -> Bool {
        if text.contains(where: \.isWhitespace) || text.contains("\n") {
            return false
        }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil {
            return true
        }
        let www = #"^www\.[A-Z0-9.\-]+\.[A-Z]{2,}(/.*)?$"#
        return text.range(of: www, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func looksLikeCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("```") {
            return true
        }
        let keywords = [
            "func ", "def ", "class ", "import ", "fn ", "struct ", "enum ",
            "function ", "#include", "package ", "impl ", "console.", "SELECT ",
            "INSERT ", "func\t",
        ]
        let keywordHits = keywords.reduce(into: 0) { count, keyword in
            if trimmed.contains(keyword) { count += 1 }
        }
        let hasBlock = trimmed.contains("{") && trimmed.contains("}")
        let hasStatementBreak = trimmed.contains(";\n") || (trimmed.contains(";") && trimmed.contains("\n"))
        if keywordHits >= 2 {
            return true
        }
        if hasBlock && trimmed.contains("\"") && trimmed.contains(":") {
            return true
        }
        if hasBlock && (keywordHits >= 1 || trimmed.contains(";")) {
            return true
        }
        if hasStatementBreak && keywordHits >= 1 {
            return true
        }
        return false
    }
}
