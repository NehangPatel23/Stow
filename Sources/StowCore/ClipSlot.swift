import Foundation

/// A fixed clipboard register. Content stays until replaced or cleared — not a history position.
struct ClipSlot: Codable, Equatable, Identifiable, Sendable {
    /// 1-based index shown in the UI and bound to the default hotkey digit.
    var index: Int
    var name: String
    var payload: SlotPayload?
    var hotkeyKeyCode: UInt32
    var hotkeyCarbonModifiers: UInt32
    var hotkeyLabel: String

    var id: Int { index }
    var isEmpty: Bool { payload == nil }

    var menuTitle: String {
        guard let payload else { return "\(name) · Empty" }
        let preview = ClipText.previewLine(from: payload.preview, limit: 48)
        if preview.isEmpty {
            return "\(name) · \(payload.kind.title)"
        }
        return "\(name) · \(preview)"
    }
}

/// Independent copy of a clip kept in a slot (survives history delete/clear).
struct SlotPayload: Codable, Equatable, Sendable {
    var kind: ClipKind
    var preview: String
    var text: String?
    var html: String?
    var rtf: Data?
    var imagePNG: Data?
    var fileURLs: [String]
    var colorHex: String?
    var sourceAppName: String
    var contentHash: String
    var imageWidth: Int?
    var imageHeight: Int?
    var byteSize: Int
    var assignedAt: Date

    static func from(clip: Clip, imagePNG: Data?) -> SlotPayload {
        SlotPayload(
            kind: clip.kind,
            preview: clip.preview,
            text: clip.text,
            html: clip.html,
            rtf: clip.rtf,
            imagePNG: imagePNG,
            fileURLs: clip.fileURLs,
            colorHex: clip.colorHex,
            sourceAppName: clip.sourceAppName,
            contentHash: clip.contentHash,
            imageWidth: clip.imageWidth,
            imageHeight: clip.imageHeight,
            byteSize: clip.byteSize,
            assignedAt: Date()
        )
    }

    func asClip() -> Clip {
        Clip(
            id: UUID(),
            createdAt: assignedAt,
            pinned: false,
            sourceAppName: sourceAppName,
            sourceBundleID: "",
            kind: kind,
            preview: preview,
            text: text,
            html: html,
            rtf: rtf,
            imageRelativePath: nil,
            thumbRelativePath: nil,
            fileURLs: fileURLs,
            colorHex: colorHex,
            contentHash: contentHash,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            byteSize: byteSize,
            copyCount: 1,
            ocrText: nil
        )
    }
}

enum SlotStore {
    static let count = 5
    private static let defaultsKey = "Stow.Slots"
    private static let signatureLabelPrefix = "⌃⌥"

    /// Physical ANSI number-row key codes for digits 1…5.
    private static let digitKeyCodes: [Int: UInt16] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
    ]

    /// Control + Option (Carbon `controlKey | optionKey`).
    static let defaultCarbonModifiers: UInt32 = 0x1800

    static func defaults() -> [ClipSlot] {
        (1...count).map { index in
            let keyCode = UInt32(digitKeyCodes[index] ?? 18)
            return ClipSlot(
                index: index,
                name: "Slot \(index)",
                payload: nil,
                hotkeyKeyCode: keyCode,
                hotkeyCarbonModifiers: defaultCarbonModifiers,
                hotkeyLabel: "\(signatureLabelPrefix)\(index)"
            )
        }
    }

    static func load(defaults: UserDefaults = .standard) -> [ClipSlot] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([ClipSlot].self, from: data) else {
            return Self.defaults()
        }
        return merge(decoded)
    }

    static func save(_ slots: [ClipSlot], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(merge(slots)) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// Ensures slots 1…count exist and keep sensible default hotkeys when missing.
    static func merge(_ slots: [ClipSlot]) -> [ClipSlot] {
        let byIndex = Dictionary(uniqueKeysWithValues: slots.map { ($0.index, $0) })
        return defaults().map { blank in
            guard var existing = byIndex[blank.index] else { return blank }
            if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = blank.name
            }
            if existing.hotkeyLabel.isEmpty {
                existing.hotkeyKeyCode = blank.hotkeyKeyCode
                existing.hotkeyCarbonModifiers = blank.hotkeyCarbonModifiers
                existing.hotkeyLabel = blank.hotkeyLabel
            }
            return existing
        }
    }
}
