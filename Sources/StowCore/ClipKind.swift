import Foundation

enum ClipKind: String, Codable, CaseIterable, Sendable, Equatable {
    case text
    case richText
    case code
    case link
    case email
    case color
    case image
    case file

    var title: String {
        switch self {
        case .text: "Text"
        case .richText: "Rich text"
        case .code: "Code"
        case .link: "Link"
        case .email: "Email"
        case .color: "Color"
        case .image: "Image"
        case .file: "File"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .email: "envelope"
        case .color: "circle.fill"
        case .image: "photo"
        case .file: "doc"
        }
    }

    /// Names accepted by `type:` search, including the stored raw value.
    var searchAliases: [String] {
        switch self {
        case .text: ["text", "plain"]
        case .richText: ["richtext", "rich", "rtf"]
        case .code: ["code"]
        case .link: ["link", "url"]
        case .email: ["email", "mail"]
        case .color: ["color", "colour"]
        case .image: ["image", "img", "picture"]
        case .file: ["file", "files"]
        }
    }

    static func fromSearchToken(_ token: String) -> ClipKind? {
        let normalized = token.lowercased().replacingOccurrences(of: "-", with: "")
        return allCases.first { $0.searchAliases.contains(normalized) }
    }
}
