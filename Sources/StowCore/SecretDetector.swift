import Foundation

/// Catches secrets that were not marked with a concealed pasteboard type.
/// The caller keeps the bytes in memory only long enough to offer an override.
enum SecretDetector {
    enum Reason: String, Equatable, Sendable {
        case privateKey
        case cardNumber
        case token

        var title: String {
            switch self {
            case .privateKey: "private key"
            case .cardNumber: "card number"
            case .token: "token"
            }
        }
    }

    static func detect(in text: String) -> Reason? {
        if isPrivateKey(text) {
            return .privateKey
        }
        if containsCardNumber(text) {
            return .cardNumber
        }
        if containsToken(text) {
            return .token
        }
        return nil
    }

    private static func isPrivateKey(_ text: String) -> Bool {
        let upper = text.uppercased()
        return upper.contains("-----BEGIN") && upper.contains("PRIVATE KEY-----")
    }

    private static func containsCardNumber(_ text: String) -> Bool {
        let scalars = Array(text)
        var index = 0
        while index < scalars.count {
            while index < scalars.count, !scalars[index].isNumber {
                index += 1
            }
            var digits: [Character] = []
            var cursor = index
            while cursor < scalars.count {
                let character = scalars[cursor]
                if character.isNumber {
                    digits.append(character)
                    cursor += 1
                    continue
                }
                let isSeparator = character == " " || character == "-"
                let nextIsDigit = cursor + 1 < scalars.count && scalars[cursor + 1].isNumber
                if isSeparator && nextIsDigit && !digits.isEmpty {
                    cursor += 1
                    continue
                }
                break
            }
            if (13...19).contains(digits.count), luhn(String(digits)) {
                return true
            }
            index = max(cursor, index + 1)
        }
        return false
    }

    static func luhn(_ digits: String) -> Bool {
        var sum = 0
        let values = digits.compactMap { $0.wholeNumberValue }.reversed()
        for (offset, digit) in values.enumerated() {
            if offset.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return !digits.isEmpty && sum.isMultiple(of: 10)
    }

    private static func containsToken(_ text: String) -> Bool {
        if wholeStringIsToken(text) {
            return true
        }
        let patterns = [
            #"sk-[A-Za-z0-9_\-]{16,}"#,
            #"ghp_[A-Za-z0-9]{20,}"#,
            #"gho_[A-Za-z0-9]{20,}"#,
            #"github_pat_[A-Za-z0-9_]{20,}"#,
            #"xox[baprs]-[A-Za-z0-9-]{10,}"#,
            #"AKIA[0-9A-Z]{16}"#,
            #"ASIA[0-9A-Z]{16}"#,
            #"npm_[A-Za-z0-9]{20,}"#,
            #"glpat-[A-Za-z0-9\-_]{16,}"#,
            #"ya29\.[A-Za-z0-9_\-\.]{16,}"#,
            #"eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{8,}"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if regex.firstMatch(in: text, range: range) != nil {
                return true
            }
        }
        return false
    }

    private static func wholeStringIsToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40, !trimmed.contains(where: \.isWhitespace) else { return false }
        guard !trimmed.contains("://"), !trimmed.hasPrefix("www.") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        let hasUpper = trimmed.contains(where: \.isUppercase)
        let hasLower = trimmed.contains(where: \.isLowercase)
        let hasDigit = trimmed.contains(where: \.isNumber)
        return hasUpper && hasLower && hasDigit
    }
}
