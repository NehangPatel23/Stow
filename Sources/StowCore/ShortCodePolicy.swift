import Foundation

enum ShortCodePattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case sixDigit
    case fourToEightDigit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sixDigit: "6-digit codes"
        case .fourToEightDigit: "4–8 digit codes"
        }
    }

    var detail: String {
        switch self {
        case .sixDigit: "The whole copy is exactly six digits."
        case .fourToEightDigit: "The whole copy is four to eight digits."
        }
    }
}

/// Matching and lifetime rules for short-lived history rows (OTP-style codes).
enum ShortCodePolicy {
    static let lifetimeChoices = [30, 60, 300, 900]
    static let defaultLifetimeSeconds = 60

    static func normalizedLifetimeSeconds(_ seconds: Int) -> Int {
        lifetimeChoices.contains(seconds) ? seconds : defaultLifetimeSeconds
    }

    static func matches(text: String?, kind: ClipKind, pattern: ShortCodePattern) -> Bool {
        switch kind {
        case .image, .file, .color:
            return false
        case .text, .richText, .code, .link, .email:
            break
        }
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        if raw.contains(where: { $0.isNewline }) {
            return false
        }
        switch pattern {
        case .sixDigit:
            return raw.range(of: #"^\d{6}$"#, options: .regularExpression) != nil
        case .fourToEightDigit:
            return raw.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
        }
    }

    static func expiresAt(createdAt: Date, lifetimeSeconds: Int, now: Date = Date()) -> Date {
        let seconds = normalizedLifetimeSeconds(lifetimeSeconds)
        return createdAt.addingTimeInterval(TimeInterval(seconds))
    }

    static func lifetimeTitle(_ seconds: Int) -> String {
        switch normalizedLifetimeSeconds(seconds) {
        case 30: return "30 seconds"
        case 60: return "1 minute"
        case 300: return "5 minutes"
        case 900: return "15 minutes"
        default: return "1 minute"
        }
    }
}
