import CryptoKit
import Foundation

enum ContentHash {
    static func text(_ text: String) -> String {
        digest(Data(text.utf8))
    }

    static func image(_ data: Data) -> String {
        digest(data)
    }

    static func files(_ paths: [String]) -> String {
        digest(Data(paths.joined(separator: "\n").utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
