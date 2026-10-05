import CommonCrypto
import CryptoKit
import Foundation
import Security

enum SyncCryptoError: Error, Equatable, CustomStringConvertible {
    case invalidFormat
    case unsupportedVersion(Int)
    case wrongPassphrase
    case emptyPassphrase

    var description: String {
        switch self {
        case .invalidFormat:
            "That file is not a Stow sync package."
        case .unsupportedVersion(let version):
            "This Stow build cannot read sync format \(version)."
        case .wrongPassphrase:
            "The sync passphrase does not match this package."
        case .emptyPassphrase:
            "Set a sync passphrase first."
        }
    }
}

/// AES-GCM package for folder sync. Key is derived from a passphrase + salt (PBKDF2).
enum SyncCrypto {
    static let pathExtension = "stowsync"
    static let fileName = "library.stowsync"
    static let formatID = "stow.sync"
    static let formatVersion = 1
    private static let saltSize = 16
    private static let pbkdfIterations: UInt32 = 100_000

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var salt: Data
        var box: Data
    }

    static func seal(plaintext: Data, passphrase: String) throws -> Data {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SyncCryptoError.emptyPassphrase }

        var salt = Data(count: saltSize)
        let status = salt.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, saltSize, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw SyncCryptoError.invalidFormat
        }

        let key = try deriveKey(passphrase: trimmed, salt: salt)
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw SyncCryptoError.invalidFormat
        }

        let envelope = Envelope(
            format: formatID,
            version: formatVersion,
            salt: salt,
            box: combined
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    static func open(package: Data, passphrase: String) throws -> Data {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SyncCryptoError.emptyPassphrase }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: package)
        } catch {
            throw SyncCryptoError.invalidFormat
        }
        guard envelope.format == formatID else { throw SyncCryptoError.invalidFormat }
        guard envelope.version == formatVersion else {
            throw SyncCryptoError.unsupportedVersion(envelope.version)
        }

        let key = try deriveKey(passphrase: trimmed, salt: envelope.salt)
        do {
            let box = try AES.GCM.SealedBox(combined: envelope.box)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw SyncCryptoError.wrongPassphrase
        }
    }

    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        let password = Array(passphrase.utf8)
        var derived = Data(count: 32)
        let result = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    pbkdfIterations,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                    32
                )
            }
        }
        guard result == kCCSuccess else { throw SyncCryptoError.invalidFormat }
        return SymmetricKey(data: derived)
    }
}
